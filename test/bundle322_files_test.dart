// Bundle 322 W1: the files card can never stay forever (S1 stuck "next",
// S2 ask failure releases the window, S3 stopped -> gone, S6 swipe after
// 10 min). Every test here is the stuck "Group 1 6/8" card from 17 Nov.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';

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

  /// Rows the phone sees. The first one is this phone's own get_chat.
  List<ChatRequestRow221> rows = [const ChatRequestRow221(id: 'r1', action: 'get_chat', state: 'done', parts: 4, of: 4)];

  /// File ids the ask() call refuses (a phone that cannot make the card).
  final Set<String> failAsk = {};
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
      if (failAsk.contains(fileId)) throw StateError('no card for $fileId');
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

  String get log => AppLogFile.instance.pendingForTest.join('\n');

  FileTrip317 get trip => FileQueue317.trips.value['r1']!;
}

void main() {
  setUp(AppLogFile.instance.resetForTest);
  tearDown(() => FileQueue317.trips.value = const {});

  group('S1: a file with a card on the server is "coming", never "next"', () {
    test('an asked row the queue does not remember still times out', () async {
      // Before 322 the file showed `next` while a Get file row existed on
      // the server: the 321 clock only watches `coming`, so nothing ever
      // timed that file out - the 17 Nov "Group 1 6/8" card.
      final t = _Q(_answer(['a', 'b', 'c', 'd']));
      // Two rows that the queue did not make in this run (lost card).
      t.rows = [
        t.rows.first,
        _file('aa_a_1', 'a', state: 'pending'),
        _file('aa_b_2', 'b', state: 'pending'),
      ];
      await t.q.tick();
      expect(t.q.viewsOf('r1')['a']!.state, FileState317.coming, reason: 'was `next` in 321');
      expect(t.q.viewsOf('r1')['b']!.state, FileState317.coming);
      expect(t.trip.coming, 2);
      expect(t.asked, isEmpty, reason: 'the window is full: c and d wait, as in 317');
      // Nothing moves: the 321 timer now runs on them, re-asks once each and
      // gives up - so the card always ends instead of sitting at 6/8.
      var ticks = 0;
      while (t.trip.active && ticks++ < 12) {
        t.now = t.now.add(const Duration(minutes: 11));
        await t.q.tick();
      }
      expect(t.trip.active, isFalse, reason: 'the card ended after $ticks idle ticks');
      expect(ticks, lessThanOrEqualTo(12), reason: 'bounded work, no endless re-ask');
      expect(t.log, contains('FILE_QUEUE_GONE'));
      expect(t.trip.gone, 4);
    });

    test('the 321 shape is unchanged: asked files keep their window and order', () async {
      final t = _Q(_answer(['a', 'b', 'c']));
      await t.q.tick();
      expect(t.asked, ['a', 'b']);
      expect(t.trip.coming, 2);
      // a comes in full, so c is asked next (regression: 317 window).
      t.rows = [t.rows.first, _file('aa_a_1', 'a', state: 'done', parts: 4, of: 4)];
      await t.q.tick();
      expect(t.q.viewsOf('r1')['a']!.state, FileState317.here);
      expect(t.asked, ['a', 'b', 'c']);
      expect(t.trip.coming, 2);
    });

    test('a file that moves is never given up', () async {
      final t = _Q(_answer(['a']));
      await t.q.tick();
      for (var i = 1; i <= 6; i++) {
        t.now = t.now.add(const Duration(minutes: 5));
        t.rows = [t.rows.first, _file('aa_a_1', 'a', state: 'done', parts: i, of: 9)];
        await t.q.tick();
      }
      expect(t.asked, ['a']);
      expect(t.log, isNot(contains('FILE_QUEUE_GONE')));
    });
  });

  group('S2: a failed ask never fills the window', () {
    test('after 5 failures the file is gone, the next one is tried', () async {
      final t = _Q(_answer(['a', 'b']));
      t.failAsk.add('a');
      final waits = <Duration>[];
      for (var i = 0; i < 6; i++) {
        await t.q.tick();
        waits.add(FileQueue317.askWait322(i));
        t.now = t.now.add(FileQueue317.askWait322(i) + const Duration(seconds: 1));
      }
      // a was tried 5 times, then dropped; b could be asked meanwhile.
      expect(t.log, contains('FILE_QUEUE_GONE|why=ask_failed tries=5'));
      expect(t.asked, contains('b'), reason: 'one bad file does not block the others');
      expect(t.q.viewsOf('r1')['a']!.state, FileState317.gone);
      expect(waits.take(4), [
        const Duration(minutes: 1),
        const Duration(minutes: 2),
        const Duration(minutes: 5),
        const Duration(minutes: 10),
      ]);
    });

    test('regression: maxAskTries322 = 0 goes back to the 321 ask-until-it-works', () {
      expect(FileQueue317.maxAskTries322, 5);
      expect(FileQueue317.askBackoff322.first, const Duration(minutes: 1));
      expect(FileQueue317.askBackoff322.last, const Duration(minutes: 10));
    });
  });

  group('S3: a file stopped on the other phone counts as gone', () {
    test('stopped file -> gone, and the card can finish', () async {
      final t = _Q(_answer(['a', 'b']));
      await t.q.tick();
      // The other phone stopped a: the row is closed, never answered.
      t.rows = [
        t.rows.first,
        const ChatRequestRow221(
            id: 'aa_a_1', action: 'get_file', state: 'done', parent: 'r1', fileId: 'a', closed: true,
            madeAt: '2026-11-16T12:00:00Z'),
        _file('aa_b_2', 'b', state: 'done', parts: 4, of: 4),
      ];
      await t.q.tick();
      expect(t.q.viewsOf('r1')['a']!.state, FileState317.gone);
      expect(t.log, contains('FILE_QUEUE_GONE|why=stopped'));
      expect(t.trip.gone, 1);
      expect(t.trip.here, 1);
      expect(t.trip.active, isFalse, reason: 'the card is Ready, not stuck at 1/2');
      final plan = await t.q.planForTest('r1');
      expect((plan!['dead321'] as Map).keys, ['a']);
    });
  });

  group('S6: the files card can be swiped', () {
    FileTrip317 trip({int quietMin = 11, int here = 6, bool waiting = true, bool stopped = false}) => FileTrip317(
          requestId: 'r1', total: 8, here: here, gone: 0, tooBig: 0, coming: 1,
          bytesHere: here * _mb, bytesTotal: 8 * _mb, waiting: waiting, stopped: stopped, quietMin: quietMin);

    test('10 min quiet is enough now (321 needed 30)', () {
      expect(FileTrip317.swipeAfter322, const Duration(minutes: 10));
      expect(trip(quietMin: 10).waitingLong, isTrue);
      expect(trip(quietMin: 9).waitingLong, isFalse);
    });

    test('a card that is still moving cannot be swiped by accident', () {
      expect(trip(quietMin: 0).waitingLong, isFalse);
      expect(trip(quietMin: 40, waiting: false).waitingLong, isFalse);
    });
  });
}
