import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';

/// Generic call media/control boundary used by LocalLink local transports.
/// LAN, Wi-Fi Direct, and multi-hop mesh routing are resolved below this
/// abstraction; the call state machine remains transport-agnostic.
abstract interface class CallTransport {
  CallTransportMode get mode;
  bool get supportsVideo;
  bool get isActive;
  Stream<Map<String, dynamic>> get events;

  Future<void> start(CallSession session);

  Future<void> sendControl({required String recipientId, required Map<String, dynamic> payload});

  Future<Map<String, dynamic>> stats(CallSession session);

  Future<void> setMuted(CallSession session, bool muted);

  Future<void> setVideoEnabled(CallSession session, bool enabled);

  Future<Map<String, dynamic>> startVideo(CallSession session);

  Future<void> switchCamera(CallSession session);

  Future<void> stopVideo(CallSession session);

  Future<void> stop(CallSession session);
}
