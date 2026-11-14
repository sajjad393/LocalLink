// Bundle 301: smaller APK. Source checks (the real APK is built by CI /
// tool/build_release_apk.ps1).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

String _block(String src, String start) {
  final i = src.indexOf(start);
  expect(i, isNonNegative, reason: 'missing "$start"');
  var depth = 0;
  for (var j = src.indexOf('{', i); j < src.length; j++) {
    if (src[j] == '{') depth++;
    if (src[j] == '}' && --depth == 0) return src.substring(i, j + 1);
  }
  fail('unclosed "$start"');
}

void main() {
  final gradle = _read('android/app/build.gradle');

  test('1. only ARM 32 + ARM 64, replacing the Flutter plugin list (no x86)', () {
    final defaults = _block(gradle, 'defaultConfig {');
    final ndk = _block(defaults, 'ndk {');
    // The Flutter Gradle plugin fills defaultConfig.ndk.abiFilters with
    // x86_64 too when it is applied; adding alone would keep it.
    expect(ndk, contains('abiFilters.clear()'));
    expect(ndk, contains("abiFilters.addAll(['armeabi-v7a', 'arm64-v8a'])"));
    expect(ndk.indexOf('abiFilters.clear()'), lessThan(ndk.indexOf('abiFilters.addAll')));
    expect(gradle, isNot(contains("'x86")));
  });

  test('2. native code is stored compressed in the APK', () {
    final packaging = _block(gradle, 'packaging {');
    expect(_block(packaging, 'jniLibs {'), contains('useLegacyPackaging true'));
    expect(_read('android/app/src/main/AndroidManifest.xml'),
        isNot(contains('extractNativeLibs="false"')));
  });

  test('3. release commands build ARM only and keep the HTTP flag', () {
    const cmd = 'flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true'
        ' --target-platform android-arm,android-arm64';
    expect(_read('.github/workflows/app_ci.yml'), contains(cmd));
    expect(_read('tool/build_release_apk.ps1'), contains(cmd));
  });

  test('4. signing and app id unchanged (installs over 3.0.96)', () {
    expect(gradle, contains('applicationId "com.sajjad.linkup"'));
    expect(gradle, contains('signingConfig signingConfigs.debug'));
    expect(gradle, contains('minifyEnabled true'));
    expect(gradle, contains('shrinkResources true'));
  });
}
