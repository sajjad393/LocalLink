import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/admin_action_book.dart';
import 'package:locallink/features/admin/data/actions/admin_action_doers.dart';
import 'package:locallink/features/admin/presentation/screens/admin_actions_screen.dart';

import 'support/b216_fonts.dart';
import 'support/b220_fakes.dart';

/// Bundle 220 (c): the server is one more carrier; Wi-Fi rule, sign out and
/// version rule on the phone; the Admin actions page; source checks.
void main() {
  setUp(() {
    AppLogFile.instance.resetForTest();
    AdminClosedFlag.closed.value = false;
  });

  test('server card: the phone does it, its Done goes to the server, server stop ends it',
      () async {
    final net = await Net220.make();
    final srv = FakeServer220();
    final ali = await net.phone('dev-ali', srv: srv, online: true);
    srv.cards = [
      await serverCard220(net.server,
          id: 'aa_web', action: 'block', need: 2, to: [await lockFor(ali)],
          inner: await net.server.blob({'kind': 'admin_block'}))
    ];
    await ali.svc.syncWithServer();
    await settle();
    expect(ali.did.log, ['block']);
    expect(ali.svc.stateOf('aa_web'), 'pending'); // need 2 (her second phone)
    await ali.svc.syncWithServer();
    expect(srv.gotReceipts.map((b) => b.body).join(), contains('"action_id":"aa_web"'));
    srv.cards = [];
    srv.states = [await serverState220(net.server, id: 'aa_web', done: 2, need: 2)];
    await ali.svc.syncWithServer();
    expect(ali.svc.stateOf('aa_web'), 'done');
    expect(ali.svc.hasCard('aa_web'), isFalse);
  });

  test('blocked / closed phone (401): cards and stops come from /mine', () async {
    final net = await Net220.make();
    final srv = FakeServer220()..unauthorized = true;
    final ali = await net.phone('dev-ali', srv: srv, online: true);
    srv.cards = [
      await serverCard220(net.server,
          id: 'aa_on', action: 'active', to: [await lockFor(ali)],
          inner: await net.server.blob({'kind': 'admin_block'}))
    ];
    await ali.svc.syncWithServer();
    await settle();
    expect(srv.mineCalls, greaterThanOrEqualTo(1));
    expect(ali.did.log, ['block', 'open']);
  });

  test('an offline card reaches the server with its label (web shows the name)', () async {
    final net = await Net220.make();
    final srv = FakeServer220();
    final admin = await net.phone('dev-admin', adminRole: 'owner', srv: srv);
    await net.phone('dev-ali', user: 'u-ali');
    net.knowAll();
    final id = await admin.svc.make(
        action: 'wifi_rule',
        targetUserId: 'u-ali',
        label: 'Ali',
        targetDevices: ['dev-ali'],
        detail: {'wifi_radio_policy': 'forced_on'},
        words: 'Wi-Fi on');
    await settle();
    await admin.svc.syncWithServer();
    expect(srv.gotCards.map((b) => b.body).join(), contains('"id":"$id"'));
    final label = srv.gotLabels.firstWhere((l) => l['id'] == id);
    expect(label['label'], 'Ali');
    expect(label['words'], 'Wi-Fi on');
    expect(admin.book.rows.single.title, 'Wi-Fi rule: Wi-Fi on');
  });

  test('Wi-Fi rule: the box detail reaches only the target phone', () async {
    final net = await Net220.make();
    final admin = await net.phone('dev-admin', adminRole: 'operator');
    final ali = await net.phone('dev-ali', user: 'u-ali');
    final bob = await net.phone('dev-bob', user: 'u-bob');
    net.knowAll();
    await net.link('dev-admin', 'dev-bob');
    await net.link('dev-bob', 'dev-ali');
    await admin.svc.make(
        action: 'wifi_rule',
        targetUserId: 'u-ali',
        label: 'Ali',
        targetDevices: ['dev-ali'],
        detail: {'wifi_radio_policy': 'forced_off'});
    await settle();
    expect(ali.did.log, ['wifi:forced_off']);
    expect(bob.did.log, isEmpty);
  });

  test('sign out: Done first, then the phone signs out (chats stay)', () async {
    final net = await Net220.make();
    final admin = await net.phone('dev-admin', adminRole: 'owner');
    final ali = await net.phone('dev-ali', user: 'u-ali');
    net.knowAll();
    await net.link('dev-admin', 'dev-ali');
    var leftChats = 0;
    AdminActionSignOut.onSignedOut = () async => leftChats++;
    final id = await admin.svc
        .make(action: 'remove_phone', targetUserId: 'u-ali', label: 'Ali', targetDevices: ['dev-ali']);
    await settle();
    expect(admin.svc.stateOf(id), 'done'); // the receipt left before signing out
    expect(ali.did.log, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(ali.did.log, ['removed']);
    expect(leftChats, 1);
    AdminActionSignOut.onSignedOut = null;
  });

  test('version rule: every phone takes it, "Reached N", receipts only to the server',
      () async {
    final net = await Net220.make();
    final srv = FakeServer220();
    final ali = await net.phone('dev-ali', srv: srv);
    final bob = await net.phone('dev-bob');
    net.knowAll();
    await net.link('dev-ali', 'dev-bob');
    final card = await serverCard220(net.server,
        id: 'aa_ver', action: 'version_rule', need: 0, to: const [],
        inner: await net.server.blob({'kind': 'version_rule', 'min': 131}));
    await ali.svc.offerCard(card, from: 'server');
    await settle();
    expect(ali.did.log, ['version']);
    expect(bob.did.log, ['version']); // carried on and taken there too
    expect(ali.svc.stateOf('aa_ver'), 'pending'); // need 0: stays until the server says
    expect(net.sent.where((s) => s.$3 == 'admin_act_done'), isEmpty);
    await ali.svc.syncWithServer();
    expect(srv.gotReceipts.map((b) => b.body).join(), contains('"action_id":"aa_ver"'));
    final row = AdminActionRow(
        id: 'v', action: 'version_rule', title: 'Old app rule', name: '', sub: '',
        state: 'pending', done: 7, need: 0);
    expect(adminActionLook(row).$2, 'Reached 7');
  });

  testWidgets('Admin actions page: crown slot, rows like mock A-4, tabs, offline bar',
      (tester) async {
    await tester.runAsync(loadRoboto216);
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final book = AdminActionBook.forTest()
      ..set(const [
        AdminActionRow(
            id: 'a1', action: 'block', title: 'Block', name: 'Ali Raza', sub: '',
            state: 'pending', done: 0, need: 1, mine: true, madeAt: '2026-11-05T10:00:00Z'),
        AdminActionRow(
            id: 'a2', action: 'off', title: 'Off (account closed)', name: 'Sumaira', sub: '',
            state: 'pending', done: 1, need: 2, mine: true, madeAt: '2026-11-04T10:00:00Z'),
        AdminActionRow(
            id: 'a3', action: 'sign_out', title: 'Sign out', name: 'Bilal', sub: '',
            state: 'done', done: 1, need: 1, mine: true, madeAt: '2026-11-03T10:00:00Z',
            finishedAt: '2026-11-03T12:00:00Z', via: 'wifi_direct'),
      ]);
    await tester.pumpWidget(MaterialApp(home: AdminActionsScreen(role: 'owner', book: book)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('admin_actions_role')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('admin_actions_role'))), const Size(36, 36));
    expect(find.byKey(const ValueKey('admin_actions_offline_bar')), findsOneWidget);
    expect(find.text('Pending 2'), findsOneWidget);
    expect(find.text('Done 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_actions_list')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_action_a1')), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Block'));
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(title.style?.fontSize, 16);
    // Order: newest first.
    expect(tester.getTopLeft(find.text('Block')).dy,
        lessThan(tester.getTopLeft(find.text('Off (account closed)')).dy));
    await tester.tap(find.byKey(const ValueKey('admin_actions_tab_1')));
    await tester.pump();
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.textContaining('via Wi-Fi Direct'), findsOneWidget);
    expect(find.text('Block'), findsNothing);
  });

  testWidgets('Admin actions page: empty Pending says there is no time limit', (tester) async {
    await tester.runAsync(loadRoboto216);
    await tester.pumpWidget(MaterialApp(
        home: AdminActionsScreen(role: 'operator', book: AdminActionBook.forTest())));
    await tester.pump();
    expect(find.text('Nothing pending'), findsOneWidget);
    expect(find.textContaining('no time limit'), findsOneWidget);
  });

  test('sources: wired in the app, mesh frames in Kotlin, no admin login words', () {
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(deps, contains('AdminActionService('));
    expect(deps, contains('SqlAdminActionStore('));
    final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/mesh/MeshBlockPolicy.kt')
        .readAsStringSync();
    for (final t in ['admin_act_digest', 'admin_act_cards', 'admin_act_done']) {
      expect(kt, contains('"$t"'));
    }
    final svc = File('lib/features/admin/data/actions/admin_action_service.dart')
        .readAsStringSync();
    expect(svc, isNot(contains('Sign in to Admin')));
    expect(svc, contains('_signStop('));
    final store = File('lib/core/services/local_store.dart').readAsStringSync();
    expect(store, contains('admin_action_receipts'));
  });
}
