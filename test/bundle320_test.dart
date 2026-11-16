// Bundle 320 (TODO_320): Conversations = ONE list (no tabs, no carousel) +
// the calmer chat viewer (shimmer while loading, waiting card, coming strip,
// kept line, "Coming by itself" tag). Regression: llev raw text and Get full
// buttons stay gone (fixed in 317).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit320.dart';
import 'package:locallink/l10n/l10n.dart';

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

/// The real service with fixed request rows (kept-copy facts included) and
/// a recorded "Get new messages only".
class _Svc extends ChatRequests221 {
  _Svc(_Srv srv, {this.rows = const [], this.hang = false})
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
  final bool hang;
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
String _ahead(Duration d) => DateTime.now().toUtc().add(d).toIso8601String();

final _chats = [
  _direct('c1', 'u-s', 'sumaira', 'u-k', 'kiran'), // ready (Open)
  _direct('c2', 'u-i', 'ibrahim', 'u-a', 'ayesha'), // kept copy (New)
  _direct('c3', 'u-n', 'noshad', 'u-z', 'sara', count: 42), // nothing (Get chat)
  _direct('c4', 'u-a', 'ayesha', 'u-k', 'kiran'), // coming (Now)
  _direct('c5', 'u-m', 'maria', 'u-q', 'qasim'), // cancelled
];

List<ChatRequestRow221> _rows() => [
      ChatRequestRow221(
          id: 'r1', action: 'get_chat', label: 'sumaira & kiran', state: 'done', parts: 4, of: 4,
          madeAt: _ago(const Duration(hours: 3)), chat: _ref('u-s', 'u-k')),
      // The kept copy (opened) and an older answer of the same chat: one row.
      ChatRequestRow221(
          id: 'r2', action: 'get_chat', label: 'ibrahim & ayesha', state: 'done', parts: 2, of: 2, opened: true,
          madeAt: _ago(const Duration(days: 1)), chat: _ref('u-a', 'u-i'), keptUntil318: _ahead(const Duration(days: 5))),
      ChatRequestRow221(
          id: 'r2old', action: 'get_chat', label: 'ibrahim & ayesha', state: 'done', parts: 1, of: 1, opened: true,
          madeAt: _ago(const Duration(days: 2)), chat: _ref('u-i', 'u-a')),
      ChatRequestRow221(
          id: 'r4', action: 'get_chat', label: 'ayesha & kiran', state: 'pending', parts: 40, of: 80,
          fromName: 'ayesha', madeAt: _ago(const Duration(minutes: 20)), chat: _ref('u-a', 'u-k')),
      // Sent 2 h ago to a group nobody here knows yet (request-only Now row).
      ChatRequestRow221(
          id: 'r6', action: 'get_chat', label: 'Friends', state: 'pending', phones: 3,
          madeAt: _ago(const Duration(hours: 2)), chat: const {'kind': 'group', 'group_id': 'g-f'}),
      ChatRequestRow221(
          id: 'r5', action: 'get_chat', label: 'maria & qasim', state: 'cancelled',
          madeAt: '2026-11-14T12:00:00Z', chat: _ref('u-m', 'u-q')),
      const ChatRequestRow221(id: 'f1', action: 'get_file', parent: 'r1', fileId: 'x'),
    ];

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

Finder _in(String key, Finder f) => find.descendant(of: find.byKey(ValueKey(key)), matching: f);

String _status(WidgetTester tester, String key) {
  final line = tester.widget<StatusLine320>(find.byKey(ValueKey(key)));
  return line.text;
}

void main() {
  group('320 A - one list (R1-R4)', () {
    testWidgets('A1: no tabs, no carousel; Now = on their way, Chats = every other chat once', (tester) async {
      await _phone(tester);
      await _openList(tester, _Svc(_Srv(chats: _chats), rows: _rows()));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('tabs221_0')), findsNothing);
      expect(find.byKey(const ValueKey('live307_carousel')), findsNothing);
      expect(find.byType(Segmented307), findsNothing);
      // Now: the coming chat + the waiting group, nothing else.
      expect(_in('conv320_now', find.byKey(const ValueKey('requests221_row_r4'))), findsOneWidget);
      expect(_in('conv320_now', find.byKey(const ValueKey('requests221_row_r6'))), findsOneWidget);
      expect(find.byKey(const ValueKey('requests221_row_r1')), findsNothing);
      // Chats: c4 is in Now -> not in Chats; the kept chat (2 answers) is ONE row.
      expect(find.byKey(const ValueKey('chats221_row_c4')), findsNothing);
      expect(find.byKey(const ValueKey('chats221_row_c2')), findsOneWidget);
      expect(find.byKey(const ValueKey('chats221_row_r2old')), findsNothing);
      expect(find.byKey(const ValueKey('chats221_row_r2')), findsNothing);
      expect(_in('chats221_list', find.byType(InkWell)).evaluate().length, greaterThanOrEqualTo(4));
    });

    testWidgets('A2: one status line + one button per row (Open / New / Get chat)', (tester) async {
      await _phone(tester);
      await _openList(tester, _Svc(_Srv(chats: _chats), rows: _rows()));
      expect(find.byKey(const ValueKey('chats320_open_c1')), findsOneWidget);
      expect(_status(tester, 'chats320_status_c1'), 'Ready to read');
      expect(find.byKey(const ValueKey('chats320_new_c2')), findsOneWidget);
      expect(_status(tester, 'chats320_status_c2'), startsWith('Kept until '));
      expect(tester.widget<StatusLine320>(find.byKey(const ValueKey('chats320_status_c2'))).icon, Icons.lock_rounded);
      expect(find.byKey(const ValueKey('chats221_ask_c3')), findsOneWidget);
      expect(_status(tester, 'chats320_status_c3'), startsWith('42 messages'));
      // R4: cancelled = status line only + Get chat.
      expect(_status(tester, 'chats320_status_c5'), 'Cancelled \u00b7 14 Nov');
      expect(find.byKey(const ValueKey('chats221_ask_c5')), findsOneWidget);
      // No old chips on the list.
      expect(find.byType(Chip307), findsNothing);
      expect(find.byType(ProgressRing307), findsNothing);
    });

    testWidgets('A3: Now rows - coming bar + "40 of 80 parts"; waiting = orange line + age, X asks first',
        (tester) async {
      await _phone(tester);
      await _openList(tester, _Svc(_Srv(chats: _chats), rows: _rows()));
      expect(_status(tester, 'now320_status_r4'), "Coming \u00b7 ayesha's phone");
      expect(find.byKey(const ValueKey('now320_parts_r4')), findsOneWidget);
      expect(find.text('40 of 80 parts'), findsOneWidget);
      expect(find.byKey(const ValueKey('parts221_bar')), findsOneWidget); // only the coming row
      expect(find.byKey(const ValueKey('requests221_cancel_r4')), findsNothing);
      expect(_status(tester, 'now320_status_r6'), 'Waiting for a phone \u00b7 2 h');
      expect(tester.widget<StatusLine320>(find.byKey(const ValueKey('now320_status_r6'))).tone, Tone320.orange);
      await tester.tap(find.byKey(const ValueKey('requests221_cancel_r6')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('chat_request_cancel_yes')), findsOneWidget);
      expect(find.text('Cancel this request?'), findsOneWidget);
    });

    testWidgets('A4: New on a kept copy = Get new messages only for that chat', (tester) async {
      await _phone(tester);
      final svc = _Svc(_Srv(chats: _chats), rows: _rows());
      await _openList(tester, svc);
      await tester.tap(find.byKey(const ValueKey('chats320_new_c2')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(svc.askedNew, hasLength(1));
      expect({svc.askedNew.single.userA, svc.askedNew.single.userB}, {'u-i', 'u-a'});
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('A5: filter chips count and filter; search finds both cards', (tester) async {
      await _phone(tester);
      await _openList(tester, _Svc(_Srv(chats: _chats), rows: _rows()));
      for (final (f, n) in [('all', '6'), ('coming', '2'), ('ready', '1'), ('kept', '1')]) {
        expect(_in('conv320_filter_$f', find.text(n)), findsOneWidget, reason: f);
      }
      await tester.tap(find.byKey(const ValueKey('conv320_filter_coming')));
      await tester.pump();
      expect(find.byKey(const ValueKey('conv320_now')), findsOneWidget);
      expect(find.byKey(const ValueKey('chats221_list')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('conv320_filter_ready')));
      await tester.pump();
      expect(find.byKey(const ValueKey('conv320_now')), findsNothing);
      expect(find.byKey(const ValueKey('chats221_row_c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('chats221_row_c2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('conv320_filter_kept')));
      await tester.pump();
      expect(find.byKey(const ValueKey('chats221_row_c2')), findsOneWidget);
      expect(find.byKey(const ValueKey('chats221_row_c1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('conv320_filter_all')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('chats307_search')), 'noshad');
      await tester.pump();
      expect(find.byKey(const ValueKey('chats221_row_c3')), findsOneWidget);
      expect(find.byKey(const ValueKey('conv320_now')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('chats307_search')), 'zzz');
      await tester.pump();
      expect(find.byKey(const ValueKey('conv320_nothing')), findsOneWidget);
    });

    testWidgets('A6: nothing slides by itself - no timer moves the rows (loops on)', (tester) async {
      Motion307.loopsForTest = true;
      addTearDown(() => Motion307.loopsForTest = null);
      await _phone(tester);
      await _openList(tester, _Svc(_Srv(chats: _chats), rows: _rows()));
      final before = tester.getTopLeft(find.byKey(const ValueKey('requests221_row_r4')));
      await tester.pump(const Duration(seconds: 12));
      expect(tester.getTopLeft(find.byKey(const ValueKey('requests221_row_r4'))), before);
      await tester.pumpWidget(const SizedBox());
    });

    for (final lang in ['en', 'ur']) {
      for (final dark in [false, true]) {
        testWidgets('A7 $lang ${dark ? 'dark' : 'light'} 320 dp x1.3: full text, no overflow, no "..."',
            (tester) async {
          LanguageBook304.instance.load(lang);
          addTearDown(() => LanguageBook304.instance.resetForTest());
          await _phone(tester, width: 320);
          await _openList(tester, _Svc(_Srv(chats: _chats), rows: _rows()), dark: dark, scale: 1.3);
          expect(tester.takeException(), isNull);
          final hints = tester
              .renderObjectList<RenderParagraph>(
                  find.descendant(of: find.byType(InputDecorator), matching: find.byType(RichText)))
              .toSet();
          for (final p in tester.renderObjectList<RenderParagraph>(
              find.descendant(of: find.byType(AdminConversationsScreen), matching: find.byType(RichText)))) {
            if (hints.contains(p)) continue;
            expect(p.overflow == TextOverflow.ellipsis || p.didExceedMaxLines, isFalse,
                reason: p.text.toPlainText());
          }
        });
      }
    }

    test('A8: age words', () {
      final now = DateTime.utc(2026, 11, 16, 12);
      expect(AdminConversationsScreenAge320.of('2026-11-16T11:59:40Z', now), 'just now');
      expect(AdminConversationsScreenAge320.of('2026-11-16T11:55:00Z', now), '5 min');
      expect(AdminConversationsScreenAge320.of('2026-11-16T10:00:00Z', now), '2 h');
      expect(AdminConversationsScreenAge320.of('2026-11-13T12:00:00Z', now), '3 d');
      expect(AdminConversationsScreenAge320.of('', now), '');
    });

    test('A9: source - the carousel, auto-advance and tabs are gone', () {
      final s = File('lib/features/admin/presentation/screens/admin_conversations_screen.dart').readAsStringSync();
      expect(s, isNot(contains('Timer.periodic(AdminConversationsScreen.advanceEvery')));
      expect(s, isNot(contains('Segmented307(')));
      expect(s, isNot(contains("ValueKey('tabs221_")));
      expect(s, isNot(contains('LiveCard307(')));
      expect(s, contains('RequestStep307.liveOrder(requests, files: FileQueue317.trips.value)'));
    });

    test('A10: every 320 word has Urdu (LTR wrapped, 304 rule)', () {
      final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
      final ur = jsonDecode(File('lib/l10n/app_ur.arb').readAsStringSync()) as Map<String, dynamic>;
      final keys = [for (final k in en.keys) if (k.endsWith('320') && !k.startsWith('@')) k];
      expect(keys.length, 31);
      for (final k in keys) {
        expect(ur[k], isA<String>(), reason: k);
        expect((ur[k] as String).startsWith('\u2067'), isTrue, reason: k);
      }
    });
  });

  group('320 B - the viewer (R5-R8)', () {
    const req = ChatRequestRow221(
        id: 'r9', action: 'get_chat', label: 'ayesha & kiran', state: 'pending', phones: 2,
        madeAt: '2026-11-16T09:54:00Z', chat: {'kind': 'direct', 'users': ['u-a', 'u-k']});

    Future<void> openViewer(WidgetTester tester, _Svc svc, ChatRequestRow221 r, {ChatAnswerView? view, bool dark = false}) async {
      await _phone(tester);
      await tester.pumpWidget(MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: AdminChatViewerScreen(service: svc, request: r, view: view)));
      await tester.pump();
    }

    testWidgets('B1 (R5): loading = grey bubble shapes, no spinner', (tester) async {
      await openViewer(tester, _Svc(_Srv(), hang: true), req);
      expect(find.byKey(const ValueKey('viewer320_loading')), findsOneWidget);
      expect(find.byType(BubbleSkeleton320), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    for (final dark in [false, true]) {
      testWidgets('B2 (R6): waiting card - who, asked, sent to, Cancel asks first (${dark ? 'dark' : 'light'})',
          (tester) async {
        final keep = adminNow216;
        adminNow216 = () => parseAdminTime216(req.madeAt)!.add(const Duration(minutes: 3));
        addTearDown(() => adminNow216 = keep);
        await openViewer(tester, _Svc(_Srv()), req, view: const ChatAnswerView(id: 'r9'), dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('viewer320_waiting')), findsOneWidget);
        expect(find.text("Waiting for ayesha's or kiran's phone"), findsOneWidget);
        expect(find.textContaining('comes by itself'), findsOneWidget);
        expect(find.textContaining('no time limit'), findsOneWidget);
        expect(find.byKey(const ValueKey('viewer320_fact_asked')), findsOneWidget);
        expect(find.text('2 phones'), findsOneWidget);
        // Asked today -> "Today 9:54" (not a bare time).
        final asked = tester.widget<Text>(find.descendant(
            of: find.byKey(const ValueKey('viewer320_fact_asked')), matching: find.byType(Text)).last);
        expect(asked.data, startsWith('Today '));
        // Last seen is not known on this phone -> its row is hidden.
        expect(find.text('Last seen'), findsNothing);
        expect(find.text('Waiting for a phone of this chat. There is no time limit.'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('viewer320_cancel')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('chat_request_cancel_yes')), findsOneWidget);
      });
    }

    testWidgets('B3 (R6): unknown facts hide; a group says "a phone in Friends"; no Cancel once answered',
        (tester) async {
      const g = ChatRequestRow221(
          id: 'g1', action: 'get_chat', label: 'Friends', state: 'pending', chat: {'kind': 'group', 'group_id': 'g-f'});
      await openViewer(tester, _Svc(_Srv()), g, view: const ChatAnswerView(id: 'g1'));
      expect(find.text('Waiting for a phone in Friends'), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer320_fact_asked')), findsNothing);
      expect(find.byKey(const ValueKey('viewer320_fact_sent')), findsNothing);
      expect(find.byKey(const ValueKey('viewer320_cancel')), findsOneWidget);
      const answered = ChatRequestRow221(
          id: 'r9', action: 'get_chat', label: 'ayesha & kiran', state: 'done', fromName: 'kiran',
          chat: {'kind': 'direct', 'users': ['u-a', 'u-k']});
      await tester.pumpWidget(const SizedBox());
      await openViewer(tester, _Svc(_Srv()), answered, view: const ChatAnswerView(id: 'r9'));
      expect(find.byKey(const ValueKey('viewer317_answered')), findsOneWidget); // 317 words unchanged
      expect(find.byKey(const ValueKey('viewer320_cancel')), findsNothing);
    });

    testWidgets('B4 (R7): coming strip + messages here + shimmer rows + "More messages on the way"', (tester) async {
      const half = ChatAnswerView(id: 'r9', answerId: 'a', fromDevice: 'dev-a', fromName: 'ayesha', of: 80, parts: 40,
          messages: [
            {'id': 'm1', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-16T11:26:00', 'body': 'hii'},
          ]);
      await openViewer(tester, _Svc(_Srv()), req, view: half);
      expect(tester.takeException(), isNull);
      expect(find.text('Coming \u00b7 40 of 80 parts'), findsOneWidget);
      expect(find.byKey(const ValueKey('parts221_bar')), findsOneWidget);
      expect(find.text('hii'), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer320_more_shimmer')), findsOneWidget);
      expect(find.text('More messages on the way\u2026'), findsOneWidget);
      // One update only: no time guess.
      expect(find.byKey(const ValueKey('viewer320_eta')), findsNothing);
      expect(find.text('No messages in these dates'), findsNothing);
    });

    test('B5 (R7): the time guess needs 2+ updates with a rate', () {
      final t0 = DateTime(2026, 11, 16, 12);
      expect(AdminChatViewerScreenEta320.of([(t0, 10)], 80), '');
      expect(AdminChatViewerScreenEta320.of([(t0, 10), (t0.add(const Duration(seconds: 10)), 20)], 80), 'about 1 min');
      expect(AdminChatViewerScreenEta320.of([(t0, 10), (t0.add(const Duration(seconds: 10)), 12)], 80), 'about 6 min');
      expect(AdminChatViewerScreenEta320.of([(t0, 10), (t0.add(const Duration(seconds: 1)), 20)], 80),
          'less than a minute');
      expect(AdminChatViewerScreenEta320.of([(t0, 10), (t0.add(const Duration(seconds: 5)), 10)], 80), '');
    });

    testWidgets('B6 (R8): kept copy - one green "Kept on this phone until" line, short header', (tester) async {
      const kept = ChatAnswerView(
          id: 'k1', answerId: 'kept318:c1', fromName: 'kiran', of: 1, parts: 1, complete: true,
          fromKept318: true, keptFull318: true, keptGotAt318: '2026-11-16T10:05:00Z',
          keptUntil318: '2026-11-23T12:00:00Z',
          messages: [
            {'id': 'm1', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-16T11:32:00', 'body': 'hi'},
          ]);
      const r = ChatRequestRow221(
          id: 'k1', action: 'get_chat', label: 'Friends', state: 'done', parts: 1, of: 1,
          chat: {'kind': 'group', 'group_id': 'g-f'});
      await openViewer(tester, _Svc(_Srv()), r, view: kept);
      expect(tester.takeException(), isNull);
      // Bundle 321 (R4, listed change): the kept line moved into the header.
      expect(find.text('Kept here until 23 Nov'), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer320_kept')), findsOneWidget);
      expect(find.textContaining('got ', findRichText: true), findsNothing);
      expect(find.byKey(const ValueKey('viewer221_parts')), findsNothing);
    });

    testWidgets('B7 (R8): a photo / video on its way says "Coming by itself"; no Get button', (tester) async {
      const half = ChatAnswerView(id: 'r9', answerId: 'a', fromDevice: 'dev-a', fromName: 'ayesha', of: 2, parts: 1,
          messages: [
            {
              'id': 'm5', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-16T11:33:00', 'body': '',
              'attachments': [
                {'file_id': 'p1', 'name': 'a.jpg', 'type': 'image/jpeg', 'size': 2048},
                {'file_id': 'v1', 'name': 'b.mp4', 'type': 'video/mp4', 'size': 4096},
                {'file_id': 'd1', 'name': 'c.pdf', 'type': 'application/pdf', 'size': 1024},
              ],
            },
          ]);
      await openViewer(tester, _Svc(_Srv()), req, view: half);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('viewer320_by_itself_p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer320_by_itself_v1')), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer320_by_itself_d1')), findsNothing);
      expect(find.textContaining('Get full'), findsNothing);
    });

    testWidgets('B8 regression (317): a group event is a centre line, never raw llev text', (tester) async {
      final ev = 'llev:v1:${jsonEncode({'k': 'create', 'by': 'dev-k', 'n': 'Friends', 't': ['dev-a'], 'nm': {'dev-k': 'kiran', 'dev-a': 'ayesha'}})}';
      final view = ChatAnswerView(id: 'k1', answerId: 'a', fromDevice: 'dev-k', fromName: 'kiran', of: 1, parts: 1,
          complete: true,
          messages: [
            {'id': 'e1', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-16T11:30:00', 'body': ev},
            {'id': 'm1', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-16T11:32:00', 'body': 'ggg'},
          ]);
      const r = ChatRequestRow221(
          id: 'k1', action: 'get_chat', label: 'Friends', state: 'done', chat: {'kind': 'group', 'group_id': 'g-f'});
      await openViewer(tester, _Svc(_Srv()), r, view: view);
      expect(find.byKey(const ValueKey('viewer317_sys_e1')), findsOneWidget);
      expect(find.textContaining('llev:v1:'), findsNothing);
      expect(find.text('ggg'), findsOneWidget);
    });

    test('B9 regression (317 G6): no Get full button code in the viewer', () {
      final s = File('lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart').readAsStringSync();
      expect(s, isNot(contains('getFull')));
      expect(s, isNot(contains("ValueKey('viewer221_getfile_")));
      expect(s, isNot(contains('CircularProgressIndicator(strokeWidth: 2))')));
    });
  });
}
