// Bundle 334: the log must tell the truth about the app.
//
// A real hour read "45 errors" at the top while every one of them was Android
// or vendor noise (mali_gralloc, MediaCodec) and the app itself was clean; and
// 7,700 of 13,163 lines were six message-loop events, 987 of them saying the
// outbox was empty.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/diagnostics/log_report.dart';

const _report = 'lib/core/diagnostics/log_report.dart';
const _msgs = 'lib/features/messaging/data/services/reliable_messaging_service.dart';

LogEntry e(String level, String area, String event, [String details = '']) =>
    LogEntry(time: DateTime(2026, 11, 20, 1), level: level, area: area, event: event, details: details);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('334 · app errors are told apart from the phone shouting', () {
    test('334-1 vendor noise is not called an app error', () {
      final s = LogReport.summary([
        e('E', 'SYSTEM', 'mali_gralloc'),
        e('E', 'SYSTEM', 'MediaCodec'),
        e('W', 'APP', 'SERVER_CLOCK_WRONG'),
      ]);
      expect(s.errors, 2, reason: 'the raw count stays available');
      expect(s.appErrors, 0);
      expect(s.systemErrors, 2);
      expect(s.warnings, 1);
    });

    test('334-2 a real app error still counts, and loudly', () {
      final s = LogReport.summary([
        e('E', 'APP', 'IDENTITY_KEY_PUT'),
        e('E', 'SYSTEM', 'mali_gralloc'),
      ]);
      expect(s.appErrors, 1);
      expect(s.systemErrors, 1);
    });

    test('334-3 the header says both, and names the loudest events', () {
      final text = LogReport.build(
        [
          for (var i = 0; i < 5; i++) e('I', 'MSGS', 'DIRECT_EVENT_RECEIVED'),
          e('E', 'SYSTEM', 'mali_gralloc'),
          e('W', 'APP', 'CONTACTS_SYNC_FAILED'),
        ],
        from: DateTime(2026, 11, 20, 0),
        to: DateTime(2026, 11, 20, 1),
        phone: 'Test',
        android: '14',
        version: 'x',
      );
      expect(text, contains('0 app errors'));
      expect(text, contains('1 system error'));
      expect(text, contains('Loudest   : MSGS/DIRECT_EVENT_RECEIVED 5'));
      expect(text, contains('CONTACTS_SYNC_FAILED'));
    });

    test('334-4 an empty log has no loudest line', () {
      final s = LogReport.summary([]);
      expect(s.loudest, '');
      expect(s.appErrors, 0);
    });
  });

  group('334 · the noise is turned down', () {
    test('334-5 an empty outbox says nothing', () {
      final src = File(_msgs).readAsStringSync();
      final i = src.indexOf('MESSAGE_OUTBOX_READ');
      expect(src.substring(i - 400, i), contains('items.isNotEmpty'));
    });

    test('334-6 peer discovery is a summary, not one line a second', () {
      final src = File(_msgs).readAsStringSync();
      final set = src.substring(src.indexOf('_hotDirectEventTypes'), src.indexOf('_hotDirectEventCounts'));
      expect(set, contains("'peer_discovered'"));
      expect(set, contains("'peer_lost'"));
      expect(set, contains('Bundle 334'));
    });

    test('334-7 the split lives in one place, and the pins follow the constants', () {
      expect(File(_report).readAsStringSync(), contains('appErrors: errors - systemErrors'));
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
