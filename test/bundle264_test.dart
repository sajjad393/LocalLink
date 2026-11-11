// Bundle 264: test-only server address for the GitHub emulator run.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/services/discovery_service.dart';

void main() {
  test('1. no switch -> only the broadcasts (phones search as before)', () {
    expect(DiscoveryService.targets264(['10.0.2.16'], testIp: ''),
        {'255.255.255.255', '10.0.2.255'});
    expect(DiscoveryService.targets264(['192.168.18.40', '192.168.18.41']),
        {'255.255.255.255', '192.168.18.255'});
  });

  test('2. the switch adds the machine address', () {
    expect(DiscoveryService.targets264(['10.0.2.16'], testIp: '10.0.2.2'),
        {'255.255.255.255', '10.0.2.255', '10.0.2.2'});
    expect(DiscoveryService.targets264(const [], testIp: ' 10.0.2.2 '),
        {'255.255.255.255', '10.0.2.2'});
  });

  test('3. a public or broken address is never added', () {
    for (final ip in ['8.8.8.8', 'example.com', '10.0.2', '300.1.1.1']) {
      expect(DiscoveryService.targets264(['10.0.2.16'], testIp: ip),
          {'255.255.255.255', '10.0.2.255'}, reason: ip);
    }
  });

  test('4. the switch is empty in normal runs', () {
    expect(DiscoveryService.testServerIp264, isEmpty);
  });

  test('5. the switch name is only in discovery, the test kit and the workflow', () {
    final hits = <String>[];
    for (final root in ['lib', 'android/app/src/main']) {
      for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') && !f.path.endsWith('.kt')) continue;
        if (f.readAsStringSync().contains('LINKUP_TEST_SERVER_IP')) hits.add(f.path);
      }
    }
    expect(hits, ['lib/features/connectivity/data/services/discovery_service.dart']);
    expect(File('tool/rt264/run_case.sh').readAsStringSync(),
        contains('--dart-define=LINKUP_TEST_SERVER_IP=10.0.2.2'));
    final wf = File('.github/workflows/runtime_test_264.yml').readAsStringSync();
    expect(wf, contains('workflow_dispatch'));
    expect(wf, isNot(contains('push:')));
    expect(wf, isNot(contains('pull_request:')));
    expect(wf, contains('flutter-version: 3.47.7'));
  });

  test('6. the search still logs one start line with the target count', () {
    final src = File('lib/features/connectivity/data/services/discovery_service.dart')
        .readAsStringSync();
    expect(src, contains('final targets = targets264(addresses); // Bundle 264 (A3)'));
    expect(src, contains("'start addrs=\${addresses.length} targets=\${targets.length} '"));
  });

  test('7. the kit makes the admin account before it starts the server', () {
    // The Go server in development mode skips the bootstrap admin, so without
    // --reset-admin every /admin/* step (block, revoke, version) gets 401.
    final ctl = File('tool/rt264/server_ctl.py').readAsStringSync();
    final reset = ctl.indexOf('[SERVER_BIN, "--reset-admin"]');
    final run = ctl.indexOf('subprocess.Popen([SERVER_BIN]');
    expect(reset, greaterThan(0));
    expect(run, greaterThan(reset));
    expect(ctl, contains('"LOCALLINK_ADMIN_BOOTSTRAP_USERNAME": ADMIN_USER'));
    expect(ctl, contains('"LOCALLINK_ENV": "development"'));
  });
}
