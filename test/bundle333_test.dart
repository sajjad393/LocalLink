// Bundle 333: the evidence record survives a restart, and it says so.
//
// Before this, Evidence329 wrote into a static map: the 329 screen worked, the
// tests passed, and on a real phone every line was lost when the app closed.
// The log had no EVIDENCE_329 line at all in an hour, which is how we found it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/evidence_329.dart';

const _store = 'lib/core/services/local_store.dart';
const _deps = 'lib/app/app_dependencies.dart';
const _evidence = 'lib/features/admin/data/evidence_329.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(Evidence329.resetForTest);

  group('333 · it is stored, not remembered', () {
    test('333-1 the app binds it to the phone storage at start', () {
      final deps = File(_deps).readAsStringSync();
      expect(deps, contains('Evidence329.bind('));
      expect(deps, contains('store.readEvidence329()'));
      expect(deps, contains('store.writeEvidence329(value)'));
    });

    test('333-2 the store keeps it in the settings table (survives a restart)', () {
      final s = File(_store).readAsStringSync();
      expect(s, contains("_evidence329Key = 'evidence_329_lines'"));
      expect(s, contains('Future<void> writeEvidence329(String lines)'));
      expect(s, contains('Future<String?> readEvidence329()'));
      expect(s, contains("_db.query('settings'"), reason: 'same place as every other setting');
    });

    test('333-3 what is written today is read tomorrow (restart simulated)', () async {
      final disk = <String, String>{};
      final today = Evidence329(
          read: (k) async => disk[k], write: (k, v) async => disk[k] = v,
          clock: () => DateTime.utc(2026, 11, 20, 1));
      await today.add('ask', 'Get chat · Ali');
      await today.add('answer', 'sent 53 KB');

      // a brand-new object over the same storage = the app opened again
      final tomorrow = Evidence329(read: (k) async => disk[k], write: (k, v) async => disk[k] = v);
      expect(await tomorrow.count(), 2);
      final text = await tomorrow.export();
      expect(text, contains('Get chat · Ali'));
      expect(Evidence329.verify(text).ok, isTrue);
    });
  });

  group('333 · it is visible', () {
    test('333-4 every recorded line leaves a log line', () {
      final s = File(_evidence).readAsStringSync();
      expect(s, contains("AppLogger.info('EVIDENCE_329'"));
      expect(s, contains('EVIDENCE_329_FAIL'), reason: 'a write failure is never silent');
    });

    test('333-5 a failing store does not break the ask', () async {
      final e = Evidence329(
        read: (k) async => null,
        write: (k, v) async => throw const FileSystemException('disk full'),
      );
      // returns a count, never throws: an ask must not die because a log did
      expect(await e.add('ask', 'Get chat · Ali'), 1);
    });

    test('333-6 the pins still live in one place, and this build follows them', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
