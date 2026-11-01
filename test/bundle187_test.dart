// Bundle 187: ZTE slow storage (4.12) - measuring only. See TODO_187.md.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/store_health.dart';

String _read(String path) => File(path).readAsStringSync();

class _Log {
  final lines = <String>[];
  void call(String event, String detail, {bool warn = false}) =>
      lines.add('${warn ? '!' : ''}$event $detail');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late _Log log;
  late List<int> asked;
  late String stallAnswer;

  StoreHealth make() => StoreHealth(
        now: () => now,
        log: log.call,
        stallOverlap: (ms) async {
          asked.add(ms);
          return stallAnswer;
        },
      );

  setUp(() {
    now = DateTime(2026, 11, 1, 12);
    log = _Log();
    asked = <int>[];
    stallAnswer = 'n';
  });

  group('A1 STORE_SUMMARY', () {
    test('nothing slow: no summary line at all', () async {
      final h = make();
      for (var i = 0; i < 50; i++) {
        await h.record('save_message', 40);
      }
      now = now.add(const Duration(minutes: 11));
      await h.record('save_message', 30);
      expect(log.lines, isEmpty);
      expect(asked, isEmpty, reason: 'fast steps never ask Android');
    });

    test('one summary per 10 min when something was slow', () async {
      final h = make();
      await h.record('outbox_read', 120);
      await h.record('call_save', 900);
      await h.record('delete_message_tx', 700, tx: true);
      await h.record('outbox_read', 80);
      now = now.add(const Duration(minutes: 9));
      await h.record('outbox_read', 10);
      expect(log.lines, isEmpty, reason: 'window not over yet');
      now = now.add(const Duration(minutes: 2));
      await h.record('outbox_read', 10);
      expect(log.lines, [
        'STORE_SUMMARY window_min=10 ops=4 slow_500=2 max_ms=900 '
            'max_op=call_save tx=1 max_tx_ms=700 max_tx=delete_message_tx '
            'during_stall=0'
      ]);
      // New window starts clean (the step that closed it counts in it).
      expect(h.summaryLine(), isNull);
    });

    test('500 ms exactly is not slow', () async {
      final h = make();
      await h.record('x', 500);
      expect(h.summaryLine(), isNull);
      await h.record('x', 501);
      expect(h.summaryLine(), contains('slow_500=1'));
    });
  });

  group('A2 during_stall', () {
    test('a slow step over 1.5 s keeps the old line, plus the stall note',
        () async {
      stallAnswer = 'y';
      final h = make();
      await h.record('call_save', 1918);
      expect(asked, [2118], reason: 'step time + 200 ms');
      expect(log.lines, ['!STORE_OP_SLOW op=call_save ms=1918 during_stall=y']);
      expect(h.summaryLine(), endsWith('during_stall=1'));
    });

    test('transactions use STORE_TX_SLOW', () async {
      final h = make();
      await h.record('clear_all_tx', 1600, tx: true);
      expect(log.lines, ['!STORE_TX_SLOW tx=clear_all_tx ms=1600 during_stall=n']);
    });

    test('500-1500 ms: counted and checked, but no single line', () async {
      stallAnswer = 'y';
      final h = make();
      await h.record('outbox_read', 800);
      expect(asked, [1000]);
      expect(log.lines, isEmpty);
      expect(h.summaryLine(), contains('during_stall=1'));
    });

    test('Android answer: unknown or missing method gives "-"', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final h = StoreHealth(now: () => now, log: log.call);
      // No handler at all (no-screen engine / tests).
      await h.record('a', 1700);
      expect(log.lines.last, endsWith('during_stall=-'));
      messenger.setMockMethodCallHandler(
          const MethodChannel('locallink/device'), (call) async {
        expect(call.method, 'stallOverlap');
        expect(call.arguments, {'window_ms': 1900});
        return 'y';
      });
      await h.record('b', 1700);
      expect(log.lines.last, endsWith('during_stall=y'));
      messenger.setMockMethodCallHandler(
          const MethodChannel('locallink/device'), (call) async => 'maybe');
      await h.record('c', 1700);
      expect(log.lines.last, endsWith('during_stall=-'));
      messenger.setMockMethodCallHandler(
          const MethodChannel('locallink/device'), null);
    });
  });

  group('wiring', () {
    test('local store steps go through StoreHealth; data saving unchanged', () {
      final src = _read('lib/core/services/local_store.dart');
      expect(src,
          contains("unawaited(StoreHealth.instance.record(name, sw.elapsedMilliseconds));"));
      expect(src, contains('.record(name, sw.elapsedMilliseconds, tx: true));'));
      expect(src, isNot(contains("AppLogger.warning('STORE_OP_SLOW'")));
      expect(src, contains('return db.transaction((txn) => body(txn)).whenComplete('));
    });
  });
}
