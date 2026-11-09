import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';

/// Bundle 239: S5 A (server 'yellow' = server connected) + S6 (one
/// LINK_AUTH_DAY line, strict stays off).
void main() {
  test('239-1 yellow is server connected; old words unchanged', () {
    expect(deviceNetworkStatusFromString('yellow'), DeviceNetworkStatus.serverConnected);
    expect(deviceNetworkStatusFromString('green'), DeviceNetworkStatus.serverConnected);
    expect(deviceNetworkStatusFromString('orange'), DeviceNetworkStatus.wifiDirect);
    expect(deviceNetworkStatusFromString('red'), DeviceNetworkStatus.disconnected);
    expect(deviceNetworkStatusFromString(null), DeviceNetworkStatus.disconnected);
  });

  test('239-2 every saved value reads back the same', () {
    for (final s in DeviceNetworkStatus.values) {
      expect(deviceNetworkStatusFromString(s.apiValue), s);
    }
  });

  test('239-3 LINK_AUTH_DAY counter, strict default off (source)', () {
    final k = File('android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt').readAsStringSync();
    expect(k, contains('Log.i("LINK_AUTH_DAY", "day=\$linkAuthDay verified=\$linkAuthVerifiedN legacy=\$linkAuthLegacyN rejected=\$linkAuthRejectedN")'));
    expect(k, contains('countLinkAuthDay(decision.verdict)'));
    expect(k, contains('getBoolean(STRICT_KEY,false)'));
  });
}
