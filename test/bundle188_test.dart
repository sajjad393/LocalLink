// Bundle 188 (B3): the "why it stopped" line also says what was running.
// The logic is Android-side (Exit188Test.kt); here: version + wiring.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  const k = 'android/app/src/main/kotlin/com/sajjad/locallink';

  test('exit line carries doing=', () {
    expect(_read('$k/AppHealthPolicy.kt'), contains('"doing=\$doing "'));
    expect(_read('$k/AppHealth.kt'), contains('setProcessStateSummary'));
  });

  group('Bundle 188 version', () {
    test('pubspec and stamp', () {
      expect(_read('pubspec.yaml'), contains('version: 3.0.19+90'));
      expect(_read('lib/app/local_link_app.dart'),
          contains("'v3 · 3.0.19 · bundles 104-188 (2026-11-01)'"));
    });
  });
}
