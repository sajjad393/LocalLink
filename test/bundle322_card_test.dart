// Bundle 322 W2: the files card always ends (S5 backstop, 30 min with no
// movement) and every card change leaves a log line (S7) - the two reasons
// the 17 Nov "Group 1 / 6 of 8" card was invisible for an hour.
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/chat_request_notifier_307.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';

const _mb = 1024 * 1024;

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

const _chat = ChatRequestRow221(
    id: 'req_17nov_group1',
    action: 'get_chat',
    label: 'Group 1',
    state: 'done',
    parts: 8,
    of: 8,
    fromName: 'kiran');

FileTrip317 _trip({int here = 6, int total = 8, int gone = 0, int quietMin = 0, bool stopped = false}) => FileTrip317(
      requestId: _chat.id,
      total: total,
      here: here,
      gone: gone,
      tooBig: 0,
      coming: total - here - gone,
      bytesHere: here * _mb,
      bytesTotal: (total - gone) * _mb,
      waiting: quietMin >= 2,
      stopped: stopped,
      from: 'kiran',
      quietMin: quietMin,
    );

class _Rig {
  _Rig({int here = 6}) : here = here;
  int here;
  int quietMin = 0;
  bool stopped = false;
  DateTime now = DateTime.utc(2026, 11, 17, 12, 0);
  final _Cards cards = _Cards();
  List<ChatRequestRow221> rows = const [_chat];

  late final ChatRequestNotifier307 n = ChatRequestNotifier307(
    mine: () async => rows,
    isOwner: () async => true,
    read: (k) async => null,
    write: (k, v) async {},
    cards: cards,
    checkEvery: const Duration(hours: 1),
    files317: () => {_chat.id: _trip(here: here, quietMin: quietMin, stopped: stopped)},
    clock: () => now,
  );

  String get log => AppLogFile.instance.pendingForTest.join('\n');

  Future<void> tick([Duration after = Duration.zero]) async {
    now = now.add(after);
    await n.refresh();
  }
}

void main() {
  setUp(AppLogFile.instance.resetForTest);

  group('S5: a files card cannot outlive its work', () {
    test('6/8 with nothing moving ends after 30 min (not before)', () async {
      final t = _Rig();
      await t.tick();
      expect(t.cards.shows, hasLength(1));
      expect(t.cards.shows.last['title'], 'Group 1 \u00b7 6/8');
      // 29 min of nothing: the card is still there, nothing is posted twice.
      await t.tick(const Duration(minutes: 29));
      expect(t.cards.shows, hasLength(1));
      expect(t.cards.cancels, isEmpty);
      // 31 min: ended with the reason in the log and on the card.
      await t.tick(const Duration(minutes: 2));
      expect(t.cards.cancels, hasLength(1));
      expect(t.cards.cancels.last['request_id'], _chat.id);
      expect(t.log, contains('CHAT_REQ_CARD_307|show id=group1 step=files'));
      expect(t.log, contains('CHAT_REQ_CARD_307|cancel reason=stuck30 id=group1 here=6/8 missing=2'));
    });

    test('a card that keeps moving is never ended', () async {
      final t = _Rig();
      await t.tick();
      for (var i = 0; i < 5; i++) {
        t.here = 6 + (i.isEven ? 1 : 0);
        await t.tick(const Duration(minutes: 25));
      }
      expect(t.cards.cancels, isEmpty, reason: 'it moved every 25 min');
    });

    test('after the backstop the card stays away until the numbers move again', () async {
      final t = _Rig();
      await t.tick();
      await t.tick(const Duration(minutes: 31));
      expect(t.cards.cancels, hasLength(1));
      final shown = t.cards.shows.length;
      // Same numbers: it does not come back on every tick.
      await t.tick();
      await t.tick();
      expect(t.cards.shows, hasLength(shown));
      // A file arrives: the card may come back (the work is not lost).
      t.here = 7;
      await t.tick(const Duration(minutes: 2));
      expect(t.cards.shows.length, shown + 1);
      expect(t.cards.shows.last['title'], 'Group 1 \u00b7 7/8');
    });

    test('a stopped queue is not a stuck card (Stop files ends it as in 321)', () async {
      final t = _Rig();
      await t.tick();
      t.stopped = true;
      await t.tick(const Duration(minutes: 31));
      expect(t.cards.cancels, isEmpty);
      expect(t.cards.shows.last['step'], isNot('files'));
    });
  });

  group('S7: every card change leaves a line', () {
    test('show at 6/8, then files_done at 8/8; the card still waits to be opened', () async {
      final t = _Rig();
      await t.tick();
      expect(t.log, contains('CHAT_REQ_CARD_307|show id=group1 step=files'));
      t.here = 8;
      await t.tick(const Duration(minutes: 2));
      expect(t.log, contains('CHAT_REQ_CARD_307|show id=group1 step=files_done'));
      // 317 G7 is unchanged: all here + not opened = the card stays.
      expect(t.cards.cancels, isEmpty);
    });

    test('opened by the user: reason=opened', () async {
      final t = _Rig(here: 8);
      await t.tick();
      t.rows = const [
        ChatRequestRow221(id: 'req_17nov_group1', action: 'get_chat', label: 'Group 1', state: 'done', parts: 8, of: 8,
            fromName: 'kiran', opened: true),
      ];
      await t.tick();
      expect(t.log, contains('drop id=group1 reason=opened'));
    });

    test('the log never carries a name or a whole id', () async {
      final t = _Rig();
      await t.tick();
      t.here = 8;
      await t.tick(const Duration(minutes: 2));
      final lines = t.log.split('\n').where((l) => l.contains('CHAT_REQ_CARD_307'));
      expect(lines, isNotEmpty);
      for (final l in lines) {
        expect(l, isNot(contains('Group 1')));
        expect(l, isNot(contains('kiran')));
        expect(l, isNot(contains('req_17nov_group1')));
      }
    });

    test('a stuck card writes at most one line a minute (no log flood)', () async {
      final t = _Rig();
      await t.tick();
      for (var i = 0; i < 10; i++) {
        await t.tick(const Duration(minutes: 1));
      }
      final lines = t.log.split('\n').where((l) => l.contains('CHAT_REQ_CARD_307')).length;
      expect(lines, lessThanOrEqualTo(2), reason: 'one show + at most one end in 10 min');
    });
  });

  group('S6: the swipe threshold is a named constant', () {
    test('10 min quiet is enough on the phone card args', () {
      final now = DateTime.utc(2026, 11, 17, 12);
      final a = ChatRequestNotifier307.filesArgs317(_chat, RequestStep307.of(_chat), _trip(quietMin: 11), now);
      expect(a['files_swipe'], isTrue);
      expect(a['step'], 'files_wait');
      final b = ChatRequestNotifier307.filesArgs317(_chat, RequestStep307.of(_chat), _trip(quietMin: 3), now);
      expect(b['files_swipe'], isFalse);
    });
  });
}
