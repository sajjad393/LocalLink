import 'package:flutter/material.dart';

import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/core/notifications/notification_preferences.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/l10n/l10n.dart';

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

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool? _enabled;
  late NotificationPrivacyMode _privacyMode;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _privacyMode = widget.notifications.preferences.privacyMode;
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await widget.notifications.platform.notificationsEnabled();
      if (!mounted) return;
      setState(() => _enabled = enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _enabled = null);
    }
  }

  Future<void> _requestPermission() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.notifications.platform.requestPermission();
      await widget.notifications.refreshPendingNotifications();
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePrivacy(NotificationPrivacyMode mode) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.notifications.preferences.setPrivacyMode(mode);
      await widget.notifications.refreshNotifications();
      if (!mounted) return;
      setState(() => _privacyMode = mode);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(L.t.notifications)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LocalLinkSpacing.screen,
          LocalLinkSpacing.md,
          LocalLinkSpacing.screen,
          LocalLinkSpacing.xxxl,
        ),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Icon(Icons.notifications_outlined),
              ),
              title: Text(L.t.notifications),
              subtitle: Text(
                _enabled == null
                    ? L.t.checkingAndroidPermission
                    : _enabled!
                        ? L.t.messageAndCallAlertsAreEnabled
                        : L.t.notificationsAreDisabledInAndroidSettings,
              ),
              trailing: _enabled == false
                  ? FilledButton.tonal(
                      onPressed: _busy ? null : _requestPermission,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(L.t.enable),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: LocalLinkSpacing.xl),
          Text(L.t.lockScreenPrivacy, style: theme.textTheme.titleSmall),
          const SizedBox(height: LocalLinkSpacing.xs),
          Text(
            L.t.chooseHowMuchMessageDetailAppears,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          _privacyTile(
            context,
            value: NotificationPrivacyMode.full,
            title: L.t.showFullContent,
            subtitle: L.t.showSenderAndMessagePreview,
          ),
          _privacyTile(
            context,
            value: NotificationPrivacyMode.senderOnly,
            title: L.t.showSenderOnly,
            subtitle: L.t.hideMessageTextOnTheLock,
          ),
          _privacyTile(
            context,
            value: NotificationPrivacyMode.hidden,
            title: L.t.hideSensitiveContent,
            subtitle: L.t.showAGenericLinkupNotification,
          ),
          const SizedBox(height: LocalLinkSpacing.lg),
          Text(L.t.androidControls, style: theme.textTheme.titleSmall),
          const SizedBox(height: LocalLinkSpacing.xs),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: Text(L.t.notificationChannels),
              subtitle: Text(
                L.t.manageSoundsVibrationAndImportanceIn,
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => widget.notifications.platform.openSystemSettings(),
            ),
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          LocalLinkInlineInfo(
            icon: Icons.lock_outline,
            message: L.t.linkupKeepsNotificationContentSeparateFrom,
          ),
        ],
      ),
    );
  }

  Widget _privacyTile(
    BuildContext context, {
    required NotificationPrivacyMode value,
    required String title,
    required String subtitle,
  }) {
    return Card(
      child: RadioListTile<NotificationPrivacyMode>(
        value: value,
        groupValue: _privacyMode,
        onChanged: _busy ? null : (mode) {
          if (mode != null) _changePrivacy(mode);
        },
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
