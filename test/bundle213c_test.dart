import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;
import 'package:locallink/features/admin/data/services/version_rule_server.dart';

import 'support/b212_fakes.dart';
import 'support/b213_fakes.dart';

/// Bundle 213 (A, C): the build header on every server call, 426, and the
/// rule to / from the server.
void main() {
  late Keys212 server;
  late Keys212 adminKey;

  setUpAll(() async {
    server = await Keys212.make();
    adminKey = await Keys212.make();
  });
  tearDown(() {
    AppBuild.pretendOld = false;
    AppBuild.onUpgradeRequired = null;
  });

  test('ApiHttpClient sends the build and reports 426', () async {
    final seen = <String?>[];
    String? body426;
    AppBuild.onUpgradeRequired = (b) => body426 = b;
    final client = ApiHttpClient(client: MockClient((r) async {
      seen.add(r.headers[kAppBuildHeader]);
      if (r.url.path == '/old') {
        return http.Response('{"error":"update_required","reason":"below_min"}', 426);
      }
      return http.Response('{}', 200);
    }));
    await client.get(Uri.parse('http://s/ok'), headers: {'X-Device-ID': 'd'});
    AppBuild.pretendOld = true;
    await client.post(Uri.parse('http://s/ok'), body: '{}');
    try {
      await client.get(Uri.parse('http://s/old'));
    } catch (_) {}
    expect(seen, ['$kAppBuild', '${kAppBuild - 1}', '${kAppBuild - 1}']);
    expect(body426, contains('update_required'));
  });

  test('BuildHeaderClient (uploads, block sync) sends the build too', () async {
    var hits = 0;
    AppBuild.onUpgradeRequired = (_) => hits++;
    final c = BuildHeaderClient(MockClient((r) async =>
        http.Response('', r.headers[kAppBuildHeader] == '$kAppBuild' ? 200 : 426)));
    expect((await c.get(Uri.parse('http://s/a'))).statusCode, 200);
    expect(hits, 0);
  });

  test('every raw server call file uses the build header', () {
    String read(String p) => File(p).readAsStringSync();
    expect(read('lib/core/services/locallink_api.dart'),
        contains("import 'package:locallink/core/network/build_http.dart' as http;"));
    expect(read('lib/features/admin/data/services/admin_service.dart'),
        contains("import 'package:locallink/core/network/build_http.dart' as http;"));
    expect(read('lib/features/files/data/services/file_transfer_service.dart'), contains('BuildHeaderClient('));
    expect(read('lib/features/admin/data/services/admin_block_server.dart'), contains('BuildHeaderClient('));
    expect(read('lib/core/services/websocket_service.dart'), contains('AppBuild.withHeader('));
  });

  test('HttpVersionRuleServer: public read, device sync', () async {
    final rule = await serverRule213(server, minBuild: 125);
    final calls = <http.Request>[];
    final s = HttpVersionRuleServer(
      baseUrl: () => 'http://srv',
      deviceId: () => 'dev-1',
      deviceToken: () => 'tok',
      client: MockClient((r) async {
        calls.add(r);
        return http.Response(jsonEncode({'rule': rule.toJson(), 'applied': true}), 200);
      }),
    );
    expect((await s.fetch())?.body, rule.body);
    expect((await s.sync(rule))?.body, rule.body);
    expect(calls[0].url.path, '/api/v1/version-rule');
    expect(calls[0].headers.containsKey('Authorization'), isFalse);
    expect(calls[1].url.path, '/api/v1/version-rule/sync');
    expect(calls[1].headers['Authorization'], 'Bearer tok');
    expect(calls[1].headers[kAppBuildHeader], '$kAppBuild');
    expect(jsonDecode(calls[1].body)['rule']['body'], rule.body);
  });

  test('server rule comes down; a newer phone rule goes up', () async {
    final mesh = Mesh213();
    final remote = FakeVersionServer213()..rule = await serverRule213(server, minBuild: 120);
    final user = mesh.phone('u', server: server, remote: remote);
    await user.syncWithServer();
    expect(user.rule?.minBuild, 120);
    expect(remote.synced, isEmpty);

    final admin = mesh.phone('a', server: server, key: adminKey, cert: await cert212(server, adminKey),
        signIn: owner212, remote: remote);
    await admin.syncWithServer();
    final made = await admin.setRule(minBuild: kAppBuild, minVersion: kAppVersion, mode: 'warn');
    await pumpEventQueue();
    await admin.syncWithServer();
    expect(remote.synced.map((b) => b.body), contains(made.blob.body));
    await user.syncWithServer();
    expect(user.rule?.id, made.id);
  });

  test('426 makes the phone read only until the server rule says ok', () async {
    final mesh = Mesh213();
    final remote = FakeVersionServer213()..fail = true;
    final p = mesh.phone('p', server: server, remote: remote);
    await p.load();
    p.onServerSaysOld('{"error":"update_required"}');
    expect(mesh.guards['p']!.stopped, isTrue);
    await pumpEventQueue();
    // Server not reachable: stays read only.
    expect(mesh.guards['p']!.stopped, isTrue);
    remote.fail = false;
    await p.syncWithServer();
    expect(mesh.guards['p']!.stopped, isFalse);
  });

  test('server down: nothing breaks', () async {
    final mesh = Mesh213();
    final p = mesh.phone('p', server: server, remote: FakeVersionServer213()..fail = true);
    await p.syncWithServer();
    expect(p.rule, isNull);
  });
}
