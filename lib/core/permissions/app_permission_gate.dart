import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locallink/core/notifications/local_link_notification_service.dart';

/// Centralized, once-managed notification-permission gate for the dashboard.
///
/// Rules (per the permission playbook):
///  * The ACTUAL system state is always re-verified — never trust that the
///    request was granted just because the runtime dialog was launched.
///  * The rationale dialog shows at most once per app start AND once per
///    install; refreshing/re-entering the dashboard never re-nags the user.
///  * A pre-Android-13 device simply returns "enabled" from the platform
///    channel, so nothing is ever shown there (POST_NOTIFICATIONS is not a
///    runtime permission below API 33).
///  * Denial does not block any other dashboard feature; the user can grant
///    later from Settings -> Notifications.
class AppPermissionGate {
  static const _prefsKey = 'permissions.notifications.asked.v1';

  static bool _inFlightThisSession = false;

  static Future<void> ensureNotificationsOnDashboardEntry(
    BuildContext context,
    LocalLinkNotificationService notifications,
  ) async {
    if (_inFlightThisSession) return;
    _inFlightThisSession = true;
    try {
      // Verify the real state first — on Android < 13 the channel reports
      // enabled, so this is a no-op there by design.
      if (await notifications.platform.notificationsEnabled()) {
        // State healed (granted elsewhere or by an earlier request): free
        // the flag so a future revoke gets asked once again.
        unawaitedFlag(clear: true);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsKey) == true) return; // asked once already
      if (!context.mounted) return;
      final wantsGrant = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.notifications_active_outlined),
          title: const Text('Allow notifications'),
          content: const Text(
            'LocalLink alerts you about new messages and incoming calls, '
            'even while the app is in the background. Without this '
            'permission you may miss incoming calls.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      await prefs.setBool(_prefsKey, true); // never re-ask on this install
      if (wantsGrant == true) {
        await notifications.platform.requestPermission();
      }
      // Re-verify the actual state — the request launch means nothing.
      final grantedNow = await notifications.platform.notificationsEnabled();
      if (!grantedNow && context.mounted) {
        _inFlightThisSession = false; // dialog is over; do not force-repeat
        return;
      }
    } finally {
      _inFlightThisSession = true; // holds the no-repeat contract for the session
    }
  }

  static Future<void> unawaitedFlag({bool clear = false}) async {
    if (!clear) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
