// Bundle 171: repeated calls share one row in the Calls list.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/features/calls/presentation/call_history_groups.dart';
import 'package:locallink/features/calls/presentation/widgets/call_history_tile.dart';

int _n = 0;
CallRecord _call(String peer, DateTime at,
        {bool out = true, String status = 'canceled', int secs = 0}) =>
    CallRecord(
      id: 'c${_n++}',
      callerId: out ? 'me' : peer,
      calleeId: out ? peer : 'me',
      status: status,
      startedAt: at,
      durationSeconds: secs,
    );

bool _missed(CallRecord c) =>
    (c.status == 'missed' || c.status == 'ringing') && c.callerId != 'me';

List<int> _sizes(List<CallRecord> h) =>
    groupCallHistory(h, selfId: 'me', isMissed: _missed)
        .map((g) => g.count)
        .toList();

void main() {
  final t = DateTime(2026, 10, 31, 18, 44);

  test('back-to-back calls with one person become one row', () {
    final h = [
      _call('sajjad', t),
      _call('sajjad', t.subtract(const Duration(minutes: 0))),
      _call('sajjad', t.subtract(const Duration(seconds: 30))),
      _call('sajjad', t.subtract(const Duration(minutes: 1))),
    ];
    final groups = groupCallHistory(h, selfId: 'me', isMissed: _missed);
    expect(groups.length, 1);
    expect(groups.first.count, 4);
    expect(groups.first.latest.id, h.first.id); // the newest is shown
  });

  test('someone else in between: still one row per person (285 C-1)', () {
    // Bundle 285 (listed change, was [2, 1, 1] "starts a new row"):
    // ONE row per person per day.
    expect(
        _sizes([
          _call('sajjad', t),
          _call('sajjad', t.subtract(const Duration(minutes: 1))),
          _call('ali', t.subtract(const Duration(minutes: 2))),
          _call('sajjad', t.subtract(const Duration(minutes: 3))),
        ]),
        [3, 1]);
  });

  test('a new day starts a new row', () {
    final y = t.subtract(const Duration(days: 1));
    expect(
        _sizes([
          _call('sajjad', t),
          _call('sajjad', t.subtract(const Duration(minutes: 5))),
          _call('sajjad', y),
        ]),
        [2, 1]);
  });

  test('missed calls are inside the person\'s one row (285 C-1)', () {
    final h = [
      _call('sajjad', t),
      _call('sajjad', t.subtract(const Duration(minutes: 1)),
          out: false, status: 'missed'),
      _call('sajjad', t.subtract(const Duration(minutes: 2)),
          out: false, status: 'missed'),
      _call('sajjad', t.subtract(const Duration(minutes: 3))),
    ];
    // Bundle 285 (listed change, was [1, 2, 1] from 255 B5): missed and
    // answered calls with the same person on one day = ONE row, 2 missed.
    expect(_sizes(h), [4]);
    final g = groupCallHistory(h, selfId: 'me', isMissed: _missed).single;
    expect(g.missed, 2);
    expect(g.latest.id, h.first.id);
  });

  test('285: the 12 Nov screenshot order = 2 rows today', () {
    // TODAY was: noshad (5), Ibrahim, noshad, Ibrahim, noshad (2),
    // Ibrahim (2), noshad (2) - 7 rows for 2 people.
    final h = <CallRecord>[];
    var m = 0;
    void add(String who, int n) {
      for (var i = 0; i < n; i++) {
        h.add(_call(who, t.subtract(Duration(minutes: m++))));
      }
    }

    add('noshad', 5);
    add('ibrahim', 1);
    add('noshad', 1);
    add('ibrahim', 1);
    add('noshad', 2);
    add('ibrahim', 2);
    add('noshad', 2);
    final g = groupCallHistory(h, selfId: 'me', isMissed: _missed);
    expect(g.map((e) => e.latest.peerId('me')).toList(), ['noshad', 'ibrahim']);
    expect(g.map((e) => e.count).toList(), [10, 4]);
    expect(g.expand((e) => e.calls).length, h.length, reason: 'no call lost');
  });

  test('285: the row position is the person\'s newest call', () {
    final g = groupCallHistory([
      _call('ali', t),
      _call('sajjad', t.subtract(const Duration(minutes: 1))),
      _call('ali', t.subtract(const Duration(minutes: 2))),
    ], selfId: 'me', isMissed: _missed);
    expect(g.map((e) => e.latest.peerId('me')).toList(), ['ali', 'sajjad']);
    expect(g.map((e) => e.missed).toList(), [0, 0]);
  });

  test('incoming and outgoing (not missed) share a row; order kept', () {
    final h = [
      _call('sajjad', t, status: 'connected', secs: 135),
      _call('sajjad', t.subtract(const Duration(minutes: 1)),
          out: false, status: 'connected', secs: 20),
      _call('ali', t.subtract(const Duration(minutes: 2))),
    ];
    final g = groupCallHistory(h, selfId: 'me', isMissed: _missed);
    expect(g.map((e) => e.count).toList(), [2, 1]);
    expect(g.expand((e) => e.calls).map((c) => c.id).toList(),
        h.map((c) => c.id).toList());
  });

  test('empty history and unknown peers', () {
    expect(_sizes(const []), isEmpty);
    expect(_sizes([_call('', t), _call('', t)]), [1, 1]);
  });

  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Material(child: child)));

  testWidgets('grouped row shows the count and opens instead of calling',
      (tester) async {
    var calls = 0;
    var opens = 0;
    await tester.pumpWidget(host(CallHistoryTile(
      call: _call('sajjad', t),
      title: 'sajjad',
      status: 'Canceled',
      date: '6:44 PM',
      duration: null,
      selfId: 'me',
      count: 4,
      onCall: () => calls++,
      onOpen: () => opens++,
    )));
    expect(find.text('sajjad'), findsOneWidget);
    expect(find.text('(4)'), findsOneWidget);
    await tester.tap(find.text('sajjad'));
    expect(opens, 1);
    expect(calls, 0);
    await tester.tap(find.byTooltip('Call back'));
    expect(calls, 1);
  });

  testWidgets('285: a row with missed calls inside is red + "· 2 missed"',
      (tester) async {
    await tester.pumpWidget(host(CallHistoryTile(
      call: _call('ibrahim', t),
      title: 'Ibrahim',
      status: 'No answer',
      date: '1:29 PM',
      duration: null,
      selfId: 'me',
      count: 4,
      missedInside: 2,
      onOpen: () {},
    )));
    final ctx = tester.element(find.text('Ibrahim'));
    final red = Theme.of(ctx).colorScheme.error;
    expect(tester.widget<Text>(find.text('Ibrahim')).style?.color, red);
    expect(tester.widget<Text>(find.text('(4)')).style?.color, red);
    expect(find.text('No answer, 1:29 PM · 2 missed', findRichText: true), findsOneWidget);
  });

  testWidgets('a single call has no count and the row calls back',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(CallHistoryTile(
      call: _call('sajjad', t),
      title: 'sajjad',
      status: 'Canceled',
      date: '6:44 PM',
      duration: null,
      selfId: 'me',
      onCall: () => calls++,
    )));
    expect(find.textContaining('('), findsNothing);
    await tester.tap(find.text('sajjad'));
    expect(calls, 1);
  });
}
