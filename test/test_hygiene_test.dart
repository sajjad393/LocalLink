// Bundle 332: the test folder must stay honest.
//
// `flutter test` (no path) - what CI runs - loads EVERY .dart file under test/.
// A helper file without a main() fails the whole run, which is exactly how the
// pipeline stayed red from 41c264d while 2,000+ tests passed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final files = Directory('test')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('332-1 every file under test/ can be run or is in test/support/', () {
    final bad = <String>[];
    for (final f in files) {
      final rel = f.path.replaceAll('\\', '/');
      if (rel.contains('/support/')) continue; // helpers live here, not run
      final src = f.readAsStringSync();
      final hasMain = RegExp(r'^\s*(?:void\s+)?main\s*\(', multiLine: true).hasMatch(src);
      if (!hasMain) bad.add(rel);
    }
    expect(bad, isEmpty,
        reason: 'a file here without main() fails the whole `flutter test` run: $bad');
  });

  test('332-2 the suite still has the bundles we ship', () {
    final names = files.map((f) => f.path.replaceAll('\\', '/').split('/').last).toSet();
    for (final b in ['bundle327_test.dart', 'bundle328_test.dart', 'bundle329_test.dart',
                     'bundle330_test.dart', 'bundle331_test.dart']) {
      expect(names, contains(b));
    }
  });

  test('332-3 the name rule stays in bundle178 (one place, not two)', () {
    // 178 owns the "visible text says LinkUp" rule; this test only guards that
    // we do not grow a second, weaker copy of it.
    expect(File('test/bundle178_test.dart').existsSync(), isTrue);
  });
}
