import 'dart:async';

import 'package:flutter/services.dart';

import 'package:locallink/core/notifications/notification_action.dart';

/// Native notification boundary. It never sends a message or call itself.
final class LocalLinkNotificationPlatform {
  static const MethodChannel _channel =
      MethodChannel('locallink/notifications');
  static const EventChannel _actionsChannel =
      EventChannel('locallink/notification_actions');

  // Bundle 151: a tap that starts the app arrives before the notification
  // service listens. Keep it (only the newest few) and hand it over on listen.
  late final StreamController<LocalLinkNotificationAction> _actions =
      StreamController<LocalLinkNotificationAction>.broadcast(
          onListen: _flushEarly);
  final List<LocalLinkNotificationAction> _early =
      <LocalLinkNotificationAction>[];
  StreamSubscription<dynamic>? _nativeActionSubscription;
  bool _disposed = false;

  // Bundle 307 (C1): taps on a Get chat request card (the request id). A tap
  // that starts the app is kept until someone listens.
  late final StreamController<String> _chatRequestTaps307 =
      StreamController<String>.broadcast(onListen: _flushTaps307);
  final List<String> _earlyTaps307 = <String>[];

  Stream<String> get chatRequestTaps307 => _chatRequestTaps307.stream;

  void _flushTaps307() {
    if (_earlyTaps307.isEmpty) return;
    final queued = List<String>.of(_earlyTaps307);
    _earlyTaps307.clear();
    scheduleMicrotask(() {
      for (final id in queued) {
        if (!_chatRequestTaps307.isClosed) _chatRequestTaps307.add(id);
      }
    });
  }

  LocalLinkNotificationPlatform() {
    _nativeActionSubscription = _actionsChannel.receiveBroadcastStream().listen(
      (event) {
        if (_disposed || event is! Map) return;
        if (event['action'] == 'open_chat_request') {
          final id = event['request_id']?.toString().trim() ?? '';
          if (id.isEmpty) return;
          if (_chatRequestTaps307.hasListener) {
            _chatRequestTaps307.add(id);
          } else {
            _earlyTaps307.add(id);
            if (_earlyTaps307.length > 4) _earlyTaps307.removeAt(0);
          }
          return;
        }
        try {
          final action = LocalLinkNotificationAction.fromMap(event);
          if (_actions.hasListener) {
            _actions.add(action);
          } else {
            _early.add(action);
            if (_early.length > 8) _early.removeAt(0);
          }
        } catch (_) {
          // Invalid or stale notification intents are ignored at the boundary.
        }
      },
      onError: (_) {},
    );
  }

  Stream<LocalLinkNotificationAction> get actions => _actions.stream;

  void _flushEarly() {
    if (_early.isEmpty) return;
    final queued = List<LocalLinkNotificationAction>.of(_early);
    _early.clear();
    // After the listener is attached.
    scheduleMicrotask(() {
      for (final action in queued) {
        if (!_actions.isClosed) _actions.add(action);
      }
    });
  }

  Future<void> initialize() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('initialize');
    } catch (_) {}
  }

  Future<void> requestPermission() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } catch (_) {}
  }

  Future<bool> notificationsEnabled() async {
    if (_disposed) return false;
    try {
      return await _channel.invokeMethod<bool>('notificationsEnabled') ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<void> openSystemSettings() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {}
  }

  Future<void> showMessage({
    required int notificationId,
    required String conversationType,
    required String conversationId,
    required String messageId,
    required String senderId,
    required String recipientId,
    required String title,
    required String body,
    required String summary,
    required String publicTitle,
    required String publicBody,
    required String initials,
    String? avatarPath,
    String? imagePath,
    String? attachmentId,
    required int unreadCount,
    required bool silent,
    required int visibility,
  }) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('showMessage', {
        'notification_id': notificationId,
        'conversation_type': conversationType,
        'conversation_id': conversationId,
        'message_id': messageId,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'title': title,
        'body': body,
        'summary': summary,
        'public_title': publicTitle,
        'public_body': publicBody,
        'initials': initials,
        'avatar_path': avatarPath,
        'image_path': imagePath,
        'attachment_id': attachmentId,
        'unread_count': unreadCount,
        'silent': silent,
        'visibility': visibility,
      });
    } catch (_) {}
  }

  Future<void> showSummary({
    required int notificationId,
    required String conversationType,
    required String conversationId,
    required String title,
    required String body,
    required bool silent,
    required int visibility,
  }) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('showSummary', {
        'notification_id': notificationId,
        'conversation_type': conversationType,
        'conversation_id': conversationId,
        'title': title,
        'body': body,
        'silent': silent,
        'visibility': visibility,
      });
    } catch (_) {}
  }

  Future<void> showSystem({
    required int notificationId,
    required String title,
    required String body,
    required bool silent,
  }) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('showSystem', {
        'notification_id': notificationId,
        'title': title,
        'body': body,
        'silent': silent,
      });
    } catch (_) {}
  }

  /// Bundle 177 (7.8): "X added you as a friend" with Remove / Block.
  Future<void> showFriendAdded({
    required int notificationId,
    required String userId,
    required String deviceId,
    required String recipientId,
    required String name,
  }) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('showFriendAdded', {
        'notification_id': notificationId,
        'user_id': userId,
        'device_id': deviceId,
        'recipient_id': recipientId,
        'name': name,
      });
    } catch (_) {}
  }

  /// Bundle 196 (12b): "Ali wants to add you" with Accept / Decline.
  Future<void> showFriendRequest({
    required int notificationId,
    required String userId,
    required String deviceId,
    required String recipientId,
    required String name,
  }) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('showFriendRequest', {
        'notification_id': notificationId,
        'user_id': userId,
        'device_id': deviceId,
        'recipient_id': recipientId,
        'name': name,
      });
    } catch (_) {}
  }

  /// Bundle 196 (12b): "sumaira accepted your request" (tap opens the chat).
  Future<void> showFriendAccepted({
    required int notificationId,
    required String deviceId,
    required String recipientId,
    required String name,
  }) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('showFriendAccepted', {
        'notification_id': notificationId,
        'device_id': deviceId,
        'recipient_id': recipientId,
        'name': name,
      });
    } catch (_) {}
  }

  /// Bundle 196: friend notices are posted without the message tag.
  Future<void> cancelFriendNotice(int notificationId) async {
    if (_disposed || notificationId <= 0) return;
    try {
      await _channel.invokeMethod<void>('cancelFriend', {
        'notification_id': notificationId,
      });
    } catch (_) {}
  }

  Future<void> cancelNotification(int notificationId) async {
    if (_disposed) return;
    if (notificationId <= 0) return;
    try {
      await _channel.invokeMethod<void>('cancel', {
        'notification_id': notificationId,
      });
    } catch (_) {}
  }

  Future<void> cancelAllMessages() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('cancelMessages');
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _channel.invokeMethod<void>('cancelMessages');
    } catch (_) {}
    await _nativeActionSubscription?.cancel();
    await _actions.close();
    await _chatRequestTaps307.close();
  }
}
