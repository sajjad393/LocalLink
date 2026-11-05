// Bundle 223 Phase 3 (I, J): permission pop-ups one at a time; the password
// lock runs off the screen thread.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/permissions/app_permission_gate.dart';

const _perm = MethodChannel('locallink/permissions');

List<String> _lines(String e) => AppLogFile.instance.pendingForTest
    .where((l) => l.contains('|$e|') || l.endsWith('|$e'))
    .toList();

Future<void> _waitFor(bool Function() ok, {int ms = 3000}) async {
  for (var i = 0; i < ms ~/ 10; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    AppLogFile.instance.resetForTest();
    AppPermissionGate.resetForTest();
    AppPermissionGate.gap = const Duration(milliseconds: 10);
    AppPermissionGate.answerLimit = const Duration(seconds: 5);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_perm, null);
    AppPermissionGate.resetForTest();
  });

  group('223-21 the gate waits for each answer', () {
    test('the next pop-up is asked only after the user answered the open one', () async {
      final asked = <String>[];
      final answers = <String, Completer<void>>{};
      messenger.setMockMethodCallHandler(_perm, (call) async {
        if (call.method == 'granted') return {'granted': false};
        final name = (call.arguments as Map)['name'] as String;
        asked.add(name);
        answers[name] = Completer<void>();
        await answers[name]!.future; // native replies after the answer
        return null;
      });
      final chain = AppPermissionGate.runChainForTest();
      await _waitFor(() => asked.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(asked, ['microphone'], reason: 'no second pop-up while one is open');
      answers['microphone']!.complete();
      await _waitFor(() => asked.length == 2);
      expect(asked, ['microphone', 'nearby']);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(asked.length, 2);
      answers['nearby']!.complete();
      await _waitFor(() => asked.length == 3);
      answers['notifications']!.complete();
      await _waitFor(() => asked.length == 4);
      answers['background']!.complete();
      await chain;
      expect(asked, ['microphone', 'nearby', 'notifications', 'background']);
      expect(_lines('PERM_GATE').first, contains('name=microphone answer'));
    });

    test('223-21b a granted permission is skipped (bundle 101 order kept)', () async {
      final asked = <String>[];
      messenger.setMockMethodCallHandler(_perm, (call) async {
        final name = (call.arguments as Map)['name'] as String;
        if (call.method == 'granted') return {'granted': name == 'nearby' || name == 'background'};
        asked.add(name);
        return null;
      });
      await AppPermissionGate.runChainForTest();
      expect(asked, ['microphone', 'notifications']);
    });
  });

  test('223-22 with no answer the gate moves on after its safety limit', () async {
    AppPermissionGate.answerLimit = const Duration(milliseconds: 150);
    final asked = <String>[];
    messenger.setMockMethodCallHandler(_perm, (call) async {
      if (call.method == 'granted') return {'granted': false};
      asked.add((call.arguments as Map)['name'] as String);
      await Completer<void>().future; // never answers
      return null;
    });
    final watch = Stopwatch()..start();
    await AppPermissionGate.runChainForTest();
    expect(asked, hasLength(4));
    expect(watch.elapsedMilliseconds, lessThan(3000));
    expect(_lines('PERM_GATE').every((l) => l.contains(' limit ')), isTrue);
  });

  group('223-23 one queue in Kotlin (source)', () {
    String kt(String f) =>
        File('android/app/src/main/kotlin/com/sajjad/locallink/$f').readAsStringSync();

    test('only fireAsk calls Android requestPermissions', () {
      final dir = Directory('android/app/src/main/kotlin');
      final hits = <String>[];
      for (final f in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.kt'))) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i].trim();
          if (l.startsWith('*') || l.startsWith('//')) continue;
          if (l.contains('requestPermissions(')) hits.add('${f.path.split('/').last}:$l');
        }
      }
      expect(hits, ['MainActivity.kt:requestPermissions(a.permissions, a.code)']);
    });

    test('the gate replies after the answer; notifications use the queue', () {
      final main = kt('MainActivity.kt');
      expect(main, contains('"request" -> gateRequest(call.argument<String>("name")?.trim().orEmpty(), result)'));
      expect(main, contains('permQueue.answered(requestCode'));
      expect(main, contains('if (gatePending != null && gateCode == requestCode) finishGate("answer")'));
      expect(main, contains('gateHandler.postDelayed(gateTimeout, PermissionQueue.GATE_LIMIT_MS)'));
      expect(main, contains('askPermissions("bg_location"'));
      expect(kt('LocalLinkNotificationManager.kt'), contains('activity.askPermissions("notifications"'));
      expect(kt('CallNotificationManager.kt'), contains('activity.askPermissions("call_notifications"'));
    });
  });

  group('223-24..26 password lock off the screen thread', () {
    final salt = Uint8List.fromList(List<int>.generate(16, (i) => i * 7 % 256));

    test('223-24 deriveAsync gives the same bytes as derive', () async {
      final a = PasswordKdf.derive('correct horse', salt);
      final b = await PasswordKdf.deriveAsync('correct horse', salt);
      expect(b, a);
      expect(_lines('KDF').single, contains('ms='));
    });

    test('223-25 an old hash verifies with verifyAsync; a wrong one does not', () async {
      final hash = PasswordKdf.b64(PasswordKdf.derive('pw-12345678', salt));
      final s = PasswordKdf.b64(salt);
      expect(await PasswordKdf.verifyAsync('pw-12345678', s, hash), isTrue);
      expect(await PasswordKdf.verifyAsync('pw-wrong', s, hash), isFalse);
      expect(PasswordKdf.verify('pw-12345678', s, hash), isTrue, reason: 'sync kept');
    });

    test('223-25b (Q4) the online-login mirror and sign-in use the async lock', () {
      final repo = File('lib/features/authentication/data/repositories/authentication_repository.dart').readAsStringSync();
      final mirror = repo.substring(repo.indexOf('Future<void> mirrorOfflineLogin('));
      expect(mirror.substring(0, 600), contains('await PasswordKdf.deriveAsync(password, salt)'));
      expect(repo, contains('implements AuthenticationRepositoryContract, AsyncOfflineLogin'));
      expect(repo, contains('Future<bool> verifyOfflineLoginAsync('));
      final bloc = File('lib/features/authentication/bloc/authentication_bloc.dart').readAsStringSync();
      expect(bloc, contains('verifyOfflineLoginAsync(user, password)'));
    });

    test('223-26 no sync derive( left in the two repositories', () {
      for (final f in [
        'lib/features/authentication/data/repositories/authentication_repository.dart',
        'lib/features/recovery/data/repositories/recovery_repository.dart',
      ]) {
        final s = File(f).readAsStringSync();
        expect(s.contains('PasswordKdf.derive('), isFalse, reason: f);
        expect(s, contains('PasswordKdf.deriveAsync('), reason: f);
      }
    });
  });
}
