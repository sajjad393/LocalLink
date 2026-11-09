import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';

/// Bundle 224 (F, G): log lines only.
/// F - 2026-11-07: 2 texts to a phone that was away were logged on every
///     flush for 19 h (MESSAGE_ROUTE_UNAVAILABLE 1950 / hour).
/// G - 2202 `mesh_dropped` lines per hour with no reason.
void main() {
  final src = File(
          'lib/features/messaging/data/services/reliable_messaging_service.dart')
      .readAsStringSync();

  group('224-F waiting messages are logged once per spell', () {
    test('10 flushes with no route -> 1 line', () {
      final q = QuietWaitLog224();
      final t0 = DateTime(2026, 11, 7, 12);
      var lines = 0;
      for (var i = 0; i < 10; i++) {
        if (q.noRoute('m1', 'android-c7deb57c9127380d',
            t0.add(Duration(seconds: 5 * i)))) {
          lines++;
        }
      }
      expect(lines, 1);
      expect(q.isWaiting('m1'), isTrue);
    });

    test('the route comes back -> the spell ends, next outage logs again',
        () {
      final q = QuietWaitLog224();
      final t0 = DateTime(2026, 11, 7, 12);
      expect(q.noRoute('m1', 'a', t0), isTrue);
      q.routeFound('m1');
      expect(q.isWaiting('m1'), isFalse);
      expect(q.noRoute('m1', 'a', t0), isTrue);
    });

    test('back-off skip: once per attempt number', () {
      final q = QuietWaitLog224();
      expect(q.backoffFirst('m2', '278'), isTrue);
      expect(q.backoffFirst('m2', '278'), isFalse);
      expect(q.backoffFirst('m2', '278'), isFalse);
      expect(q.backoffFirst('m2', '279'), isTrue);
    });

    test('MESSAGE_WAITING summary at most every 10 min', () {
      final q = QuietWaitLog224();
      final t0 = DateTime(2026, 11, 7, 12);
      q.noRoute('m1', 'android-c7deb57c9127380d', t0);
      q.noRoute('m2', 'android-c7deb57c9127380d', t0);
      expect(q.summary(t0), isNull, reason: 'the per-message line came first');
      expect(q.summary(t0.add(const Duration(minutes: 9))), isNull);
      final line = q.summary(t0.add(const Duration(minutes: 10)));
      expect(line, 'n=2 oldest_min=10 to=9127380d');
      expect(q.summary(t0.add(const Duration(minutes: 15))), isNull);
    });

    test('sent / removed messages are forgotten (no growth)', () {
      final q = QuietWaitLog224();
      final t0 = DateTime(2026, 11, 7, 12);
      q.noRoute('m1', 'a', t0);
      q.backoffFirst('m3', '4');
      q.keepOnly({'other'});
      expect(q.isWaiting('m1'), isFalse);
      expect(q.backoffFirst('m3', '4'), isTrue);
      expect(q.summary(t0.add(const Duration(hours: 1))), isNull);
    });

    test('the route is still checked on every flush (behaviour unchanged)',
        () {
      // The quiet check only wraps the LOG lines: the `continue` and the
      // route lookup before it are the same as in 223.
      final start = src.indexOf("if (!socket.isConnected) {\n          // Bundle 224 (F1)");
      expect(start, greaterThan(0));
      final block = src.substring(start, start + 900);
      expect(block, contains('_quiet224.noRoute(id, recipientId, DateTime.now())'));
      expect(block, contains('continue;'));
      expect(src, contains('final localRoute = await _localRouteFor(recipientId);'));
      expect(src, contains('!store.internetOnly && localRoute?.isAvailable == true;'));
    });

    test('a found route ends the spell on both paths', () {
      expect('_quiet224.routeFound(id);'.allMatches(src).length, 2);
    });

    test('normal route choices are INFO now, not WARN', () {
      expect(src, isNot(contains("AppLogger.warning(\n            'MESSAGE_ROUTE_SELECTED_DIRECT'")));
      expect(src, isNot(contains("AppLogger.warning(\n          'MESSAGE_ROUTE_SELECTED_SERVER'")));
      expect(src, contains("AppLogger.info(\n            'MESSAGE_ROUTE_SELECTED_DIRECT'"));
    });
  });

  group('224-G1 dropped relay messages show their reason', () {
    test('reason counts, most first', () {
      expect(dropReasonText224({}), '');
      expect(
          dropReasonText224(
              {'ttl_expired': 3, 'loop_detected': 10, 'relay_plain_refused': 1}),
          ' drop=loop_detected:10,ttl_expired:3,relay_plain_refused:1');
    });

    test('mesh_dropped goes into the 10 s summary with its reason', () {
      final hot = src.substring(src.indexOf('static const Set<String> _hotDirectEventTypes'));
      expect(hot.substring(0, 900), contains("'mesh_dropped',"));
      expect(src, contains("_recordHotDirectEvent(eventType, reason: event['reason']?.toString());"));
      expect(src, contains('dropReasonText224(_dropReasonCounts)'));
    });

    test('the event still reaches the rest of the app (only the log changed)',
        () {
      final handler = src.substring(src.indexOf('Future<void> _handleDirectEvent('));
      final hotIf = handler.indexOf('if (_hotDirectEventTypes.contains(eventType)) {');
      final afterLog = handler.indexOf("if (eventType == 'network_changed')");
      expect(hotIf, greaterThan(0));
      expect(afterLog, greaterThan(hotIf),
          reason: 'processing continues after the log choice');
    });
  });
}
