// Bundle 210 (E1, D5): the Share LinkUp steps.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/app_share_controller.dart';
import 'package:locallink/features/share_app/domain/share_address_picker.dart';

import 'support/g210_fakes.dart';

void main() {
  late FakeShareNative native;
  late FakeShareServer server;
  late AppShareController c;

  AppShareController make({Duration status = const Duration(hours: 1)}) =>
      AppShareController(
        native: native,
        ownerName: 'Sajjad',
        serverFactory: (apk, name) => server,
        statusEvery: status,
        notifyGap: Duration.zero,
      );

  setUp(() {
    native = FakeShareNative();
    server = FakeShareServer();
    c = make();
  });

  tearDown(() => c.dispose());

  test('normal: page, Wi-Fi, Step 1 with both QR texts; stop undoes all',
      () async {
    await c.start();
    expect(c.stage, ShareStage.step1);
    expect(server.started, isTrue);
    expect(c.ssid, 'AndroidShare_4821');
    expect(c.password, 'k7m2x9qp');
    expect(c.wifiQr, 'WIFI:T:WPA;S:AndroidShare_4821;P:k7m2x9qp;;');
    expect(c.downloadUrl, 'http://192.168.43.1:8080');
    expect(c.downloadLabel, '192.168.43.1:8080');
    expect(c.sizeLabel, '62 MB');
    expect(native.calls, containsAllInOrder(['apk', 'battery', 'start', 'screen true']));
    expect(c.sharing, isTrue);

    await c.stop('user');
    expect(c.stage, ShareStage.stopped);
    expect(c.reason, 'user');
    expect(server.stopped, isTrue);
    expect(native.calls, containsAllInOrder(['stop user', 'screen false']));
    expect(c.sharing, isFalse);
  });

  test('re-used mesh hotspot is reported', () async {
    native.start = const ShareStart(
        ok: true, ssid: 'A', password: 'pass1234', ip: '192.168.43.1',
        reused: true);
    await c.start();
    expect(c.reusedHotspot, isTrue);
  });

  test('installed in parts → cantShare, nothing started', () async {
    native.apk = const ApkInfo(
        ok: true, path: '/a', size: 10, version: '1', split: true);
    await c.start();
    expect(c.stage, ShareStage.cantShare);
    expect(native.calls, isNot(contains('start')));
    expect(server.started, isFalse);
  });

  test('APK unreadable → failed apk_missing', () async {
    native.apk = const ApkInfo(ok: false, reason: 'apk_missing');
    await c.start();
    expect(c.stage, ShareStage.failed);
    expect(c.reason, 'apk_missing');
  });

  test('battery 8% not charging → warning; Share anyway → Step 1', () async {
    native.batteryInfo = const ShareBattery(charging: false, level: 8);
    await c.start();
    expect(c.stage, ShareStage.batteryLow);
    expect(native.calls, isNot(contains('start')));
    await c.shareAnyway();
    expect(c.stage, ShareStage.step1);
  });

  test('battery 8% while charging, or unknown → no warning', () async {
    native.batteryInfo = const ShareBattery(charging: true, level: 8);
    await c.start();
    expect(c.stage, ShareStage.step1);
    await c.stop('user');
    native.batteryInfo = const ShareBattery(charging: false, level: -1);
    await c.start();
    expect(c.stage, ShareStage.step1);
  });

  test('battery exactly 10% warns, 11% does not', () async {
    native.batteryInfo = const ShareBattery(level: 10);
    await c.start();
    expect(c.stage, ShareStage.batteryLow);
    final c2 = make();
    native.batteryInfo = const ShareBattery(level: 11);
    await c2.start();
    expect(c2.stage, ShareStage.step1);
    c2.dispose();
  });

  test('own hotspot on → only QR 2 with the tether address', () async {
    native.start = const ShareStart(ok: false, reason: 'own_hotspot');
    native.addrs = const ShareAddresses(list: kHotspotAddrs);
    await c.start();
    expect(c.stage, ShareStage.ownHotspot);
    expect(c.downloadUrl, 'http://192.168.43.1:8080');
    expect(server.started, isTrue);
    await c.stop('user');
    // We didn't start a hotspot, so we don't stop one.
    expect(native.calls, isNot(contains('stop user')));
    expect(native.calls, contains('screen false'));
  });

  test('own hotspot but no address → failed, page closed', () async {
    native.start = const ShareStart(ok: false, reason: 'own_hotspot');
    await c.start();
    expect(c.stage, ShareStage.failed);
    expect(c.reason, 'own_hotspot');
    expect(server.stopped, isTrue);
  });

  test("Wi-Fi didn't start but on a router → same Wi-Fi QR", () async {
    native.start = const ShareStart(ok: false, reason: 'couldnt_start');
    native.addrs = const ShareAddresses(wifiIp: '192.168.1.7');
    await c.start();
    expect(c.stage, ShareStage.sameWifi);
    expect(c.reason, 'couldnt_start');
    expect(c.downloadUrl, 'http://192.168.1.7:8080');
  });

  test("Wi-Fi didn't start, no router → failed, page closed", () async {
    native.start = const ShareStart(ok: false, reason: 'location_off');
    await c.start();
    expect(c.stage, ShareStage.failed);
    expect(c.reason, 'location_off');
    expect(server.stopped, isTrue);
  });

  test('page port busy → failed, Wi-Fi never asked', () async {
    server.failStart = true;
    await c.start();
    expect(c.stage, ShareStage.failed);
    expect(c.reason, 'port_busy');
    expect(native.calls, isNot(contains('start')));
  });

  test('first download moves Step 1 to Step 2 by itself', () async {
    await c.start();
    expect(c.stage, ShareStage.step1);
    server.addPhone(upTo: 1024);
    expect(c.stage, ShareStage.step2);
    expect(c.phones, hasLength(1));
    c.goToStep(1);
    expect(c.stage, ShareStage.step1);
    c.goToStep(2);
    expect(c.stage, ShareStage.step2);
  });

  test('idle (10 min) → stopped idle, Wi-Fi off', () async {
    await c.start();
    server.onIdle!();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.stage, ShareStage.stopped);
    expect(c.reason, 'idle');
    expect(native.calls, contains('stop idle'));
  });

  test('Android stopped the Wi-Fi → stopped "stopped"', () async {
    c.dispose();
    c = make(status: const Duration(milliseconds: 10));
    await c.start();
    native.stillOn = false;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(c.stage, ShareStage.stopped);
    expect(c.reason, 'stopped');
  });

  test('address unknown → asks again, then offers choices', () async {
    native.start = const ShareStart(
        ok: true, ssid: 'A', password: 'pass1234', addresses: <ShareAddress>[]);
    native.addrs = const ShareAddresses(list: [
      ShareAddress(iface: 'eth1', ip: '10.0.0.1'),
      ShareAddress(iface: 'eth2', ip: '10.0.0.2'),
    ]);
    await c.start();
    expect(native.calls, contains('addresses'));
    expect(c.downloadUrl, isNull);
    expect(c.ipChoices, hasLength(2));
    c.chooseIp('10.0.0.2');
    expect(c.downloadUrl, 'http://10.0.0.2:8080');
  });

  test('leaving while Android is still starting → Wi-Fi stopped after', () async {
    native.holdStart = Completer<void>();
    final run = c.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(native.calls, contains('start'));
    c.dispose();
    native.holdStart!.complete();
    await run;
    expect(native.calls, contains('stop left'));
    expect(server.stopped, isTrue);
  });

  test('start again after a stop works', () async {
    await c.start();
    await c.stop('user');
    server = FakeShareServer();
    await c.start();
    expect(c.stage, ShareStage.step1);
  });
}
