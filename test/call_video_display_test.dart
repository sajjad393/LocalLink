import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/calls/presentation/widgets/call_video_view.dart';

void main() {
  group('video display orientation math', () {
    // Wire contract: the sender advertises `rotation` = the CLOCKWISE degrees
    // needed to make its raw (unrotated, unmirrored) sensor buffer upright:
    //   rotation = (sensorOrientation - displayRotation + 360) % 360
    // The receiver therefore rotates the texture clockwise by exactly that
    // amount: quarterTurns = r/90. Rotating the OTHER way (360-r) is what
    // produced the "remote feed lands upside-down / sideways" regression this
    // bundle fixes — do not revert this table.
    test('receiver rotates WITH the advertised clockwise angle (r/90)', () {
      expect(videoDisplayQuarterTurns(0), 0);
      expect(videoDisplayQuarterTurns(90), 1); // portrait phone, 90deg sensor
      expect(videoDisplayQuarterTurns(180), 2);
      expect(videoDisplayQuarterTurns(270), 3); // typical front sensor 270deg
      expect(videoDisplayQuarterTurns(360), 0);
    });

    test('sender-side table stays upright for every sensor/display combo', () {
      // (sensor, display, advertisedR, quarterTurns) — both cameras use the
      // same formula now; the first column pair comes straight out of the
      // Camera2 SENSOR_ORIENTATION contract.
      const cases = <List<int>>[
        [90, 0, 90, 1], // portrait, back camera (the classic case)
        [90, 90, 0, 0], // landscape-right, back
        [90, 180, 270, 3], // upside-down natural, back
        [90, 270, 180, 2], // landscape-left, back
        [270, 0, 270, 3], // portrait, front (many devices)
        [270, 90, 180, 2], // landscape-right, front
        [0, 90, 270, 3], // landscape on a 0deg-sensor tablet
      ];
      for (final c in cases) {
        final advertised = (c[0] - c[1] + 360) % 360;
        expect(advertised, c[2], reason: 'sensor=${c[0]} display=${c[1]}');
        expect(videoDisplayQuarterTurns(advertised), c[3],
            reason: 'sensor=${c[0]} display=${c[1]} must end upright');
      }
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
