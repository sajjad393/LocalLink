import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/server_clock_255.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/chat_request_notifier_307.dart';
import 'package:locallink/features/admin/data/actions/group_notes_314.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart' show SignedBlob;
import 'package:locallink/features/admin/presentation/screens/admin_chat_request_sheet.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';

import 'support/b216_fonts.dart';

/// Bundle 314 (TODO_314): not my own chats, one open request per chat,
/// nearby group notes, the notification time.
class _Srv implements ChatAdminServer {
  List<Map<String, dynamic>> chats = const [];
  List<Map<String, dynamic>> reqs = const [];
  ChatAdminRefused? refuse;
  final List<Map<String, dynamic>> created = [];
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => chats;
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => reqs;
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async {
    final r = refuse;
    if (r != null) throw r;
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

class _World {
  bool online = true;
  final saved = <String, String>{};
  final srv = _Srv();
  Map<String, dynamic> serverGroups = {
    'groups': [
      {'id': 'g-mine', 'name': 'Family', 'members': 5, 'me': true, 'member_devices': ['dev-admin', 'd1']},
      {'id': 'g-srv', 'name': 'Office', 'members': 3, 'me': false, 'member_devices': ['d1', 'd2', 'd3']},
    ],
    'nearby': [
      {'id': 'g-near', 'name': 'Study group', 'members': 4, 'me': false, 'member_devices': ['d4', 'd5', 'd6', 'd7']},
    ],
  };
  List<Map<String, dynamic>> reported = [
    {'id': 'g-rep', 'name': 'Cricket', 'members': ['d5', 'd6', 'd7'], 'made_at': '2026-11-15T10:00:00Z'},
    {'id': 'g-rep-mine', 'name': 'Cousins', 'members': ['dev-admin', 'd8']},
  ];
  final localGroups = <Map<String, dynamic>>[
    {'id': 'g-local-mine', 'name': 'Neighbours'},
    {'id': 'g-local-other', 'name': 'Old team'},
  ];
  final groupDevices = <String, List<String>>{
    'g-local-mine': ['dev-admin', 'd1'],
    'g-local-other': ['d2', 'd3'],
  };
  int serverGroupCalls = 0;

  ChatRequests221 svc() => ChatRequests221(
        server: srv,
        signIn: () async => (token: 't', role: 'owner', username: 'sajjad'),
        serverOnline: () => online,
        actions: null,
        reader: ChatAnswerReader(
            store: MemoryAnswerPartStore(),
            selfDeviceId: () => 'dev-admin',
            boxKeys: () async => const [],
            nameOf: (_) async => ''),
        myBoxKey: () async => '',
        selfUserId: () => 'u-admin',
        selfDeviceId: () => 'dev-admin',
        phonesOf: (u) async => switch (u) {
          'u-admin' => ['dev-admin'],
          'u-a' => ['dev-a'],
          'u-b' => ['dev-b'],
          _ => [u],
        },
        groupDevices: (g) async => groupDevices[g] ?? const [],
        localChats: () async => const [],
        people: () async => const [
              {'id': 'u-admin', 'name': 'sajjad', 'username': '', 'device': 'dev-admin', 'me': true},
              {'id': 'u-a', 'name': 'ayesha', 'username': 'ayesha', 'device': 'dev-a'},
              {'id': 'u-b', 'name': 'kiran', 'username': 'kiran', 'device': 'dev-b'},
            ],
        localGroups: () async => localGroups,
        read: (k) async => saved[k],
        write: (k, v) async => saved[k] = v,
        serverGroups: (token) async {
          serverGroupCalls++;
          return serverGroups;
        },
        reportedGroups: () async => reported,
      );
}

Map<String, dynamic> _req(String id,
        {String state = 'pending',
        int parts = 0,
        int of = 0,
        bool empty = false,
        bool closed = false,
        Map<String, dynamic>? chat}) =>
    {
      'id': id,
      'action': 'get_chat',
      'label': 'ayesha & kiran',
      'words': 'Full chat',
      'state': state,
      'parts': parts,
      'of': of,
      'empty': empty,
      'closed': closed,
      'made_at': '2026-11-16T10:00:00Z',
      'chat': chat ?? {'kind': 'direct', 'users': ['u-a', 'u-b']},
    };

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openPicker(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await _settle(tester);
}

class _Keys {
  final pub = <String, String>{};
}

void main() {
  setUp(() => ServerClock255.wrong.value = null);

  group('Issue 1 - chats I am in are not asked', () {
    testWidgets('person picker: no Me row and no 307 Me note', (tester) async {
      await tester.runAsync(loadRoboto216);
      tester.view.physicalSize = const Size(400 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final w = _World();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ChatRequestSheet221(service: w.svc())))));
      await _openPicker(tester, 'request221_first');
      expect(find.byKey(const ValueKey('pick221_u-admin')), findsNothing);
      expect(find.byKey(const ValueKey('pick254_me_tag')), findsNothing);
      expect(find.text('Me (sajjad)'), findsNothing);
      expect(find.byKey(const ValueKey('pick221_u-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick221_u-b')), findsOneWidget);
      expect(find.byKey(const ValueKey('request307_me_note')), findsNothing);
    });

    test('group list = every group I am not in (server, nearby, this phone, reported)', () async {
      final w = _World();
      final ids = [for (final g in await w.svc().pickerGroups314()) g['id']];
      expect(ids.toSet(), {'g-srv', 'g-near', 'g-local-other', 'g-rep'});
      expect(ids, isNot(contains('g-mine')));
      expect(ids, isNot(contains('g-local-mine')));
      expect(ids, isNot(contains('g-rep-mine')));
      final byId = {for (final g in await w.svc().pickerGroups314()) g['id']: g};
      expect(groupPickLine314(byId['g-srv']!), '3 members');
      expect(groupPickLine314(byId['g-near']!), 'Nearby \u00b7 4 members');
      expect(groupPickLine314(byId['g-rep']!), 'Nearby \u00b7 3 members');
      expect(byId['g-near']!['member_devices'], ['d4', 'd5', 'd6', 'd7']);
    });

    test('offline: the group list comes from the last saved server list + reported', () async {
      final w = _World();
      await w.svc().pickerGroups314(); // online: saved
      w.online = false;
      w.serverGroups = const {};
      final ids = {for (final g in await w.svc().pickerGroups314()) g['id']};
      expect(ids, {'g-srv', 'g-near', 'g-local-other', 'g-rep'});
    });

    testWidgets('group picker rows read "Office · 3 members" and "Study group · Nearby · 4 members"',
        (tester) async {
      await tester.runAsync(loadRoboto216);
      tester.view.physicalSize = const Size(400 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final w = _World();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ChatRequestSheet221(
                      service: w.svc(), preset: const ChatPick221.group('g-x', label: 'x'))))));
      await _settle(tester);
      await _openPicker(tester, 'request221_group');
      expect(find.byKey(const ValueKey('pick221_g-mine')), findsNothing);
      expect(find.text('Office'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);
      expect(find.text('Study group'), findsOneWidget);
      expect(find.text('Nearby \u00b7 4 members'), findsOneWidget);
      expect(find.byKey(const ValueKey('pick314_line_g-near')), findsOneWidget);
    });

    test('my own chat is refused (online and offline), the server is never asked', () async {
      for (final online in [true, false]) {
        final w = _World()..online = online;
        final s = w.svc();
        for (final pick in [
          const ChatPick221.direct('u-admin', 'u-a', label: 'sajjad & ayesha'),
          const ChatPick221.direct('u-b', 'dev-admin', label: 'kiran & me'),
          const ChatPick221.group('g-local-mine', label: 'Neighbours'),
        ]) {
          await expectLater(
              s.request(pick, range: '7'),
              throwsA(isA<ChatAdminRefused>()
                  .having((e) => e.code, 'code', ownChatCode314)
                  .having((e) => e.message, 'words', "You are in this chat. It's already on your phone.")));
        }
        expect(w.srv.created, isEmpty);
      }
    });

    test('regression: other people\'s chat still goes to the server', () async {
      final w = _World();
      await w.svc().request(const ChatPick221.direct('u-a', 'u-b', label: 'ayesha & kiran'), range: '7');
      expect(w.srv.created, hasLength(1));
      expect(w.srv.created.single['user_a'], 'u-a');
    });
  });

  group('Issue 1b - one open request per chat', () {
    test('Sent / Reached / Coming block any range; Ready, empty, closed, cancelled do not', () async {
      for (final (row, blocks) in [
        (_req('r1'), true), // Sent
        (_req('r1', parts: 3, of: 10), true), // Coming
        (_req('r1', parts: 10, of: 10), false), // Ready
        (_req('r1', state: 'done', empty: true), false),
        (_req('r1', state: 'done', closed: true, parts: 1, of: 1), false),
        (_req('r1', state: 'cancelled'), false),
      ]) {
        final w = _World();
        w.srv.reqs = [row];
        final s = w.svc();
        for (final range in ['full', '7', '30']) {
          const pick = ChatPick221.direct('u-b', 'u-a', label: 'kiran & ayesha'); // any order
          if (blocks) {
            await expectLater(
                s.request(pick, range: range),
                throwsA(isA<ChatAdminRefused>()
                    .having((e) => e.code, 'code', alreadyAskedCode314)
                    .having((e) => e.openId, 'open id', 'r1')));
          } else {
            await s.request(pick, range: range);
          }
        }
        expect(w.srv.created, blocks ? isEmpty : hasLength(3), reason: '$row');
      }
    });

    test('the same people by phone id (server rows) and the same group are found', () async {
      final w = _World();
      w.srv.reqs = [
        _req('r-dev', chat: {'kind': 'direct', 'users': ['dev-a', 'dev-b']}),
        _req('r-g', chat: {'kind': 'group', 'group_id': 'g-srv'}),
      ];
      final s = w.svc();
      expect((await s.openRequestFor314(const ChatPick221.direct('u-a', 'u-b', label: '')))?.id, 'r-dev');
      expect((await s.openRequestFor314(const ChatPick221.group('g-srv', label: '')))?.id, 'r-g');
      expect(await s.openRequestFor314(const ChatPick221.group('g-near', label: '')), isNull);
    });

    testWidgets('sheet: "Already asked · Open it" - Get chat is off, the box opens the card', (tester) async {
      await tester.runAsync(loadRoboto216);
      tester.view.physicalSize = const Size(400 * 3, 1000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final w = _World();
      w.srv.reqs = [_req('r-open')];
      ChatRequestRow221? opened;
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('go'),
              onPressed: () async {
                result = await showChatRequestSheet(context,
                    service: w.svc(),
                    preset: const ChatPick221.direct('u-a', 'u-b', label: 'ayesha & kiran'),
                    onOpen: (r) => opened = r);
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('go')));
      await _settle(tester);
      await _settle(tester);
      expect(find.byKey(const ValueKey('request314_already')), findsOneWidget);
      expect(find.text('Already asked \u00b7 Open it'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('request221_send')), warnIfMissed: false);
      await _settle(tester);
      expect(w.srv.created, isEmpty);
      await tester.tap(find.byKey(const ValueKey('request314_already')));
      await _settle(tester);
      expect(opened?.id, 'r-open');
      expect(result, isFalse);
      expect(find.byKey(const ValueKey('request314_already')), findsNothing);
    });

    testWidgets('sheet: the server says already_asked -> the box shows that request', (tester) async {
      await tester.runAsync(loadRoboto216);
      tester.view.physicalSize = const Size(400 * 3, 1000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final w = _World();
      // The phone can't match it (another phone's ids), the server can.
      w.srv.reqs = [_req('r-srv', chat: {'kind': 'direct', 'users': ['x1', 'x2']})];
      w.srv.refuse = const ChatAdminRefused(409, 'already_asked', 'This chat already has an open request.',
          openId: 'r-srv');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ChatRequestSheet221(
                      service: w.svc(), preset: const ChatPick221.direct('u-a', 'u-b', label: 'ayesha & kiran'))))));
      await _settle(tester);
      expect(find.byKey(const ValueKey('request314_already')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('request221_send')));
      await _settle(tester);
      await _settle(tester);
      expect(find.byKey(const ValueKey('request314_already')), findsOneWidget);
    });
  });

  group('K5 - offline Chats tab', () {
    final serverChats = [
      {
        'id': 'c-mine',
        'kind': 'direct',
        'participants': [
          {'id': 'dev-admin', 'name': 'sajjad'},
          {'id': 'dev-a', 'name': 'ayesha'},
        ],
        'message_count': 4,
      },
      {
        'id': 'c-other',
        'kind': 'direct',
        'participants': [
          {'id': 'dev-a', 'name': 'ayesha'},
          {'id': 'dev-b', 'name': 'kiran'},
        ],
        'message_count': 9,
      },
      {'id': 'g-own', 'kind': 'group', 'group_id': 'g-local-mine', 'group_name': 'Neighbours', 'member_count': 2},
      {'id': 'g-me-flag', 'kind': 'group', 'group_id': 'g-mine', 'group_name': 'Family', 'member_count': 5, 'me': true},
      {'id': 'g-o', 'kind': 'group', 'group_id': 'g-srv', 'group_name': 'Office', 'member_count': 3},
    ];

    test('online marks my chats; offline = saved server list without mine + reported groups', () async {
      final w = _World();
      w.srv.chats = serverChats;
      final online = await w.svc().conversations();
      final mine = {for (final c in online) if (c['me'] == true) c['id']};
      expect(mine, {'c-mine', 'g-own', 'g-me-flag'});
      expect(w.saved[ChatRequests221.chatsSavedKey314], isNot(contains('message_text')));
      w.online = false;
      final off = await w.svc().conversations();
      final ids = [for (final c in off) c['id']];
      expect(ids, ['c-other', 'g-o', 'n:g-rep']);
      final rep = off.last;
      expect(rep['nearby'], isTrue);
      expect(rep['group_id'], 'g-rep');
      expect(rep['member_count'], 3);
    });

    test('offline Get chat of a group I am not in: targets from the note (K8)', () async {
      final w = _World();
      w.online = false;
      final who = await w.svc().resolve314(const ChatPick221.group('g-rep', label: 'Cricket'));
      expect(who.targets, ['d5', 'd6', 'd7']);
      expect(who.meIn, isFalse);
      // A group known only from the saved server list.
      w.online = true;
      await w.svc().pickerGroups314();
      w.online = false;
      final srv = await w.svc().resolve314(const ChatPick221.group('g-near', label: 'Study group'));
      expect(srv.targets, ['d4', 'd5', 'd6', 'd7']);
      // Regression: a group of this phone still uses its own member list.
      final local = await w.svc().resolve314(const ChatPick221.group('g-local-other', label: 'Old team'));
      expect(local.targets, ['d2', 'd3']);
    });
  });

  group('K1 - Chats tab rows', () {
    testWidgets('my own row: no Get chat button and the row does not open the sheet; open request row opens it',
        (tester) async {
      await tester.runAsync(loadRoboto216);
      tester.view.physicalSize = const Size(411 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final w = _World();
      w.srv.chats = [
        {
          'id': 'c-mine',
          'kind': 'direct',
          'me': true,
          'participants': [
            {'id': 'dev-admin', 'name': 'sajjad'},
            {'id': 'dev-a', 'name': 'ayesha'},
          ],
          'message_count': 4,
        },
        {
          'id': 'c-open',
          'kind': 'direct',
          'participants': [
            {'id': 'u-a', 'name': 'ayesha'},
            {'id': 'u-b', 'name': 'kiran'},
          ],
          'message_count': 9,
        },
        {
          'id': 'c-free',
          'kind': 'direct',
          'participants': [
            {'id': 'u-b', 'name': 'kiran'},
            {'id': 'u-c', 'name': 'sumaira'},
          ],
          'message_count': 2,
        },
      ];
      w.srv.reqs = [_req('r-open')];
      await tester.pumpWidget(MaterialApp(home: AdminConversationsScreen(requests: w.svc())));
      await _settle(tester);
      await _settle(tester);
      expect(find.byKey(const ValueKey('chats221_ask_c-mine')), findsNothing);
      expect(find.byKey(const ValueKey('chats314_mine_c-mine')), findsOneWidget);
      expect(find.text('On your phone'), findsOneWidget);
      expect(find.byKey(const ValueKey('chats221_ask_c-open')), findsNothing);
      expect(find.byKey(const ValueKey('chats221_ask_c-free')), findsOneWidget); // regression
      await tester.tap(find.byKey(const ValueKey('chats221_row_c-mine')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('request221_send')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chats221_row_c-open')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('request221_send')), findsNothing);
      // The open request's card is shown on the Requests tab (not a sheet).
      expect(find.byKey(const ValueKey('chats221_row_c-open')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tabs221_0')));
      await _settle(tester);
      // The free row still opens the sheet.
      await tester.tap(find.byKey(const ValueKey('chats221_ask_c-free')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('request221_send')), findsOneWidget);
    });
  });

  group('Issue 1c - nearby group notes', () {
    late Map<String, String> store;
    late DateTime now;
    late List<List<SignedBlob>> posted;
    late List<(String, Map<String, dynamic>)> locked;
    late int status;
    late bool online;
    late List<Map<String, dynamic>> groups;
    late StreamController<Map<String, dynamic>> events;
    late bool owner;
    late _Keys keys;

    GroupNotes314 make({String self = 'd5'}) => GroupNotes314(
          selfDeviceId: () => self,
          myGroups: () async => groups,
          sign: (body) async => 'sig:${body.length}',
          events: events.stream,
          read: (k) async => store[k],
          write: (k, v) async => store[k] = v,
          post: (notes) async {
            posted.add(notes);
            return status;
          },
          serverOnline: () => online,
          ownerPhones: () async => ['dev-admin'],
          canReach: (id) => id == 'dev-admin',
          sendLocked: (to, payload) async {
            locked.add((to, payload));
            return true;
          },
          isOwnerPhone: () async => owner,
          signingKeyOf: (d) async => keys.pub[d] ?? '',
          verify: (body, sig, key) async => sig == 'good:$key',
          clock: () => now,
        );

    setUp(() {
      store = {};
      now = DateTime.utc(2026, 11, 16, 10);
      posted = [];
      locked = [];
      status = 200;
      online = true;
      groups = [
        {'id': 'g-rep', 'name': 'Cricket', 'members': ['d7', 'd5', 'd6'], 'made_at': '2026-11-15T10:00:00Z'},
      ];
      events = StreamController<Map<String, dynamic>>.broadcast();
      owner = false;
      keys = _Keys();
    });

    test('the note: gid, name, sorted members, made_at, from, at - no messages, no keys', () {
      final n = GroupNotes314.noteOf(groups.single, 'd5', now);
      expect(n.keys.toSet(), {'t', 'v', 'gid', 'name', 'members', 'made_at', 'from', 'at'});
      expect(n['t'], 'group_note_314');
      expect(n['members'], ['d5', 'd6', 'd7']);
      expect(n['from'], 'd5');
    });

    test('sent to the server and (locked) to the owner phone once; again only on a change or after a day',
        () async {
      final g = make();
      await g.tick();
      expect(posted, hasLength(1));
      final body = jsonDecode(posted.single.single.body) as Map;
      expect(body['gid'], 'g-rep');
      expect(posted.single.single.sig, startsWith('sig:'));
      expect(locked, hasLength(1));
      expect(locked.single.$1, 'dev-admin');
      expect(locked.single.$2['type'], 'group_notes_314');
      // Same group, an hour later: nothing.
      now = now.add(const Duration(hours: 1));
      await g.tick();
      expect(posted, hasLength(1));
      expect(locked, hasLength(1));
      // A new member: at once.
      groups = [
        {...groups.single, 'members': ['d5', 'd6', 'd7', 'd9']},
      ];
      await g.tick();
      expect(posted, hasLength(2));
      expect(locked, hasLength(2));
      // A day later: once more.
      now = now.add(const Duration(hours: 25));
      await g.tick();
      expect(posted, hasLength(3));
    });

    test('an old server (404) keeps the note and is asked again the next day', () async {
      status = 404;
      final g = make();
      await g.tick();
      expect(posted, hasLength(1));
      now = now.add(const Duration(hours: 2));
      await g.tick();
      expect(posted, hasLength(1)); // waits
      status = 200;
      now = now.add(const Duration(hours: 23));
      await g.tick();
      expect(posted, hasLength(2)); // tried again, the note was not dropped
    });

    test('no server: only the owner phone (and only when linked); a group the owner is in is not sent',
        () async {
      online = false;
      groups.add({'id': 'g-own', 'name': 'With owner', 'members': ['d5', 'dev-admin']});
      final g = make();
      await g.tick();
      expect(posted, isEmpty);
      expect(locked, hasLength(1));
      final notes = (locked.single.$2['notes'] as List).map((b) => jsonDecode((b as Map)['body'] as String)['gid']);
      expect(notes, ['g-rep']);
    });

    test('a group I am not a member of is never reported', () async {
      groups = [
        {'id': 'g-x', 'name': 'Not mine', 'members': ['d1', 'd2']},
      ];
      await make().tick();
      expect(posted, isEmpty);
      expect(locked, isEmpty);
    });

    Map<String, dynamic> blob(Map<String, dynamic> note, {String sig = ''}) =>
        SignedBlob(body: jsonEncode(note), sig: sig.isEmpty ? 'x' : sig).toJson();

    test('owner phone keeps a signed member note; drops bad signature, non-member writer, carried unknown key',
        () async {
      owner = true;
      keys.pub['d5'] = 'K5';
      final g = make(self: 'dev-admin');
      final good = GroupNotes314.noteOf(groups.single, 'd5', now);
      expect(await g.take('d5', [blob(good, sig: 'good:K5')]), 1);
      expect((await g.reported()).single['members'], ['d5', 'd6', 'd7']);
      // Bad signature.
      expect(await g.take('d5', [blob({...good, 'name': 'Changed', 'at': now.add(const Duration(minutes: 1)).toIso8601String()}, sig: 'bad')]), 0);
      // A writer that is not a member.
      final liar = GroupNotes314.noteOf({'id': 'g-z', 'name': 'Fake', 'members': ['d1']}, 'd9', now);
      expect(await g.take('d9', [blob(liar)]), 0);
      // Carried by another phone and the writer's key is unknown here.
      final carried = GroupNotes314.noteOf({'id': 'g-c', 'name': 'Carried', 'members': ['d6', 'd7']}, 'd6', now);
      expect(await g.take('d7', [blob(carried)]), 0);
      // The writer itself (proven sender) with no saved key: kept.
      expect(await g.take('d6', [blob(carried)]), 1);
      expect({for (final r in await g.reported()) r['id']}, {'g-rep', 'g-c'});
      // Older note does not replace a newer one.
      final older = GroupNotes314.noteOf({...groups.single, 'name': 'Old name'}, 'd5', now.subtract(const Duration(hours: 1)));
      expect(await g.take('d5', [blob(older, sig: 'good:K5')]), 0);
      expect((await g.reported()).firstWhere((r) => r['id'] == 'g-rep')['name'], 'Cricket');
    });

    test('a phone that is not the owner keeps nothing; unlocked or stranger packets are dropped', () async {
      final g = make(self: 'dev-admin')..start();
      addTearDown(g.stop);
      final note = GroupNotes314.noteOf(groups.single, 'd5', now);
      expect(await g.take('d5', [blob(note)]), 0); // not the owner
      owner = true;
      final payload = {'type': 'group_notes_314', 'sender_id': 'd5', 'notes': [blob(note)]};
      events.add({'type': 'message', 'payload': jsonEncode(payload), 'sealed': false});
      events.add({
        'type': 'message',
        'payload': jsonEncode({...payload, '_locked_spk': 'stranger'}),
        'sealed': true,
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await g.reported(), isEmpty);
      events.add({'type': 'message', 'payload': jsonEncode(payload), 'sealed': true});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect((await g.reported()).single['id'], 'g-rep');
      expect(g.changed.value, 1);
    });
  });

  group('Issue 3 / K11 - the notification', () {
    ChatRequestRow221 row({bool offline = false, int parts = 0, int of = 0, int phones = 0, int reached = 0}) =>
        ChatRequestRow221.fromServer({
          ..._req('r1', parts: parts, of: of),
          'offline': offline,
          'phones': phones,
          'reached': reached,
        });

    test('"when" uses the server clock offset (server 2 h 34 min slow = not "2h ago")', () {
      final made = DateTime.parse('2026-11-16T10:00:00Z').millisecondsSinceEpoch;
      expect(ChatRequestNotifier307.madeOnPhoneClock314(row()), made);
      ServerClock255.wrong.value = const Duration(seconds: -9230);
      expect(ChatRequestNotifier307.madeOnPhoneClock314(row()), made + 9230 * 1000);
      // Made on this phone offline: its own clock, no change.
      expect(ChatRequestNotifier307.madeOnPhoneClock314(row(offline: true)), made);
      ServerClock255.wrong.value = null;
    });

    test('rock_until = made + 10 min while Sent / Reached, 0 once parts come', () async {
      final made = DateTime.parse('2026-11-16T10:00:00Z').millisecondsSinceEpoch;
      Future<Map<String, Object?>> card(ChatRequestRow221 r) async {
        final shown = <Map<String, Object?>>[];
        await ChatRequestNotifier307(
          mine: () async => [r],
          isOwner: () async => true,
          read: (_) async => null,
          write: (_, __) async {},
          cards: _Cards(shown),
          clock: () => DateTime.utc(2026, 11, 16, 10, 1),
        ).refresh();
        return shown.single;
      }

      final sent = await card(row());
      expect(sent['step'], Step307.sent.name);
      expect(sent['rock_until'], made + 10 * 60 * 1000);
      final reached = await card(row(phones: 2, reached: 1));
      expect(reached['step'], Step307.reached.name);
      expect(reached['rock_until'], made + 10 * 60 * 1000);
      final coming = await card(row(parts: 3, of: 10));
      expect(coming['step'], Step307.coming.name);
      expect(coming['rock_until'], 0);
    });
  });
}

class _Cards implements ChatRequestCards307 {
  _Cards(this.shown);
  final List<Map<String, Object?>> shown;
  @override
  Future<void> show(Map<String, Object?> args) async => shown.add(args);
  @override
  Future<void> cancel(Map<String, Object?> args) async {}
  @override
  Future<void> cancelAll() async {}
}
