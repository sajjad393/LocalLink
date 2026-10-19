import 'package:locallink/features/calls/data/platform/call_ringtone_platform_service.dart';

/// Owns the lifecycle of the local call tones: the incoming-call ringtone and
/// the dialer-side ringback ("calling…" tone).
class CallRingtoneService {
  final CallRingtonePlatformService platform;
  String? _activeCallId;
  String? _activeRingbackCallId;
  bool _disposed = false;

  CallRingtoneService({required this.platform});

  Future<void> start(String callId) async {
    if (_disposed || callId.isEmpty || _activeCallId == callId) return;
    if (_activeCallId != null && _activeCallId != callId) {
      await stop();
    }
    _activeCallId = callId;
    try {
      await platform.start(callId: callId);
    } catch (_) {
      _activeCallId = null;
      rethrow;
    }
  }

  Future<void> startRingback(String callId) async {
    if (_disposed || callId.isEmpty || _activeRingbackCallId == callId) return;
    if (_activeRingbackCallId != null && _activeRingbackCallId != callId) {
      await stopRingback();
    }
    _activeRingbackCallId = callId;
    await platform.startRingback(callId: callId);
  }

  Future<void> stopRingback() async {
    _activeRingbackCallId = null;
    await platform.stopRingback();
  }

  Future<void> stop() async {
    _activeCallId = null;
    await platform.stop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _activeCallId = null;
    await platform.dispose();
  }
}
