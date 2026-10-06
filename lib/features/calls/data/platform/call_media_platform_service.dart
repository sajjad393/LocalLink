import 'package:flutter/services.dart';

/// Android bridge for LAN-routed call media. Audio and video are handled by the
/// native transport service using the local transport/session security provided by the native networking layer.
class CallMediaPlatformService {
  static const MethodChannel _channel = MethodChannel('locallink/call_media');

  Future<void> start({required String callId, required String peerId, String codec = 'auto'}) async {
    await _channel.invokeMethod('start', {'call_id': callId, 'peer_id': peerId, 'codec': codec});
  }

  Future<Map<String, dynamic>> startVideo({required String callId, required String peerId}) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('video_start', {
      'call_id': callId, 'peer_id': peerId,
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

  Future<Map<String, dynamic>> stats({required String callId}) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('stats', {'call_id': callId}) ?? const {};
    return Map<String, dynamic>.from(raw);
  }
}
