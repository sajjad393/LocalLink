import 'dart:async';

import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/transport/call_transport.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

final class NativeMeshCallTransport implements CallTransport {
  final PeerTransportContract mesh;
  final CallMediaPlatformService media;
  final CallAudioPlatformService audio;
  final IdentityTrustService identityTrust;

  NativeMeshCallTransport({
    required this.mesh,
    required this.media,
    required this.audio,
    IdentityTrustService? identityTrust,
  }) : identityTrust = identityTrust ?? const IdentityTrustService();

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _meshSubscription;
  String? _callId;
  bool _active = false;

  @override
  CallTransportMode get mode => CallTransportMode.offlineMesh;

  @override
  bool get supportsVideo => true;

  @override
  bool get isActive => _active;

  @override
  Stream<Map<String, dynamic>> get events {
    _meshSubscription ??= mesh.events.listen((event) {
      final callId = event['call_id']?.toString();
      final current = _callId;
      final type = event['type']?.toString() ?? '';
      final relevant = type == 'message' ||
          type.startsWith('call_media_') ||
          type.startsWith('route_') ||
          type == 'mesh_forwarded' ||
          type == 'mesh_dropped';
      if (relevant && (current == null || callId == null || callId.isEmpty || callId == current)) {
        _events.add(Map<String, dynamic>.from(event));
      }
    });
    return _events.stream;
  }

  @override
  Future<void> sendControl({required String recipientId, required Map<String, dynamic> payload}) async {
    if (!mesh.isStarted) {
      try {
        await mesh.resume();
      } catch (_) {}
    }
    if (!mesh.isStarted) throw StateError('local native transport is unavailable');
    await mesh.send(recipientId: recipientId, payload: {
      ...payload,
      'direct': true,
      'mesh_call': true,
    });
  }

  @override
  Future<void> start(CallSession session) async {
    if (!mesh.isStarted) {
      try {
        await mesh.resume();
      } catch (_) {}
    }
    if (!mesh.isStarted) throw StateError('local native transport is unavailable');
    if (!await identityTrust.canEstablishLocalCall(session.peerId)) {
      throw StateError('Peer identity is changed or revoked; local call is blocked');
    }
    _callId = session.id;
    _active = true;
    try {
      await audio.setSpeakerphoneOn(session.speakerOn);
      await media.start(callId: session.id, peerId: session.peerId, codec: session.mediaCodec);
      // Bundle 146: one line per call so phone logs show the audio format.
      AppLogger.info('CALL_MEDIA_START',
          detail: 'call=${session.id} codec=${session.mediaCodec} rate=16000');
    } catch (_) {
      _active = false;
      _callId = null;
      rethrow;
    }
  }


  @override
  Future<Map<String, dynamic>> stats(CallSession session) => media.stats(callId: session.id);

  @override
  Future<void> setMuted(CallSession session, bool muted) =>
      media.setMuted(callId: session.id, muted: muted);

  @override
  Future<void> setVideoEnabled(CallSession session, bool enabled) =>
      media.setVideoEnabled(callId: session.id, enabled: enabled);

  @override
  Future<Map<String, dynamic>> startVideo(CallSession session,
      {bool enableCamera = true}) async {
    if (!await identityTrust.canEstablishLocalCall(session.peerId)) {
      throw StateError('Peer identity is changed or revoked; local video is blocked');
    }
    return media.startVideo(
        callId: session.id, peerId: session.peerId, enableCamera: enableCamera);
  }

  @override
  Future<void> switchCamera(CallSession session) => media.switchCamera(callId: session.id);

  @override
  Future<void> stopVideo(CallSession session) => media.stopVideo(callId: session.id);

  @override
  Future<void> stop(CallSession session) async {
    // Bundle 146: audio totals at the end of every call (played=0 means the
    // speaker never got a frame - the 142-145 Opus symptom).
    try {
      final stats = await media
          .stats(callId: session.id)
          .timeout(const Duration(milliseconds: 400));
      if (stats.isNotEmpty) {
        AppLogger.info('CALL_MEDIA_STATS',
            detail: 'call=${session.id} codec=${stats['codec']} '
                'send=${stats['send_codec'] ?? '-'} rx=${stats['rx_codec'] ?? '-'} '
                'fallback=${(stats['opus_fallback'] ?? '').toString().isEmpty ? '-' : stats['opus_fallback']} '
                'sent=${stats['sent_packets']} played=${stats['received_packets']} '
                'lost=${stats['lost_packets']} dropped=${stats['dropped_packets']}');
      }
    } catch (_) {}
    try {
      await media.stop(callId: session.id);
    } finally {
      try { await audio.clearCommunicationDevice(); } catch (_) {}
      _active = false;
      _callId = null;
    }
  }

  Future<void> dispose() async {
    await _meshSubscription?.cancel();
    _meshSubscription = null;
    await _events.close();
  }
}
