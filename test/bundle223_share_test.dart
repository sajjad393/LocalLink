// Bundle 223 (D, E): Share app. D = the download QR says "camera app, not
// the Wi-Fi scanner". E = step 2 is never an empty "Tap the one" (Phase 5).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/app_share_controller.dart';
import 'package:locallink/features/share_app/domain/share_address_picker.dart';
import 'package:locallink/features/share_app/presentation/share_app_entry.dart';
import 'package:locallink/features/share_app/presentation/share_app_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/g210_fakes.dart';

void main() {
  late FakeShareNative native;
  late FakeShareServer server;

  AppShareController make() => AppShareController(
        native: native,
        ownerName: 'Sajjad',
        serverFactory: (apk, name) => server,
        statusEvery: const Duration(hours: 1),
        notifyGap: Duration.zero,
      );

  Future<AppShareController> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = make();
    await c.start();
    await tester.pumpWidget(MaterialApp(
        home: ShareAppScreen(ownerName: 'Sajjad', native: native, controller: c)));
    await tester.pump();
    return c;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShareAppNewBadge.resetForTest();
    native = FakeShareNative();
    server = FakeShareServer();
    AppLogFile.instance.resetForTest();
  });

  List<String> log() => AppLogFile.instance.pendingForTest;
  const noIpStart = ShareStart(ok: true, ssid: 'AndroidShare_1', password: 'pass1234');
  Future<void> toStep2(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('share_next')));
    await tester.tap(find.byKey(const ValueKey('share_next')));
    await tester.pump();
  }

  testWidgets('223-9 same Wi-Fi screen: the yellow "camera app" note, old text gone', (tester) async {
    native.start = const ShareStart(ok: false, reason: 'couldnt_start');
    native.addrs = const ShareAddresses(wifiIp: '192.168.1.7');
    await show(tester);
    expect(find.byKey(const ValueKey('share_same_wifi')), findsOneWidget);
    expect(find.byKey(const ValueKey('share_scan_note')), findsOneWidget);
    expect(find.text('Scan with the camera app,\nnot the Wi-Fi scanner'), findsOneWidget);
    expect(find.text('Scan with the camera, open in Chrome'), findsNothing);
    final box = tester.widget<Container>(find.byKey(const ValueKey('share_scan_note')));
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color, const Color(0xFFFFF4CC), reason: 'soft yellow fill');
    expect(deco.border, isNotNull);
    expect(find.text('192.168.1.7:8080'), findsOneWidget, reason: '"or type" address unchanged');
    await close(tester);
  });

  testWidgets('223-10 step 1 keeps its Wi-Fi scanner text; step 2 has the new note', (tester) async {
    await show(tester);
    expect(find.text('Settings → Wi-Fi → tap the QR icon and scan this code.'), findsOneWidget);
    expect(find.byKey(const ValueKey('share_scan_note')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('share_next')));
    await tester.tap(find.byKey(const ValueKey('share_next')));
    await tester.pump();
    expect(find.byKey(const ValueKey('share_scan_note')), findsOneWidget);
    await close(tester);
  });

  group('223-11 / 223-12 picker', () {
    const wlanHot = ShareAddress(iface: 'wlan0', ip: '192.168.43.1');
    const wlanRouter = ShareAddress(iface: 'wlan0', ip: '192.168.1.7');
    const p2p = ShareAddress(iface: 'p2p-wlan0-0', ip: '192.168.49.1');

    test('223-11 wlan0 with a .1 address and no router is picked', () {
      expect(pickShareIp(list: const [wlanHot, p2p], noRouter: true), '192.168.43.1');
      // The "new address" case comes from Android as nativeIp.
      expect(pickShareIp(nativeIp: '192.168.43.1', list: const [wlanHot]), '192.168.43.1');
      // A real hotspot interface still wins.
      expect(
          pickShareIp(list: const [wlanHot, ShareAddress(iface: 'ap0', ip: '10.1.1.1', hotspot: true)], noRouter: true),
          '10.1.1.1');
    });

    test('223-12 wlan0 on a router is skipped', () {
      expect(pickShareIp(list: const [wlanHot, p2p]), isNull, reason: 'on a router: wlan0 .1 is the router side');
      expect(pickShareIp(list: const [wlanRouter, p2p], noRouter: true), isNull, reason: 'not .1');
      expect(shareIpChoices(const [wlanRouter]), isEmpty);
    });

    test('223-13 the "every address" list has wlan0 too, never Wi-Fi Direct', () {
      final all = shareIpAll(const [wlanRouter, p2p, ShareAddress(iface: 'rmnet0', ip: '8.8.8.8'), wlanRouter]);
      expect(all.map((a) => a.ip), ['192.168.1.7']);
      expect(shareIpListForLog(const [wlanRouter, p2p]), 'wlan0=192.168.1.7,p2p-wlan0-0=192.168.49.1');
      expect(shareIpListForLog(const []), 'none');
    });
  });

  testWidgets('223-13 nothing found: spinner, then Gateway tip + Try again, never an empty "Tap the one"', (tester) async {
    native.start = noIpStart;
    final c = await show(tester);
    await toStep2(tester);
    expect(find.byKey(const ValueKey('share_ip_looking')), findsOneWidget);
    expect(find.text('Getting the download address...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Tap the one that starts with'), findsNothing);
    expect(c.lookingForIp, isTrue);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.byKey(const ValueKey('share_ip_none')), findsOneWidget);
    expect(find.text("Couldn't get the address by itself"), findsOneWidget);
    expect(find.byKey(const ValueKey('share_ip_retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('share_gateway_tip')), findsOneWidget);
    expect(find.textContaining('"Gateway" address in Chrome with :8080'), findsOneWidget);
    expect(find.text('Tap the one your friend can open:'), findsNothing, reason: 'no empty list');
    expect(log().any((l) => l.contains('SHARE_APP') && l.contains('ip_none ms=10000 list=none')), isTrue);
    await close(tester);
  });

  testWidgets('223-13 after 10 s every address is a button with its name; a tap shows the QR', (tester) async {
    native.start = noIpStart;
    native.addrs = const ShareAddresses(wifiIp: '192.168.1.1', list: [
      ShareAddress(iface: 'wlan0', ip: '192.168.1.1'),
      ShareAddress(iface: 'eth9', ip: '10.164.88.1'),
      ShareAddress(iface: 'eth8', ip: '10.164.88.2'),
    ]);
    await show(tester);
    await toStep2(tester);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('Tap the one your friend can open:'), findsOneWidget);
    expect(find.text('wlan0'), findsOneWidget);
    expect(find.text('eth9'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share_ip_10.164.88.1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('share_qr_download')), findsOneWidget);
    expect(find.text('10.164.88.1:8080'), findsOneWidget);
    expect(log().any((l) => l.contains('ip_picked ip=10.164.88.1 iface=by_hand')), isTrue);
    await close(tester);
  });

  testWidgets('223-14 an address that comes late shows the QR on the same screen', (tester) async {
    native.start = noIpStart;
    await show(tester);
    await toStep2(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('share_ip_looking')), findsOneWidget);
    native.addrs = const ShareAddresses(list: [ShareAddress(iface: 'wlan0', ip: '192.168.43.1')]);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.byKey(const ValueKey('share_step2')), findsOneWidget, reason: 'did not leave step 2');
    expect(find.byKey(const ValueKey('share_qr_download')), findsOneWidget);
    expect(find.text('192.168.43.1:8080'), findsOneWidget);
    expect(find.byKey(const ValueKey('share_ip_looking')), findsNothing);
    expect(log().any((l) => l.contains('ip_wait found=192.168.43.1 ms=6000 iface=wlan0')), isTrue);
    expect(log().where((l) => l.contains('ip_wait')).length, 1, reason: 'once');
    expect(log().any((l) => l.contains('ip_picked ip=192.168.43.1 iface=wlan0')), isTrue);
    await close(tester);
  });

  testWidgets('223-14 Try again finds it', (tester) async {
    native.start = noIpStart;
    await show(tester);
    await toStep2(tester);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    native.addrs = const ShareAddresses(list: [ShareAddress(iface: 'swlan0', ip: '192.168.43.1', hotspot: true)]);
    await tester.tap(find.byKey(const ValueKey('share_ip_retry')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('share_qr_download')), findsOneWidget);
    await close(tester);
  });

  testWidgets('223-14 the address found at once: no spinner, no extra checks', (tester) async {
    final c = await show(tester);
    expect(c.lookingForIp, isFalse);
    await toStep2(tester);
    expect(find.byKey(const ValueKey('share_qr_download')), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
    expect(native.calls.where((x) => x == 'addresses'), isEmpty);
    expect(log().any((l) => l.contains('ip_picked ip=192.168.43.1')), isTrue);
    await close(tester);
  });
}
