// Bundle 329: export evidence.
//
// A record the phone writes for itself: what it asked, what it answered, what
// the owner said on each consent card - each line carrying the stamp of the
// line before it, so an edit shows. Nothing is uploaded; the file leaves the
// phone only when the owner copies it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/evidence_329.dart';
import 'package:locallink/l10n/l10n.dart';

const _src = 'lib/features/admin/data/evidence_329.dart';
const _screen = 'lib/features/admin/presentation/screens/evidence_329_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> disk;
  Evidence329 ev() => Evidence329(
        read: (k) async => disk[k],
        write: (k, v) async => disk[k] = v,
        clock: () => DateTime.utc(2026, 11, 19, 6, 30),
      );

  setUp(() {
    disk = {};
    Evidence329.resetForTest();
  });

  group('329 · the record', () {
    test('329-1 nothing recorded yet is honest about it', () async {
      final e = ev();
      expect(await e.count(), 0);
      expect(await e.export(), '');
      expect(await e.last(), isNull);
      expect(Evidence329.fileWords(0), 'Nothing recorded yet');
    });

    test('329-2 each line is added, numbered and chained', () async {
      final e = ev();
      await e.add('ask', 'Get chat · Ali');
      await e.add('answer', 'sent 61 MB');
      await e.add('consent', 'owner said send');
      expect(await e.count(), 3);
      final text = await e.export();
      expect(text, contains('Get chat'));
      expect(text, contains('"n":1'));
      expect(text, contains('"n":3'));
      final last = await e.last();
      expect(last!.n, 3);
      expect(last.prev, isNotEmpty, reason: 'line 3 carries line 2');
    });

    test('329-3 the file it writes checks out', () async {
      final e = ev();
      await e.add('ask', 'Get chat · Ali');
      await e.add('answer', 'sent');
      final v = Evidence329.verify(await e.export());
      expect(v.ok, isTrue);
      expect(v.lines, 2);
      expect(v.firstBad, 0);
    });

    test('329-4 change one word and it says which line broke', () async {
      final e = ev();
      await e.add('ask', 'Get chat · Ali');
      await e.add('answer', 'sent 61 MB');
      final good = await e.export();
      final bad = good.replaceFirst('sent 61 MB', 'sent 1 MB');
      final v = Evidence329.verify(bad);
      expect(v.ok, isFalse);
      expect(v.firstBad, 2);
      expect(v.why, 'changed');
    });

    test('329-5 delete a line and the chain breaks', () async {
      final e = ev();
      for (var i = 1; i <= 4; i++) {
        await e.add('ask', 'line $i');
      }
      final lines = (await e.export()).split('\n').where((l) => l.startsWith('{')).toList();
      final cut = [lines[0], lines[2], lines[3]].join('\n');
      expect(Evidence329.verify(cut).ok, isFalse);
    });

    test('329-6 reorder two lines and it breaks', () async {
      final e = ev();
      await e.add('a', 'one');
      await e.add('b', 'two');
      final l = (await e.export()).split('\n').where((x) => x.startsWith('{')).toList();
      expect(Evidence329.verify([l[1], l[0]].join('\n')).ok, isFalse);
    });

    test('329-7 an empty or junk file is never "fine"', () {
      expect(Evidence329.verify('').ok, isFalse);
      expect(Evidence329.verify('# only a header').ok, isFalse);
      expect(Evidence329.verify('{not json').ok, isFalse);
    });

    test('329-8 words with a newline do not break the file', () async {
      final e = ev();
      await e.add('ask', 'Ali\nasked\nfor a chat');
      expect(Evidence329.verify(await e.export()).ok, isTrue);
    });

    test('329-9 the record keeps the newest lines, it never grows forever', () async {
      final e = ev();
      for (var i = 0; i < Evidence329.keep + 12; i++) {
        await e.add('ask', 'line $i');
      }
      expect(await e.count(), Evidence329.keep);
      final text = await e.export();
      expect(text, contains('line ${Evidence329.keep + 11}'));
      expect(text, isNot(contains('"words":"line 0"')));
    });

    test('329-10 the same line twice is a different hash (time is in it)', () async {
      var t = DateTime.utc(2026, 11, 19, 6);
      final e = Evidence329(
          read: (k) async => disk[k], write: (k, v) async => disk[k] = v, clock: () => t);
      await e.add('ask', 'same');
      t = t.add(const Duration(seconds: 1));
      await e.add('ask', 'same');
      final l = (await e.export()).split('\n').where((x) => x.startsWith('{')).toList();
      expect(l[0], isNot(l[1].replaceFirst('"n":2', '"n":1')));
      expect(Evidence329.verify(l.join('\n')).ok, isTrue);
    });
  });

  group('329 · the phone, the screen, the words', () {
    test('329-11 the app records an ask when one is made', () {
      expect(File('lib/features/admin/data/actions/chat_answer_reader.dart').readAsStringSync(),
          contains('Evidence329.instance'));
    });

    test('329-12 the screen copies it out and never uploads it', () {
      final src = File(_screen).readAsStringSync();
      expect(src, contains("Key('evidence_329_copy')"));
      expect(src, contains('Clipboard.setData'));
      expect(src, isNot(contains('http')));
      expect(File(_src).readAsStringSync(), isNot(contains('http')));
    });

    test('329-13 it is reachable from Security', () {
      expect(File('lib/features/admin/presentation/screens/admin_security_screen.dart')
          .readAsStringSync(), contains('a216_evidence_329'));
    });

    test('329-14 the words exist in both languages', () {
      expect(L.t.evidence329, 'Export evidence');
      expect(L.t.evidenceChecksOut329(3), contains('3'));
      expect(L.t.evidenceBroken329(2), contains('2'));
      expect(File('lib/l10n/app_ur.arb').readAsStringSync(), contains('"evidence329"'));
    });

    test('329-15 the pins still live in one place, and this build follows them', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
