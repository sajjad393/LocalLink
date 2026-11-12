// Bundle 210 (C, E): the Share LinkUp screen and its two entry points.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/app_share_controller.dart';
import 'package:locallink/features/share_app/presentation/share_app_entry.dart';
import 'package:locallink/features/share_app/presentation/share_app_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/g210_fakes.dart';

void main() {
  // ---------------------------------------------------- source checks first
  group('placement (source)', () {
    test('Settings: Storage → Share LinkUp → Reset setup', () {
      final src = File(
              'lib/features/home/presentation/screens/messenger_settings_screen.dart')
          .readAsStringSync();
      final storage = src.indexOf('StorageSettingsRow(store: store)');
      final share = src.indexOf('ShareAppSettingsRow(');
      final reset = src.indexOf("title: 'Reset setup'");
      expect(storage, greaterThan(0));
      expect(share, greaterThan(storage));
      expect(reset, greaterThan(share));
    });

    test('People: card before Requests, hidden while searching', () {
      final src =
          File('lib/features/directory/presentation/contacts_screen.dart')
              .readAsStringSync();
      final card = src.indexOf('InviteNearbyCard(');
      final requests = src.indexOf("MessengerGroupLabel('Requests'");
      expect(card, greaterThan(0));
      expect(requests, greaterThan(card));
      expect(src.substring(card - 80, card), contains('if (query.isEmpty)'));
    });

    test('no new permission; channel registered; logs never hold the password',
        () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect('uses-permission'.allMatches(manifest).length, 26); // Bundle 226: +4 Bluetooth; 275: +1 REQUEST_INSTALL_PACKAGES
      final main = File(
              'android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt')
          .readAsStringSync();
      expect(main, contains('AppShareNative.CHANNEL'));
      final native = File(
              'android/app/src/main/kotlin/com/sajjad/locallink/AppShareNative.kt')
          .readAsStringSync();
      for (final line in native.split('\n').where((l) => l.contains('Log.'))) {
        expect(line, isNot(contains('ssid')));
        expect(line, isNot(contains('key')));
        expect(line, isNot(contains('password')));
      }
      final lnm = File(
              'android/app/src/main/kotlin/com/sajjad/locallink/LocalNetManager.kt')
          .readAsStringSync();
      expect(lnm, contains('"for" to forOwners'));
      expect(lnm, contains('owners.has(AppSharePolicy.OWNER_MESH)) tags()?.setHotspot'));
    });
  });

  // ---------------------------------------------------- widgets
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
    // A tall phone so every part of the list is built.
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
  });

  testWidgets('Step 1: QR, name, password, tip; Next → Step 2', (tester) async {
    await show(tester);
    expect(find.byKey(const ValueKey('share_step1')), findsOneWidget);
    expect(find.byKey(const ValueKey('share_qr_wifi')), findsOneWidget);
    expect(find.text('AndroidShare_4821'), findsOneWidget);
    expect(find.text('k7m2x9qp'), findsOneWidget);
    expect(find.textContaining('Stay connected?'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('share_next')));
    await tester.tap(find.byKey(const ValueKey('share_next')));
    await tester.pump();
    expect(find.byKey(const ValueKey('share_step2')), findsOneWidget);
    expect(find.byKey(const ValueKey('share_qr_download')), findsOneWidget);
    expect(find.text('192.168.43.1:8080'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('share_phones_none')));
    expect(find.text('None yet. Waiting…'), findsOneWidget);
    await close(tester);
    expect(native.calls, contains('stop left'));
  });

  testWidgets('phones: 64% bar, then Done', (tester) async {
    await show(tester);
    server.addPhone(upTo: (server.apkSize * 0.64).ceil());
    await tester.pump();
    expect(find.byKey(const ValueKey('share_step2')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('share_phone_1')));
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('40 of 62 MB'), findsOneWidget);
    server.fakePhones.first
      ..upTo = server.apkSize
      ..doneAt = DateTime(2026, 11, 5, 10, 0, 12);
    server.onChange!();
    await tester.pump(const Duration(milliseconds: 1)); // notify timer
    expect(find.text('Done, 62 MB'), findsOneWidget);
    expect(find.text('12 s'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Stop sharing stops everything', (tester) async {
    await show(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('share_stop')));
    await tester.tap(find.byKey(const ValueKey('share_stop')));
    await tester.pump();
    expect(native.calls, contains('stop user'));
    expect(native.calls, contains('screen false'));
    await close(tester);
  });

  testWidgets('battery low → Share anyway → Step 1', (tester) async {
    native.batteryInfo = const ShareBattery(level: 5);
    await show(tester);
    expect(find.text('Battery low (10% or less)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share_anyway')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('share_step1')), findsOneWidget);
    await close(tester);
  });

  testWidgets('Location off → Turn on Location opens settings', (tester) async {
    native.start = const ShareStart(ok: false, reason: 'location_off');
    await show(tester);
    expect(find.text('Turn on Location'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('share_location')));
    await tester.pump();
    expect(native.calls, contains('open_location'));
    await close(tester);
  });

  testWidgets("Wi-Fi couldn't start → Turn on Wi-Fi + Try again", (tester) async {
    native.start = const ShareStart(ok: false, reason: 'couldnt_start');
    await show(tester);
    expect(find.text("Couldn't turn on Wi-Fi"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share_wifi')));
    await tester.pump();
    expect(native.calls, contains('open_wifi'));
    native.start = const ShareStart(
        ok: true, ssid: 'B', password: 'pass1234', ip: '192.168.43.1');
    server = FakeShareServer();
    await tester.tap(find.byKey(const ValueKey('share_try_again')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('share_step1')), findsOneWidget);
    await close(tester);
  });

  testWidgets('own hotspot → QR 2 + Open hotspot settings', (tester) async {
    native.start = const ShareStart(ok: false, reason: 'own_hotspot');
    native.addrs = const ShareAddresses(list: kHotspotAddrs);
    await show(tester);
    expect(find.byKey(const ValueKey('share_own_hotspot')), findsOneWidget);
    expect(find.text('192.168.43.1:8080'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('share_open_hotspot')));
    await tester.tap(find.byKey(const ValueKey('share_open_hotspot')));
    await tester.pump();
    expect(native.calls, contains('open_hotspot'));
    await close(tester);
  });

  testWidgets('stopped after 10 min → Share again', (tester) async {
    final c = await show(tester);
    server.onIdle!();
    await tester.pump();
    await tester.pump();
    expect(c.stage, ShareStage.stopped);
    expect(find.text('No downloads for 10 minutes.'), findsOneWidget);
    expect(find.text('Share again'), findsOneWidget);
    await close(tester);
  });

  testWidgets("installed in parts → can't share", (tester) async {
    native.apk =
        const ApkInfo(ok: true, path: '/a', size: 10, version: '1', split: true);
    await show(tester);
    expect(find.text("This copy of LinkUp can't be shared"), findsOneWidget);
    await close(tester);
  });

  testWidgets('Settings row and People card show NEW and open the screen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: const [
          ShareAppSettingsRow(ownerName: 'Sajjad'),
          InviteNearbyCard(ownerName: 'Sajjad'),
        ]),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Share LinkUp'), findsOneWidget);
    expect(find.text('Give the app to a nearby phone · no internet'),
        findsOneWidget);
    expect(find.text('Invite a friend nearby'), findsOneWidget);
    expect(find.byKey(const ValueKey('share_new_badge')), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('people_invite_nearby')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(AppBar, 'Share LinkUp'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  test('NEW badge goes after 14 days', () async {
    SharedPreferences.setMockInitialValues({
      ShareAppNewBadge.key:
          DateTime(2026, 10, 1).millisecondsSinceEpoch,
    });
    ShareAppNewBadge.resetForTest();
    expect(await ShareAppNewBadge.isNew(now: DateTime(2026, 10, 14)), isTrue);
    ShareAppNewBadge.resetForTest();
    expect(await ShareAppNewBadge.isNew(now: DateTime(2026, 10, 16)), isFalse);
  });
}
