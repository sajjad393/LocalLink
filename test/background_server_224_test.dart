import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/server_reach.dart';

/// Bundle 224 (H): with the app closed (BOOT_ENGINE_DART_START) a phone-only
/// account still called the server: "VERSION_RULE_SERVER_FAIL
/// FormatException: Server address is required" ~8 s after every background
/// start (logs 2026-11-07 05:15, 11:43, 12:24). The background start never
/// bound the 223 server gate.
void main() {
  tearDown(() => ServerReach.instance = ServerReach());

  group('224-H1 the background start binds the server gate', () {
    test('background_runner binds before the steps run', () {
      final s = File('lib/app/background_runner.dart').readAsStringSync();
      final bind = s.indexOf('deps.bindServerReach()');
      final steps = s.indexOf('runBackgroundSteps([');
      expect(bind, greaterThan(0));
      expect(bind, lessThan(steps),
          reason: 'the gate must know "no server" before admin_badges runs');
    });

    test('app start and background start share one helper', () {
      final s = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(s, contains('void bindServerReach()'));
      final core = s.substring(s.indexOf('Future<void> initializeCore('));
      expect(core.substring(0, 400), contains('bindServerReach();'));
    });

    test('no address -> skipped with one INFO reason', () {
      final r = ServerReach()..bind(address: () => '', socketUp: () => false);
      expect(r.shouldSkip('version_rule'), isTrue);
      expect(r.skipWhy(), 'no_server');
    });
  });

  group('224-H2 "Server address is required" counts as no server', () {
    const noServer = FormatException('Server address is required');

    test('the error is recognised, but it is not a network error', () {
      expect(ServerReach.isNoServerError(noServer), isTrue);
      expect(ServerReach.isNoServerError(const FormatException('bad')), isFalse);
      expect(ServerReach.isNetworkError(noServer), isFalse,
          reason: '223 rule kept: a FormatException is not "server down"');
    });

    test('after that error the next calls are skipped (no_server)', () {
      // An unbound gate (address == null) used to let every call through.
      final r = ServerReach();
      expect(r.shouldSkip('admin_badges'), isFalse);
      r.noteFailure(noServer);
      expect(r.shouldSkip('admin_badges'), isTrue);
      expect(r.skipWhy(), 'no_server');
    });

    test('a new sign-in (bind) opens the gate again', () {
      final r = ServerReach()..noteFailure(noServer);
      expect(r.skipWhy(), 'no_server');
      r.bind(address: () => 'http://10.0.0.2:8080', socketUp: () => false);
      expect(r.skipWhy(), isNull);
    });

    test('old rule kept: a network error closes the gate for 30 s only', () {
      var now = DateTime(2026, 11, 8, 12);
      final r = ServerReach(clock: () => now)
        ..bind(address: () => 'http://x', socketUp: () => false);
      r.noteFailure(const SocketException('Connection refused'));
      expect(r.skipWhy(), 'server_down');
      now = now.add(const Duration(seconds: 31));
      expect(r.skipWhy(), isNull);
    });
  });
}
