// Bundle 313 (A): "No answer, 9:30 PM · 1 missed" - when the line wraps,
// "1 missed" moves to line 2 as one piece (never "1" / "missed").
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/features/calls/presentation/widgets/call_history_tile.dart';

void main() {
  final call = CallRecord(
    id: 'c1',
    callerId: 'me',
    calleeId: 'ayesha',
    status: 'canceled',
    startedAt: DateTime(2026, 11, 15, 21, 30),
    durationSeconds: 0,
  );

  Future<RenderParagraph> row(WidgetTester tester, double width, int missed, {double scale = 1}) async {
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Material(
          child: CallHistoryTile(
            call: call,
            title: 'ayesha',
            status: 'No answer',
            date: '9:30 PM',
            duration: null,
            selfId: 'me',
            count: 3,
            missedInside: missed,
            onOpen: () {},
          ),
        ),
      ),
    ));
    final finder = find.textContaining('missed', findRichText: true);
    return tester.renderObject<RenderParagraph>(finder.first);
  }

  testWidgets('at every phone width "1 missed" stays on one line', (tester) async {
    addTearDown(tester.view.reset);
    var wrapped = 0;
    for (final scale in [1.0, 1.3]) {
    for (var w = 300.0; w <= 640; w += 2) {
      final p = await row(tester, w, 1, scale: scale);
      final text = p.text.toPlainText();
      expect(text, contains('1\u00A0missed'));
      expect(text, contains('PM\u00A0· '));
      final one = text.indexOf('1\u00A0missed');
      final end = one + '1\u00A0missed'.length - 1;
      final boxes = p.getBoxesForSelection(TextSelection(baseOffset: one, extentOffset: end + 1));
      // (The test font is wide: on narrow sizes the 2 lines are full before
      // "1 missed" - nothing to check there.)
      if (boxes.isEmpty) continue;
      final tops = {for (final b in boxes) b.top.round()};
      expect(tops.length, 1, reason: 'width $w x$scale: "1" and "missed" on one line');
      final first = p.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
      if (tops.single > first.top.round()) wrapped++;
    }
    }
    expect(wrapped, greaterThan(0), reason: 'some widths really wrap');
  });

  testWidgets('regression: "2 missed" text is the same words', (tester) async {
    addTearDown(tester.view.reset);
    final p = await row(tester, 411, 2);
    expect(p.text.toPlainText().replaceAll('\u00A0', ' '), 'No answer, 9:30 PM · 2 missed');
  });
}
