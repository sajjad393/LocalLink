import 'dart:convert';

import 'package:flutter/services.dart';

/// Bundle 176 (3): hands a ringing call from one app engine to the next.
///
/// The no-screen engine (app closed) rings a call; when the user opens the
/// app (or taps Accept) that engine stops and the app engine starts. The
/// caller stopped re-sending its invite once it heard "ringing", so the
/// invite is kept natively in memory (60 s, never on disk) and the next
/// engine takes it. The same works the other way (app swiped away while
/// ringing).
class CallHandoverPlatformService {
  const CallHandoverPlatformService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('locallink/call_handover');

  final MethodChannel _channel;

  Future<void> park(String callId, Map<String, dynamic> invite) async {
    try {
      await _channel.invokeMethod<void>(
          'park', {'call_id': callId, 'invite': jsonEncode(invite)});
    } catch (_) {
      // Older native side / tests: no hand-over.
    }
  }

  Future<Map<String, dynamic>?> take() async {
    try {
      final raw = await _channel.invokeMethod<String>('take');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String callId) async {
    try {
      await _channel.invokeMethod<void>('clear', {'call_id': callId});
    } catch (_) {}
  }
}
