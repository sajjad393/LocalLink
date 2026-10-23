import 'package:flutter/services.dart';

/// Bundle 94: thin wrapper over the native batched permission channel.
/// The native side is the single source of truth for verdicts (it re-checks
/// after every prompt — a launched dialog never counts as granted).
class PermissionGate {
  static const _channel = MethodChannel('locallink/permissions');

  /// name -> {granted: bool, can_request: bool}
  static Future<Map<String, Map<String, bool>>> statuses() async {
    final raw =
        await _channel.invokeMapMethod<String, Map<dynamic, dynamic>>('status');
    return (raw ?? const {}).map(
      (k, v) => MapEntry(k, (v ?? const {}).map(
            (tk, tv) => MapEntry(tk.toString(), tv == true),
          )),
    );
  }

  /// Requests the given names (subset of microphone/camera/nearby/
  /// notifications) in ONE system batch, then returns the re-verified map.
  static Future<Map<String, Map<String, bool>>> request(
      List<String> names) async {
    final raw = await _channel
        .invokeMapMethod<String, Map<dynamic, dynamic>>('request', {
      'permissions': names,
    });
    return (raw ?? const {}).map(
      (k, v) => MapEntry(k, (v ?? const {}).map(
            (tk, tv) => MapEntry(tk.toString(), tv == true),
          )),
    );
  }

  static Future<void> openSettings() =>
      _channel.invokeMethod<void>('openSettings');

  static bool granted(Map<String, Map<String, bool>> m, String name) =>
      m[name]?['granted'] == true;

  /// DECISION RULE (pinned by test/permission_gate_rule_test.dart): the gate
  /// appears whenever a REQUIRED permission is missing; camera/notifications
  /// are always optional so they never block the dashboard alone.
  static const requiredNames = ['microphone', 'nearby'];
  static const optionalNames = ['camera', 'notifications'];

  static bool requiredSatisfied(Map<String, Map<String, bool>> statuses) =>
      requiredNames.every((n) => granted(statuses, n));
}
