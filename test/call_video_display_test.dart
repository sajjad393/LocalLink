import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/calls/presentation/widgets/call_video_view.dart';

void main() {
  group('video display orientation math', () {
    test('inverse rotation maps correctly (bundle 64 direction fix)', () {
      expect(videoDisplayQuarterTurns(0), 0);
      expect(videoDisplayQuarterTurns(90), 3); // portrait phone, back camera
      expect(videoDisplayQuarterTurns(180), 2);
      expect(videoDisplayQuarterTurns(270), 1); // typical front camera
      expect(videoDisplayQuarterTurns(360), 0);
    });
  });

  group('call session video geometry', () {
    test('defaults preserve the legacy 640x360 contract', () {
      final s = CallSession(
        id: 'c1',
        peerId: 'p',
        peerName: 'peer',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        startedAt: DateTime.now(),
        transportMode: CallTransportMode.auto,
        videoEnabled: true,
      );
      expect(s.remoteVideoWidth, 640);
      expect(s.remoteVideoHeight, 360);
      expect(s.localVideoWidth, 640);
      expect(s.localVideoHeight, 360);
    });

    test('copyWith carries adaptive ladder geometry (720p, 540p)', () {
      final s = CallSession(
        id: 'c1',
        peerId: 'p',
        peerName: 'peer',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        startedAt: DateTime.now(),
        transportMode: CallTransportMode.auto,
        videoEnabled: true,
      );
      final hd = s.copyWith(remoteVideoWidth: 1280, remoteVideoHeight: 720);
      expect(hd.remoteVideoWidth, 1280);
      expect(hd.remoteVideoHeight, 720);
      final sd = hd.copyWith(localVideoWidth: 960, localVideoHeight: 540);
      expect(sd.localVideoWidth, 960);
      expect(sd.localVideoHeight, 540);
    });
  });
}
