import 'package:flutter/services.dart';

/// Android bridge for LAN-routed call media. Audio and video are handled by the
/// native transport service using the local transport/session security provided by the native networking layer.
class CallMediaPlatformService {
  static const MethodChannel _channel = MethodChannel('locallink/call_media');

  /// Bundle 159: [voiceKey] (base64, 32 bytes) locks the call sound so
  /// phones in the middle can't hear it. Memory only; never logged.
  Future<void> start({required String callId, required String peerId, String codec = 'auto', String? voiceKey}) async {
    await _channel.invokeMethod('start', {
      'call_id': callId,
      'peer_id': peerId,
      'codec': codec,
      if (voiceKey != null && voiceKey.isNotEmpty) 'voice_key': voiceKey,
    });
  }

  Future<Map<String, dynamic>> startVideo({required String callId, required String peerId, bool enableCamera = true}) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('video_start', {
      'call_id': callId, 'peer_id': peerId, 'enable_camera': enableCamera,
    }) ?? const {};
    return Map<String, dynamic>.from(raw);
  }


  Future<List<String>> supportedCodecs() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('supported_codecs') ?? const [];
      final codecs = raw.map((value) => value.toString().trim().toLowerCase()).where((value) => value.isNotEmpty).toSet().toList();
      return codecs.isEmpty ? const ['pcm_s16le'] : codecs;
    } catch (_) {
      return const ['pcm_s16le'];
    }
  }

  Future<void> setMuted({required String callId, required bool muted}) async {
    await _channel.invokeMethod('mute', {'call_id': callId, 'muted': muted});
  }

  Future<void> setVideoEnabled({required String callId, required bool enabled}) async {
    await _channel.invokeMethod('video_enabled', {'call_id': callId, 'enabled': enabled});
  }

  Future<void> switchCamera({required String callId}) async {
    await _channel.invokeMethod('video_switch_camera', {'call_id': callId});
  }

  Future<void> stopVideo({required String callId}) async {
    await _channel.invokeMethod('video_stop', {'call_id': callId});
  }

  Future<void> stop({required String callId}) async {
    try { await _channel.invokeMethod('video_stop', {'call_id': callId}); } catch (_) {}
    await _channel.invokeMethod('stop', {'call_id': callId});
  }

  /// Bundle 266 (B2): this call may talk through the server when there is
  /// no nearby way (the native side still prefers any nearby way).
  Future<void> setServerVoice({required String callId, required bool on}) async {
    await _channel.invokeMethod('server_voice', {'call_id': callId, 'on': on});
  }

  /// Bundle 266 (B2): locked voice pieces that came through the server
  /// (a small batch; the native side opens them with the call key).
  Future<void> serverVoiceIn({required String callId, required String senderId, required List<String> voices}) async {
    await _channel.invokeMethod('server_voice_in', {'call_id': callId, 'sender_id': senderId, 'voices': voices});
  }

  static const EventChannel _serverVoiceOut = EventChannel('locallink/call_voice_server');

  /// Bundle 266 (B2): locked voice pieces to send through the server
  /// ({call_id, voices}). Listened to only while a call talks that way.
  Stream<Map<String, dynamic>> serverVoiceOut() => _serverVoiceOut
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => Map<String, dynamic>.from(e as Map));

  Future<Map<String, dynamic>> stats({required String callId}) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('stats', {'call_id': callId}) ?? const {};
    return Map<String, dynamic>.from(raw);
  }
}
