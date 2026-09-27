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

  Future<void> cancelIncoming() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('cancelIncoming');
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
