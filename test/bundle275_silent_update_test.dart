import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/share_address_picker.dart';
import 'package:locallink/features/share_app/domain/silent_update_275.dart';
import 'package:locallink/features/share_app/domain/update_request_service.dart';

import 'support/g210_fakes.dart';

/// Bundle 275: the old phone's quiet update - one popup by itself, no
/// names, in-app download, checked, then Android's installer; the file is
/// deleted by itself.
class _Install extends UpdateInstallNative275 {
  _Install(this.dir);
  final String dir;
  String? bad;
  bool allowed = true;
  final installed = <String>[];
  var settings = 0;
  @override
  Future<String> updateDir() async => dir;
  @override
  Future<String?> checkApk(String path, int size) async => bad;
  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<bool> openInstallSettings() async {
    settings++;
    return true;
  }

  @override
  Future<bool> installApk(String path) async {
    installed.add(path);
    return true;
  }
}

void main() {
  late Directory tmp;
  late UpdateRequestService ali, sum;
  late Map<String, String> store;
  late _Install install;
  final now = DateTime(2026, 11, 14, 12);
  final urls = <String>[];

  setUp(() {
    UpdateRequestService.resetHooksForTest();
    SilentUpdate275.resetForTest();
    AppBuild.pretendOld = true;
    tmp = Directory.systemTemp.createTempSync('u275');
    store = {};
    urls.clear();
    install = _Install(tmp.path);
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
      peerBuilds: () => {'sum': (build: kAppBuild + 1, version: '9.9.9', at: now)},
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
        ..apk = const ApkInfo(ok: true, path: '/x/base.apk', size: 4, version: '9.9.9'),
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

  SilentUpdate275 make() => SilentUpdate275(
        requests: ali,
        read: (k) async => store[k],
        write: (k, v) async => store[k] = v,
        native: install,
        clock: () => now,
        download: (url, path, size, progress) async {
          urls.add(url);
          File(path).writeAsBytesSync([1, 2, 3, 4]);
          progress(4);
        },
      );

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await pumpEventQueue();
    }
  }

  test('popup by itself -> download inside LinkUp -> ready -> installer', () async {
    final s = make();
    final shown = <SilentStage275>[];
    SilentUpdate275.showPopup = (x) => shown.add(x.stage);
    expect(await s.check(), isTrue);
    await settle();
    expect(shown.first, SilentStage275.getting);
    expect(s.stage, SilentStage275.ready);
    expect(urls.single, 'http://192.168.1.30:8080/LinkUp.apk');
    expect(s.path, '${tmp.path}/LinkUp-${kAppBuild + 1}.apk');
    expect(store[SilentUpdate275.fileKey], '${s.path}|${kAppBuild + 1}');
    await s.install();
    expect(install.installed, [s.path]);
  });

  test('at most once per build per day (auto); the Update button always', () async {
    final s = make();
    var popups = 0;
    SilentUpdate275.showPopup = (_) => popups++;
    await s.check();
    await settle();
    await s.cancel();
    expect(await s.check(), isFalse);
    expect(await s.check(manual: true), isTrue);
    expect(popups, greaterThan(1));
  });

  test('not in a call (auto)', () async {
    final s = make();
    UpdateRequestService.inCall = () => true;
    expect(await s.check(), isFalse);
  });

  test('bad file (size / package): deleted, never offered', () async {
    install.bad = 'package';
    final s = make();
    await s.check();
    await settle();
    expect(s.stage, SilentStage275.none);
    expect(tmp.listSync(), isEmpty);
  });

  test('cancel deletes the file', () async {
    final s = make();
    await s.check();
    await settle();
    expect(tmp.listSync(), isNotEmpty);
    await s.cancel();
    expect(tmp.listSync(), isEmpty);
    expect(store[SilentUpdate275.fileKey], '');
  });

  test('first time: Install opens Android\'s allow page', () async {
    install.allowed = false;
    final s = make();
    await s.check();
    await settle();
    expect(s.needsAllow, isTrue);
    await s.install();
    expect(install.settings, 1);
    expect(install.installed, isEmpty);
  });

  test('start: new version deletes the file; leftovers > 24 h too', () async {
    final f = File('${tmp.path}/LinkUp-$kAppBuild.apk')..writeAsBytesSync([1]);
    final old = File('${tmp.path}/old.apk')..writeAsBytesSync([1]);
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 25)));
    final fresh = File('${tmp.path}/fresh.apk')..writeAsBytesSync([1]);
    store[SilentUpdate275.fileKey] = '${f.path}|$kAppBuild';
    final updated = await SilentUpdate275.cleanAtStart(
        read: (k) async => store[k], write: (k, v) async => store[k] = v, dirOverride: tmp.path);
    expect(updated, isTrue);
    expect(f.existsSync(), isFalse);
    expect(old.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(store[SilentUpdate275.fileKey], '');
  });

  test('Android: permission, FileProvider, 5 methods; app wiring', () {
    final man = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(man, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(man, contains(r'${applicationId}.update275'));
    expect(File('android/app/src/main/res/xml/update_paths_275.xml').readAsStringSync(), contains('path="update275/"'));
    final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/AppShareNative.kt').readAsStringSync();
    for (final m in ['updateDir275', 'checkApk275', 'canInstall275', 'openInstallSettings275', 'installApk275']) {
      expect(kt, contains('"$m"'), reason: m);
    }
    expect(File('android/app/src/main/kotlin/com/sajjad/locallink/UpdateInstall275.kt').readAsStringSync(),
        contains('com.sajjad.linkup'));
    final app = File('lib/app/local_link_app.dart').readAsStringSync();
    expect(app, isNot(contains('showUpdateAskDialog')));
    expect(app, isNot(contains('openShareApp(')));
    expect(File('lib/app/app_dependencies.dart').readAsStringSync(), contains('SilentUpdate275.cleanAtStart('));
  });
}
