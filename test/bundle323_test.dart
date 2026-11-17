// Bundle 323 (17 Nov 18:54 logs): the two things the Owner hit, from the
// offline side - the group picker knew only one group, and "Get chat" on a
// group on screen did nothing at all, with no line in the log.
//
//  P1 the picker also reads the saved Conversations list (the groups on
//     screen are askable).
//  P2 the group list (with `member_devices`) is saved by the Conversations
//     load too, not only when the picker happens to be opened while online -
//     those phones are the only way an offline Get chat can find its targets.
//  P3 every silent exit says why (PICKER_LIST323 / GROUPS_SAVED323 /
//     GET_CHAT_FAIL323).
//  P4 deleteGroupLocal's statement is complete again (bundle 308 broke it:
//     "incomplete input", the whole delete_group_tx rolled back).
//  P7 the file queue says why it asked nothing, and a card the queue itself
//     asked no longer counts twice against its own window.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialApp, Size, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';

import 'support/b216_fonts.dart';

const _mb = 1024 * 1024;

// ---------------------------------------------------------------- chat side

class _Srv implements ChatAdminServer {
  List<Map<String, dynamic>> chats = const [];
  List<Map<String, dynamic>> reqs = const [];
  final List<Map<String, dynamic>> created = [];

  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => chats;
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => reqs;
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async {
    created.add(body);
    return {'id': 'aa_323'};
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

class _ChatWorld {
  bool online = true;
  final saved = <String, String>{};
  final srv = _Srv();
  int groupListCalls = 0;
  bool groupFetchFails = false;

  /// `/admin/groups`: the only place `member_devices` comes from.
  Map<String, dynamic> serverGroups = {
    'groups': [
      {'id': 'g-other', 'name': 'Old team', 'members': 2, 'member_devices': ['d1', 'd2']},
    ],
    'nearby': const [],
  };

  /// This phone's own groups table (groups it has locally).
  List<Map<String, dynamic>> localGroups = const [];
  final Map<String, List<String>> groupDevices = {'g-local': ['d9', 'd10']};

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
          _ => [u],
        },
        groupDevices: (g) async => groupDevices[g] ?? const [],
        localChats: () async => const [],
        people: () async => const [
              {'id': 'u-admin', 'name': 'sajjad', 'username': '', 'device': 'dev-admin', 'me': true},
            ],
        localGroups: () async => localGroups,
        read: (k) async => saved[k],
        write: (k, v) async => saved[k] = v,
        serverGroups: (token) async {
          groupListCalls++;
          if (groupFetchFails) throw StateError('groups endpoint down');
          return serverGroups;
        },
        reportedGroups: () async => const [],
      );

  String get log => AppLogFile.instance.pendingForTest.join('\n');

  List<Map<String, dynamic>> savedGroups() {
    final raw = saved[ChatRequests221.groupsSavedKey314];
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final g in (jsonDecode(raw) as List)) Map<String, dynamic>.from(g as Map),
    ];
  }
}

Map<String, dynamic> _groupChat(String id, String name, {int members = 2}) => {
      'id': 'g:$id',
      'kind': 'group',
      'group_id': id,
      'group_name': name,
      'member_count': members,
      'message_count': 9,
      'last_message_at': '2026-11-17T18:40:00Z',
    };

// ---------------------------------------------------------------- file side

ChatRequestRow221 _fileRow(String id, String fileId) => ChatRequestRow221(
    id: id, action: 'get_file', state: 'pending', parts: 0, of: 0, parent: 'r1', fileId: fileId);

ChatAnswerView _answer(List<String> ids) => ChatAnswerView(
      id: 'r1',
      answerId: 'an_1',
      fromDevice: 'dev-k',
      fromName: 'kiran',
      of: 4,
      parts: 4,
      complete: true,
      messages: [
        {
          'id': 'm1',
          'sender': 'dev-k',
          'created_at': '2026-11-14T10:00:00',
          'body': '',
          'attachments': [
            for (final i in ids) {'file_id': i, 'name': '$i.jpg', 'type': 'image/jpeg', 'size': _mb},
          ],
        },
      ],
    );

class _QueueWorld {
  final saved = <String, String>{};
  final asked = <String>[];
  int n = 0;
  DateTime now = DateTime.utc(2026, 11, 17, 18, 46);

  List<ChatRequestRow221> rows = [
    const ChatRequestRow221(id: 'r1', action: 'get_chat', state: 'done', parts: 4, of: 4),
  ];

  late final FileQueue317 q = FileQueue317(
    rows: () async => rows,
    mineIds: () async => {'r1'},
    open: (r) async => _answer(const ['c', 'd']),
    ask: (parent, {required fileId, messageId = '', name = ''}) async {
      asked.add(fileId);
      return 'aa_${fileId}_${++n}';
    },
    close: (r) async {},
    cancel: (r) async {},
    isOwner: () async => true,
    read: (k) async => saved[k],
    write: (k, v) async => saved[k] = v,
    clock: () => now,
  );

  String get log => AppLogFile.instance.pendingForTest.join('\n');

  /// A plan already on the phone: files [c, d] are still `next`, the asked
  /// map is what the queue itself made before.
  void planAsked(Map<String, String> askedIds) {
    saved[FileQueue317.planKey] = jsonEncode({
      'r1': {
        'files': [
          {'f': 'c', 'm': 'm1', 'n': 'c.jpg', 't': 'image/jpeg', 's': _mb},
          {'f': 'd', 'm': 'm1', 'n': 'd.jpg', 't': 'image/jpeg', 's': _mb},
        ],
        'asked': askedIds,
        'from': 'kiran',
        'at': '2026-11-17T18:45:58.000Z',
      },
    });
  }
}

void main() {
  setUp(AppLogFile.instance.resetForTest);
  tearDown(() => FileQueue317.trips.value = const {});

  group('P1: the group picker knows every group the Conversations list shows', () {
    test('offline, a group only the saved Conversations list knows is askable', () async {
      final w = _ChatWorld();
      w.srv.chats = [_groupChat('g-g1', 'Group 1'), _groupChat('g-g2', 'Group 2', members: 3)];
      await w.svc().conversations(); // online: the two lists are saved
      expect(w.savedGroups(), isNotEmpty);
      // The 322 state: no saved server group list (the picker was never
      // opened while the server answered).
      w.saved.remove(ChatRequests221.groupsSavedKey314);
      w.online = false;
      final rows = await w.svc().pickerGroups314();
      final ids = {for (final g in rows) g['id']};
      expect(ids, containsAll(['g-g1', 'g-g2']), reason: 'these are the rows on screen');
      final byId = {for (final g in rows) g['id']: g};
      expect(byId['g-g1']!['name'], 'Group 1');
      expect(byId['g-g1']!['members'], 2, reason: 'the member count is on the row');
    });

    test('a group the saved server list knows keeps its phones', () async {
      final w = _ChatWorld();
      w.srv.chats = [_groupChat('g-other', 'Old team')];
      await w.svc().conversations();
      w.online = false;
      final byId = {for (final g in await w.svc().pickerGroups314()) g['id']: g};
      expect(byId['g-other']!['member_devices'], ['d1', 'd2']);
    });
  });

  group('P2: the group list (with the member phones) is kept fresh by the load', () {
    test('conversations() saves /admin/groups too', () async {
      final w = _ChatWorld();
      await w.svc().conversations();
      expect(w.groupListCalls, 1);
      final saved = w.savedGroups();
      expect(saved.map((g) => g['id']), contains('g-other'));
      expect(saved.firstWhere((g) => g['id'] == 'g-other')['member_devices'], ['d1', 'd2']);
      expect(w.log, contains('GROUPS_SAVED323'));
    });

    test('offline Get chat finds its target phones (was: targets_empty)', () async {
      final w = _ChatWorld();
      await w.svc().conversations();
      w.online = false;
      final who = await w.svc().resolve314(ChatPick221.group('g-other', label: 'Old team'));
      expect(who.targets, ['d1', 'd2'], reason: 'the 17 Nov dead end');
      expect(who.meIn, isFalse);
    });

    test('a failed group fetch leaves the old list alone', () async {
      final w = _ChatWorld();
      w.srv.chats = [_groupChat('g-other', 'Old team')];
      await w.svc().conversations();
      final before = w.savedGroups();
      expect(before, isNotEmpty);
      w.groupFetchFails = true;
      AppLogFile.instance.resetForTest;
      // the chat list itself still loads; the group list just stays as it was
      final rows = await w.svc().conversations();
      expect(rows, isNotEmpty);
      expect(w.log, contains('ADMIN_GROUPS_LIST323_SKIP'));
      expect(w.savedGroups(), before, reason: 'never wipe a good list with a failed read');
    });
  });

  group('P3: the silent exits say why', () {
    test('the picker names its source', () async {
      final w = _ChatWorld();
      await w.svc().pickerGroups314();
      expect(w.log, contains('PICKER_LIST323|src=server'));

      w.online = false;
      AppLogFile.instance.resetForTest;
      await w.svc().pickerGroups314();
      expect(w.log, contains('PICKER_LIST323|src=saved'));

      w.saved.remove(ChatRequests221.groupsSavedKey314);
      AppLogFile.instance.resetForTest;
      await w.svc().pickerGroups314();
      expect(w.log, contains('PICKER_LIST323|src=local'));
    });

    test('a Get chat that cannot be made logs the reason', () async {
      final w = _ChatWorld();
      w.online = false;
      await expectLater(
          w.svc().request(ChatPick221.group('g-other', label: 'Old team')), throwsA(isA<StateError>()));
      expect(w.log, contains('GET_CHAT_FAIL323|why=actions_not_ready'));
    });
  });

  group('P7: the file queue says why it asked nothing', () {
    test('the cards the queue itself made do not fill its own window', () async {
      final w = _QueueWorld();
      // Three live Get file cards made by the queue before (they are in the
      // plan's `asked` map), and the plan's two files are still `next`.
      w.planAsked({'x': 'aa_x', 'y': 'aa_y', 'z': 'aa_z'});
      w.rows = [
        w.rows.first,
        _fileRow('aa_x', 'x'),
        _fileRow('aa_y', 'y'),
        _fileRow('aa_z', 'z'),
      ];
      await w.q.tick();
      expect(w.asked, ['c', 'd'], reason: 'before 323 the window was "full" and nothing was asked');
    });

    test('a card nobody tracks blocks the window - and it is logged', () async {
      final w = _QueueWorld();
      w.planAsked(const {});
      w.rows = [
        w.rows.first,
        _fileRow('zz_1', 'x'),
        _fileRow('zz_2', 'y'),
        _fileRow('zz_3', 'z'),
      ];
      await w.q.tick();
      expect(w.asked, isEmpty, reason: '3 foreign cards still fill the window');
      expect(w.log, contains('FILE_QUEUE_SKIP323|why=window on_way=0 cards=3'));
    });

    test('the line is not repeated on every tick', () async {
      final w = _QueueWorld();
      w.planAsked(const {});
      w.rows = [
        w.rows.first,
        _fileRow('zz_1', 'x'),
        _fileRow('zz_2', 'y'),
        _fileRow('zz_3', 'z'),
      ];
      await w.q.tick();
      await w.q.tick();
      await w.q.tick();
      final lines = w.log.split('\n').where((l) => l.contains('FILE_QUEUE_SKIP323')).length;
      expect(lines, 1, reason: 'once per change, not once per tick');
    });
  });

  group('P4: deleteGroupLocal runs a complete statement again', () {
    test('the delete query ends with the empty-string test (bundle 308 lock)', () {
      final src = File('lib/core/services/local_store.dart').readAsStringSync();
      final at = src.indexOf('group_message_id IN (SELECT id FROM group_messages WHERE group_id=?) AND local_path IS NOT NULL AND local_path != ');
      expect(at, greaterThan(0), reason: 'the delete query moved: update this lock');
      // The Dart string that follows the "!=" must put the closing quotes back
      // (`''`), or SQLite answers "incomplete input" and nothing is deleted.
      final tail = src.substring(at, at + 320);
      final joined = tail
          .split('\n')
          .skip(1)
          .take(3)
          .map((l) => l.trim())
          .where((l) => l.startsWith('"') || l.startsWith("'"))
          .map((l) => l.replaceAll(RegExp(r',$'), '').replaceAll('"', "'"))
          .join();
      expect(joined, startsWith("''"), reason: 'the empty-string quotes must close the statement: got $joined');
      final quotes = RegExp("'").allMatches("local_path != $joined").length;
      expect(quotes.isEven, isTrue, reason: 'an odd number of quotes = incomplete SQL');
    });
  });

  group('P5: with the server off the words say so (was a dead end)', () {
    test('offline, a group with no known phones says the server is off', () {
      expect(ChatRequests221.unknownPhonesWords323(group: true, serverOff: true),
          "Server off - this group's phones are not known yet.");
    });

    test('offline, a person with no known phone says the server is off', () {
      expect(ChatRequests221.unknownPhonesWords323(group: false, serverOff: true),
          "Server off - this person's phone is not known yet.");
    });

    test('online the old sentence stays (it is true there)', () {
      expect(ChatRequests221.unknownPhonesWords323(group: true, serverOff: false),
          "This phone doesn't know their phones yet.");
    });

    test('the throw uses the words helper and the live server state', () {
      final src =
          File('lib/features/admin/data/actions/chat_answer_reader.dart').readAsStringSync();
      expect(src, contains('unknownPhonesWords323(group: pick.isGroup, serverOff: off323)'));
      expect(src, contains('final off323 = !serverOnline();'));
      // the old silent sentence must not be thrown directly any more
      expect(src, isNot(contains('throw StateError("This phone doesn\'t know their phones yet.")')));
    });
  });

  group('P6: the saved list says when it was saved', () {
    test('conversations() stamps the list, savedAt323() reads it back', () async {
      final w = _ChatWorld();
      w.srv.chats = [_groupChat('g-g1', 'Group 1')];
      expect(await w.svc().savedAt323(), isNull, reason: 'nothing saved yet');
      final before = DateTime.now().subtract(const Duration(seconds: 2));
      await w.svc().conversations();
      final at = await w.svc().savedAt323();
      expect(at, isNotNull);
      expect(at!.isAfter(before), isTrue);
      expect(at.isAfter(DateTime.now().add(const Duration(minutes: 1))), isFalse);
    });

    test('the label: the time today, the date on an older day, nothing when never saved', () {
      final now = DateTime(2026, 11, 17, 20, 5);
      expect(AdminConversationsScreen.savedLabel323(DateTime(2026, 11, 17, 18, 44), now),
          'Saved 18:44');
      final older = AdminConversationsScreen.savedLabel323(DateTime(2026, 11, 16, 18, 44), now);
      expect(older, startsWith('Saved '));
      expect(older, endsWith('18:44'));
      expect(older.length, greaterThan('Saved 18:44'.length), reason: 'the day must show');
      expect(older, isNot(contains('11')));
      expect(AdminConversationsScreen.savedLabel323(null, now), '');
    });

    testWidgets('offline, the Conversations header shows when the list was saved',
        (tester) async {
      await tester.runAsync(loadRoboto216);
      tester.view.physicalSize = const Size(400 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final w = _ChatWorld();
      w.srv.chats = [_groupChat('g-g1', 'Group 1')];
      await w.svc().conversations(); // online once: the list + its stamp are saved
      w.online = false;

      await tester.pumpWidget(MaterialApp(home: AdminConversationsScreen(requests: w.svc())));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      final saved = find.byKey(const ValueKey('conv323_saved'));
      expect(saved, findsOneWidget, reason: 'offline: the old list must say how old it is');
      expect(tester.widget<Text>(saved).data, contains('Saved '));
      expect(find.text('Group 1'), findsOneWidget, reason: 'the saved list is on screen');
    });
  });
}
