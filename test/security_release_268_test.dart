// Bundle 268 (R268-1): the release HTTP rule of SecurityPolicy.
//
// `flutter test` always runs as debug (kDebugMode = true), so a normal run
// can never see the release rule. This file is run 3 ways; RT268_MODE says
// which one, and test 0 proves the build constants really are that mode:
//
//   flutter test test/security_release_268_test.dart                (debug)
//   flutter test --dart-define=dart.vm.product=true \
//       --dart-define=RT268_MODE=release test/security_release_268_test.dart
//   flutter test --dart-define=dart.vm.product=true \
//       --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true \
//       --dart-define=RT268_MODE=release_flag test/security_release_268_test.dart
//
// `dart.vm.product` is the constant behind kReleaseMode (and so kDebugMode);
// App CI runs all 3. Only the tests of the active mode are registered, so
// nothing is skipped and nothing passes without checking.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/network/tls_pin_243.dart';
import 'package:locallink/core/security/security_policy.dart';
import 'package:locallink/core/services/locallink_api.dart';

const String mode = String.fromEnvironment('RT268_MODE', defaultValue: 'debug');
const bool flag = bool.fromEnvironment('LOCLINK_ALLOW_INSECURE_HTTP');

const String lan = '192.168.18.27:8080';
const String plainError = 'Plain HTTP is disabled in release builds';

Matcher get _plainHttpRefused => throwsA(isA<FormatException>()
    .having((e) => e.message, 'message', contains(plainError)));

void _pinOnHttpOnly() {
  // A saved, active pin for the same server (what phones kept from 3.0.78).
  TlsPin243.setForTest(
      host: '192.168.18.27', port: 8443, sha: 'ab' * 32, active: true, httpPort: 8080);
  TlsPin243.httpOnly262 = true; // what the app sets at start (bundle 262)
}

void main() {
  tearDown(() {
    TlsPin243.httpOnly262 = false;
    TlsPin243.setForTest();
  });

  test('0. the build constants are really mode=$mode', () {
    switch (mode) {
      case 'debug':
        expect(kReleaseMode, isFalse);
        expect(kDebugMode, isTrue);
        expect(flag, isFalse);
        expect(SecurityPolicy.allowInsecureHttp, isTrue);
      case 'release':
        expect(kReleaseMode, isTrue, reason: 'needs --dart-define=dart.vm.product=true');
        expect(kDebugMode, isFalse);
        expect(flag, isFalse);
        expect(SecurityPolicy.allowInsecureHttp, isFalse);
      case 'release_flag':
        expect(kReleaseMode, isTrue, reason: 'needs --dart-define=dart.vm.product=true');
        expect(kDebugMode, isFalse);
        expect(flag, isTrue, reason: 'needs --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true');
        expect(SecurityPolicy.allowInsecureHttp, isTrue);
      default:
        fail('unknown RT268_MODE=$mode (debug | release | release_flag)');
    }
  });

  if (mode == 'debug') {
    test('1. debug: plain HTTP to the LAN server is allowed (API, files, socket)', () {
      expect(SecurityPolicy.normalizeServerUri(lan).toString(), 'http://$lan');
      expect(LocalLinkApi.normalizeServerAddress(lan), 'http://$lan');
      expect(
          SecurityPolicy.resolveLocalResource('/api/v1/files/x', baseAddress: lan).toString(),
          'http://$lan/api/v1/files/x');
    });
  }

  if (mode == 'release') {
    test('2. release without the flag: plain HTTP is refused everywhere', () {
      expect(() => SecurityPolicy.normalizeServerUri(lan), _plainHttpRefused);
      expect(() => SecurityPolicy.normalizeServerUri('http://$lan'), _plainHttpRefused);
      expect(() => LocalLinkApi.normalizeServerAddress(lan), _plainHttpRefused);
      expect(() => SecurityPolicy.resolveLocalResource('/api/v1/files/x', baseAddress: lan),
          _plainHttpRefused);
    });

    test('2b. release without the flag: the saved pin does not hide it any more', () {
      _pinOnHttpOnly();
      expect(() => SecurityPolicy.normalizeServerUri(lan), _plainHttpRefused);
    });
  }

  if (mode == 'release_flag') {
    test('3. release with the flag: plain HTTP to the LAN server is allowed', () {
      expect(SecurityPolicy.normalizeServerUri(lan).toString(), 'http://$lan');
      expect(LocalLinkApi.normalizeServerAddress(lan), 'http://$lan');
      expect(
          SecurityPolicy.resolveLocalResource('/api/v1/files/x', baseAddress: lan).toString(),
          'http://$lan/api/v1/files/x');
    });
  }

  test('3b. the flag never opens a public host (mode=$mode)', () {
    for (final host in ['8.8.8.8:8080', 'example.com:8080', 'http://1.1.1.1']) {
      expect(() => SecurityPolicy.normalizeServerUri(host), throwsFormatException,
          reason: host);
    }
  });

  test('4. HTTP only: a saved pin never turns http into https (mode=$mode)', () {
    // Control: the same pin WITHOUT the HTTP-only switch does upgrade, so
    // the pin set up here is a real, working one.
    TlsPin243.setForTest(
        host: '192.168.18.27', port: 8443, sha: 'ab' * 32, active: true, httpPort: 8080);
    expect(SecurityPolicy.normalizeServerUri(lan).toString(), 'https://192.168.18.27:8443');

    _pinOnHttpOnly();
    expect(TlsPin243.active, isFalse);
    expect(TlsPin243.upgrade(Uri.parse('http://$lan')).toString(), 'http://$lan');
    if (SecurityPolicy.allowInsecureHttp) {
      expect(SecurityPolicy.normalizeServerUri(lan).scheme, 'http');
      expect(SecurityPolicy.resolveLocalResource('http://$lan/x', baseAddress: lan).scheme,
          'http');
    } else {
      // release without the flag: refused, never quietly moved to https
      expect(() => SecurityPolicy.normalizeServerUri(lan), _plainHttpRefused);
    }
  });

  test('5. the release build command carries the flag (CI + build script)', () {
    const cmd = 'flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true';
    final ci = File('.github/workflows/app_ci.yml').readAsStringSync();
    expect(ci, contains(cmd));
    expect(ci, contains('--dart-define=RT268_MODE=release test/security_release_268_test.dart'));
    expect(ci, contains('--dart-define=RT268_MODE=release_flag test/security_release_268_test.dart'));
    expect(File('tool/build_release_apk.ps1').readAsStringSync(), contains(cmd));
    // The policy itself is unchanged: debug or the explicit build flag only.
    expect(File('lib/core/security/security_policy.dart').readAsStringSync(),
        contains('static bool get allowInsecureHttp => kDebugMode || _allowInsecureHttpOverride;'));
  });
}
