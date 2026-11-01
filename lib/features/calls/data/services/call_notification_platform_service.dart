import 'dart:async';

import 'package:flutter/services.dart';

import 'package:locallink/features/calls/data/models/call_notification_action.dart';

/// Android incoming-call notification boundary. It never performs call
/// signaling itself; notification actions are delivered back to CallSessionManager,
/// which validates the active CallSession before acting on them.
class CallNotificationPlatformService {
  static const MethodChannel _channel = MethodChannel('locallink/call_notifications');
  static const EventChannel _actionChannel = EventChannel('locallink/call_notification_actions');

  final StreamController<CallNotificationAction> _actions =
      StreamController<CallNotificationAction>.broadcast();
  StreamSubscription<dynamic>? _nativeActionSub;
  bool _disposed = false;

  CallNotificationPlatformService() {
    _nativeActionSub = _actionChannel.receiveBroadcastStream().listen(
      (event) {
        if (_disposed || event is! Map) return;
        try {
          _actions.add(CallNotificationAction.fromMap(event));
        } catch (_) {
          // Invalid notification intents are deliberately ignored.
        }
      },
      onError: (_) {},
    );
  }

  Stream<CallNotificationAction> get actions => _actions.stream;

  Future<void> requestPermission() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } catch (_) {}
  }

  Future<void> showIncoming({
    required String callId,
    required String callerId,
    required String callerName,
  }) async {
    if (_disposed || callId.isEmpty || callerId.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('showIncoming', {
        'call_id': callId,
        'caller_id': callerId,
        'caller_name': callerName.trim().isEmpty ? callerId : callerName.trim(),
      });
    } catch (_) {}
  }

  /// Bundle 179 (2): the Accept tapped on the notification, kept by Android
  /// for 60 s (survives the screen being rebuilt). Null = none / too old.
  Future<SavedCallAccept?> acceptedCall() async {
    if (_disposed) return null;
    try {
      final raw =
          await _channel.invokeMethod<Map<Object?, Object?>>('acceptedCall');
      return SavedCallAccept.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  /// Bundle 179 (2): forget the saved Accept (applied, rejected or too old).
  Future<void> clearAcceptedCall(String callId) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('clearAcceptedCall', {'call_id': callId});
    } catch (_) {}
  }

  Future<void> cancelIncoming() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('cancelIncoming');
    } catch (_) {}
  }

  /// Bundle 146: keep the call UI above the lock screen while a call is live.
  /// [turnScreenOn] is only true while an incoming call rings.
  Future<void> setCallLockScreen(
      {required bool show, required bool turnScreenOn}) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('setCallLockScreen', {
        'show': show,
        'turn_screen_on': turnScreenOn,
      });
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } catch (_) {}
    await _nativeActionSub?.cancel();
    await _actions.close();
  }
}

/// Bundle 179 (2): a notification Accept saved on the Android side.
class SavedCallAccept {
  const SavedCallAccept({
    required this.callId,
    required this.callerId,
    required this.remaining,
  });

  final String callId;
  final String callerId;

  /// Time left of the 60 s.
  final Duration remaining;

  CallNotificationAction get action => CallNotificationAction(
      type: CallNotificationActionType.accept,
      callId: callId,
      callerId: callerId);

  static SavedCallAccept? fromMap(Map<Object?, Object?>? raw) {
    if (raw == null) return null;
    final callId = raw['call_id']?.toString().trim() ?? '';
    final callerId = raw['caller_id']?.toString().trim() ?? '';
    final ms = int.tryParse(raw['remaining_ms']?.toString() ?? '') ?? 0;
    if (callId.isEmpty || callerId.isEmpty || ms <= 0) return null;
    return SavedCallAccept(
        callId: callId,
        callerId: callerId,
        remaining: Duration(milliseconds: ms.clamp(0, 60000)));
  }
}
