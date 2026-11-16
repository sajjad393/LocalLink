// Bundle 317 (TODO_317): A Ready only when every part is here, B group
// system lines, C deleted look, D one row per file / video / size, G the
// files come by themselves (queue, viewer states, phone card, admin card).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/chat_request_notifier_307.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';

const int _mb = 1024 * 1024;

ChatRequestRow221 _chat(String id,
        {String state = 'done',
        int parts = 0,
        int of = 0,
        bool opened = false,
        bool closed = false,
        String action = 'get_chat',
        String fromName = 'kiran'}) =>
    ChatRequestRow221(
      id: id,
      action: action,
      label: 'kiran & ayesha',
      words: 'Full chat',
      state: state,
      parts: parts,
      of: of,
      opened: opened,
      closed: closed,
      fromName: fromName,
      phones: 2,
      reached: 1,
      madeAt: '2026-11-16T11:39:05Z',
    );

ChatRequestRow221 _file(String id, String parent, String fileId,
        {String state = 'pending', int parts = 0, int of = 0, String refused = '', String madeAt = '2026-11-16T11:40:00Z'}) =>
    ChatRequestRow221(
      id: id,
      action: 'get_file',
      state: state,
      parts: parts,
      of: of,
      parent: parent,
      fileId: fileId,
      refused: refused,
      madeAt: madeAt,
    );

FileTrip317 _trip({
  int total = 13,
  int here = 3,
  int gone = 0,
  int tooBig = 0,
  int coming = 2,
  int bytesHere = 6 * _mb,
  int bytesTotal = 24 * _mb,
  bool waiting = false,
  bool stopped = false,
  int quietMin = 0,
}) =>
    FileTrip317(
      requestId: 'r1',
      total: total,
      here: here,
      gone: gone,
      tooBig: tooBig,
      coming: coming,
      bytesHere: bytesHere,
      bytesTotal: bytesTotal,
      waiting: waiting,
      stopped: stopped,
      from: 'kiran',
      via: 'ayesha',
      quietMin: quietMin,
    );

Map<String, dynamic> _att(String id, {int size = _mb, String type = 'image/jpeg', bool gone = false}) =>
    {'file_id': id, 'name': '$id.jpg', 'type': type, 'size': size, if (gone) 'file_gone': true};

class _Cards implements ChatRequestCards307 {
  final List<Map<String, Object?>> shows = [];
  final List<Map<String, Object?>> cancels = [];
  @override
  Future<void> show(Map<String, Object?> args) async => shows.add(args);
  @override
  Future<void> cancel(Map<String, Object?> args) async => cancels.add(args);
  @override
  Future<void> cancelAll() async {}
}

/// A queue with fake rows / answers; records the asks / closes / cancels.
class _Q {
  _Q(this.view);
  ChatAnswerView view;
  List<ChatRequestRow221> rows = [];
  Set<String> mine = {'r1'};
  bool owner = true;
  final Map<String, String> saved = {};
  final List<String> asked = [];
  final List<String> closed = [];
  final List<String> cancelled = [];
  int opens = 0;
  DateTime now = DateTime.utc(2026, 11, 16, 12);

  late final FileQueue317 q = FileQueue317(
    rows: () async => rows,
    mineIds: () async => mine,
    open: (r) async {
      opens++;
      return view;
    },
    ask: (parent, {required fileId, messageId = '', name = ''}) async {
      asked.add(fileId);
      return 'aa_$fileId';
    },
    close: (r) async => closed.add(r.id),
    cancel: (r) async => cancelled.add(r.id),
    isOwner: () async => owner,
    read: (k) async => saved[k],
    write: (k, v) async => saved[k] = v,
    clock: () => now,
  );
}

ChatAnswerView _answer(List<Map<String, dynamic>> atts, {String fromName = 'kiran'}) => ChatAnswerView(
      id: 'r1',
      answerId: 'an_1',
      fromDevice: 'dev-k',
      fromName: fromName,
      of: 40,
      parts: 40,
      complete: true,
      messages: [
        {'id': 'm1', 'sender': 'dev-k', 'created_at': '2026-11-14T10:00:00', 'body': '', 'attachments': atts.take(2).toList()},
        {'id': 'm2', 'sender': 'dev-k', 'created_at': '2026-11-14T10:05:00', 'body': '', 'attachments': atts.skip(2).toList()},
      ],
    );

void main() {
  tearDown(() {
    FileQueue317.instance = null;
    FileQueue317.trips.value = const {};
  });

  group('317 A - Ready only when every part is here', () {
    test('done with no parts = "kiran\'s phone answered", Coming at 0 %', () {
      final st = RequestStep307.of(_chat('r1'));
      expect(st.step, Step307.coming);
      expect(st.ring, '0%');
      expect(st.chip, 'Answered');
      expect(st.sub, 'The chat is on the way');
      expect(st.live, isTrue);
      expect('${st.bigBefore}${st.highlight}${st.bigAfter}', contains('answered'));
    });

    test('a file answer says "The file is on the way"', () {
      expect(RequestStep307.of(_chat('f1', action: 'get_file')).sub, isNot('The chat is on the way'));
      expect(RequestStep307.of(_chat('f1', action: 'get_file')).step, Step307.coming);
    });

    test('every part here = Ready; a closed copy stays Ready; other actions unchanged', () {
      expect(RequestStep307.of(_chat('r1', parts: 40, of: 40)).step, Step307.ready);
      expect(RequestStep307.of(_chat('r1', closed: true)).step, Step307.ready);
      expect(RequestStep307.of(_chat('r1', action: 'delete_completely')).step, Step307.ready);
      expect(RequestStep307.of(_chat('r1', parts: 31, of: 80)).step, Step307.coming);
    });

    test('regression: pending steps (sent / reached / coming) unchanged', () {
      expect(RequestStep307.of(const ChatRequestRow221(id: 'x', action: 'get_chat', phones: 2)).step, Step307.sent);
      expect(RequestStep307.of(const ChatRequestRow221(id: 'x', action: 'get_chat', phones: 2, reached: 1)).step,
          Step307.reached);
      expect(RequestStep307.of(const ChatRequestRow221(id: 'x', action: 'get_chat', parts: 3, of: 9)).step,
          Step307.coming);
    });

    test('no buzz before Ready: a "done" card with no parts never buzzes', () async {
      final cards = _Cards();
      final n = ChatRequestNotifier307(
        mine: () async => [_chat('r1')],
        isOwner: () async => true,
        read: (k) async => null,
        write: (k, v) async {},
        cards: cards,
        clock: () => DateTime.utc(2026, 11, 16, 12),
        checkEvery: const Duration(hours: 1),
      );
      await n.refresh();
      expect(cards.shows.single['step'], 'coming');
      expect(cards.shows.single['buzz'], isFalse);
    });
  });

  group('317 G1 - the file queue', () {
    test('planOf: one entry per file id, newest message first, gone kept', () {
      final plan = FileQueue317.planOf(_answer([_att('a'), _att('b'), _att('c'), _att('a'), _att('g', gone: true)]));
      expect(plan.map((i) => i.fileId), ['c', 'a', 'g', 'b']);
      expect(plan.firstWhere((i) => i.fileId == 'g').gone, isTrue);
    });

    test('asks 2 files at a time, skips gone and over 50 MB', () async {
      final t = _Q(_answer([_att('a'), _att('b'), _att('big', size: 60 * _mb), _att('g', gone: true), _att('c')]));
      t.rows = [_chat('r1', parts: 40, of: 40)];
      await t.q.tick();
      expect(t.asked, hasLength(2));
      expect(t.asked, isNot(contains('big')));
      expect(t.asked, isNot(contains('g')));
      final trip = FileQueue317.trips.value['r1']!;
      expect(trip.total, 5);
      expect(trip.gone, 1);
      expect(trip.tooBig, 1);
      expect(trip.wanted, 3);
      expect(trip.here, 0);
      expect(trip.active, isTrue);
      expect(trip.from, 'kiran');
      // Asked once: the next tick asks nothing new while 2 are on the way.
      await t.q.tick();
      expect(t.asked, hasLength(2));
      expect(t.opens, 1);
    });

    test('16 MB window: one big file at a time', () async {
      final t = _Q(_answer([_att('a', size: 10 * _mb), _att('b', size: 10 * _mb)]));
      t.rows = [_chat('r1', parts: 40, of: 40)];
      await t.q.tick();
      expect(t.asked, hasLength(1));
    });

    test('max 3 pending cards: the Owner can still make actions', () async {
      final t = _Q(_answer([_att('a'), _att('b')]));
      t.rows = [
        _chat('r1', parts: 40, of: 40),
        for (var i = 0; i < 3; i++) _file('p$i', 'other', 'x$i'),
      ];
      await t.q.tick();
      expect(t.asked, isEmpty);
    });

    test('next file when one is here; refused = gone, never asked again', () async {
      final t = _Q(_answer([_att('a'), _att('b'), _att('c')]));
      t.rows = [_chat('r1', parts: 40, of: 40)];
      await t.q.tick();
      final first = List.of(t.asked);
      expect(first, hasLength(2));
      t.rows = [
        _chat('r1', parts: 40, of: 40),
        _file('aa_${first[0]}', 'r1', first[0], state: 'done', parts: 3, of: 3),
        _file('aa_${first[1]}', 'r1', first[1], state: 'done', refused: 'file_gone'),
      ];
      await t.q.tick();
      expect(t.asked, hasLength(3));
      final trip = FileQueue317.trips.value['r1']!;
      expect(trip.here, 1);
      expect(trip.gone, 1);
      expect(t.q.viewsOf('r1')[first[1]]!.state, FileState317.gone);
      expect(t.q.viewsOf('r1')[first[0]]!.state, FileState317.here);
      await t.q.tick();
      expect(t.asked.where((x) => x == first[1]), hasLength(1));
    });

    test('Stop files: queue stops, pending cards cancelled, answers on the way closed', () async {
      final t = _Q(_answer([_att('a'), _att('b'), _att('c')]));
      t.rows = [_chat('r1', parts: 40, of: 40)];
      await t.q.tick();
      t.rows = [
        _chat('r1', parts: 40, of: 40),
        _file('aa_${t.asked[0]}', 'r1', t.asked[0]),
        _file('aa_${t.asked[1]}', 'r1', t.asked[1], state: 'done', parts: 1, of: 9),
      ];
      await t.q.tick();
      await t.q.stopFiles('r1');
      expect(t.cancelled, ['aa_${t.asked[0]}']);
      expect(t.closed, ['aa_${t.asked[1]}']);
      expect(FileQueue317.trips.value['r1']!.stopped, isTrue);
      expect((await t.q.planForTest('r1'))!['stopped'], isTrue);
      final before = t.asked.length;
      await t.q.tick();
      expect(t.asked.length, before);
    });

    test('waiting after 2 min with no new parts; quiet minutes counted', () async {
      final t = _Q(_answer([_att('a')]));
      t.rows = [_chat('r1', parts: 40, of: 40)];
      await t.q.tick();
      t.rows = [_chat('r1', parts: 40, of: 40), _file('aa_a', 'r1', 'a', state: 'done', parts: 2, of: 9)];
      await t.q.tick();
      expect(FileQueue317.trips.value['r1']!.waiting, isFalse);
      t.now = t.now.add(const Duration(minutes: 3));
      await t.q.tick();
      expect(FileQueue317.trips.value['r1']!.waiting, isTrue);
      expect(FileQueue317.trips.value['r1']!.quietMin, 3);
      t.now = t.now.add(const Duration(minutes: 30));
      await t.q.tick();
      expect(FileQueue317.trips.value['r1']!.waitingLong, isTrue);
    });

    test('not the Owner / not my request / chat not complete: nothing asked', () async {
      final t = _Q(_answer([_att('a')]));
      t.rows = [_chat('r1', parts: 40, of: 40)];
      t.owner = false;
      await t.q.tick();
      t.owner = true;
      t.mine = {};
      await t.q.tick();
      t.mine = {'r1'};
      t.rows = [_chat('r1', parts: 3, of: 40)];
      await t.q.tick();
      expect(t.asked, isEmpty);
    });
  });

  group('317 G7 - the phone card after "Chat ready"', () {
    final ready = RequestStep307.of(_chat('r1', parts: 40, of: 40));
    final row = _chat('r1', parts: 40, of: 40);
    final now = DateTime.utc(2026, 11, 16, 12);

    test('files coming: one line "chat · 3/13" (321 pick B), short, no Stop button', () {
      final a = ChatRequestNotifier307.filesArgs317(row, ready, _trip(), now);
      expect(a['step'], 'files');
      expect(a['title'], 'kiran & ayesha · 3/13');
      expect(a.containsKey('text'), isFalse);
      expect(a['from_name'], 'kiran');
      expect(a['short'], '3/13');
      expect(a.containsKey('stop_label'), isFalse);
      expect(a['progress'], 25);
      expect(a['files_trips'], 3);
      expect(a['files_swipe'], isFalse);
      expect(a['request_id'], 'r1');
    });

    test('waiting: orange step + "last parts 4 min ago"; 30 min = swipeable', () {
      final a = ChatRequestNotifier307.filesArgs317(row, ready, _trip(waiting: true, quietMin: 4), now);
      expect(a['step'], 'files_wait');
      expect(a['title'], 'kiran & ayesha · waiting');
      expect(ChatRequestNotifier307.filesArgs317(row, ready, _trip(waiting: true, quietMin: 31), now)['files_swipe'],
          isTrue);
    });

    test('done: "11 files here · 2 not on the phone any more", no short', () {
      final a = ChatRequestNotifier307.filesArgs317(
          row, ready, _trip(here: 11, gone: 2, coming: 0, bytesHere: 19 * _mb, bytesTotal: 19 * _mb), now);
      expect(a['step'], 'files_done');
      // 2 files can't come: no check (Ready = all files), the count instead.
      expect(a['title'], 'kiran & ayesha · 11/13');
      expect(ChatRequestNotifier307.filesArgs317(row, ready, _trip(here: 13, coming: 0), now)['title'], 'kiran & ayesha \u2713');
      expect(a['short'], '');
    });

    test('summary lines: Files 3/13 / Files waiting / All files here', () {
      expect(ChatRequestNotifier307.filesLine317(ready, _trip()), 'Files 3/13');
      expect(ChatRequestNotifier307.filesLine317(ready, _trip(waiting: true)), contains('3/13'));
      expect(ChatRequestNotifier307.filesLine317(ready, _trip(here: 13, coming: 0)), 'All files here');
      expect(ChatRequestNotifier307.filesLine317(ready, null), isNull);
      expect(ChatRequestNotifier307.filesLine317(ready, _trip(stopped: true)), isNull);
    });

    test('the card stays while files come (even opened), one buzz, goes when done + opened', () async {
      final cards = _Cards();
      var rows = [_chat('r1', parts: 40, of: 40)];
      var files = {'r1': _trip()};
      var now = DateTime.utc(2026, 11, 16, 12);
      final saved = <String, String>{};
      final n = ChatRequestNotifier307(
        mine: () async => rows,
        isOwner: () async => true,
        read: (k) async => saved[k],
        write: (k, v) async => saved[k] = v,
        cards: cards,
        files317: () => files,
        clock: () => now,
        checkEvery: const Duration(hours: 1),
      );
      await n.refresh();
      expect(cards.shows.last['step'], 'files');
      expect(cards.shows.last['buzz'], isTrue); // the one "Chat ready" buzz
      now = now.add(const Duration(seconds: 5));
      rows = [_chat('r1', parts: 40, of: 40, opened: true)];
      files = {'r1': _trip(here: 4)};
      await n.refresh();
      expect(cards.cancels, isEmpty);
      expect(cards.shows.last['step'], 'files');
      expect(cards.shows.last['buzz'], isFalse);
      now = now.add(const Duration(seconds: 5));
      files = {'r1': _trip(here: 13, coming: 0)};
      await n.refresh();
      expect(cards.cancels.single['request_id'], 'r1');
      expect(cards.shows.where((s) => s['buzz'] == true), hasLength(1));
    });

    test('Stop files on the card comes back as a tap "stop317:<id>" and stops the queue', () async {
      final t = _Q(_answer([_att('a'), _att('b'), _att('c')]));
      t.rows = [_chat('r1', parts: 40, of: 40)];
      await t.q.tick();
      FileQueue317.instance = t.q;
      final taps = StreamController<String>();
      final opened = <String>[];
      ChatRequestNotifier307.openViewer = (id) async => opened.add(id);
      final n = ChatRequestNotifier307(
        mine: () async => t.rows,
        isOwner: () async => true,
        read: (k) async => null,
        write: (k, v) async {},
        cards: _Cards(),
        taps: taps.stream,
        clock: () => t.now,
        checkEvery: const Duration(hours: 1),
      )..start();
      taps.add('${ChatRequestNotifier307.stopPrefix317}r1');
      for (var i = 0; i < 20 && !(FileQueue317.trips.value['r1']?.stopped ?? false); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(FileQueue317.trips.value['r1']!.stopped, isTrue);
      expect(opened, isEmpty);
      n.stop();
      await taps.close();
      ChatRequestNotifier307.openViewer = null;
    });
  });

  group('317 G8 - admin card + live row', () {
    test('liveOrder keeps a Ready request live while its files come', () {
      final r = _chat('r1', parts: 40, of: 40, opened: true);
      expect(RequestStep307.liveOrder([r]), isEmpty);
      expect(RequestStep307.liveOrder([r], files: {'r1': _trip()}).single.id, 'r1');
      expect(RequestStep307.liveOrder([r], files: {'r1': _trip(here: 13, coming: 0)}), isEmpty);
    });

    Future<void> card(WidgetTester tester, FileTrip317 trip, {bool dark = false}) async {
      await tester.pumpWidget(MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LiveCard307(
              step: RequestStep307.of(_chat('r1', parts: 40, of: 40)),
              names: const ['kiran', 'ayesha'],
              title: 'kiran & ayesha',
              range: 'Last 7 days',
              brand: 'Get chat',
              files: trip,
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('files strip: "3 of 13 files", from / via, Coming pill, one bar per 8 MB trip', (tester) async {
      await card(tester, _trip());
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('live317_files')), findsOneWidget);
      expect(find.textContaining('3 of 13 files', findRichText: true), findsOneWidget);
      expect(find.textContaining("from kiran's phone"), findsOneWidget);
      expect(find.textContaining('via ayesha'), findsOneWidget);
      expect(find.text('Coming'), findsOneWidget);
      expect(find.byKey(const ValueKey('live317_trip_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('live317_trip_3')), findsNothing);
    });

    testWidgets('done (dark): "11 files here", All files here, gone line', (tester) async {
      await card(tester, _trip(here: 11, gone: 2, coming: 0, bytesHere: 19 * _mb, bytesTotal: 19 * _mb), dark: true);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('11 files here', findRichText: true), findsOneWidget);
      expect(find.text('All files here'), findsOneWidget);
      expect(find.text('2 not on the phone any more'), findsOneWidget);
    });

    testWidgets('stopped / no files: no strip', (tester) async {
      await card(tester, _trip(stopped: true));
      expect(find.byKey(const ValueKey('live317_files')), findsNothing);
    });

    test('source: request row second chip + card fed from the queue', () {
      final s = File('lib/features/admin/presentation/screens/admin_conversations_screen.dart').readAsStringSync();
      expect(s, contains("ValueKey('requests317_files_\${r.id}')"));
      expect(s, contains('files: FileQueue317.trips.value[r.id], // Bundle 317 (G8)'));
      expect(s, contains('RequestStep307.liveOrder(requests, files: FileQueue317.trips.value)'));
      final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(deps, contains('files317: () => FileQueue317.trips.value, // Bundle 317 (G7)'));
      expect(deps, contains('FileQueue317.trips]),'));
    });
  });

  group('317 B / C / D / G6 - the viewer', () {
    Future<void> open(WidgetTester tester, ChatAnswerView view, {List<Map<String, dynamic>> reqs = const []}) async {
      tester.view.physicalSize = const Size(400 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: AdminChatViewerScreen(
              service: _svc(_Srv(view, reqs: reqs)),
              request: ChatRequestRow221(
                  id: 'r1', action: 'get_chat', label: 'Friends', state: 'done', parts: 1, of: 1,
                  fromName: 'kiran', chat: view.chat))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    testWidgets('B: a group event is a centred system line, never llev code', (tester) async {
      final ev = 'llev:v1:${jsonEncode({'k': 'create', 'by': 'dev-k', 'n': 'Friends', 't': ['dev-a'], 'nm': {'dev-k': 'kiran', 'dev-a': 'ayesha'}})}';
      await open(
          tester,
          ChatAnswerView(id: 'r1', answerId: 'an', fromDevice: 'dev-k', complete: true, of: 1, parts: 1,
              chat: const {'kind': 'group', 'group_id': 'g1', 'name': 'Friends'},
              messages: [
                {'id': 'm1', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-16T11:30:00', 'body': ev},
                {'id': 'm2', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-16T11:31:00', 'body': 'hi'},
              ]));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('viewer317_sys_m1')), findsOneWidget);
      expect(find.text('kiran created group "Friends"'), findsOneWidget);
      expect(find.textContaining('llev:v1:'), findsNothing);
      expect(find.text('kiran'), findsOneWidget); // the next bubble shows its name
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('C: deleted = small red "Deleted <time>"', (tester) async {
      await open(
          tester,
          const ChatAnswerView(id: 'r1', answerId: 'an', fromDevice: 'dev-k', complete: true, of: 1, parts: 1, messages: [
            {
              'id': 'm1', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-16T11:30:00',
              'body': 'old', 'deleted_at': '2026-11-16T11:41:00',
            },
          ]));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Deleted', findRichText: true), findsWidgets);
      expect(find.textContaining('Deleted by user'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('D + G6: one row per file, no Get button, every state in words', (tester) async {
      await open(
          tester,
          const ChatAnswerView(id: 'r1', answerId: 'an', fromDevice: 'dev-k', fromName: 'kiran', complete: true, of: 1, parts: 1, messages: [
            {
              'id': 'm1', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-16T11:30:00', 'body': '',
              'attachments': [
                {'file_id': 'v1', 'name': 'clip.mp4', 'type': 'video/mp4', 'size': 2097152},
                {'file_id': 'v1', 'name': 'clip.mp4', 'type': 'video/mp4', 'size': 2097152},
              ],
            },
            {
              'id': 'm2', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-16T11:31:00', 'body': '',
              'attachments': [
                {'file_id': 'big', 'name': 'film.mp4', 'type': 'video/mp4', 'size': 60 * 1024 * 1024},
              ],
            },
            {
              'id': 'm3', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-16T11:32:00', 'body': '',
              'attachments': [
                {'file_id': 'g1', 'name': 'a.pdf', 'type': 'application/pdf', 'size': 3000},
              ],
            },
          ]),
          reqs: [
            {'id': 'aa_g1', 'action': 'get_file', 'state': 'done', 'parent': 'r1', 'file_id': 'g1', 'refused': 'file_gone'},
          ]);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Next in line', findRichText: true), findsOneWidget); // v1 once, not twice
      expect(find.textContaining('Too big to bring (over 50 MB)', findRichText: true), findsOneWidget);
      expect(find.textContaining('phone any more', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer221_getfile_v1')), findsNothing);
      expect(find.textContaining('Get full'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    test('source: Stop files in the viewer strip + "All files here" fades', () {
      final s = File('lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart').readAsStringSync();
      expect(s, contains("ValueKey('viewer317_stop_files')"));
      expect(s, contains('FileQueue317.instance?.stopFiles(widget.request.id)'));
      expect(s, isNot(contains('Future<void> _getFile(')));
    });
  });

  group('317 E / F', () {
    test('E: the map hint fades after 4 s; the first view keeps out of the buttons column', () {
      final s = File('lib/features/admin/presentation/screens/link_paths_full_screen.dart').readAsStringSync();
      expect(s, contains('_hintTimer = Timer(const Duration(seconds: 4)'));
      expect(s, contains("ValueKey('link_map_hint_fade317')"));
      expect(s, contains('static const double controlsInset317 = 70;'));
      expect(s, contains('_hintTimer?.cancel();'));
    });

    test('F: the seen packets load on a background thread', () {
      final s = File('android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt').readAsStringSync();
      expect(s, contains('startSeenLoad317();restoreIncomingTransfers()'));
      expect(s, contains('"linkup-seen-load"'));
    });
  });

  test('regression: carrier + notifier locks still in place', () {
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(deps, contains('taps: notifications.platform.chatRequestTaps307,'));
    expect(deps, contains('ChatRequests221.changed307 = card307.kick;'));
    expect(ChatAnswerCarrier.progress, isNotNull);
  });
}

// ---------------------------------------------------------------- fakes

class _Srv implements ChatAdminServer {
  final ChatAnswerView view;
  final List<Map<String, dynamic>> reqs;
  _Srv(this.view, {this.reqs = const []});
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => const [];
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => reqs;
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async => {'id': 'aa_new'};
  @override
  Future<ChatAnswerView> answer(String token, String id) async => view;
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

ChatRequests221 _svc(ChatAdminServer server) {
  final saved = <String, String>{};
  return ChatRequests221(
    server: server,
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
    read: (k) async => saved[k],
    write: (k, v) async => saved[k] = v,
  );
}
