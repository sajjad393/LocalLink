import 'package:flutter/material.dart';

import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/core/notifications/notification_preferences.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final LocalLinkNotificationService notifications;

  const NotificationSettingsScreen({
    super.key,
    required this.notifications,
  });

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool? _enabled;
  late NotificationPrivacyMode _privacyMode;

  @override
  void initState() {
    super.initState();
    _privacyMode = widget.notifications.preferences.privacyMode;
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.notifications.platform.notificationsEnabled();
    if (!mounted) return;
    setState(() => _enabled = enabled);
  }

  Future<void> _changePrivacy(NotificationPrivacyMode mode) async {
    await widget.notifications.preferences.setPrivacyMode(mode);
    await widget.notifications.refreshNotifications();
    if (!mounted) return;
    setState(() => _privacyMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Android notifications'),
              subtitle: Text(
                _enabled == null
                    ? 'Checking permission…'
                    : _enabled!
                        ? 'Enabled'
                        : 'Disabled in Android settings',
              ),
              trailing: _enabled == false
                  ? TextButton(
                      onPressed: () async {
                        await widget.notifications.platform.requestPermission();
                        await widget.notifications.refreshPendingNotifications();
                        await _load();
                      },
                      child: const Text('Enable'),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Lock-screen privacy',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          RadioListTile<NotificationPrivacyMode>(
            value: NotificationPrivacyMode.full,
            groupValue: _privacyMode,
            onChanged: (mode) {
              if (mode != null) _changePrivacy(mode);
            },
            title: const Text('Show full content'),
            subtitle: const Text('Show sender and message preview'),
          ),
          RadioListTile<NotificationPrivacyMode>(
            value: NotificationPrivacyMode.senderOnly,
            groupValue: _privacyMode,
            onChanged: (mode) {
              if (mode != null) _changePrivacy(mode);
            },
            title: const Text('Show sender only'),
            subtitle: const Text('Hide message text on the lock screen'),
          ),
          RadioListTile<NotificationPrivacyMode>(
            value: NotificationPrivacyMode.hidden,
            groupValue: _privacyMode,
            onChanged: (mode) {
              if (mode != null) _changePrivacy(mode);
            },
            title: const Text('Hide sensitive content'),
            subtitle: const Text('Show only a generic LocalLink notification'),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Android channel controls'),
              subtitle: const Text(
                'Manage message, call, and system sounds, vibration, and importance in Android settings.',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => widget.notifications.platform.openSystemSettings(),
            ),
          ),
        ],
      ),
    );
  }
}
