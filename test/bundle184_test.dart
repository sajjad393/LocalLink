// Bundle 184: voice breaking in calls (both phones).
//
// The voice work itself is native (Kotlin) and tested in
// android/app/src/test/.../Voice184Test.kt with simulated networks. These
// checks keep the Flutter side honest: version + stamp, the end-of-call line,
// and that nothing in Dart needs a per-voice-piece event any more.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  // Version + stamp checks moved to the newest bundle test (185).

  group('Bundle 184 voice events', () {
    test('no Dart code waits for call_media_received', () {
      final hits = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final text = e.readAsStringSync();
        if (!text.contains('call_media_received')) continue;
        hits.add(e.path);
      }
      // Only the hot-event counter still names it (for older native builds).
      expect(hits.length, 1);
      expect(hits.single, endsWith('reliable_messaging_service.dart'));
    });

    test('call quality still reads the played counter from stats', () {
      final manager =
          _read('lib/features/calls/data/services/call_session_manager.dart');
      expect(manager, contains("stats['received_packets']"));
    });

    test('end-of-call line shows how much voice was heard', () {
      final transport = _read(
          'lib/features/calls/data/transport/native_mesh_call_transport.dart');
      expect(transport, contains("heard=\${stats['played_percent']}%"));
      expect(transport, contains("udp_tx=\${stats['udp_tx']}"));
    });
  });

  group('Bundle 184 native wiring', () {
    const service =
        'android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt';

    test('voice pieces send no app events', () {
      final s = _read(service);
      expect(s, isNot(contains('transportEvent("call_media_received"')));
      expect(
          s,
          contains(
              'if (packet.type == "call_media" || packet.type == MeshRelayPolicy.SEALED_VOICE) return'));
    });

    test('new waiting line, UDP voice and Nearby pause are wired', () {
      final s = _read(service);
      expect(s, contains('CallJitterBuffer()'));
      expect(s, contains('CallVoiceUdp.PORT'));
      expect(s, contains('CALL_VOICE_HEALTH'));
      expect(s, contains('CALL_VOICE_SUMMARY'));
      expect(s, contains('CallNearbyPause.callStarted()'));
      expect(
          _read(
              'android/app/src/main/kotlin/com/sajjad/locallink/NearbyRadio.kt'),
          contains('CallNearbyPause.searchAllowed()'));
    });
  });
}
