import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/share_app/data/app_latest_server_299.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/share_address_picker.dart';
import 'package:locallink/features/share_app/domain/silent_update_275.dart';
import 'package:locallink/features/share_app/domain/update_request_service.dart';

import 'support/g210_fakes.dart';

/// Bundle 299 (C): the update comes from the LinkUp server first; nearby
/// phones stay the fallback. Same popup, same once-per-day gate, sha256.
class _Install extends UpdateInstallNative275 {
  _Install(this.dir);
  final String dir;
  String? bad;
  final checked = <String>[];
  @override
  Future<String> updateDir() async => dir;
  @override
  Future<String?> checkApk(String path, int size) async {
    checked.add(path);
    return bad;
  }

  @override
  Future<bool> canInstall() async => true;
}

class _Server implements AppLatestSource299 {
  ServerApk299? apk;
  Object? error;
  var asked = 0;
  @override
  Future<ServerApk299?> latest() async {
    asked++;
    if (error != null) throw error!;
    return apk;
  }

  @override
  String fileUrl(ServerApk299 a) => 'http://192.168.18.27:8080${a.path}';
}

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late Directory tmp;
  late UpdateRequestService ali, sum;
  late Map<String, String> store;
  late _Install install;
  late _Server server;
  late DateTime now;
  late bool phonesNear;
  late String fileHash;
  final urls = <String>[];

  setUp(() {
    UpdateRequestService.resetHooksForTest();
    SilentUpdate275.resetForTest();
    // Like the 275 test: this phone reports one build lower, so the nearby
    // phone (same test build) is "newer" and shares.
    AppBuild.pretendOld = true;
    tmp = Directory.systemTemp.createTempSync('u299');
    store = {};
    urls.clear();
    now = DateTime(2026, 11, 14, 12);
    phonesNear = true;
    fileHash = _sha;
    install = _Install(tmp.path);
    server = _Server()
      ..apk = const ServerApk299(
          version: '3.0.96', build: kAppBuild + 1, size: 4, sha256: _sha, path: '/download/LinkUp-3.0.96.apk');
    Future<void> Function(String, Map<String, dynamic>) sender(String from) => (peer, payload) async {
          final to = peer == 'sum' ? sum : ali;
          unawaited(to.handleEvent({'type': 'message', 'sender_id': from, 'payload': jsonEncode(payload)}));
        };
    ali = UpdateRequestService(
      send: sender('ali'),
      events: const Stream.empty(),
      selfDeviceId: () => 'ali',
      myName: () => 'Ali',
      peerName: (_) async => 'Sumaira',
      peerBuilds: () => phonesNear ? {'sum': (build: kAppBuild + 1, version: '3.0.96', at: now)} : const {},
      native: FakeShareNative()
        ..addrs =
            const ShareAddresses(wifiIp: '192.168.1.20', list: [ShareAddress(iface: 'wlan0', ip: '192.168.1.20')]),
      clock: () => now,
    );
    sum = UpdateRequestService(
      send: sender('sum'),
      events: const Stream.empty(),
      selfDeviceId: () => 'sum',
      myName: () => 'Sumaira',
      peerName: (_) async => 'Ali',
      peerBuilds: () => const {},
      native: FakeShareNative()
        ..addrs = const ShareAddresses(wifiIp: '192.168.1.30', list: [ShareAddress(iface: 'wlan0', ip: '192.168.1.30')])
        ..apk = const ApkInfo(ok: true, path: '/x/base.apk', size: 4, version: '3.0.96'),
      startServer: (apk, ip, owner) async => 'http://$ip:8080/',
      clock: () => now,
    );
  });
  tearDown(() {
    UpdateRequestService.resetHooksForTest();
    SilentUpdate275.resetForTest();
    AppBuild.pretendOld = false;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  SilentUpdate275 make({AppLatestSource299? src}) => SilentUpdate275(
        requests: ali,
        read: (k) async => store[k],
        write: (k, v) async => store[k] = v,
        native: install,
        clock: () => now,
        server: src ?? server,
        hashFile: (_) async => fileHash,
        download: (url, path, size, progress) async {
          urls.add(url);
          File(path).writeAsBytesSync([1, 2, 3, 4]);
          progress(4);
        },
      );

  Future<void> settle() async {
    for (var i = 0; i < 80; i++) {
      await pumpEventQueue();
    }
  }

  test('server newer -> popup "from the server" -> download -> sha ok -> ready', () async {
    final s = make();
    final shown = <bool>[];
    SilentUpdate275.showPopup = (x) => shown.add(x.fromServer);
    expect(await s.check(), isTrue);
    await settle();
    expect(shown.first, isTrue);
    expect(s.stage, SilentStage275.ready);
    expect(s.fromServer, isTrue);
    expect(urls, ['http://192.168.18.27:8080/download/LinkUp-3.0.96.apk']);
    expect(install.checked, [s.path]);
    expect(s.version, '3.0.96');
    expect(store[SilentUpdate275.gateKey], '${kAppBuild + 1}|2026-11-14');
  });

  test('wrong sha256 -> file deleted -> nearby phone gives it', () async {
    fileHash = 'b' * 64;
    final s = make();
    SilentUpdate275.showPopup = (_) {};
    expect(await s.check(), isTrue);
    await settle();
    expect(urls.first, contains('/download/LinkUp-3.0.96.apk'));
    expect(urls.last, 'http://192.168.1.30:8080/LinkUp.apk');
    expect(s.stage, SilentStage275.ready);
    expect(s.fromServer, isFalse);
    // Only the phone's file is left (the server's bad file was deleted).
    expect(tmp.listSync().length, 1);
    // The phone file has no sha (phones never had one): checked by size + package.
    expect(install.checked.length, 1);
  });

  test('wrong sha and no phone nearby -> "could not get it", no file left', () async {
    fileHash = 'b' * 64;
    phonesNear = false;
    final s = make();
    SilentUpdate275.showPopup = (_) {};
    await s.check();
    await settle();
    expect(s.stage, SilentStage275.none);
    expect(tmp.listSync(), isEmpty);
  });

  test('server has no APK (204) or same build -> nearby phones as before', () async {
    server.apk = null;
    final s = make();
    SilentUpdate275.showPopup = (_) {};
    expect(await s.check(), isTrue);
    await settle();
    expect(s.fromServer, isFalse);
    expect(urls.single, 'http://192.168.1.30:8080/LinkUp.apk');

    final s2 = make(src: _Server()
      ..apk = ServerApk299(version: '3.0.95', build: AppBuild.sent, size: 4, sha256: _sha, path: '/download/x.apk'));
    store.clear();
    urls.clear();
    now = now.add(const Duration(minutes: 3)); // 275: one ask per phone per 2 min
    await s2.check();
    await settle();
    expect(urls.single, 'http://192.168.1.30:8080/LinkUp.apk');
  });

  test('server not reached -> phones now; asked again next time', () async {
    server.error = const SocketException('down');
    final s = make();
    SilentUpdate275.showPopup = (_) {};
    await s.check();
    await settle();
    expect(s.fromServer, isFalse);
    expect(server.asked, 1);
    await s.cancel();
    await s.check(manual: true);
    expect(server.asked, 2);
  });

  test('once per build per day; the server is asked at most every 6 h', () async {
    final s = make();
    var popups = 0;
    SilentUpdate275.showPopup = (_) => popups++;
    await s.check();
    await settle();
    await s.cancel();
    expect(await s.check(), isFalse, reason: 'Cancel = not again today');
    expect(server.asked, 1, reason: 'the 6 h answer is reused');
    now = now.add(const Duration(hours: 6));
    await s.check();
    expect(server.asked, 2);
    s.serverAgain(); // reconnect
    await s.check();
    expect(server.asked, 3);
    expect(await s.check(manual: true), isTrue, reason: 'the Update button always');
  });

  test('in a call -> nothing (no server ask, no popup)', () async {
    UpdateRequestService.inCall = () => true;
    final s = make();
    var popups = 0;
    SilentUpdate275.showPopup = (_) => popups++;
    expect(await s.check(), isFalse);
    expect(server.asked, 0);
    expect(popups, 0);
  });

  test('min build rule above the server APK -> phones only', () async {
    final s = SilentUpdate275(
      requests: ali,
      read: (k) async => store[k],
      write: (k, v) async => store[k] = v,
      native: install,
      clock: () => now,
      server: server,
      hashFile: (_) async => fileHash,
      minBuild: () => kAppBuild + 5,
      download: (url, path, size, progress) async => urls.add(url),
    );
    SilentUpdate275.showPopup = (_) {};
    await s.check();
    await settle();
    expect(urls.where((u) => u.contains('/download/')), isEmpty);
  });

  group('HttpAppLatestServer299', () {
    test('200 -> fields; 204 -> null; device headers + build header sent', () async {
      final seen = <http.Request>[];
      var code = 200;
      final client = MockClient((r) async {
        seen.add(r);
        if (code == 204) return http.Response('', 204);
        return http.Response(
            jsonEncode({
              'version': '3.0.96',
              'build': 167,
              'size': 65432123,
              'sha256': _sha.toUpperCase(),
              'file': 'LinkUp-3.0.96.apk',
              'path': '/download/LinkUp-3.0.96.apk',
            }),
            200);
      });
      final api = HttpAppLatestServer299(
          baseUrl: () => 'http://192.168.18.27:8080/',
          deviceId: () => 'dev1',
          deviceToken: () => 'tok',
          client: client);
      final a = await api.latest();
      expect(a!.build, 167);
      expect(a.sha256, _sha);
      expect(api.fileUrl(a), 'http://192.168.18.27:8080/download/LinkUp-3.0.96.apk');
      expect(seen.single.url.toString(), 'http://192.168.18.27:8080/api/v1/app/latest');
      expect(seen.single.headers['Authorization'], 'Bearer tok');
      expect(seen.single.headers['X-Device-ID'], 'dev1');
      expect(seen.single.headers[kAppBuildHeader], isNotNull);
      code = 204;
      expect(await api.latest(), isNull);
    });

    test('bad answers are not used', () {
      expect(ServerApk299.fromJson({'build': 1, 'size': 1, 'sha256': 'x', 'path': '/download/a'}), isNull);
      expect(ServerApk299.fromJson({'build': 1, 'size': 1, 'sha256': _sha, 'path': 'http://evil/a.apk'}), isNull);
      expect(ServerApk299.fromJson({'build': 0, 'size': 1, 'sha256': _sha, 'path': '/download/a'}), isNull);
      expect(ServerApk299.fromJson('nope'), isNull);
    });

    test('no server address -> throws (phones are used)', () async {
      final api = HttpAppLatestServer299(baseUrl: () => '', deviceId: () => '', deviceToken: () => '');
      expect(api.latest(), throwsException);
    });
  });
}
