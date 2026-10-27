import 'dart:async';

import 'package:flutter/services.dart';

import 'package:locallink/core/notifications/local_link_notification_service.dart';

/// Bundle 101 — dashboard permission sequencer (user-specified policy).
///
/// Rules:
///  * NO pre-info/rationale dialog anywhere — the native system dialog only.
///  * Fire order at dashboard entry: microphone -> 5s pause -> Nearby devices
///    -> 5s pause -> Notifications -> 5s pause -> Background (battery
///    optimization exemption, Bundle 121). Each step is skipped when already
///    granted, and each native prompt fires even if the previous one is still
///    open (Android serializes them).
///  * Anything still missing after the chain re-asks every 10 minutes while
///    the app stays open, and again on the next dashboard entry. Once granted
///    it is never asked again until revoked from system settings.
///  * Bundle 121 note: the "background" step asks the system battery-exemption
///    dialog ("Let LocalLink always run in the background?"). The existing
///    once-per-install splash prompt in MainActivity.onCreate stays as the
///    very first ask; this step is what makes a denial recoverable instead of
///    silent forever, matching the same policy as mic/nearby/notifications.
///
/// Note: Android itself may stop rendering a dialog after about two denials
/// of the same permission; from then on only Settings can heal it. That is a
/// platform rule, not an app decision.
class AppPermissionGate {
  static const _channel = MethodChannel('locallink/permissions');
  static const _order = ['microphone', 'nearby', 'notifications', 'background'];
  static const _gap = Duration(seconds: 5);
  static const _reaskAfter = Duration(minutes: 10);

  static bool _chainRunning = false;
  static Timer? _reaskTimer;

  /// Entry hook kept with its historic signature so the dashboard call site
  /// stays one line; [notifications] is retained for API stability.
  static void ensureRequiredOnDashboardEntry(
    Object context, // legacy BuildContext arg — sequencing is context-free now
    LocalLinkNotificationService notifications,
  ) {
    unawaited(_runChain());
  }

  static Future<void> _runChain() async {
    if (_chainRunning) return;
    _chainRunning = true;
    _reaskTimer?.cancel();
    try {
      for (final name in _order) {
        if (await _granted(name)) continue;
        await _request(name); // native dialog only, never anything custom
        await Future<void>.delayed(_gap);
      }
      final remaining = await _missing();
      if (remaining.isNotEmpty) {
        _reaskTimer = Timer(_reaskAfter, () {
          _chainRunning = false; // let the chain re-enter
          unawaited(_runChain());
        });
      }
    } finally {
      if (_reaskTimer == null || !_reaskTimer!.isActive) _chainRunning = false;
    }
  }

  static Future<Set<String>> _missing() async {
    final missing = <String>{};
    for (final name in _order) {
      if (!await _granted(name)) missing.add(name);
    }
    return missing;
  }

  static Future<bool> _granted(String name) async {
    try {
      final raw =
          await _channel.invokeMapMethod<String, bool>('granted', {'name': name});
      return raw?['granted'] == true;
    } catch (_) {
      return false; // hiccup: treat as missing — the 10-min loop keeps healing
    }
  }

  static Future<void> _request(String name) async {
    try {
      await _channel.invokeMethod<void>('request', {'name': name});
    } catch (_) {}
  }
}
