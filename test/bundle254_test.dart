import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_request_sheet.dart';
import 'package:locallink/features/admin/presentation/screens/admin_panel_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/admin_action_book.dart';
import 'package:locallink/features/admin/data/actions/admin_action_card.dart';
import 'package:locallink/features/admin/data/actions/admin_action_doers.dart';
import 'package:locallink/features/admin/presentation/screens/admin_actions_screen.dart';

import 'support/b216_fonts.dart';
import 'support/b220_fakes.dart';

class _Server implements ChatAdminServer {
  final List<Map<String, dynamic>> created = [];
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => const [];
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => const [];
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async {
    created.add(body);
    return {'id': 'aa_new'};
  }

  @override
  Future<ChatAnswerView> answer(String token, String id) async => ChatAnswerView(id: id);
  @override
  Future<Uint8List?> download(String token, String id) async => null;
  @override
  Future<void> close(String token, String id) async {}
  @override
  Future<Map<String, dynamic>> file(String token, String id,
          {required String fileId, String messageId = '', String name = ''}) async =>
      {'id': 'aa_file'};
  @override
  Future<Map<String, dynamic>> purge(String token, Map<String, dynamic> body) async => {'need': 2};
}

const _people = [
  {'id': 'u-me', 'name': 'sajjad', 'username': '', 'device': 'dev-me', 'me': true},
  {'id': 'u-n-old', 'name': 'noshad', 'username': 'noshad', 'device': 'd181c0', 'old': true},
  {'id': 'u-n-new', 'name': 'noshad', 'username': 'noshad2', 'device': 'd181c0'},
];

ChatRequests221 _svc(_Server server, {bool online = true}) {
  final saved = <String, String>{};
  final phones = {'u-me': ['dev-me'], 'u-n-old': ['d181c0'], 'u-n-new': ['d181c0']};
  return ChatRequests221(
    server: server,
    signIn: () async => (token: 't', role: 'owner', username: 'sajjad'),
    serverOnline: () => online,
    actions: null,
    reader: ChatAnswerReader(
        store: MemoryAnswerPartStore(),
        selfDeviceId: () => 'dev-me',
        boxKeys: () async => const [],
        nameOf: (_) async => ''),
    myBoxKey: () async => '',
    selfUserId: () => 'u-me',
    selfDeviceId: () => 'dev-me',
    phonesOf: (u) async => phones[u] ?? const [],
    groupDevices: (_) async => const [],
    localChats: () async => const [],
    people: () async => _people,
    localGroups: () async => const [],
    read: (k) async => saved[k],
    write: (k, v) async => saved[k] = v,
  );
}

/// Bundle 254 (Phase 21): problems seen in the 9 Nov screenshots.
void main() {
  late Net220 net;
  late Phone220 admin;
  late Phone220 noshad;

  List<String> logs(String e) =>
      AppLogFile.instance.pendingForTest.where((l) => l.contains('|$e|') || l.endsWith('|$e')).toList();

  setUp(() async {
    AppLogFile.instance.resetForTest();
    AdminClosedFlag.closed.value = false;
    net = await Net220.make();
    admin = await net.phone('dev-admin', user: 'u-sajjad', adminRole: 'owner');
    noshad = await net.phone('dev-noshad', user: 'u-noshad', trust: false);
    net.knowAll();
  });

  group('21.3 no server key yet', () {
    test('the card is kept aside once, the admin sees "reached the phone", no re-send', () async {
      await net.link('dev-admin', 'dev-noshad');
      final id = await admin.svc.make(
          action: 'block', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      await settle();
      expect(noshad.did.log, isEmpty);
      expect(noshad.svc.waitTrustCount, 1);
      expect(admin.svc.stateOf(id), 'pending');
      final row = admin.book.rows.single;
      expect(row.waitTrust, isTrue);
      expect(adminActionLook(row).$1, 'reached the phone · it must reach the server once');
      expect(logs('ADMIN_ACT_WAIT_TRUST'), hasLength(1));
      expect(logs('ADMIN_ACT_REJECT'), isEmpty);
      // A minute later: the admin phone does not send the card again.
      final cardsBefore = net.count(AdminActionRules.cardsType, from: 'dev-admin', to: 'dev-noshad');
      net.now = net.now.add(const Duration(minutes: 2));
      await admin.svc.sendDigests();
      await noshad.svc.sendDigests();
      await settle();
      expect(net.count(AdminActionRules.cardsType, from: 'dev-admin', to: 'dev-noshad'), cardsBefore);
      expect(logs('ADMIN_ACT_WAIT_TRUST'), hasLength(1));
    });

    test('when the key is saved the kept card is done by itself (no new copy)', () async {
      await net.link('dev-admin', 'dev-noshad');
      final id = await admin.svc.make(
          action: 'block', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      await settle();
      net.unlink('dev-admin', 'dev-noshad');
      noshad.trust = true;
      await noshad.svc.recheckWaitTrust();
      await settle();
      expect(noshad.did.log, ['block']);
      expect(noshad.svc.waitTrustCount, 0);
      await net.link('dev-admin', 'dev-noshad');
      await settle();
      expect(admin.svc.stateOf(id), 'done');
    });

    test('a kept cancel wins over its kept action', () async {
      await net.link('dev-admin', 'dev-noshad');
      final id = await admin.svc.make(
          action: 'block', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      await settle();
      await admin.svc.cancel(id);
      // The cancel reaches noshad through the admin's digest answer.
      net.now = net.now.add(const Duration(minutes: 2));
      await noshad.svc.sendDigests();
      await settle();
      expect(noshad.svc.waitTrustCount, 2);
      noshad.trust = true;
      await noshad.svc.recheckWaitTrust();
      await settle();
      expect(noshad.did.log, isEmpty);
    });

    test('a "seen" note from a phone that is not the target changes nothing', () async {
      final mid = await net.phone('dev-mid', user: 'u-mid', trust: false);
      net.knowAll();
      await net.link('dev-admin', 'dev-mid');
      await admin.svc.make(
          action: 'block', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      await settle();
      expect(mid.svc.waitTrustCount, 1);
      expect(admin.book.rows.single.waitTrust, isFalse);
      expect(adminActionLook(admin.book.rows.single).$1, contains('no phone reached yet'));
    });

    test('a phone that is not the target logs ADMIN_ACT_NOT_MINE once', () async {
      final mid = await net.phone('dev-mid', user: 'u-mid');
      net.knowAll();
      await net.link('dev-admin', 'dev-mid');
      await admin.svc.make(
          action: 'block', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      await settle();
      expect(mid.did.log, isEmpty);
      expect(logs('ADMIN_ACT_NOT_MINE'), hasLength(1));
    });
  });

  group('21.1 / 21.11 order of Block/Unblock and Off/Active', () {
    test('Block then Unblock offline: one pending (Unblock), the Block says Replaced', () async {
      final b = await admin.svc.make(
          action: 'block', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      net.now = net.now.add(const Duration(minutes: 1));
      final u = await admin.svc.make(
          action: 'unblock', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      await settle();
      expect(admin.svc.stateOf(b), 'replaced');
      expect(admin.svc.stateOf(u), 'pending');
      expect(admin.svc.pendingMine, 1);
      final rows = admin.book.rows;
      expect(rows.where((r) => r.pending), hasLength(1));
      expect(adminActionLook(rows.firstWhere((r) => r.id == b)).$2, 'Replaced');
      // Another person or another kind of action is not touched.
      final other = await admin.svc.make(
          action: 'sign_out', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      expect(admin.svc.stateOf(u), 'pending');
      expect(admin.svc.stateOf(other), 'pending');
    });

    test('the target never does a replaced Block', () async {
      final b = await admin.svc.make(
          action: 'block', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      final u = await admin.svc.make(
          action: 'unblock', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      noshad.trust = true;
      await net.link('dev-admin', 'dev-noshad');
      await settle(60);
      expect(noshad.did.log, hasLength(1)); // the Unblock card's 212 record only
      expect(noshad.store.receiptRows['$u|dev-noshad'], isNotNull);
      expect(noshad.store.receiptRows['$b|dev-noshad'], isNull);
      expect(admin.svc.stateOf(u), 'done');
    });

    test('an old Off that arrives after a newer Active leaves the phone open', () async {
      final admin2 = await net.phone('dev-admin2', user: 'u-admin2', adminRole: 'owner');
      noshad.trust = true;
      net.knowAll();
      await admin.svc.make(
          action: 'off', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      net.now = net.now.add(const Duration(hours: 1));
      await admin2.svc.make(
          action: 'active', targetUserId: 'u-noshad', label: 'noshad', targetDevices: ['dev-noshad']);
      await net.link('dev-admin2', 'dev-noshad');
      await settle();
      expect(noshad.did.log.last, 'open');
      await net.link('dev-admin', 'dev-noshad');
      await settle();
      expect(noshad.did.log, isNot(contains('closed')));
      expect(AdminClosedFlag.closed.value, isFalse);
      expect(logs('ADMIN_ACT_OLD_CLOSE'), hasLength(1));
    });
  });

  group('21.2 / 21.12 chat requests', () {
    test('two accounts on one phone: the request is refused (online and offline)', () async {
      for (final online in [true, false]) {
        final server = _Server();
        final svc = _svc(server, online: online);
        await expectLater(
            svc.request(ChatPick221.direct('u-n-old', 'u-n-new', label: 'x'), range: '7'),
            throwsA(predicate((e) => '$e'.contains('on the same phone'))));
        expect(server.created, isEmpty);
      }
      expect(await _svc(_Server()).samePhone('u-me', 'u-n-new'), isFalse);
    });

    test('label uses @usernames when the names are the same', () {
      expect(chatRequestLabel254(_people[1], _people[2]), '@noshad & @noshad2');
      expect(chatRequestLabel254(_people[0], _people[2]), 'sajjad & noshad');
    });

    testWidgets('picker: Me on top, @username + old account; same phone blocks Send; Me note',
        (tester) async {
      await tester.runAsync(loadRoboto216);
      tester.view.physicalSize = const Size(400 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final server = _Server();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ChatRequestSheet221(service: _svc(server))))));
      Future<void> pick(String field, String id) async {
        await tester.tap(find.byKey(ValueKey(field)));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(ValueKey('pick221_$id')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      await tester.tap(find.byKey(const ValueKey('request221_first')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Me (sajjad)'), findsOneWidget);
      expect(find.byKey(const ValueKey('pick254_me_tag')), findsOneWidget);
      expect(find.text('@noshad · old account'), findsOneWidget);
      expect(find.text('@noshad2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pick221_u-n-old')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await pick('request221_second', 'u-n-new');
      expect(find.byKey(const ValueKey('request254_same_phone')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('request221_send')));
      await tester.pump();
      expect(server.created, isEmpty);
      await pick('request221_first', 'u-me');
      expect(find.byKey(const ValueKey('request254_same_phone')), findsNothing);
      expect(find.textContaining('You already have this chat'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('request221_send')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(server.created, hasLength(1));
      expect(server.created.single['user_a'], 'u-me');
    });

    test('every target phone has no copy: one CHAT_REQ_EMPTY each, the request closes "No messages"',
        () async {
      final b = await net.phone('dev-b', user: 'u-b');
      noshad.trust = true;
      net.knowAll();
      noshad.did.chat = (c, p) async => throw StateError('no_copy_here');
      b.did.chat = (c, p) async => throw StateError('no_copy_here');
      await net.link('dev-admin', 'dev-noshad');
      await net.link('dev-admin', 'dev-b');
      final id = await admin.svc.make(
          action: 'get_chat', targetUserId: '', label: 'noshad & b',
          targetDevices: ['dev-noshad', 'dev-b'], replyKey: 'k', need: 1);
      await settle(60);
      expect(logs('CHAT_REQ_EMPTY'), hasLength(2));
      expect(logs('ADMIN_ACT_DO_FAIL'), isEmpty);
      expect(admin.svc.stateOf(id), 'cancelled');
      final row = admin.book.rows.single;
      expect(row.emptyAll, isTrue);
      expect(adminActionLook(row).$2, 'No messages');
      expect(const ChatRequestRow221(id: 'x', action: 'get_chat', state: 'cancelled', empty: true).tag,
          'No messages');
    });

    test('one phone empty, the other answers: the answer wins', () async {
      final b = await net.phone('dev-b', user: 'u-b');
      noshad.trust = true;
      net.knowAll();
      noshad.did.chat = (c, p) async => throw StateError('no_copy_here');
      b.did.chat = (c, p) async => 'ok';
      await net.link('dev-admin', 'dev-noshad');
      final id = await admin.svc.make(
          action: 'get_chat', targetUserId: '', label: 'noshad & b',
          targetDevices: ['dev-noshad', 'dev-b'], replyKey: 'k', need: 1);
      await settle(60);
      expect(admin.svc.stateOf(id), 'pending'); // b not met yet: stays pending
      await net.link('dev-admin', 'dev-b');
      await settle(60);
      expect(admin.svc.stateOf(id), 'done');
      expect(admin.book.rows.single.emptyAll, isFalse);
    });
  });

  group('21.4 admin status = chat header', () {
    test('a phone on local_net / wifi_direct with no saved flag counts as Wi-Fi Direct', () {
      var t = DateTime(2026, 11, 9, 23, 10);
      final hub = PresenceHub(clock: () => t);
      expect(adminHubTag254('n1', hub), isNull);
      hub.notePath('n1', up: true);
      hub.noteRoute(const PresenceRoute('n1', 'local_net'));
      expect(adminHubNearby254('n1', hub), isTrue);
      expect(adminHubTag254('n1', hub), LinkTag.wifiDirect);
      hub.noteRoute(const PresenceRoute('n1', 'lan'));
      adminHubTag254('n1', hub);
      t = t.add(const Duration(seconds: 6)); // a better way shows after 5 s
      expect(adminHubTag254('n1', hub), LinkTag.localWifi);
      hub.noteRoute(const PresenceRoute('n1', 'mesh', hops: 2, via: 'b'));
      expect(adminHubTag254('n1', hub), LinkTag.mesh);
    });

    test('the admin screen asks PresenceHub first and blocks by owner id', () {
      final src = File('lib/features/admin/presentation/screens/admin_panel_screen.dart').readAsStringSync();
      expect(src, contains('(_hubNearby(d.id) ||'));
      expect(src, contains('!_isBlockedDevice(d.id)'));
      expect(src, contains('final hub = _hubTag(d.id);'));
    });
  });

  group('21.5 / 21.6 / 21.8 / 21.9 looks', () {
    test('21.5 the map "You" avatar uses my real name; 21.6 the card clips itself', () {
      final map = File('lib/features/admin/presentation/widgets/link_paths_map.dart').readAsStringSync();
      expect(map, contains('AdminPersonAvatar216.noteYouName(selfName); // Bundle 254 (21.5)'));
      AdminPersonAvatar216.noteYouName('You');
      AdminPersonAvatar216.noteYouName('Sajjad');
      expect(AdminPersonAvatar216.youName, 'Sajjad');
      AdminPersonAvatar216.noteYouName('You'); // the default label never wins
      expect(AdminPersonAvatar216.youName, 'Sajjad');
      final kit = File('lib/features/admin/presentation/widgets/admin_kit216.dart').readAsStringSync();
      final card = kit.substring(kit.indexOf('class AdminCard216'), kit.indexOf('class AdminNote216'));
      expect(card, contains('clipBehavior: Clip.antiAlias,'));
      expect(card, isNot(contains('ClipRRect')));
    });

    testWidgets('21.8 banner pinned outside the list; 21.9 "Tap to cancel" only on cancellable rows',
        (tester) async {
      await tester.runAsync(loadRoboto216);
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final book = AdminActionBook.forTest()
        ..set(const [
          AdminActionRow(
              id: 'p1', action: 'block', title: 'Block', name: 'Ali Raza', sub: '',
              state: 'pending', done: 0, need: 1, mine: true, madeAt: '2026-11-05T10:00:00Z'),
          AdminActionRow(
              id: 'p2', action: 'version_rule', title: 'Old app rule', name: '', sub: '',
              state: 'pending', done: 3, need: 0, mine: true, madeAt: '2026-11-04T10:00:00Z'),
          AdminActionRow(
              id: 'd1', action: 'sign_out', title: 'Sign out', name: 'Bilal', sub: '',
              state: 'done', done: 1, need: 1, mine: true, madeAt: '2026-11-03T10:00:00Z',
              finishedAt: '2026-11-03T12:00:00Z', via: 'wifi_direct'),
        ]);
      await tester.pumpWidget(MaterialApp(home: AdminActionsScreen(role: 'owner', book: book)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final bar = find.byKey(const ValueKey('admin_actions_offline_bar'));
      expect(bar, findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('a216_list')), matching: bar), findsNothing);
      final top = tester.getTopLeft(bar).dy;
      await tester.drag(find.byKey(const ValueKey('a216_list')), const Offset(0, -200));
      await tester.pump();
      expect(tester.getTopLeft(bar).dy, top, reason: 'does not scroll away');
      expect(find.byKey(const ValueKey('admin_action_cancel_hint_p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin_action_cancel_hint_p2')), findsNothing);
      expect(find.text('Tap to cancel'), findsOneWidget);
    });

    testWidgets('21.5 "You" avatar draws the letter of my name', (tester) async {
      AdminPersonAvatar216.youName = 'Sajjad';
      addTearDown(() => AdminPersonAvatar216.youName = '');
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AdminPersonAvatar216(name: 'You'))));
      expect(find.text('S'), findsOneWidget);
      expect(find.text('Y'), findsNothing);
    });

    testWidgets('AdminCard216 still shows its child with padding', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: AdminCard216(padding: EdgeInsets.all(12), child: Text('Link paths')))));
      expect(find.text('Link paths'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Link paths')).dx, greaterThanOrEqualTo(12));
    });
  });
}
