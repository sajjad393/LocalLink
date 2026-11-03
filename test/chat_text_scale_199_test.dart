import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/messaging/data/chat_text_scale.dart';
import 'package:locallink/features/messaging/presentation/widgets/pinch_text_zoom.dart';

/// Bundle 199 (Part 1): chat text size setting + the pinch gesture brain.
void main() {
  tearDown(() => ChatTextScale.instance.debugSet(1.0));

  group('ChatTextScale.snap', () {
    test('steps of 0.1 between 1.0 (normal, smallest) and 2.0', () {
      expect(ChatTextScale.snap(0.8), 1.0);
      expect(ChatTextScale.snap(0.95), 1.0);
      expect(ChatTextScale.snap(1.04), 1.0);
      expect(ChatTextScale.snap(1.27), closeTo(1.3, 1e-9));
      expect(ChatTextScale.snap(1.5), closeTo(1.5, 1e-9));
      expect(ChatTextScale.snap(2.3), 2.0);
      expect(ChatTextScale.snap(double.nan), 1.0);
      expect(ChatTextScale.snap(double.infinity), 1.0);
    });
  });

  group('ChatTextScale load / save', () {
    Future<double> loaded(String? raw) async {
      final s = ChatTextScale.instance;
      s.debugSet(1.0);
      await s.load(read: (_) async => raw, write: (_, __) async {});
      return s.value;
    }

    test('missing / bad / too small / too big', () async {
      expect(await loaded(null), 1.0);
      expect(await loaded('1.5'), closeTo(1.5, 1e-9));
      expect(await loaded('abc'), 1.0);
      expect(await loaded('0.9'), 1.0);
      expect(await loaded('5'), 2.0);
    });

    test('commit saves once; same value twice saves once; reset saves 1.0',
        () async {
      final saved = <String>[];
      final s = ChatTextScale.instance;
      s.debugSet(1.0, write: (k, v) async => saved.add('$k=$v'));
      s.preview(1.3);
      await s.commit(from: 'pinch');
      await s.commit(from: 'pinch');
      expect(saved, ['chat_text_scale=1.3']);
      await s.reset();
      expect(saved, ['chat_text_scale=1.3', 'chat_text_scale=1.0']);
      expect(s.value, 1.0);
    });

    test('preview notifies only on a step change and does not save', () async {
      final saved = <String>[];
      final s = ChatTextScale.instance;
      s.debugSet(1.0, write: (k, v) async => saved.add(v));
      var notes = 0;
      void count() => notes++;
      s.addListener(count);
      expect(s.preview(1.02), isFalse);
      expect(s.preview(1.12), isTrue);
      expect(s.preview(1.14), isFalse);
      expect(s.preview(0.5), isTrue); // back to 1.0
      s.removeListener(count);
      expect(notes, 2);
      expect(saved, isEmpty);
    });

    test('a failed save never throws', () async {
      final s = ChatTextScale.instance;
      s.debugSet(1.0, write: (_, __) async => throw StateError('disk'));
      s.preview(1.6);
      await s.commit(from: 'pinch');
      expect(s.value, closeTo(1.6, 1e-9));
    });
  });

  group('PinchZoomTracker', () {
    late double scale;
    late PinchZoomTracker t;
    setUp(() {
      scale = 1.0;
      t = PinchZoomTracker(current: () => scale);
    });

    /// Two fingers 100 px apart; finger 1 moves 13 px (past the slop, the
    /// measuring starts at 113 px), then finger 2 moves to make the gap
    /// [factor] times bigger.
    double? spread(double factor) {
      t.down(1, const Offset(100, 250), 0);
      t.down(2, const Offset(100, 350), 0);
      t.move(1, const Offset(100, 237), 10);
      final u = t.move(2, Offset(100, 237 + 113 * factor), 20);
      expect(u.kind, PinchKind.change);
      return u.scale;
    }

    test('spreading two fingers x1.5 from 1.0 asks for 1.5', () {
      final s = spread(1.5)!;
      expect(ChatTextScale.snap(s), closeTo(1.5, 1e-9));
    });

    test('pinching from 1.0 never goes below 1.0', () {
      final s = spread(0.5)!;
      expect(s, lessThan(1.0));
      expect(ChatTextScale.snap(s), 1.0);
    });

    test('from 1.5, pinching by x0.5 ends at 1.0', () {
      scale = 1.5;
      final s = spread(0.5)!;
      expect(ChatTextScale.snap(s), 1.0);
    });

    test('no change until a finger moved more than the slop', () {
      expect(t.down(1, const Offset(100, 250), 0).kind, PinchKind.none);
      expect(t.down(2, const Offset(100, 350), 0).kind, PinchKind.start);
      expect(t.move(1, const Offset(100, 245), 10).kind, PinchKind.none);
      expect(t.move(1, const Offset(100, 230), 20).kind, PinchKind.change);
    });

    test('a 3rd finger is ignored; lifting one finger ends the pinch', () {
      t.down(1, const Offset(100, 250), 0);
      t.down(2, const Offset(100, 350), 0);
      expect(t.down(3, const Offset(200, 300), 0).kind, PinchKind.none);
      expect(t.move(3, const Offset(260, 300), 5).kind, PinchKind.none);
      t.move(1, const Offset(100, 200), 300);
      expect(t.up(1, 400).kind, PinchKind.end);
      expect(t.pinching, isFalse);
      // the other finger alone does nothing
      expect(t.move(2, const Offset(100, 500), 410).kind, PinchKind.none);
      expect(t.up(2, 420).kind, PinchKind.none);
    });

    test('cancel ends the pinch', () {
      t.down(1, const Offset(100, 250), 0);
      t.down(2, const Offset(100, 350), 0);
      expect(t.cancel(2, 50).kind, PinchKind.end);
    });

    test('one finger never pinches', () {
      t.down(1, const Offset(100, 250), 0);
      expect(t.move(1, const Offset(100, 100), 10).kind, PinchKind.none);
      expect(t.up(1, 20).kind, PinchKind.none);
    });

    void tap(int at, {double move = 0}) {
      t.down(1, const Offset(100, 250), at);
      t.down(2, const Offset(100, 350), at);
      if (move > 0) t.move(1, Offset(100, 250 - move), at + 10);
    }

    test('two quick two-finger taps = reset', () {
      tap(0);
      expect(t.up(1, 80).kind, PinchKind.end);
      t.up(2, 85);
      tap(300);
      expect(t.up(1, 380).kind, PinchKind.reset);
    });

    test('slow second tap (over 350 ms) is not a reset', () {
      tap(0);
      t.up(1, 80);
      t.up(2, 85);
      tap(500);
      expect(t.up(1, 580).kind, PinchKind.end);
    });

    test('a long press (over 250 ms) or a moved tap is not a tap', () {
      tap(0);
      t.up(1, 400); // too long
      t.up(2, 405);
      tap(500);
      expect(t.up(1, 560).kind, PinchKind.end); // first real tap
      t.up(2, 565);
      tap(700, move: 20); // moved
      expect(t.up(1, 760).kind, PinchKind.end);
    });
  });
}
