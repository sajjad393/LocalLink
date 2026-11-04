import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/diagnostics/log_report.dart';
import 'package:locallink/core/diagnostics/log_rules.dart';
import 'package:locallink/core/diagnostics/log_share_flow.dart';
import 'package:locallink/core/diagnostics/log_share_service.dart';
import 'package:locallink/core/diagnostics/tap_burst_counter.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'support/safe_delete.dart';

String nativeLine(DateTime t, String level, String tag, String msg) {
  final ms = t.millisecondsSinceEpoch;
  final sec = ms ~/ 1000;
  final milli = (ms % 1000).toString().padLeft(3, '0');
  return '  $sec.$milli  4321  4400 $level $tag: $msg';
}

void main() {
  group('Bundle 180 tap counter', () {
    test('5 taps within 3 s fire once, then it starts again', () {
      final c = TapBurstCounter();
      final t0 = DateTime(2026, 11, 1, 12);
      for (var i = 0; i < 4; i++) {
        expect(c.tap(t0.add(Duration(milliseconds: 300 * i))), isFalse);
      }
      expect(c.tap(t0.add(const Duration(milliseconds: 1500))), isTrue);
      expect(c.tap(t0.add(const Duration(milliseconds: 1600))), isFalse);
    });

    test('slow taps never fire', () {
      final c = TapBurstCounter();
      final t0 = DateTime(2026, 11, 1, 12);
      for (var i = 0; i < 10; i++) {
        expect(c.tap(t0.add(Duration(milliseconds: 900 * i))), isFalse);
      }
    });
  });

  group('Bundle 180 file rules (1 hour, 10 MB)', () {
    test('slots are 10 minutes and names parse', () {
      expect(LogRules.slotOf(0), 0);
      expect(LogRules.slotOf(600000), 1);
      expect(LogRules.slotFromName('native-2900000.log'), 2900000);
      expect(LogRules.slotFromName('app-ui-12.log'), 12);
      expect(LogRules.slotFromName('app-bg-12.log'), 12);
      expect(LogRules.slotFromName('notes.txt'), isNull);
      expect(LogRules.slotFromName('native-12.log.bak'), isNull);
    });

    test('older than the hour goes, the hour stays', () {
      final files = [
        for (var s = 90; s <= 100; s++) (name: 'native-$s.log', slot: s, size: 10),
      ];
      final del = LogRules.filesToDelete(files, 100);
      expect(del, ['native-90.log', 'native-91.log', 'native-92.log', 'native-93.log']);
    });

    test('over 10 MB the oldest go first, never the current file', () {
      const mb = 1024 * 1024;
      final files = [
        (name: 'native-98.log', slot: 98, size: 5 * mb),
        (name: 'app-ui-99.log', slot: 99, size: 4 * mb),
        (name: 'native-100.log', slot: 100, size: 3 * mb),
      ];
      expect(LogRules.filesToDelete(files, 100), ['native-98.log']);
      final big = [(name: 'native-100.log', slot: 100, size: 50 * mb)];
      expect(LogRules.filesToDelete(big, 100), isEmpty);
    });
  });

  group('Bundle 180 line parsing and areas', () {
    final t = DateTime(2026, 11, 1, 14, 9, 2, 774);

    test('Android line: event word, level, area', () {
      final e = LogReport.parseNativeLine(
          nativeLine(t, 'E', 'NEARBY', 'WD_CONNECT_FAILED reason=busy'))!;
      expect(e.time, t);
      expect(e.level, 'E');
      expect(e.area, 'NEARBY');
      expect(e.event, 'WD_CONNECT_FAILED');
      expect(e.details, 'reason=busy');
    });

    test('Android line without an event word uses the tag', () {
      final e = LogReport.parseNativeLine(
          nativeLine(t, 'D', 'LocalLinkCall', 'speaker on, route=earpiece'))!;
      expect(e.level, 'I');
      expect(e.area, 'CALLS');
      expect(e.event, 'LocalLinkCall');
      expect(e.details, 'speaker on, route=earpiece');
    });

    test('other tags in our process are SYSTEM; F and A are errors', () {
      final e = LogReport.parseNativeLine(
          nativeLine(t, 'F', 'libc', 'Fatal signal 11 (SIGSEGV)'))!;
      expect(e.area, 'SYSTEM');
      expect(e.level, 'E');
      expect(LogReport.parseNativeLine('--------- beginning of main'), isNull);
      expect(LogReport.parseNativeLine('garbage'), isNull);
    });

    test('areas by event and tag', () {
      expect(LogReport.areaOf('', 'CALL_AUDIO_DELAY', native: false), 'CALLS');
      expect(LogReport.areaOf('', 'FILE_PAUSED_FOR_CALL', native: false), 'FILES');
      expect(LogReport.areaOf('', 'DIRECT_EVENT_SENT', native: false), 'MSGS');
      expect(LogReport.areaOf('', 'MESSAGE_SENT', native: false), 'MSGS');
      expect(LogReport.areaOf('RELAY', 'RELAY', native: true), 'NEARBY');
      expect(LogReport.areaOf('', 'WD_GROUP_READY', native: false), 'NEARBY');
      expect(LogReport.areaOf('LocalLinkNotify', 'LocalLinkNotify', native: true), 'NOTIFY');
      expect(LogReport.areaOf('LocalLinkBoot', 'LocalLinkBoot', native: true), 'BG');
      expect(LogReport.areaOf('', 'BG_ENGINE_READY', native: false), 'BG');
      expect(LogReport.areaOf('', 'settings_saved', native: false), 'APP');
      expect(LogReport.areaOf('flutter', 'flutter', native: true), 'APP');
      expect(LogReport.areaOf('ActivityThread', 'ActivityThread', native: true), 'SYSTEM');
    });

    test('app line round trip keeps full details, one line', () {
      final long = 'x' * 500;
      final raw = AppLogFile.encodeLine(
          t.millisecondsSinceEpoch, 'W', 'FILE_PAUSED_FOR_CALL', 'transfer=9f3e01c2\n$long|a');
      expect(raw.contains('\n'), isFalse);
      final e = LogReport.parseAppLine(raw)!;
      expect(e.time, t);
      expect(e.level, 'W');
      expect(e.area, 'FILES');
      expect(e.details, contains(long));
      expect(e.details, endsWith('|a'));
    });
  });

  group('Bundle 180 report', () {
    final to = DateTime(2026, 11, 1, 14, 14);
    final from = to.subtract(const Duration(hours: 1));
    LogEntry entry(DateTime t, String level, String area, String event, String details) =>
        LogEntry(time: t, level: level, area: area, event: event, details: details);

    test('header, summary and neat columns with marks', () {
      final entries = [
        entry(DateTime(2026, 11, 1, 14, 2, 10, 5), 'I', 'CALLS', 'CALL_START', 'call=c1'),
        entry(DateTime(2026, 11, 1, 14, 5, 40, 221), 'W', 'FILES', 'FILE_PAUSED_FOR_CALL', 'transfer=9f3e01c2'),
        entry(DateTime(2026, 11, 1, 14, 9, 2, 774), 'E', 'NEARBY', 'WD_CONNECT_FAILED', 'reason=busy'),
        entry(DateTime(2026, 11, 1, 14, 9, 3), 'I', 'CALLS', 'CALL_END', 'call=c1'),
      ];
      final text = LogReport.build(entries,
          from: from, to: to, phone: 'ZTE Blade A73', android: '13', version: '3.0.11+82');
      expect(text, contains('Phone     : ZTE Blade A73 (Android 13)'));
      expect(text, contains('LinkUp    : 3.0.11+82'));
      expect(text, contains('2026-11-01 13:14  ->  2026-11-01 14:14 (1 h)'));
      expect(text, contains('Summary   : 1 error, 1 warning, 1 call, 1 file, 1 Nearby event'));
      final lines = text.split('\n');
      final err = lines.firstWhere((l) => l.contains('WD_CONNECT_FAILED'));
      expect(err, '14:09:02.774  ERROR !!  NEARBY   WD_CONNECT_FAILED       reason=busy');
      final warn = lines.firstWhere((l) => l.contains('FILE_PAUSED'));
      expect(warn, '14:05:40.221  WARN  !   FILES    FILE_PAUSED_FOR_CALL    transfer=9f3e01c2');
      final info = lines.firstWhere((l) => l.contains('CALL_START'));
      expect(info.indexOf('call=c1'), err.indexOf('reason=busy'));
      expect(text.contains('-----  2026'), isFalse);
    });

    test('long details wrap under DETAILS and are never cut', () {
      final words = List.generate(40, (i) => 'word$i').join(' ');
      final text = LogReport.build(
          [entry(DateTime(2026, 11, 1, 14, 0), 'I', 'APP', 'X', words)],
          from: from, to: to, phone: 'P', android: '14', version: 'v');
      final lines = text.split('\n').where((l) => l.contains('word')).toList();
      expect(lines.length, greaterThan(1));
      for (final l in lines.skip(1)) {
        expect(l.startsWith(' ' * 57), isTrue);
      }
      final joined = lines.map((l) => l.trim()).join(' ');
      for (var i = 0; i < 40; i++) {
        expect(joined, contains('word$i'));
      }
    });

    test('a day line appears when the hour crosses midnight', () {
      final to2 = DateTime(2026, 11, 2, 0, 30);
      final text = LogReport.build([
        entry(DateTime(2026, 11, 1, 23, 50), 'I', 'APP', 'A', ''),
        entry(DateTime(2026, 11, 2, 0, 10), 'I', 'APP', 'B', ''),
      ], from: to2.subtract(const Duration(hours: 1)), to: to2, phone: 'P', android: '14', version: 'v');
      expect(text, contains('----- 2026-11-02 -----'));
      expect(text.indexOf('----- 2026-11-02 -----'), lessThan(text.indexOf('  B')));
    });

    test('phone name does not repeat the brand', () {
      expect(LogReport.phoneName('ZTE', 'ZTE Blade A73'), 'ZTE Blade A73');
      expect(LogReport.phoneName('realme', 'RMX3511'), 'Realme RMX3511');
      expect(LogReport.phoneName('zte', 'A73'), 'ZTE A73');
    });
  });

  group('Bundle 180 merge (both sides, last hour, time order)', () {
    test('lines from Android and app are merged by time, old ones dropped', () {
      final to = DateTime(2026, 11, 1, 14, 14);
      final from = to.subtract(const Duration(hours: 1));
      final native = [
        nativeLine(DateTime(2026, 11, 1, 12, 0), 'I', 'RELAY', 'RELAY too_old'),
        nativeLine(DateTime(2026, 11, 1, 14, 1), 'W', 'LocalLinkCall', 'CALL_AUDIO_DELAY call=c9 ms=900'),
        nativeLine(DateTime(2026, 11, 1, 14, 3), 'I', 'NEARBY', 'WD_GROUP_READY ok'),
      ].join('\n');
      final app = [
        AppLogFile.encodeLine(DateTime(2026, 11, 1, 14, 2).millisecondsSinceEpoch, 'I', 'MESSAGE_SENT', 'id=1'),
        AppLogFile.encodeLine(DateTime(2026, 11, 1, 14, 4).millisecondsSinceEpoch, 'E', 'uncaught_async_error', 'error=boom'),
      ].join('\n');
      final text = LogShareService.buildFromFiles(LogBuildInput(
        fromMs: from.millisecondsSinceEpoch,
        toMs: to.millisecondsSinceEpoch,
        nativeTexts: [native],
        appTexts: [app],
        phone: 'ZTE Blade A73',
        android: '13',
        version: '3.0.11+82',
      ));
      expect(text, isNot(contains('too_old')));
      final a = text.indexOf('CALL_AUDIO_DELAY');
      final b = text.indexOf('MESSAGE_SENT');
      final c = text.indexOf('WD_GROUP_READY');
      final d = text.indexOf('uncaught_async_error');
      expect(a < b && b < c && c < d, isTrue);
      expect(text, contains('Summary   : 1 error, 1 warning, 1 call, 0 files, 1 Nearby event'));
      expect(text, contains('Lines     : 4'));
    });

    test('file name is safe', () {
      expect(LogShareService.fileName('Blade A73/5G', DateTime(2026, 11, 1, 9, 5)),
          'LinkUp-logs-Blade-A73-5G-2026-11-01-0905.txt');
      expect(LogShareService.safeName('  '), 'phone');
    });
  });

  group('Bundle 180 app log file', () {
    tearDown(() => AppLogFile.instance.resetForTest());

    test('no folder yet: lines wait in memory (capped), no timer', () {
      final f = AppLogFile.instance..resetForTest();
      for (var i = 0; i < AppLogFile.earlyCap + 10; i++) {
        f.add('I', 'E$i', null);
      }
      expect(f.pendingForTest.length, AppLogFile.earlyCap);
      expect(f.pendingForTest.last, contains('|E${AppLogFile.earlyCap + 9}|'));
    });

    test('AppLogger lines go to the file with full details', () {
      final dir = Directory.systemTemp.createTempSync('l180');
      addTearDown(() => safeDeleteDir(dir));
      final f = AppLogFile.instance..resetForTest();
      AppLogger.warning('FILE_PAUSED_FOR_CALL', detail: 'transfer=${'a' * 300}');
      AppLogger.error('boom_event', error: StateError('bad'), detail: 'x=1');
      f.useDir(dir.path, engine: 'ui');
      f.flushNow();
      final files = dir.listSync().whereType<File>().toList();
      expect(files.length, 1);
      expect(files.single.uri.pathSegments.last, startsWith('app-ui-'));
      final text = files.single.readAsStringSync();
      expect(text, contains('|W|FILE_PAUSED_FOR_CALL|transfer=${'a' * 300}'));
      expect(text, contains('|E|boom_event|x=1 error=Bad state: bad'));
    });

    test('clearAll removes our files only', () async {
      final dir = Directory.systemTemp.createTempSync('l180c');
      addTearDown(() => safeDeleteDir(dir));
      File('${dir.path}/native-5.log').writeAsStringSync('a');
      File('${dir.path}/app-ui-5.log').writeAsStringSync('a');
      File('${dir.path}/keep.txt').writeAsStringSync('a');
      final f = AppLogFile.instance..resetForTest();
      f.useDir(dir.path, engine: 'ui');
      await f.clearAll();
      final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList();
      expect(names, ['keep.txt']);
    });
  });

  group('Bundle 180 share flow', () {
    Future<void> pump(WidgetTester tester, Future<void> Function(BuildContext) onTap) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(onPressed: () => onTap(ctx), child: const Text('go')),
          ),
        ),
      ));
    }

    testWidgets('shows Preparing, then shares the file', (tester) async {
      String? shared;
      await pump(tester, (ctx) => runLogShare(ctx,
          prepare: () async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return '/tmp/x.txt';
          },
          share: (p) async => shared = p));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('Preparing logs...'), findsOneWidget);
      expect(find.text('Last 1 hour'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(find.text('Preparing logs...'), findsNothing);
      expect(shared, '/tmp/x.txt');
    });

    testWidgets('Cancel skips the share', (tester) async {
      String? shared;
      await pump(tester, (ctx) => runLogShare(ctx,
          prepare: () async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return '/tmp/x.txt';
          },
          share: (p) async => shared = p));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('log_share_cancel')));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(shared, isNull);
      expect(find.text('Preparing logs...'), findsNothing);
    });

    testWidgets('failure shows a short message', (tester) async {
      await pump(tester, (ctx) => runLogShare(ctx,
          prepare: () async => throw StateError('x'), share: (p) async {}));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Could not prepare logs'), findsOneWidget);
    });
  });
}
