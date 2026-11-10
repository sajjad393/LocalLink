import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/network/tls_pin_243.dart';
import 'package:locallink/core/network/tls_upgrade_243.dart';

/// Bundle 255 D1: HTTPS on -> the live ws:// socket moves to wss:// once.
void main() {
  tearDown(() => TlsPin243.setForTest());
  final sha = 'ab' * 32;

  TlsUpgrade243 make(List<int> calls, {bool socket = true, String addr = '192.168.1.5:8080'}) =>
      TlsUpgrade243(
        serverAddress: () => addr,
        pairingInfo: () async => throw StateError('away'),
        read: (k) async => null,
        write: (k, v) async {},
        socketUp: () => socket,
        onHttpsOn: () => calls.add(1),
        probeTls: (h, p, s) async => true,
        probeHttp: (_) async => true,
      );

  test('HTTPS already on (ok) -> switch hook runs', () async {
    TlsPin243.setForTest(host: '192.168.1.5', port: 8443, sha: sha, active: true);
    final calls = <int>[];
    expect(await make(calls).tick(), 'ok');
    expect(calls, [1]);
  });

  test('no HTTPS -> no switch', () async {
    final calls = <int>[];
    expect(await make(calls).tick(), 'server_away');
    expect(make(calls, addr: '').tick(), completion('no_server'));
    expect(calls, isEmpty);
  });

  test('the app moves only a ws:// socket, never during a call', () {
    final d = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(d, contains('onHttpsOn: _wssSwitch255'));
    final i = d.indexOf('void _wssSwitch255()');
    final body = d.substring(i, d.indexOf('\n  }\n', i));
    expect(body, contains("startsWith('ws://')"));
    expect(body, contains("startsWith('wss://')"));
    expect(body, contains('callService.session != null'));
    expect(body, contains('WS_TLS_SWITCH'));
    expect(body, contains('api.connectRealtime()'));
  });
}
