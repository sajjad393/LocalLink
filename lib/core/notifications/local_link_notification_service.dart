import 'dart:async';
import 'dart:io';

import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/notifications/local_link_notification_platform.dart';
import 'package:locallink/core/notifications/notification_action.dart';
import 'package:locallink/core/notifications/notification_identity_resolver.dart';
import 'package:locallink/core/notifications/notification_id.dart';
import 'package:locallink/core/notifications/notification_policy.dart';
import 'package:locallink/core/notifications/notification_preferences.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' hide CallState;
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';

/// Coordinates modern message/system notifications on top of the existing
/// messaging and calling services. It does not own any networking.
///
/// Each message notification has its own stable notification ID. This is
/// deliberate: actions must always target the exact message represented by the
/// notification instead of being rewritten to the newest unread message.
final class LocalLinkNotificationService {
  static const Duration _perConversationAlertWindow = Duration(seconds: 4);
  static const Duration _globalAlertWindow = Duration(seconds: 10);
  static const int _maxGlobalAlerts = 6;
  static const int _maxVisibleMessagesPerConversation = 24;

  final LocalStore store;
  final MessagingRepositoryContract messaging;
  final GroupMessagingRepositoryContract groups;
  final CallBloc calls;
  final LocalLinkNotificationPlatform platform;
  final LocalLinkNotificationPolicy policy;
  final NotificationPreferences preferences;
  late final NotificationIdentityResolver identities;

  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<GroupMessage>? _groupSubscription;
  StreamSubscription<CallSession?>? _callSubscription;
  StreamSubscription<String>? _deletedMessageSubscription;
  StreamSubscription<LocalLinkNotificationAction>? _actionSubscription;
  final StreamController<LocalLinkNotificationAction> _openRequests =
      StreamController<LocalLinkNotificationAction>.broadcast();
  final Map<String, DateTime> _lastAlertAt = <String, DateTime>{};
  final List<DateTime> _globalAlertTimes = <DateTime>[];
  Timer? _cleanupTimer;
  bool _started = false;
  bool _disposed = false;

  LocalLinkNotificationService({
    required this.store,
    required this.messaging,
    required this.groups,
    required this.calls,
    LocalLinkNotificationPlatform? platform,
    LocalLinkNotificationPolicy? policy,
    NotificationPreferences? preferences,
  })  : platform = platform ?? LocalLinkNotificationPlatform(),
        policy = policy ?? LocalLinkNotificationPolicy(),
        preferences = preferences ?? NotificationPreferences() {
    identities = NotificationIdentityResolver(store);
  }

  Stream<LocalLinkNotificationAction> get openRequests => _openRequests.stream;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    await preferences.load();
    await platform.initialize();
    _messageSubscription = messaging.incoming.listen(_onDirectMessage);
    _groupSubscription = groups.incoming.listen(_onGroupMessage);
    _callSubscription = calls.sessionStream.listen(_onCallSession);
    _deletedMessageSubscription =
        store.deletedMessageIds.listen(_onMessageDeleted);
    _actionSubscription = platform.actions.listen(_handleAction);
    _cleanupTimer = Timer.periodic(const Duration(hours: 12), (_) {
      unawaited(_cleanup());
    });
    // Rebuild the notification presentation from unread DB state after a
    // process restart. This also removes orphaned group summaries.
    await platform.cancelAllMessages();
    await _cleanup();
    await restorePending();
  }

  void setAppLifecycleResumed(bool resumed) {
    // Lifecycle changes only affect suppression policy. Becoming foreground
    // does not itself mean the user viewed any conversation.
    policy.setAppLifecycleResumed(resumed);
  }

  void setActiveDirectConversation(String? id) {
    policy.setActiveDirectConversation(id);
  }

  void setActiveGroupConversation(String? id) {
    policy.setActiveGroupConversation(id);
  }

  /// Marks a conversation as read after the conversation screen has actually
  /// been opened and rendered. This is intentionally separate from lifecycle
  /// callbacks and notification dismissal.
  Future<void> markDirectConversationRead(String conversationId) async {
    final id = conversationId.trim();
    if (id.isEmpty) return;
    final messages = await store.unreadMessagesForConversation(id);
    for (final message in messages) {
      await _markDirectMessageRead(message);
    }
    await platform.cancelNotification(notificationIdForDirectSummary(id));
  }

  Future<void> markGroupConversationRead(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty) return;
    final messages = await store.unreadGroupMessages(id);
    for (final message in messages) {
      await _markGroupMessageRead(message);
    }
    await platform.cancelNotification(notificationIdForGroupSummary(id));
  }

  /// Explicitly removes a notification for a message that was deleted by a
  /// future UI/service caller. The database state remains the source of truth.
  Future<void> handleMessageDeleted(String messageId) async {
    final id = messageId.trim();
    if (id.isEmpty) return;
    final states = await store.notificationStates();
    for (final state in states) {
      if (state['message_id']?.toString() != id) continue;
      final notificationId =
          int.tryParse(state['notification_id']?.toString() ?? '') ?? 0;
      if (notificationId > 0) {
        await platform.cancelNotification(notificationId);
      }
    }
    await store.removeNotificationStateForMessage(id);
  }

  Future<void> showSystemNotification({
    required String id,
    required String title,
    required String body,
    bool silent = false,
  }) async {
    if (_disposed) return;
    final safeId = id.trim();
    if (safeId.isEmpty || title.trim().isEmpty) return;
    final notificationId = LocalLinkNotificationId.system(safeId);
    await platform.showSystem(
      notificationId: notificationId,
      title: title.trim(),
      body: body.trim(),
      silent: silent || policy.shouldBeSilent,
    );
    await store.markNotificationShown(
      kind: 'system',
      conversationId: safeId,
      messageId: safeId,
      notificationId: notificationId,
    );
  }

  Future<void> refreshPendingNotifications() => refreshNotifications();

  Future<void> refreshNotifications() async {
    if (_disposed) return;
    await platform.cancelAllMessages();
    await _cleanup();
    await restorePending();
  }

  Future<void> restorePending() async {
    if (_disposed) return;

    final directConversationIds =
        await store.unreadDirectConversationIds(limit: 100);
    for (final conversationId in directConversationIds) {
      if (!policy.shouldNotifyDirect(conversationId)) continue;
      if (await store.isBlockedPeer(conversationId)) continue;
      final messages =
          await store.unreadMessagesForConversation(conversationId);
      if (messages.isEmpty) continue;
      await _showRestoredDirect(messages);
    }

    final groupIds = await store.unreadGroupConversationIds(limit: 100);
    for (final groupId in groupIds) {
      if (!policy.shouldNotifyGroup(groupId)) continue;
      final messages = await store.unreadGroupMessages(groupId);
      final valid = <GroupMessage>[];
      for (final message in messages) {
        if (!_validGroupIncomingMessage(message)) continue;
        if (await store.isBlockedPeer(message.senderId)) continue;
        if (!await _isValidGroupNotificationSender(message)) continue;
        valid.add(message);
      }
      if (valid.isEmpty) continue;
      await _showRestoredGroup(valid);
    }
  }

  Future<void> _showRestoredDirect(List<Message> messages) async {
    if (messages.isEmpty) return;
    final start = messages.length > _maxVisibleMessagesPerConversation
        ? messages.length - _maxVisibleMessagesPerConversation
        : 0;
    for (var i = start; i < messages.length; i++) {
      await _showDirect(messages[i], allowAlert: false);
    }
    await _showDirectSummary(messages.first.senderId, messages.length,
        silent: true);
  }

  Future<void> _showRestoredGroup(List<GroupMessage> messages) async {
    if (messages.isEmpty) return;
    final start = messages.length > _maxVisibleMessagesPerConversation
        ? messages.length - _maxVisibleMessagesPerConversation
        : 0;
    for (var i = start; i < messages.length; i++) {
      await _showGroup(messages[i], allowAlert: false);
    }
    await _showGroupSummary(messages.first.groupId, messages.length,
        silent: true);
  }

  Future<void> _onDirectMessage(Message message) async {
    if (_disposed || !_validDirectIncomingMessage(message)) return;
    if (await store.isBlockedPeer(message.senderId)) return;

    if (!policy.shouldNotifyDirect(message.senderId)) {
      // The matching conversation is active in the foreground. The live chat
      // UI receives this same message stream, so this message is now viewed.
      await store.markMessageRead(message.id);
      await store.removeNotificationStateForMessage(message.id);
      return;
    }
    await _showDirect(message);
  }

  Future<void> _onGroupMessage(GroupMessage message) async {
    if (_disposed || !_validGroupIncomingMessage(message)) return;
    if (await store.isBlockedPeer(message.senderId)) return;
    if (!await _isValidGroupNotificationSender(message)) return;

    if (!policy.shouldNotifyGroup(message.groupId)) {
      await store.markGroupMessageRead(message.id);
      await store.removeNotificationStateForMessage(message.id);
      return;
    }
    await _showGroup(message);
  }

  void _onCallSession(CallSession? session) {
    if (session == null) {
      policy.setCallState(ringing: false, active: false);
      return;
    }
    final ringing = session.state == CallState.ringing;
    final active = session.state == CallState.connected ||
        session.state == CallState.reconnecting ||
        session.state == CallState.connecting;
    policy.setCallState(ringing: ringing, active: active);
  }

  Future<void> _onMessageDeleted(String messageId) async {
    await handleMessageDeleted(messageId);
  }

  bool _validDirectIncomingMessage(Message message) =>
      message.id.trim().isNotEmpty &&
      message.senderId.trim().isNotEmpty &&
      message.senderId != store.deviceId &&
      message.recipientId == store.deviceId;

  bool _validGroupIncomingMessage(GroupMessage message) =>
      message.id.trim().isNotEmpty &&
      message.groupId.trim().isNotEmpty &&
      message.senderId.trim().isNotEmpty &&
      message.senderId != store.deviceId;

  Future<bool> _isValidGroupNotificationSender(GroupMessage message) async {
    final members = await store.groupMembers(message.groupId);
    if (!members.any((row) => row['device_id']?.toString() == store.deviceId)) {
      return false;
    }
    return members
        .any((row) => row['device_id']?.toString() == message.senderId);
  }

  Future<void> _showDirect(Message message, {bool allowAlert = true}) async {
    final unread = await store.unreadMessagesForConversation(message.senderId);
    Message? target;
    for (final candidate in unread) {
      if (candidate.id == message.id) {
        target = candidate;
        break;
      }
    }
    if (target == null) return;

    final identity = await identities.resolvePeer(target.senderId);
    final attachment = preferences.privacyMode == NotificationPrivacyMode.full
        ? _firstLocalImage(target)
        : null;
    final shouldAlert = allowAlert && _shouldAlert(message.senderId);
    final notificationId = notificationIdForDirectMessage(
      target.senderId,
      target.id,
    );
    await platform.showMessage(
      notificationId: notificationId,
      conversationType: 'direct',
      conversationId: target.senderId,
      messageId: target.id,
      senderId: target.senderId,
      recipientId: target.recipientId,
      title: _titleForPrivacy(identity.displayName, isGroup: false),
      body: _bodyForPrivacy(_bodyForMessage(target)),
      summary: _summaryForConversation(
        displayName: identity.displayName,
        unreadCount: unread.length,
        isGroup: false,
      ),
      publicTitle: _publicTitle(identity.displayName, isGroup: false),
      publicBody: _publicBody(),
      initials: identity.initials,
      avatarPath: identity.localAvatarPath,
      imagePath: attachment?.path,
      attachmentId: attachment?.id,
      unreadCount: unread.length,
      silent: !shouldAlert || policy.shouldBeSilent,
      visibility: _visibilityForMessage(),
    );
    await store.markNotificationShown(
      kind: 'direct',
      conversationId: target.senderId,
      messageId: target.id,
      notificationId: notificationId,
    );
    await _showDirectSummary(
      target.senderId,
      unread.length,
      silent: true,
    );
  }

  Future<void> _showGroup(GroupMessage message,
      {bool allowAlert = true}) async {
    final unread = await store.unreadGroupMessages(message.groupId);
    GroupMessage? target;
    for (final candidate in unread) {
      if (candidate.id == message.id) {
        target = candidate;
        break;
      }
    }
    if (target == null) return;

    final identity =
        await identities.resolveGroupSender(target.groupId, target.senderId);
    final groupName = await identities.groupName(target.groupId);
    final attachment = preferences.privacyMode == NotificationPrivacyMode.full
        ? _firstLocalImageForGroup(target)
        : null;
    final shouldAlert = allowAlert && _shouldAlert(message.groupId);
    final notificationId = notificationIdForGroupMessage(
      target.groupId,
      target.id,
    );
    await platform.showMessage(
      notificationId: notificationId,
      conversationType: 'group',
      conversationId: target.groupId,
      messageId: target.id,
      senderId: target.senderId,
      recipientId: store.deviceId ?? '',
      title: _titleForPrivacy(
        groupName,
        isGroup: true,
        senderName: identity.displayName,
      ),
      body: _bodyForPrivacy(_bodyForGroupMessage(target)),
      summary: _summaryForConversation(
        displayName: groupName,
        unreadCount: unread.length,
        isGroup: true,
        senderName: identity.displayName,
      ),
      publicTitle: _publicTitle(
        groupName,
        isGroup: true,
        senderName: identity.displayName,
      ),
      publicBody: _publicBody(),
      initials: identity.initials,
      avatarPath: identity.localAvatarPath,
      imagePath: attachment?.path,
      attachmentId: attachment?.id,
      unreadCount: unread.length,
      silent: !shouldAlert || policy.shouldBeSilent,
      visibility: _visibilityForMessage(),
    );
    await store.markNotificationShown(
      kind: 'group',
      conversationId: target.groupId,
      messageId: target.id,
      notificationId: notificationId,
    );
    await _showGroupSummary(target.groupId, unread.length, silent: true);
  }

  bool _shouldAlert(String conversationId) {
    final now = DateTime.now().toUtc();
    _globalAlertTimes.removeWhere(
      (time) => now.difference(time) >= _globalAlertWindow,
    );

    final last = _lastAlertAt[conversationId];
    if (last != null && now.difference(last) < _perConversationAlertWindow) {
      return false;
    }
    if (_globalAlertTimes.length >= _maxGlobalAlerts) return false;

    _lastAlertAt[conversationId] = now;
    _globalAlertTimes.add(now);
    return true;
  }

  Future<void> _showDirectSummary(
    String conversationId,
    int unreadCount, {
    required bool silent,
  }) async {
    if (unreadCount <= 0) {
      await platform.cancelNotification(
        notificationIdForDirectSummary(conversationId),
      );
      return;
    }
    final identity = await identities.resolvePeer(conversationId);
    await platform.showSummary(
      notificationId: notificationIdForDirectSummary(conversationId),
      conversationType: 'direct',
      conversationId: conversationId,
      title: _summaryTitleForPrivacy(
        displayName: identity.displayName,
      ),
      body: '$unreadCount new ${unreadCount == 1 ? 'message' : 'messages'}',
      silent: silent || policy.shouldBeSilent,
      visibility: _visibilityForMessage(),
    );
  }

  Future<void> _showGroupSummary(
    String groupId,
    int unreadCount, {
    required bool silent,
  }) async {
    if (unreadCount <= 0) {
      await platform.cancelNotification(notificationIdForGroupSummary(groupId));
      return;
    }
    final groupName = await identities.groupName(groupId);
    final summaryTitle = preferences.privacyMode == NotificationPrivacyMode.full
        ? groupName
        : preferences.privacyMode == NotificationPrivacyMode.senderOnly
            ? 'New messages'
            : 'LocalLink';
    await platform.showSummary(
      notificationId: notificationIdForGroupSummary(groupId),
      conversationType: 'group',
      conversationId: groupId,
      title: summaryTitle,
      body: '$unreadCount new ${unreadCount == 1 ? 'message' : 'messages'}',
      silent: silent || policy.shouldBeSilent,
      visibility: _visibilityForMessage(),
    );
  }

  Future<void> _handleAction(LocalLinkNotificationAction action) async {
    if (_disposed) return;
    switch (action.conversationType) {
      case NotificationConversationType.direct:
        await _handleDirectAction(action);
      case NotificationConversationType.group:
        await _handleGroupAction(action);
      case NotificationConversationType.system:
        // System notifications currently carry no actionable deep link.
        return;
    }
  }

  Future<void> _handleDirectAction(LocalLinkNotificationAction action) async {
    final localId = store.deviceId;
    if (localId == null ||
        action.messageId.isEmpty ||
        action.conversationId.isEmpty ||
        action.senderId.isEmpty ||
        action.recipientId != localId ||
        action.senderId != action.conversationId) {
      return;
    }

    final notificationId = int.tryParse(action.notificationId) ?? 0;
    if (notificationId !=
        notificationIdForDirectMessage(
          action.conversationId,
          action.messageId,
        )) return;
    if (!await store.notificationStateMatches(
      kind: 'direct',
      conversationId: action.conversationId,
      messageId: action.messageId,
      notificationId: notificationId,
    )) return;

    final message = await store.messageById(action.messageId);
    if (message == null ||
        message.id != action.messageId ||
        message.senderId != action.senderId ||
        message.recipientId != localId ||
        await store.isBlockedPeer(message.senderId) ||
        (action.attachmentId != null &&
            !message.attachments.any((a) => a.id == action.attachmentId))) {
      return;
    }

    switch (action.action) {
      case NotificationActionType.reply:
        final reply = action.replyText?.trim() ?? '';
        if (reply.isEmpty || reply.length > 16 * 1024) return;
        await messaging.send(message.senderId, reply);
        await _markDirectMessageRead(message);
      case NotificationActionType.markRead:
        await _markDirectMessageRead(message);
      case NotificationActionType.open:
        await _markDirectMessageRead(message);
        if (!_openRequests.isClosed) _openRequests.add(action);
    }
  }

  Future<void> _handleGroupAction(LocalLinkNotificationAction action) async {
    final localId = store.deviceId;
    if (localId == null ||
        action.messageId.isEmpty ||
        action.conversationId.isEmpty ||
        action.senderId.isEmpty ||
        action.recipientId != localId) {
      return;
    }

    final notificationId = int.tryParse(action.notificationId) ?? 0;
    if (notificationId !=
        notificationIdForGroupMessage(
          action.conversationId,
          action.messageId,
        )) return;
    if (!await store.notificationStateMatches(
      kind: 'group',
      conversationId: action.conversationId,
      messageId: action.messageId,
      notificationId: notificationId,
    )) return;

    final message = await store.groupMessageById(action.messageId);
    if (message == null ||
        message.id != action.messageId ||
        message.groupId != action.conversationId ||
        message.senderId != action.senderId ||
        await store.isBlockedPeer(message.senderId) ||
        (action.attachmentId != null &&
            !message.attachments.any((a) => a.id == action.attachmentId))) {
      return;
    }

    final members = await store.groupMembers(action.conversationId);
    if (!members.any((row) => row['device_id']?.toString() == localId) ||
        !members
            .any((row) => row['device_id']?.toString() == action.senderId)) {
      return;
    }

    switch (action.action) {
      case NotificationActionType.reply:
        final reply = action.replyText?.trim() ?? '';
        if (reply.isEmpty || reply.length > 16 * 1024) return;
        await groups.send(action.conversationId, reply);
        await _markGroupMessageRead(message);
      case NotificationActionType.markRead:
        await _markGroupMessageRead(message);
      case NotificationActionType.open:
        await _markGroupMessageRead(message);
        if (!_openRequests.isClosed) _openRequests.add(action);
    }
  }

  Future<void> _markDirectMessageRead(Message message) async {
    await store.markMessageRead(message.id);
    await store.removeNotificationStateForMessage(message.id);
    await platform.cancelNotification(
      notificationIdForDirectMessage(message.senderId, message.id),
    );
    await _refreshDirectSummary(message.senderId);
  }

  Future<void> _markGroupMessageRead(GroupMessage message) async {
    await store.markGroupMessageRead(message.id);
    await store.removeNotificationStateForMessage(message.id);
    await platform.cancelNotification(
      notificationIdForGroupMessage(message.groupId, message.id),
    );
    await _refreshGroupSummary(message.groupId);
  }

  Future<void> _refreshDirectSummary(String conversationId) async {
    final unread = await store.unreadMessagesForConversation(conversationId);
    if (unread.isEmpty) {
      await platform.cancelNotification(
        notificationIdForDirectSummary(conversationId),
      );
      return;
    }
    await _showDirectSummary(
      conversationId,
      unread.length,
      silent: true,
    );
  }

  Future<void> _refreshGroupSummary(String groupId) async {
    final unread = await store.unreadGroupMessages(groupId);
    if (unread.isEmpty) {
      await platform.cancelNotification(notificationIdForGroupSummary(groupId));
      return;
    }
    await _showGroupSummary(groupId, unread.length, silent: true);
  }

  int notificationIdForDirectMessage(String conversationId, String messageId) =>
      LocalLinkNotificationId.directMessage(conversationId, messageId);

  int notificationIdForGroupMessage(String groupId, String messageId) =>
      LocalLinkNotificationId.groupMessage(groupId, messageId);

  int notificationIdForDirectSummary(String conversationId) =>
      LocalLinkNotificationId.directSummary(conversationId);

  int notificationIdForGroupSummary(String groupId) =>
      LocalLinkNotificationId.groupSummary(groupId);

  String _bodyForMessage(Message message) {
    if (message.body.trim().isNotEmpty) return message.body.trim();
    if (message.attachments.any((a) => a.isImage)) return '📷 Photo';
    if (message.attachments.isNotEmpty) return '📎 Attachment';
    return 'New message';
  }

  String _bodyForGroupMessage(GroupMessage message) {
    if (message.body.trim().isNotEmpty) return message.body.trim();
    if (message.attachments.any((a) => a.isImage)) return '📷 Photo';
    if (message.attachments.isNotEmpty) return '📎 Attachment';
    return 'New message';
  }

  AttachmentTarget? _firstLocalImage(Message message) {
    for (final attachment in message.attachments) {
      if (!attachment.isImage) continue;
      final path = _usableLocalPath(attachment.localPath);
      if (path != null) return AttachmentTarget(attachment.id, path);
    }
    return null;
  }

  AttachmentTarget? _firstLocalImageForGroup(GroupMessage message) {
    for (final attachment in message.attachments) {
      if (!attachment.isImage) continue;
      final path = _usableLocalPath(attachment.localPath);
      if (path != null) return AttachmentTarget(attachment.id, path);
    }
    return null;
  }

  String? _usableLocalPath(String? path) {
    final value = path?.trim() ?? '';
    if (value.isEmpty) return null;
    try {
      return File(value).existsSync() ? value : null;
    } catch (_) {
      return null;
    }
  }

  String _titleForPrivacy(
    String title, {
    required bool isGroup,
    String? senderName,
  }) {
    switch (preferences.privacyMode) {
      case NotificationPrivacyMode.full:
        return isGroup ? '$title • ${senderName ?? 'Message'}' : title;
      case NotificationPrivacyMode.senderOnly:
        return isGroup ? (senderName ?? 'New message') : title;
      case NotificationPrivacyMode.hidden:
        return 'LocalLink';
    }
  }

  String _publicTitle(
    String title, {
    required bool isGroup,
    String? senderName,
  }) {
    switch (preferences.privacyMode) {
      case NotificationPrivacyMode.full:
        return isGroup ? '$title • ${senderName ?? 'Message'}' : title;
      case NotificationPrivacyMode.senderOnly:
        return isGroup ? (senderName ?? 'New message') : title;
      case NotificationPrivacyMode.hidden:
        return 'LocalLink';
    }
  }

  String _bodyForPrivacy(String body) {
    switch (preferences.privacyMode) {
      case NotificationPrivacyMode.full:
        return body;
      case NotificationPrivacyMode.senderOnly:
        return 'New message';
      case NotificationPrivacyMode.hidden:
        return 'New notification';
    }
  }

  String _publicBody() => switch (preferences.privacyMode) {
        NotificationPrivacyMode.full => 'LocalLink notification',
        NotificationPrivacyMode.senderOnly => 'New message',
        NotificationPrivacyMode.hidden => 'New notification',
      };

  String _summaryForConversation({
    required String displayName,
    required int unreadCount,
    required bool isGroup,
    String? senderName,
  }) {
    switch (preferences.privacyMode) {
      case NotificationPrivacyMode.full:
        if (unreadCount <= 1) {
          return isGroup ? displayName : 'New message from $displayName';
        }
        return '$displayName • $unreadCount new messages';
      case NotificationPrivacyMode.senderOnly:
        final safeName = isGroup ? (senderName ?? 'New message') : displayName;
        return unreadCount <= 1
            ? safeName
            : '$safeName • $unreadCount new messages';
      case NotificationPrivacyMode.hidden:
        return unreadCount <= 1 ? 'New message' : '$unreadCount new messages';
    }
  }

  String _summaryTitleForPrivacy({
    required String displayName,
  }) {
    switch (preferences.privacyMode) {
      case NotificationPrivacyMode.full:
        return displayName;
      case NotificationPrivacyMode.senderOnly:
        return displayName;
      case NotificationPrivacyMode.hidden:
        return 'LocalLink';
    }
  }

  int _visibilityForMessage() {
    switch (preferences.privacyMode) {
      case NotificationPrivacyMode.full:
        return 1; // PUBLIC
      case NotificationPrivacyMode.senderOnly:
        return 0; // PRIVATE
      case NotificationPrivacyMode.hidden:
        return -1; // SECRET
    }
  }

  Future<void> _cleanup() async {
    if (_disposed) return;
    final states = await store.notificationStates();
    final activeDirectConversations = <String>{};
    final activeGroupConversations = <String>{};

    for (final state in states) {
      final kind = state['kind']?.toString() ?? '';
      final conversationId = state['conversation_id']?.toString() ?? '';
      final messageId = state['message_id']?.toString() ?? '';
      final notificationId =
          int.tryParse(state['notification_id']?.toString() ?? '') ?? 0;
      var stale =
          notificationId <= 0 || conversationId.isEmpty || messageId.isEmpty;

      if (!stale && kind == 'direct') {
        final message = await store.messageById(messageId);
        stale = message == null ||
            message.senderId != conversationId ||
            message.recipientId != store.deviceId ||
            await store.isBlockedPeer(message.senderId) ||
            !(await store.unreadMessagesForConversation(conversationId))
                .any((candidate) => candidate.id == messageId);
        if (!stale) activeDirectConversations.add(conversationId);
      } else if (!stale && kind == 'group') {
        final message = await store.groupMessageById(messageId);
        final members = message == null
            ? <Map<String, dynamic>>[]
            : await store.groupMembers(conversationId);
        stale = message == null ||
            message.groupId != conversationId ||
            await store.isBlockedPeer(message.senderId) ||
            !members
                .any((row) => row['device_id']?.toString() == store.deviceId) ||
            !members.any(
                (row) => row['device_id']?.toString() == message.senderId) ||
            !(await store.unreadGroupMessages(conversationId))
                .any((candidate) => candidate.id == messageId);
        if (!stale) activeGroupConversations.add(conversationId);
      }

      if (stale) {
        await platform.cancelNotification(notificationId);
        await store.removeNotificationStateForMessage(messageId);
      }
    }

    for (final id in activeDirectConversations) {
      await _refreshDirectSummary(id);
    }
    for (final id in activeGroupConversations) {
      await _refreshGroupSummary(id);
    }

    await store.cleanupNotificationState();
  }

  Future<void> clearAll() async {
    if (_disposed) return;
    _lastAlertAt.clear();
    _globalAlertTimes.clear();
    await store.clearNotificationState();
    await platform.cancelAllMessages();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cleanupTimer?.cancel();
    await _messageSubscription?.cancel();
    await _groupSubscription?.cancel();
    await _callSubscription?.cancel();
    await _deletedMessageSubscription?.cancel();
    await _actionSubscription?.cancel();
    await platform.dispose();
    await _openRequests.close();
  }
}

final class AttachmentTarget {
  final String id;
  final String path;

  const AttachmentTarget(this.id, this.path);
}
