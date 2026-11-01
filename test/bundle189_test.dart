// Bundle 189: (A) a Nearby search already running when call voice starts is
// stopped; (B) CALL_SOUND_STATE log line (volume, output, battery, saver).
// The logic is Android-side (Call189Test.kt); here: version + wiring.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  const k = 'android/app/src/main/kotlin/com/sajjad/locallink';

  test('call voice start stops a running Nearby search', () {
    final service = _read('$k/LocalLinkTransportService.kt');
    final started = service.indexOf('CallNearbyPause.callStarted()');
    final stop = service.indexOf('NearbyRadio.stopSearchForCall()');
    expect(started, greaterThan(0));
    expect(stop, greaterThan(started));
    expect(_read('$k/NearbyRadio.kt'), contains('stopPeerDiscovery'));
  });

  test('sound state line is written during and at the end of a call', () {
    final service = _read('$k/LocalLinkTransportService.kt');
    expect(service, contains('noteSoundState("call", false)'));
    expect(service, contains('noteSoundState("end", true)'));
  });
}
