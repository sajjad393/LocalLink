// Bundle 321 Phase 6: stuck files (F7), kept voice (F8), Conversations
// status words (R1).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit320.dart';

import 'support/b216_fonts.dart';

class _Srv implements ChatAdminServer {
  _Srv({this.chats = const []});
  final List<Map<String, dynamic>> chats;
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => chats;
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => const [];
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async => {'id': 'aa_new'};
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

class _Svc extends ChatRequests221 {
  _Svc(_Srv srv, {this.rows = const []})
      : super(
          server: srv,
          signIn: () async => (token: 't', role: 'owner', username: 'sajjad'),
          serverOnline: () => true,
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
          people: () async => const [],
          localGroups: () async => const [],
          read: (k) async => null,
          write: (k, v) async {},
        );

  final List<ChatRequestRow221> rows;
  final bool hang = false;
  final List<ChatPick221> askedNew = [];
  final Completer<ChatAnswerView> _never = Completer<ChatAnswerView>();

  @override
  Future<List<ChatRequestRow221>> requests() async => rows;

  @override
  Future<String> requestNew318(ChatPick221 pick) async {
    askedNew.add(pick);
    return 'aa_new_only';
  }

  @override
  Future<ChatAnswerView> open(ChatRequestRow221 r) => hang ? _never.future : super.open(r);
}

Map<String, dynamic> _who(String id, String n) => {'id': id, 'name': n, 'username': n};

Map<String, dynamic> _direct(String id, String a, String an, String b, String bn, {int count = 9}) => {
      'id': id,
      'kind': 'direct',
      'participants': [_who(a, an), _who(b, bn)],
      'message_count': count,
      'last_message_at': '2026-11-14T09:20:00Z',
    };

Map<String, dynamic> _ref(String a, String b) => {'kind': 'direct', 'users': [a, b]};

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

Future<void> _phone(WidgetTester tester, {double width = 400}) async {
  await tester.runAsync(loadRoboto216);
  tester.view.physicalSize = Size(width * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _openList(WidgetTester tester, _Svc svc, {bool dark = false, double scale = 1}) async {
  await tester.pumpWidget(MaterialApp(
    theme: dark ? ThemeData.dark() : ThemeData.light(),
    builder: (context, child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: AdminConversationsScreen(requests: svc),
  ));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}



const _mb = 1024 * 1024;

ChatRequestRow221 _file(String id, String fileId,
        {String state = 'pending', int parts = 0, int of = 0, String madeAt = '2026-11-16T12:00:00Z'}) =>
    ChatRequestRow221(
        id: id, action: 'get_file', state: state, parts: parts, of: of, parent: 'r1', fileId: fileId, madeAt: madeAt);

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
          'attachments': [for (final i in ids) {'file_id': i, 'name': '$i.jpg', 'type': 'image/jpeg', 'size': _mb}],
        },
      ],
    );

class _Q {
  _Q(this.view);
  ChatAnswerView view;
  List<ChatRequestRow221> rows = [const ChatRequestRow221(id: 'r1', action: 'get_chat', state: 'done', parts: 4, of: 4)];
  final Map<String, String> saved = {};
  final List<String> asked = [];
  final List<String> stoppedIds = [];
  int n = 0;
  DateTime now = DateTime.utc(2026, 11, 16, 12);

  late final FileQueue317 q = FileQueue317(
    rows: () async => rows,
    mineIds: () async => {'r1'},
    open: (r) async => view,
    ask: (parent, {required fileId, messageId = '', name = ''}) async {
      asked.add(fileId);
      return 'aa_${fileId}_${++n}';
    },
    close: (r) async => stoppedIds.add(r.id),
    cancel: (r) async => stoppedIds.add(r.id),
    isOwner: () async => true,
    read: (k) async => saved[k],
    write: (k, v) async => saved[k] = v,
    clock: () => now,
  );
}

void main() {
  setUp(AppLogFile.instance.resetForTest);
  tearDown(() => FileQueue317.trips.value = const {});

  group('F7 stuck files', () {
    test('no new part for 10 min -> asked once more; 2nd time -> gone, the next file goes', () async {
      final t = _Q(_answer(['a', 'b', 'c']));
      await t.q.tick();
      expect(t.asked, ['a', 'b']);
      // a moves, b is stuck at 2 / 9.
      t.rows = [t.rows.first, _file('aa_a_1', 'a', state: 'done', parts: 1, of: 9), _file('aa_b_2', 'b', state: 'done', parts: 2, of: 9)];
      await t.q.tick();
      t.now = t.now.add(const Duration(minutes: 5));
      t.rows = [t.rows.first, _file('aa_a_1', 'a', state: 'done', parts: 5, of: 9), t.rows[2]];
      await t.q.tick();
      expect(t.asked, ['a', 'b'], reason: 'nothing before 10 min');
      t.now = t.now.add(const Duration(minutes: 6));
      t.rows = [t.rows.first, _file('aa_a_1', 'a', state: 'done', parts: 8, of: 9), t.rows[2]];
      await t.q.tick();
      expect(t.asked, ['a', 'b', 'b'], reason: 'b asked once more');
      expect(t.stoppedIds, ['aa_b_2'], reason: 'the stuck answer is stopped');
      expect(AppLogFile.instance.pendingForTest.join('\n'), contains('FILE_QUEUE_RETRY|quiet_min=10 parts=2/9'));
      expect(t.q.viewsOf('r1')['b']!.state, FileState317.coming, reason: 'still Coming, not Stopped');
      // The old stopped row stays in the list (closed): still Coming.
      t.rows = [
        t.rows.first,
        _file('aa_a_1', 'a', state: 'done', parts: 8, of: 9),
        const ChatRequestRow221(id: 'aa_b_2', action: 'get_file', state: 'done', parts: 2, of: 9, parent: 'r1', fileId: 'b', closed: true, madeAt: '2026-11-16T12:00:00Z'),
        _file('aa_b_3', 'b', madeAt: '2026-11-16T12:11:00Z'),
      ];
      await t.q.tick();
      expect(t.q.viewsOf('r1')['b']!.state, FileState317.coming);
      t.now = t.now.add(const Duration(minutes: 11));
      await t.q.tick();
      expect(t.q.viewsOf('r1')['b']!.state, FileState317.gone);
      expect(AppLogFile.instance.pendingForTest.join('\n'), contains('FILE_QUEUE_GONE|why=stuck_twice'));
      expect(FileQueue317.trips.value['r1']!.gone, 1);
      // a is 8/9 and moved earlier - also asked again (stuck too), b never again.
      expect(t.asked.where((x) => x == 'b'), hasLength(2));
      expect(t.asked, contains('c'), reason: 'the window is free for the next file');
      final plan = await t.q.planForTest('r1');
      expect((plan!['dead321'] as Map).keys, ['b']);
    });

    test('a file that moves is never re-asked', () async {
      final t = _Q(_answer(['a']));
      await t.q.tick();
      for (var i = 1; i <= 5; i++) {
        t.now = t.now.add(const Duration(minutes: 8));
        t.rows = [t.rows.first, _file('aa_a_1', 'a', state: 'done', parts: i, of: 9)];
        await t.q.tick();
      }
      expect(t.asked, ['a']);
    });

    test('old manual rows: a pre-plan Get file row does not block; old cards do not fill the window', () async {
      final t = _Q(_answer(['a', 'b']));
      t.rows = [
        t.rows.first,
        _file('old_a', 'a', madeAt: '2026-11-01T10:00:00Z'), // 3.0.107 manual, never answered
        for (var i = 0; i < 3; i++)
          ChatRequestRow221(id: 'p$i', action: 'get_file', state: 'pending', parent: 'other', fileId: 'x$i', madeAt: '2026-11-02T10:00:00Z'),
      ];
      await t.q.tick();
      expect(t.asked, ['a', 'b']);
    });

    test('regression: recent pending cards still fill the 3-card window', () async {
      final t = _Q(_answer(['a']));
      t.rows = [
        t.rows.first,
        for (var i = 0; i < 3; i++)
          ChatRequestRow221(id: 'p$i', action: 'get_file', state: 'pending', parent: 'other', fileId: 'x$i', madeAt: '2026-11-16T11:30:00Z'),
      ];
      await t.q.tick();
      expect(t.asked, isEmpty);
    });
  });

  group('F8 voice', () {
    test('a kept / here voice note plays; a coming one shows its parts or "Coming from X"', () {
      final s = File('lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart').readAsStringSync();
      final v = s.substring(s.indexOf('  Widget _voice310Row('));
      expect(v, contains('(st.state == FileState317.here && st.row != null)'));
      expect(v, contains('onTap = () => unawaited(_playVoice310(playRow));'));
      expect(v, contains('st.state == FileState317.coming'));
      expect(v, contains('L.t.comingFrom317(who)'));
    });
  });

  group('R1 Conversations words', () {
    FileTrip317 trip({int here = 3, int gone = 0, int coming = 2}) => FileTrip317(
        requestId: 'r1', total: 7, here: here, gone: gone, tooBig: 0, coming: coming,
        bytesHere: here * _mb, bytesTotal: (7 - gone) * _mb, waiting: false, stopped: false);
    final chats = [_direct('c1', 'u-s', 'sumaira', 'u-k', 'kiran')];
    final rows = [
      ChatRequestRow221(id: 'r1', action: 'get_chat', label: 'sumaira & kiran', state: 'done', parts: 4, of: 4,
          madeAt: _ago(const Duration(hours: 1)), chat: _ref('u-s', 'u-k')),
    ];

    testWidgets('text here + files coming = blue words, Open stays, counted under Coming', (tester) async {
      await _phone(tester);
      FileQueue317.trips.value = {'r1': trip()};
      await _openList(tester, _Svc(_Srv(chats: chats), rows: rows));
      final line = tester.widget<StatusLine320>(find.byKey(const ValueKey('requests317_files_r1')));
      expect(line.text, 'Messages here \u00b7 3 of 7 files coming');
      expect(line.tone, Tone320.blue);
      expect(find.byKey(const ValueKey('chats320_open_c1')), findsOneWidget);
      final chips = tester.widget<FilterChips320>(find.byType(FilterChips320));
      expect(chips.counts, [1, 1, 0, 0]);
      expect(find.byKey(const ValueKey('chats321_gone_c1')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every file here or gone = green "Ready to read" + grey "2 files not available"', (tester) async {
      await _phone(tester);
      FileQueue317.trips.value = {'r1': trip(here: 5, gone: 2, coming: 0)};
      await _openList(tester, _Svc(_Srv(chats: chats), rows: rows), dark: true);
      final line = tester.widget<StatusLine320>(find.byKey(const ValueKey('chats320_status_c1')));
      expect(line.text, 'Ready to read');
      expect(line.tone, Tone320.green);
      final gone = tester.widget<StatusLine320>(find.byKey(const ValueKey('chats321_gone_c1')));
      expect(gone.text, '2 files not available');
      expect(gone.tone, Tone320.grey);
      expect(tester.widget<FilterChips320>(find.byType(FilterChips320)).counts, [1, 0, 1, 0]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no files = "Ready to read" as before (regression)', (tester) async {
      await _phone(tester);
      await _openList(tester, _Svc(_Srv(chats: chats), rows: rows));
      expect(tester.widget<StatusLine320>(find.byKey(const ValueKey('chats320_status_c1'))).text, 'Ready to read');
    });
  });
}
