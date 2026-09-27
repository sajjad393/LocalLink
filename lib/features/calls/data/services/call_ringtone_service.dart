import 'package:locallink/features/calls/data/platform/call_ringtone_platform_service.dart';

/// Owns the lifecycle of the single LocalLink incoming-call ringtone.
class CallRingtoneService {
  final CallRingtonePlatformService platform;
  String? _activeCallId;
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
