import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/call_quality.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';

void main() {
  test('video fields default to disabled and have no textures', () {
    final session = CallSession(
      id: 'call-1',
      peerId: 'peer-1',
      peerName: 'Peer',
      direction: CallDirection.outgoing,
      state: CallState.connected,
      startedAt: DateTime.utc(2026, 9, 21),
    );
    expect(session.videoEnabled, isFalse);
    expect(session.localVideoTextureId, isNull);
    expect(session.remoteVideoTextureId, isNull);
  });

  test('video state and texture ids survive session copies', () {
    final sample = CallQualitySample(
      callId: 'call-1',
      sampledAt: DateTime.utc(2026, 9, 21),
      connectionState: 'mesh',
      transportState: 'mesh',
      packetsLost: 0,
      packetsReceived: 0,
      packetLossPercent: 0,
      quality: 'excellent',
    );
    final session = CallSession(
      id: 'call-1',
      peerId: 'peer-1',
      peerName: 'Peer',
      direction: CallDirection.outgoing,
      state: CallState.connected,
      startedAt: DateTime.utc(2026, 9, 21),
      qualitySample: sample,
    ).copyWith(
      videoEnabled: true,
      localVideoTextureId: 10,
      remoteVideoTextureId: 11,
    );
    expect(session.videoEnabled, isTrue);
    expect(session.localVideoTextureId, 10);
    expect(session.remoteVideoTextureId, 11);
  });
}
