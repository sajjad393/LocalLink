import 'dart:async';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/security/identity_trust_service.dart';
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
  final IdentityCryptoService crypto;
  final IdentityTrustService identityTrust;

  NativeMeshCallTransport({
    required this.mesh,
    required this.media,
    required this.audio,
    required this.crypto,
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
    if (!mesh.isStarted) throw StateError('local mesh transport is unavailable');
    await mesh.send(recipientId: recipientId, payload: {
      ...payload,
      'direct': true,
      'mesh_call': true,
    });
  }

  @override
  Future<void> start(CallSession session) async {
    if (!mesh.isStarted) throw StateError('local mesh transport is unavailable');
    if (!await identityTrust.canEstablishLocalCall(session.peerId)) {
      throw StateError('Peer identity is changed or revoked; local call is blocked');
    }
    final publicKeys = await crypto.cachedPeerPublicKeys();
    final publicKey = publicKeys[session.peerId];
    if (publicKey == null || publicKey.isEmpty) {
      throw StateError('Peer identity key is unavailable for this call');
    }
    final mediaKey = await crypto.deriveCallMediaKey(
      peerId: session.peerId,
      peerPublicKey: publicKey,
      callId: session.id,
    );
    _callId = session.id;
    _active = true;
    try {
      await audio.setSpeakerphoneOn(session.speakerOn);
      await media.start(callId: session.id, peerId: session.peerId, mediaKey: mediaKey, codec: session.mediaCodec);
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
  Future<Map<String, dynamic>> startVideo(CallSession session) async {
    if (!await identityTrust.canEstablishLocalCall(session.peerId)) {
      throw StateError('Peer identity is changed or revoked; local video is blocked');
    }
    final publicKeys = await crypto.cachedPeerPublicKeys();
    final publicKey = publicKeys[session.peerId];
    if (publicKey == null || publicKey.isEmpty) {
      throw StateError('Peer identity key is unavailable for this call');
    }
    final mediaKey = await crypto.deriveCallMediaKey(
      peerId: session.peerId,
      peerPublicKey: publicKey,
      callId: session.id,
    );
    return media.startVideo(callId: session.id, peerId: session.peerId, mediaKey: mediaKey);
  }

  @override
  Future<void> switchCamera(CallSession session) => media.switchCamera(callId: session.id);

  @override
  Future<void> stopVideo(CallSession session) => media.stopVideo(callId: session.id);

  @override
  Future<void> stop(CallSession session) async {
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
