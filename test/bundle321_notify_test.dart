// Bundle 321 Phase 6b N1-N4: the phone card, USER PICK B "minimal" - one
// line (chat + "3/7" / "waiting" / check), no text line, no buttons, the
// picture of the file coming and one bar piece per file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/chat_request_notifier_307.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';

const _mb = 1024 * 1024;

class _Cards implements ChatRequestCards307 {
  final List<Map<String, Object?>> shows = [];
  @override
  Future<void> show(Map<String, Object?> args) async => shows.add(args);
  @override
  Future<void> cancel(Map<String, Object?> args) async {}
  @override
  Future<void> cancelAll() async {}
}

ChatRequestRow221 _file(String id, String fileId, {String state = 'done', int parts = 0, int of = 0}) =>
    ChatRequestRow221(id: id, action: 'get_file', state: state, parts: parts, of: of, parent: 'r1', fileId: fileId,
        madeAt: '2026-11-16T12:00:00Z');

ChatAnswerView _answer() => ChatAnswerView(
      id: 'r1',
      answerId: 'an_1',
      fromDevice: 'dev-a',
      fromName: 'ayesha',
      of: 4,
      parts: 4,
      complete: true,
      messages: [
        {
          'id': 'm1',
          'sender': 'dev-a',
          'created_at': '2026-11-14T10:00:00',
          'body': '',
          'attachments': [
            {'file_id': 'p1', 'name': 'p1.jpg', 'type': 'image/jpeg', 'size': _mb, 'thumb': 'UDE='},
            {'file_id': 'v1', 'name': 'v1.mp4', 'type': 'video/mp4', 'size': 2 * _mb, 'thumb': 'VjE='},
            {'file_id': 'a1', 'name': 'a1.m4a', 'type': 'audio/mp4', 'size': 30000},
          ],
        },
      ],
    );

class _Q {
  final Map<String, String> saved = {};
  int opens = 0;
  List<ChatRequestRow221> rows = [
    const ChatRequestRow221(id: 'r1', action: 'get_chat', label: 'ayesha & kiran', state: 'done', parts: 4, of: 4),
  ];

  FileQueue317 make() => FileQueue317(
        rows: () async => rows,
        mineIds: () async => {'r1'},
        open: (r) async {
          opens++;
          return _answer();
        },
        ask: (parent, {required fileId, messageId = '', name = ''}) async => 'aa_$fileId',
        close: (r) async {},
        isOwner: () async => true,
        read: (k) async => saved[k],
        write: (k, v) async => saved[k] = v,
        clock: () => DateTime.utc(2026, 11, 16, 12),
      );
}

const _chat = ChatRequestRow221(id: 'r1', action: 'get_chat', label: 'ayesha & kiran', state: 'done', parts: 40, of: 40,
    fromName: 'ayesha');

FileTrip317 _trip({int here = 3, int total = 7, int gone = 0, bool waiting = false, bool stopped = false}) => FileTrip317(
      requestId: 'r1',
      total: total,
      here: here,
      gone: gone,
      tooBig: 0,
      coming: total - here - gone,
      bytesHere: here * _mb,
      bytesTotal: (total - gone) * _mb,
      waiting: waiting,
      stopped: stopped,
      from: 'ayesha',
      kind321: 'photo',
      thumb321: 'UDE=',
      pieces321: '100,100,100,40,0,0,0',
    );

void main() {
  tearDown(() => FileQueue317.trips.value = const {});

  group('N1/N2 - the file the card shows', () {
    test('kind, picture and one fill per file (here first, then coming, then next)', () async {
      final t = _Q();
      final q = t.make();
      await q.tick();
      t.rows = [t.rows.first, _file('aa_p1', 'p1', parts: 5, of: 5), _file('aa_v1', 'v1', parts: 3, of: 9)];
      await q.tick();
      final trip = FileQueue317.trips.value['r1']!;
      expect(trip.here, 1);
      expect(trip.kind321, 'video');
      expect(trip.thumb321, 'VjE=');
      expect(trip.pieces321, '100,33,0');
      expect(trip.toArgs()['files_pieces'], '100,33,0');
      expect(trip.toArgs()['files_kind'], 'video');
      expect(t.opens, 1, reason: 'the answer is read once (the plan)');
    });

    test('after a restart the pictures are read once more; all here = the newest picture', () async {
      final t = _Q();
      await t.make().tick();
      t.rows = [t.rows.first, _file('aa_p1', 'p1', parts: 5, of: 5), _file('aa_v1', 'v1', parts: 3, of: 9)];
      final again = t.make();
      await again.tick();
      expect(t.opens, 2);
      expect(FileQueue317.trips.value['r1']!.thumb321, 'VjE=');
      await again.tick();
      expect(t.opens, 2, reason: 'not again in the same run');
      t.rows = [t.rows.first, _file('aa_p1', 'p1', parts: 5, of: 5), _file('aa_v1', 'v1', parts: 9, of: 9),
        _file('aa_a1', 'a1', parts: 1, of: 1)];
      await again.tick();
      final done = FileQueue317.trips.value['r1']!;
      expect(done.done, isTrue);
      expect(done.kind321, 'photo');
      expect(done.thumb321, 'UDE=');
      expect(done.pieces321, '100,100,100');
    });

    test('kindOf321', () {
      expect(FileTrip317.kindOf321('image/png'), 'photo');
      expect(FileTrip317.kindOf321('VIDEO/mp4'), 'video');
      expect(FileTrip317.kindOf321('audio/mp4'), 'voice');
      expect(FileTrip317.kindOf321('application/pdf'), 'file');
      expect(FileTrip317.kindOf321(''), 'file');
    });
  });

  group('N1 - one line, no text, no buttons', () {
    final ready = RequestStep307.of(_chat);
    final now = DateTime.utc(2026, 11, 16, 12);

    test('files: "chat · 3/7", "chat · waiting", "chat ✓"; 2 gone = the count, not the check', () {
      final a = ChatRequestNotifier307.filesArgs317(_chat, ready, _trip(), now);
      expect(a['title'], 'ayesha & kiran \u00b7 3/7');
      for (final k in ['text', 'sub_text', 'open_label', 'stop_label']) {
        expect(a.containsKey(k), isFalse, reason: k);
      }
      expect(a['files_thumb'], 'UDE=');
      expect(a['files_kind'], 'photo');
      expect(a['files_pieces'], '100,100,100,40,0,0,0');
      expect(a['from_name'], 'ayesha');
      expect(a['short'], '3/7');
      expect(ChatRequestNotifier307.filesArgs317(_chat, ready, _trip(waiting: true), now)['title'],
          'ayesha & kiran \u00b7 waiting');
      expect(ChatRequestNotifier307.filesArgs317(_chat, ready, _trip(here: 7), now)['title'], 'ayesha & kiran \u2713');
      expect(ChatRequestNotifier307.filesArgs317(_chat, ready, _trip(here: 5, gone: 2), now)['title'],
          'ayesha & kiran \u00b7 5/7');
    });

    test('request steps: waiting / 12/40 / check / No messages; stopped files = the request line', () {
      String title(ChatRequestRow221 r, [FileTrip317? f]) => ChatRequestNotifier307.cardTitle321(r, RequestStep307.of(r), f);
      const sent = ChatRequestRow221(id: 'r', action: 'get_chat', label: 'sumaira', phones: 2);
      expect(title(sent), 'sumaira \u00b7 waiting');
      const parts = ChatRequestRow221(id: 'r', action: 'get_chat', label: 'sumaira', state: 'done', phones: 2, reached: 1,
          parts: 12, of: 40);
      expect(title(parts), 'sumaira \u00b7 12/40');
      expect(title(_chat), 'ayesha & kiran \u2713');
      expect(title(_chat, _trip(stopped: true)), 'ayesha & kiran \u2713');
      const nothing = ChatRequestRow221(id: 'r', action: 'get_chat', label: '', state: 'done', empty: true);
      expect(title(nothing), 'Chat \u00b7 No messages');
    });

    test('the group: "3 chats" + each card line', () async {
      final cards = _Cards();
      final n = ChatRequestNotifier307(
        mine: () async => const [
          ChatRequestRow221(id: 'a', action: 'get_chat', label: 'ayesha & kiran', phones: 2, madeAt: '2026-11-16T11:59:00Z'),
          ChatRequestRow221(id: 'b', action: 'get_chat', label: 'sumaira', phones: 1, madeAt: '2026-11-16T11:59:00Z'),
          ChatRequestRow221(id: 'c', action: 'get_chat', label: 'Pricesess', state: 'done', parts: 4, of: 4,
              madeAt: '2026-11-16T11:59:00Z'),
        ],
        isOwner: () async => true,
        read: (k) async => null,
        write: (k, v) async {},
        cards: cards,
        clock: () => DateTime.utc(2026, 11, 16, 12),
        checkEvery: const Duration(hours: 1),
      );
      await n.refresh();
      final last = cards.shows.last;
      expect(last['summary_title'], '3 chats');
      expect(last['summary_lines'], ['ayesha & kiran \u00b7 waiting', 'sumaira \u00b7 waiting', 'Pricesess \u2713']);
      for (final a in cards.shows) {
        expect(a.containsKey('text'), isFalse);
        expect(a.containsKey('open_label'), isFalse);
      }
      // Only Ready buzzes (unchanged).
      expect(cards.shows.where((a) => a['buzz'] == true).map((a) => a['request_id']), ['c']);
    });
  });

  test('Urdu has the two new words; the Android 15 card + new icons are in the app', () {
    final ur = jsonDecode(File('lib/l10n/app_ur.arb').readAsStringSync()) as Map<String, dynamic>;
    expect(ur['waitingShort321'], isNotEmpty);
    expect(ur['nChats321'], contains('{n}'));
    expect(File('android/app/src/main/res/layout/notif321_card.xml').existsSync(), isTrue);
    expect(File('android/app/src/main/kotlin/com/sajjad/locallink/ChatCard321.kt').existsSync(), isTrue);
  });
}
