import 'package:flutter/services.dart';

/// Android ringtone boundary for incoming LocalLink calls.
///
/// Call signaling/state remains in CallSessionManager/CallBloc. This adapter only
/// controls the local incoming-call ringtone and Android audio focus.
class CallRingtonePlatformService {
  static const MethodChannel _channel = MethodChannel('locallink/call_ringtone');
  String? _activeCallId;
  bool _disposed = false;

  Future<void> start({required String callId}) async {
    if (_disposed || callId.isEmpty) return;
    if (_activeCallId == callId) return;
    _activeCallId = callId;
    try {
      await _channel.invokeMethod<void>('start', {'call_id': callId});
    } catch (_) {
      _activeCallId = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    _activeCallId = null;
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<void> dispose() async {
    _disposed = true;
    _activeCallId = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
