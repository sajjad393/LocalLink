import 'package:shared_preferences/shared_preferences.dart';

enum NotificationPrivacyMode { full, senderOnly, hidden }

final class NotificationPreferences {
  static const _privacyKey = 'notification_privacy_mode';

  NotificationPrivacyMode privacyMode = NotificationPrivacyMode.full;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_privacyKey)) {
      case 'sender_only':
        privacyMode = NotificationPrivacyMode.senderOnly;
      case 'hidden':
        privacyMode = NotificationPrivacyMode.hidden;
      default:
        privacyMode = NotificationPrivacyMode.full;
    }
  }

  Future<void> setPrivacyMode(NotificationPrivacyMode mode) async {
    privacyMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_privacyKey, switch (mode) {
      NotificationPrivacyMode.full => 'full',
      NotificationPrivacyMode.senderOnly => 'sender_only',
      NotificationPrivacyMode.hidden => 'hidden',
    });
  }
}
