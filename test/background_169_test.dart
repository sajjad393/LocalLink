import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/app/background_runner.dart';
import 'package:locallink/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bundle 169 (4.3): start after reboot', () {
    test('runs only for a signed-in account', () {
      expect(
          decideBackgroundStart(
              configured: true, offlinePending: false, signedOut: false),
          BackgroundStart.run);
      expect(
          decideBackgroundStart(
              configured: false, offlinePending: true, signedOut: false),
          BackgroundStart.run,
          reason: 'phone-only accounts get nearby messages too');
      expect(
          decideBackgroundStart(
              configured: false, offlinePending: false, signedOut: false),
          BackgroundStart.noAccount);
      expect(
          decideBackgroundStart(
              configured: true, offlinePending: false, signedOut: true),
          BackgroundStart.signedOut,
          reason: 'a signed-out phone stays quiet until the user logs in');
    });

    test('a failing step never stops the next one', () async {
      final ran = <String>[];
      final failed = await runBackgroundSteps([
        (name: 'a', run: () async => ran.add('a')),
        (name: 'b', run: () async => throw StateError('no channel')),
        (name: 'c', run: () async => ran.add('c')),
      ]);
      expect(ran, ['a', 'c']);
      expect(failed, ['b']);
    });

    test('a stuck step times out and the rest still run', () async {
      final ran = <String>[];
      final failed = await runBackgroundSteps([
        (name: 'stuck', run: () => Completer<void>().future),
        (name: 'next', run: () async => ran.add('next')),
      ], timeout: const Duration(milliseconds: 20));
      expect(failed, ['stuck']);
      expect(ran, ['next']);
    });

    test('a broken store tells the native side to stop the engine', () async {
      const channel = MethodChannel('locallink/background_engine_test');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await BackgroundRunner(
        create: () => throw StateError('no storage'),
        channel: channel,
      ).run();
      expect(calls.single.method, 'idle');
      expect((calls.single.arguments as Map)['detail'], 'store_failed');
    });

    test('the background entry point exists for Android', () {
      expect(app.backgroundMain, isA<void Function()>());
    });
  });
}
