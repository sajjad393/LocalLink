import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/transport/call_transport.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/calls/data/transport/native_mesh_call_transport.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

/// Resolves the single local call media transport. LAN and Wi-Fi Direct are
/// physical links; the same native transport also supports multi-hop mesh.
final class CallTransportFactory {
  final PeerTransportContract mesh;
  final NativeMeshCallTransport nativeMesh;

  CallTransportFactory({
    required this.mesh,
    required CallMediaPlatformService media,
    required CallAudioPlatformService audio,
  }) : nativeMesh = NativeMeshCallTransport(mesh: mesh, media: media, audio: audio);

  Future<void> ensureReady() async {
    if (mesh.isStarted) return;
    try {
      await mesh.resume();
    } catch (error) {
      throw StateError('local native transport could not be resumed: $error');
    }
    if (!mesh.isStarted) {
      throw StateError('local native transport is unavailable');
    }
  }

  CallTransport resolve({required CallTransportMode requested}) => nativeMesh;

  Future<void> dispose() async => nativeMesh.dispose();
}
