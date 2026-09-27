import 'package:locallink/core/notifications/notification_action.dart';

/// Central policy used by both direct and group notifications.
final class LocalLinkNotificationPolicy {
  bool _appResumed = true;
  String? _activeDirectConversationId;
  String? _activeGroupConversationId;
  bool _callIsRinging = false;
  bool _callIsActive = false;

  void setAppLifecycleResumed(bool resumed) => _appResumed = resumed;

  void setActiveDirectConversation(String? id) {
    _activeDirectConversationId = id?.trim().isEmpty == true ? null : id?.trim();
  }

  void setActiveGroupConversation(String? id) {
    _activeGroupConversationId = id?.trim().isEmpty == true ? null : id?.trim();
  }

  void setCallState({required bool ringing, required bool active}) {
    _callIsRinging = ringing;
    _callIsActive = active;
  }

  bool shouldNotifyDirect(String conversationId) {
    if (!_appResumed) return true;
    if (_activeDirectConversationId == conversationId) return false;
    return true;
  }

  bool shouldNotifyGroup(String conversationId) {
    if (!_appResumed) return true;
    if (_activeGroupConversationId == conversationId) return false;
    return true;
  }

  bool get shouldBeSilent {
    return _callIsRinging || _callIsActive;
  }

  String? get activeDirectConversationId => _activeDirectConversationId;
  String? get activeGroupConversationId => _activeGroupConversationId;

  NotificationConversationType conversationTypeFor(bool group) =>
      group ? NotificationConversationType.group : NotificationConversationType.direct;
}
