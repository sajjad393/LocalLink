// Bundle 307: Get chat fixes (A) + Conversations redesign (B) + live card (C).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/services/hidden_store_221.dart';
import 'package:locallink/features/admin/data/actions/admin_action_card.dart';
import 'package:locallink/features/admin/data/actions/admin_action_doers.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_request_sheet.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'support/b216_fonts.dart';
import 'support/b220_fakes.dart';

/// A tiny messages DB: `sender IN (..) AND recipient IN (..)` like SQLite.
class _Db307 implements Database {
  _Db307(this.messages);
  final List<Map<String, Object?>> messages;
  final List<Map<String, Object?>> hiddenRows = const [];
  final List<List<Object?>> asked = [];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) async {
    if (table != 'messages' && table != 'hidden_messages') return const [];
    final args = whereArgs ?? const [];
    asked.add(args);
    final half = args.length ~/ 2;
    final a = args.sublist(0, half).toSet();
    final b = args.sublist(half).toSet();
    final src = table == 'messages' ? messages : hiddenRows;
    return [
      for (final r in src)
        if (a.contains(r['sender_id']) && b.contains(r['recipient_id']) && r['sender_id'] != r['recipient_id']) r,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _m(String id, String from, String to) => {
      'id': id,
      'sender_id': from,
      'recipient_id': to,
      'body': 'hi $id',
      'created_at': '2026-11-10T10:00:00.000Z',
      'status': 'delivered',
      'channel': '',
    };

void main() {
  group('307 A9 Get chat reads the friend\'s old phones', () {
    // ayesha's phone (self) talked to kiran on his OLD phone (kOld) and on his
    // new phone (kNew). The card only knows kNew + ayesha.
    const self = 'android-ayesha';
    const kNew = 'android-kiran-new';
    const kOld = 'android-kiran-old';
    const other = 'android-sumaira';
    final db = _Db307([
      _m('1', self, kOld),
      _m('2', kOld, self),
      _m('3', self, kNew),
      _m('4', self, other), // a third person: never in the answer
    ]);
    ChatPhones307 phones({Map<String, Set<String>> past = const {}, Map<String, List<String>> users = const {}}) =>
        ChatPhones307(
          personPhones: (d) async => {d, ...?past[d]},
          userPhones: (u) async => users[u] ?? const [],
          selfDevice: () => self,
          selfUser: () => 'u-ayesha',
        );
    SqlChatRows221 rows(ChatPhones307? p) => SqlChatRows221(
        hidden: Hidden221(() => db), db: () => db, name: (_) async => '', widen: p?.of);
    const chat = ChatRef221(kind: 'direct', users: ['u-kiran', 'u-ayesha'], devices: [kNew, self]);

    test('before 307 (no widen) only the new phone is read', () async {
      final got = await rows(null).rows(chat);
      expect(got.map((r) => r.id).toList(), ['3']);
    });

    test('old phone from the 237 list -> all messages, never the third person', () async {
      final got = await rows(phones(past: {kNew: {kOld}})).rows(chat);
      expect(got.map((r) => r.id).toSet(), {'1', '2', '3'});
    });

    test('old phone kept with the contact (users) -> found too', () async {
      final got = await rows(phones(users: {'u-kiran': [kOld]})).rows(chat);
      expect(got.map((r) => r.id).toSet(), {'1', '2', '3'});
    });

    test('card without this phone id: my own phone is added when my account is in the chat', () async {
      const card = ChatRef221(kind: 'direct', users: ['u-kiran', 'u-ayesha'], devices: [kOld, 'android-ayesha-gone']);
      final got = await rows(phones()).rows(card);
      expect(got.map((r) => r.id).toSet(), {'1', '2'});
    });

    test('my phone is NOT added when my account is not one of the two', () async {
      final p = ChatPhones307(
          personPhones: (d) async => {d},
          userPhones: (_) async => const [],
          selfDevice: () => self,
          selfUser: () => 'u-noshad');
      const card = ChatRef221(kind: 'direct', users: ['u-kiran', 'u-sumaira'], devices: [kOld, other]);
      expect(await p.of(card), {kOld, other});
    });

    test('group chats are unchanged', () async {
      const g = ChatRef221(kind: 'group', groupId: 'g1');
      expect(await phones(past: {kNew: {kOld}}).of(g), <String>{});
    });

    test('a failing lookup never breaks the answer', () async {
      final p = ChatPhones307(
          personPhones: (_) async => throw StateError('x'),
          userPhones: (_) async => throw StateError('y'),
          selfDevice: () => self,
          selfUser: () => 'u-ayesha');
      final got = await rows(p).rows(chat);
      expect(got.map((r) => r.id).toSet(), {'3'}); // the card ids still work
    });

    test('wired in the app + empty log line', () {
      final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(deps, contains('personPhones: store.phonesOfPerson237'));
      expect(deps, contains('widen: chatPhones307.of'));
      final hs = File('lib/core/services/hidden_store_221.dart').readAsStringSync();
      expect(hs, contains("'CHAT_ROWS_EMPTY_307'"));
      expect(hs, contains(r"widened=${all.length - given.length}"));
    });
  });

  _tests307();

  group('307 E animations', () {
    test('numbers count up inside the highlight only', () {
      expect(countUp307('12 of 40', 12, 9), '9 of 40');
      expect(countUp307('12 of 40', 12, 12), '12 of 40');
      expect(countUp307('40 of 40', 40, 39), '39 of 40'); // the first whole number
      expect(countUp307('112 of 140', 12, 3), '112 of 140'); // not inside other numbers
      expect(countUp307('Sent', -1, 0), 'Sent');
    });

    testWidgets('with Remove animations on, batches and entrances show the end state', (tester) async {
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [
            Batch307(batch: 2, child: Text('m1')),
            Enter307(index: 3, child: Text('r1')),
          ]),
        ),
      ));
      expect(find.byType(Opacity), findsNothing);
      expect(find.text('m1'), findsOneWidget);
    });

    testWidgets('viewer messages fade in by 3s, later ones are plain', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [Batch307(batch: 0, child: Text('a')), Batch307(batch: 8, child: Text('z'))]),
      ));
      expect(find.ancestor(of: find.text('a'), matching: find.byType(Opacity)), findsOneWidget);
      expect(find.ancestor(of: find.text('z'), matching: find.byType(Opacity)), findsNothing);
      await tester.pumpAndSettle();
      final src = File('lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart').readAsStringSync();
      expect(src, contains('Batch307(batch: shown++ ~/ 3, child: _bubble(v, m))'));
      final screen = File('lib/features/admin/presentation/screens/admin_conversations_screen.dart').readAsStringSync();
      expect(screen, contains('curve: Curves.easeOutBack'));
      expect(screen, contains("duration: Motion307.d(context, 550),"));
    });
  });
}

// ------------------------------------------------- 307 A1-A7 + B (UI)

class _Srv307 implements ChatAdminServer {
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> reqs;
  final List<Map<String, dynamic>> created = [];
  _Srv307({this.chats = const [], this.reqs = const []});
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => chats;
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => reqs;
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

ChatRequests221 _svc307(_Srv307 server, {bool Function()? online}) {
  final saved = <String, String>{};
  return ChatRequests221(
    server: server,
    signIn: () async => (token: 't', role: 'owner', username: 'sajjad'),
    serverOnline: online ?? () => true,
    actions: null,
    reader: ChatAnswerReader(
        store: MemoryAnswerPartStore(),
        selfDeviceId: () => 'dev-admin',
        boxKeys: () async => const [],
        nameOf: (_) async => ''),
    myBoxKey: () async => '',
    selfUserId: () => 'u-admin',
    selfDeviceId: () => 'dev-admin',
    phonesOf: (u) async => [u],
    groupDevices: (_) async => const [],
    localChats: () async => const [],
    people: () async => const [
      {'id': 'u-k', 'name': 'kiran', 'username': 'kiran'},
      {'id': 'u-a', 'name': 'ayesha', 'username': 'ayesha'},
    ],
    localGroups: () async => const [],
    read: (k) async => saved[k],
    write: (k, v) async => saved[k] = v,
  );
}

Map<String, dynamic> _who307(String id, String n) => {'id': id, 'name': n, 'username': n};

final _chats307 = [
  {
    'id': 'c1',
    'kind': 'direct',
    'participants': [_who307('u-s', 'sajjad'), _who307('u-i', 'ibrahim')],
    'message_count': 128,
    'last_message_at': '2026-11-14T09:20:00Z',
  },
  {
    'id': 'c2',
    'kind': 'direct',
    'participants': [_who307('u-k', 'kiran'), _who307('u-a', 'ayesha')],
    'message_count': 56,
    'last_message_at': '2026-11-13T12:00:00Z',
  },
];

final _reqs307 = [
  {
    'id': 'r1', 'action': 'get_chat', 'label': 'sajjad & ibrahim', 'words': 'Full chat', 'state': 'done',
    'parts': 26, 'of': 26, 'made_at': '2026-11-14T10:00:00Z',
    'chat': {'kind': 'direct', 'users': ['u-s', 'u-i']},
  },
  {
    'id': 'r2', 'action': 'get_chat', 'label': 'kiran & ayesha', 'words': 'Last 7 days', 'state': 'pending',
    'parts': 12, 'of': 40, 'made_at': '2026-11-14T09:00:00Z',
    'chat': {'kind': 'direct', 'users': ['u-k', 'u-a']},
  },
  {
    'id': 'r3', 'action': 'get_chat', 'label': 'ibrahim & sumaira', 'words': 'Full chat', 'state': 'pending',
    'phones': 2, 'reached': 1, 'made_at': '2026-11-14T08:00:00Z',
    'chat': {'kind': 'direct', 'users': ['u-i', 'u-m']},
  },
  {
    'id': 'r5', 'action': 'get_chat', 'label': 'noshad & zara', 'words': 'Full chat', 'state': 'cancelled',
    'empty': true, 'made_at': '2026-11-12T07:00:00Z',
    'chat': {'kind': 'direct', 'users': ['u-n', 'u-z']},
  },
];

Future<void> _phone307(WidgetTester tester) async {
  await tester.runAsync(loadRoboto216);
  tester.view.physicalSize = const Size(400 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _open307(WidgetTester tester, ChatRequests221 svc, {bool dark = false}) async {
  await tester.pumpWidget(MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(), home: AdminConversationsScreen(requests: svc)));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
}

void _tests307() {
  List<String> logs(String e) =>
      AppLogFile.instance.pendingForTest.where((l) => l.contains('|$e|') || l.endsWith('|$e')).toList();

  group('307 A1-A7 Get chat fixes', () {
    late Net220 net;
    late Phone220 admin;

    setUp(() async {
      AppLogFile.instance.resetForTest();
      AdminClosedFlag.closed.value = false;
      net = await Net220.make();
      admin = await net.phone('dev-admin', user: 'u-sajjad', adminRole: 'owner');
    });

    test('A1: a "seen" note passes a relay and reaches the card maker', () async {
      final mid = await net.phone('dev-mid', user: 'u-mid');
      final kiran = await net.phone('dev-kiran', user: 'u-kiran', trust: false);
      net.knowAll();
      await net.link('dev-admin', 'dev-mid');
      await net.link('dev-mid', 'dev-kiran');
      final id = await admin.svc.make(
          action: 'block', targetUserId: 'u-kiran', label: 'kiran', targetDevices: ['dev-kiran']);
      await settle(60);
      expect(kiran.svc.waitTrustCount, 1);
      // The note went to the relay; the relay passed it on to the maker once.
      expect(net.count(AdminActionRules.seenType, from: 'dev-mid', to: 'dev-admin'), greaterThanOrEqualTo(1));
      expect(logs('ADMIN_ACT_SEEN_PASS'), hasLength(1));
      expect(admin.book.rows.singleWhere((r) => r.id == id).waitTrust, isTrue);
      expect(mid.did.log, isEmpty);
    });

    test('A3: "file not on this phone" answers "empty" (no fail, no receipt)', () async {
      final kiran = await net.phone('dev-kiran', user: 'u-kiran');
      net.knowAll();
      kiran.did.chat = (c, p) async => throw StateError('no_file');
      await net.link('dev-admin', 'dev-kiran');
      await admin.svc.make(
          action: 'get_file', targetUserId: '', label: 'kiran & ayesha',
          targetDevices: ['dev-kiran'], replyKey: 'k', need: 1);
      await settle(60);
      expect(logs('CHAT_REQ_EMPTY').single, contains('why=no_file'));
      expect(logs('ADMIN_ACT_DO_FAIL'), isEmpty);
      expect(net.count(AdminActionRules.seenType, from: 'dev-kiran', to: 'dev-admin'), greaterThanOrEqualTo(1));
    });

    test('A7: the row knows how many phones it went to and how many answered', () async {
      final kiran = await net.phone('dev-kiran', user: 'u-kiran');
      await net.phone('dev-ayesha', user: 'u-ayesha');
      net.knowAll();
      kiran.did.chat = (c, p) async => throw StateError('no_copy_here');
      await net.link('dev-admin', 'dev-kiran');
      await admin.svc.make(
          action: 'get_chat', targetUserId: '', label: 'kiran & ayesha',
          targetDevices: ['dev-kiran', 'dev-ayesha'], replyKey: 'k', need: 1);
      await settle(60);
      final row = admin.svc.rows().single;
      expect(row.phones, 2);
      expect(row.reached, 1);
    });

    test('A1 / A5: seen notes and the final state go to the server once', () async {
      final srv = FakeServer220();
      final owner = await net.phone('dev-own', user: 'u-own', adminRole: 'owner', srv: srv, online: true);
      final kiran = await net.phone('dev-kiran', user: 'u-kiran');
      final ayesha = await net.phone('dev-ayesha', user: 'u-ayesha');
      net.knowAll();
      kiran.did.chat = (c, p) async => throw StateError('no_copy_here');
      ayesha.did.chat = (c, p) async => throw StateError('no_copy_here');
      await net.link('dev-own', 'dev-kiran');
      await net.link('dev-own', 'dev-ayesha');
      final id = await owner.svc.make(
          action: 'get_chat', targetUserId: '', label: 'kiran & ayesha',
          targetDevices: ['dev-kiran', 'dev-ayesha'], replyKey: 'k', need: 1);
      await settle(60);
      expect(owner.svc.stateOf(id), 'cancelled');
      await owner.svc.syncWithServer();
      await settle(20);
      await owner.svc.syncWithServer();
      await settle(20);
      expect(srv.gotSeen, isNotEmpty);
      final closed = srv.gotClosed.where((c) => c['id'] == id).toList();
      expect(closed, hasLength(1), reason: 'uploaded once');
      expect(closed.single['state'], 'cancelled');
      expect(closed.single['empty'], isTrue);
    });

    test('A2: the server row fields are read (empty, phones, reached, closed)', () {
      final r = ChatRequestRow221.fromServer(const {
        'id': 'x', 'action': 'get_chat', 'state': 'cancelled', 'empty': true,
        'phones': 3, 'reached': 2, 'closed': true, 'opened': true, 'from_name': 'ayesha',
      });
      expect(r.empty, isTrue);
      expect(r.phones, 3);
      expect(r.reached, 2);
      expect(r.closed, isTrue);
      expect(r.opened, isTrue);
      expect(r.fromName, 'ayesha');
      expect(r.tag, 'No messages');
    });
  });

  group('307 RequestStep307 (C0 table)', () {
    RequestStep307 of(ChatRequestRow221 r) => RequestStep307.of(r);

    test('sent', () {
      final s = of(const ChatRequestRow221(id: 'a', action: 'get_chat', phones: 2));
      expect(s.step, Step307.sent);
      expect(s.progress, RequestStep307.startAt);
      expect(s.big, 'Sent to 2 phones');
      expect(s.highlight, 'Sent');
      expect(s.chip, 'Sent');
      expect(s.ring, '\u2026');
      expect(s.sub, 'Waiting for their phones');
      expect(s.live, isTrue);
    });

    test('reached', () {
      final s = of(const ChatRequestRow221(id: 'a', action: 'get_chat', phones: 2, reached: 1));
      expect(s.step, Step307.reached);
      expect(s.progress, RequestStep307.reachedAt);
      expect(s.big, '1 of 2 phones');
      expect(s.highlight, '1 of 2');
      expect(s.chip, '1 of 2 phones');
      expect(s.ring, '1/2');
      expect(s.short, '1/2');
      expect(s.sub, 'Looking for the chat');
    });

    test('coming', () {
      final s = of(const ChatRequestRow221(id: 'a', action: 'get_chat', parts: 12, of: 40, fromName: 'ayesha'));
      expect(s.step, Step307.coming);
      expect(s.big, '12 of 40 parts');
      expect(s.chip, '12 of 40');
      expect(s.ring, '30%');
      expect(s.short, '12/40');
      expect(s.sub, "Answer coming from ayesha's phone");
      expect(s.progress, closeTo(66.666 + 33.334 * 0.3, 0.01));
    });

    test('40 of 40 -> Ready (live until opened or closed)', () {
      final s = of(const ChatRequestRow221(id: 'a', action: 'get_chat', parts: 40, of: 40));
      expect(s.step, Step307.ready);
      expect(s.progress, 100);
      expect(s.big, 'Ready to read');
      expect(s.chip, 'Ready');
      expect(s.sub, 'Tap to open \u00b7 40 parts');
      expect(s.live, isTrue);
      expect(of(const ChatRequestRow221(id: 'a', action: 'get_chat', parts: 40, of: 40, opened: true)).live,
          isFalse);
    });

    test('empty + cancelled + group', () {
      final e = of(const ChatRequestRow221(id: 'a', action: 'get_chat', state: 'cancelled', empty: true));
      expect(e.step, Step307.empty);
      expect(e.chip, 'No messages');
      expect(e.sub, 'No phone has this chat');
      expect(e.live, isFalse);
      final c = of(const ChatRequestRow221(id: 'a', action: 'get_chat', state: 'cancelled'));
      expect(c.step, Step307.cancelled);
      expect(c.live, isFalse);
      final g = of(const ChatRequestRow221(
          id: 'a', action: 'get_chat', phones: 5, chat: {'kind': 'group', 'group_id': 'g1'}));
      expect(g.big, 'Sent to 5 phones');
    });

    test('live order: Ready, then furthest along, newest first', () {
      final rows = [
        const ChatRequestRow221(id: 'sent', action: 'get_chat', madeAt: '2026-11-14T12:00:00Z'),
        const ChatRequestRow221(id: 'reach', action: 'get_chat', phones: 2, reached: 1, madeAt: '2026-11-14T11:00:00Z'),
        const ChatRequestRow221(id: 'parts', action: 'get_chat', parts: 2, of: 9, madeAt: '2026-11-14T10:00:00Z'),
        const ChatRequestRow221(id: 'ready', action: 'get_chat', parts: 9, of: 9, madeAt: '2026-11-14T09:00:00Z'),
        const ChatRequestRow221(id: 'gone', action: 'get_chat', state: 'cancelled', empty: true),
        const ChatRequestRow221(id: 'file', action: 'get_file'),
      ];
      expect(RequestStep307.liveOrder(rows).map((r) => r.id), ['ready', 'parts', 'reach', 'sent']);
    });
  });

  group('307 B screens', () {
    tearDown(() => Motion307.loopsForTest = null);

    for (final dark in [false, true]) {
      final tag = dark ? 'dark' : 'light';

      testWidgets('header pill + Requests tab: live card, In progress, Finished ($tag)', (tester) async {
        await _phone307(tester);
        await _open307(tester, _svc307(_Srv307(chats: _chats307, reqs: _reqs307)), dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('chats221_online_bar')), findsOneWidget);
        expect(find.text('Server connected'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('tabs221_1')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        // Live: Ready first, 3 live (r1 ready, r2 parts, r3 reached), dots.
        expect(find.byKey(const ValueKey('live307_card_r1')), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          expect(find.byKey(ValueKey('live307_dot_$i')), findsOneWidget);
        }
        expect(find.byKey(const ValueKey('live307_dot_3')), findsNothing);
        // In progress: chip + ring; the parts row keeps its text and bar.
        expect(find.byKey(const ValueKey('requests221_row_r2')), findsOneWidget);
        expect(find.text('12 of 40 parts'), findsOneWidget);
        expect(find.byKey(const ValueKey('parts221_bar')), findsOneWidget);
        expect(find.text('1 of 2 phones'), findsOneWidget);
        expect(find.byType(ProgressRing307), findsNWidgets(2));
        // Finished: Ready + No messages tags; no "since", no path words.
        expect(find.byKey(const ValueKey('requests307_finished')), findsOneWidget);
        expect(find.text('No messages'), findsOneWidget);
        expect(find.textContaining('since'), findsNothing);
        expect(find.textContaining('Wi-Fi Direct'), findsNothing);
      });
    }

    testWidgets('carousel: swipe, auto-advance, a touch pauses it', (tester) async {
      Motion307.loopsForTest = true;
      await _phone307(tester);
      await _open307(tester, _svc307(_Srv307(chats: _chats307, reqs: _reqs307)));
      await tester.tap(find.byKey(const ValueKey('tabs221_1')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('live307_card_r1')), findsOneWidget);
      // Swipe left -> the next card (r2).
      await tester.fling(find.byKey(const ValueKey('live307_carousel')), const Offset(-300, 0), 1200);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('live307_card_r2')), findsOneWidget);
      // The touch pauses auto-advance for 10 s.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('live307_card_r2')), findsOneWidget);
      // After the pause, it moves on by itself.
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('live307_card_r2')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Chats tab: Ready to read tile only for a ready answer; Get chat capsule; search', (tester) async {
      await _phone307(tester);
      await _open307(tester, _svc307(_Srv307(chats: _chats307, reqs: _reqs307)));
      expect(find.byKey(const ValueKey('chats307_ready_c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('chats307_ready_c2')), findsNothing);
      expect(find.text('12/40'), findsOneWidget); // c2's request is running
      await tester.enterText(find.byKey(const ValueKey('chats307_search')), 'kir');
      await tester.pump();
      expect(find.byKey(const ValueKey('chats221_row_c1')), findsNothing);
      expect(find.byKey(const ValueKey('chats221_row_c2')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _open307(tester, _svc307(_Srv307(chats: _chats307)));
      expect(find.byKey(const ValueKey('chats307_ready')), findsNothing);
      expect(find.byKey(const ValueKey('chats221_ask_c1')), findsOneWidget);
      expect(find.text('Get chat'), findsNWidgets(2));
    });

    testWidgets('A2: the pill flips within 10 s when the server drops', (tester) async {
      var up = true;
      await _phone307(tester);
      await _open307(tester, _svc307(_Srv307(chats: _chats307), online: () => up));
      expect(find.byKey(const ValueKey('chats221_online_bar')), findsOneWidget);
      up = false;
      await tester.pump(AdminConversationsScreen.pillEvery);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.byKey(const ValueKey('chats221_offline_bar')), findsOneWidget);
      expect(find.text('No server'), findsOneWidget);
    });

    testWidgets('sheet: person tiles + swap + range grid + Get chat', (tester) async {
      await _phone307(tester);
      await _open307(tester, _svc307(_Srv307(chats: _chats307)));
      await tester.tap(find.byKey(const ValueKey('chats221_ask_c2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final r in ['full', '7', '30', 'dates']) {
        expect(find.byKey(ValueKey('request221_range_$r')), findsOneWidget);
      }
      expect(find.text('First person'), findsOneWidget);
      expect(find.text('Second person'), findsOneWidget);
      expect(find.text('kiran'), findsOneWidget);
      expect(find.textContaining('They see nothing'), findsOneWidget);
      expect(find.textContaining('Wi-Fi Direct'), findsNothing);
      expect(find.byKey(const ValueKey('request307_swap')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sheet swap button swaps the two people', (tester) async {
      await _phone307(tester);
      final server = _Srv307();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ChatRequestSheet221(
                      service: _svc307(server),
                      preset: const ChatPick221.direct('u-k', 'u-a', label: 'kiran & ayesha'))))));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('request307_swap')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('request221_send')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(server.created.single['user_a'], 'u-a');
      expect(server.created.single['user_b'], 'u-k');
    });

    testWidgets('viewer: progress card with ring, then Ready (no route words)', (tester) async {
      await _phone307(tester);
      const req = ChatRequestRow221(
          id: 'r2', action: 'get_chat', label: 'kiran & ayesha', chat: {'kind': 'direct', 'users': ['u-k', 'u-a']});
      const half = ChatAnswerView(id: 'r2', answerId: 'a', fromDevice: 'dev-a', fromName: 'ayesha', of: 40, parts: 28,
          messages: [
            {'id': 'm1', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-13T10:00:00', 'body': 'Salam', 'route': 'mesh'},
          ]);
      await tester.pumpWidget(
          MaterialApp(home: AdminChatViewerScreen(service: _svc307(_Srv307()), request: req, view: half)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('viewer221_parts')), findsOneWidget);
      expect(find.text('28 of 40 parts · the rest is on the way'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('viewer221_parts')), matching: find.byType(ProgressRing307)),
          findsOneWidget);
      expect(find.text('Mesh'), findsNothing);
      const full = ChatAnswerView(id: 'r2', answerId: 'a', fromDevice: 'dev-a', fromName: 'ayesha', of: 40, parts: 40,
          complete: true, messages: []);
      expect(full.complete, isTrue);
      final src = File('lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart').readAsStringSync();
      expect(src, contains("ValueKey('viewer307_ready')"));
      expect(src, contains('Duration(seconds: 3)'));
    });

    test('no path words on the 3 screens + the locked bits stay', () {
      for (final f in [
        'lib/features/admin/presentation/screens/admin_conversations_screen.dart',
        'lib/features/admin/presentation/screens/admin_chat_request_sheet.dart',
        'lib/features/admin/presentation/widgets/conversations_kit307.dart',
      ]) {
        final s = File(f).readAsStringSync();
        expect(s.contains('wiFiDirect') || s.contains("'Wi-Fi Direct'") || s.contains('noServerRequestsGoByWi('),
            isFalse, reason: f);
      }
      final conv = File('lib/features/admin/presentation/screens/admin_conversations_screen.dart').readAsStringSync();
      expect(conv, contains('AdminCrown.mark(15, halo: null)'));
      expect(conv, isNot(contains('LinkBanner221(online')));
    });

    test('every 307 word has Urdu words', () {
      final en = File('lib/l10n/app_en.arb').readAsStringSync();
      final ur = File('lib/l10n/app_ur.arb').readAsStringSync();
      final keys = RegExp(r'"(\w+307)":').allMatches(en).map((m) => m.group(1)!).toSet();
      expect(keys.length, greaterThanOrEqualTo(31));
      for (final k in keys) {
        expect(ur, contains('"$k":'), reason: k);
      }
    });
  });
}
