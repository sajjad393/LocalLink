// Bundle 338: a phone that cannot bind its key must say so, and the owner must
// be able to fix it.
//
// RMX5303: `IDENTITY_KEY_PUT bound (server has another key)` and the server
// answered `identity key is already bound` to every device-key PUT, while the
// other phone said `ok`. 291 settled that silently - correct, a stolen token
// must not swap a key - but nothing told the owner, so every server feature was
// quietly off on that phone.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/services/identity_key_upload_291.dart';
import 'package:locallink/features/admin/data/actions/rebind_338.dart';
import 'package:locallink/features/admin/presentation/widgets/rebind_338_sheet.dart';
import 'package:locallink/l10n/l10n.dart';

const _svc = 'lib/core/services/identity_key_upload_291.dart';
const _screen = 'lib/features/admin/presentation/screens/admin_security_screen.dart';

IdentityKeyUpload291 _rig(List<int> answers) {
  var i = 0;
  return IdentityKeyUpload291(
    put: (_) async => answers[i++ < answers.length ? i - 1 : answers.length - 1],
    publicKey: () async => 'KEY-1',
    deviceId: () => 'dev-1',
    clock: () => DateTime(2026, 11, 20, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => IdentityKeyUpload291.boundDevice291.value = '');

  group('338 · a 409 is a fact the owner can see', () {
    test('338-1 bound raises the state', () async {
      final s = _rig([409]);
      expect(await s.maybeUpload(), 'bound');
      expect(IdentityKeyUpload291.boundDevice291.value, 'bound');
      expect(Rebind338.needsRow(IdentityKeyUpload291.boundDevice291.value), isTrue);
    });

    test('338-2 a bound key is not retried by itself', () async {
      final s = _rig([409, 200]);
      await s.maybeUpload();
      expect(await s.maybeUpload(reason: 'connect'), 'skip', reason: 'settled, as 291 says');
      expect(IdentityKeyUpload291.boundDevice291.value, 'bound');
    });

    test('338-3 ok clears the row', () async {
      final s = _rig([200]);
      expect(await s.maybeUpload(), 'ok');
      expect(Rebind338.needsRow(IdentityKeyUpload291.boundDevice291.value), isFalse);
    });

    test('338-4 a network failure leaves the last known state alone', () async {
      IdentityKeyUpload291.boundDevice291.value = 'bound';
      final s = IdentityKeyUpload291(
        put: (_) async => throw const SocketException('down'),
        publicKey: () async => 'KEY-1',
        deviceId: () => 'dev-1',
        clock: () => DateTime(2026, 11, 20, 1),
      );
      expect(await s.maybeUpload(), 'fail');
      expect(IdentityKeyUpload291.boundDevice291.value, 'bound',
          reason: 'not knowing is not the same as being registered');
    });
  });

  group('338 · the owner, and only the owner, replaces the key', () {
    test('338-5 a re-register needs consent AND a bound phone', () {
      expect(Rebind338.mayReRegister(consented: false, state: 'bound'), isFalse);
      expect(Rebind338.mayReRegister(consented: true, state: 'ok'), isFalse);
      expect(Rebind338.mayReRegister(consented: true, state: ''), isFalse);
      expect(Rebind338.mayReRegister(consented: true, state: 'bound'), isTrue);
    });

    test('338-6 the forced send really goes, and then settles again', () async {
      final s = _rig([409, 200]);
      expect(await s.maybeUpload(), 'bound');
      expect(await s.maybeUpload(reason: 'owner', force: true), 'ok');
      expect(IdentityKeyUpload291.boundDevice291.value, 'ok');
      expect(await s.maybeUpload(reason: 'owner', force: true), 'skip',
          reason: 'a settled ok is not sent again');
    });

    testWidgets('338-7 refuse sends nothing at all', (tester) async {
      var sent = 0;
      IdentityKeyUpload291.boundDevice291.value = 'bound';
      await _open(tester, onSend: () async {
        sent++;
        return 'ok';
      });
      await tester.tap(find.byKey(const ValueKey('rebind338_no')));
      await tester.pumpAndSettle();
      expect(sent, 0);
      expect(find.byKey(const ValueKey('rebind338_card')), findsNothing);
    });

    testWidgets('338-8 Send on a phone that is NOT bound sends nothing', (tester) async {
      var sent = 0;
      IdentityKeyUpload291.boundDevice291.value = 'ok';
      await _open(tester, onSend: () async {
        sent++;
        return 'ok';
      });
      await tester.tap(find.byKey(const ValueKey('rebind338_send')));
      await tester.pumpAndSettle();
      expect(sent, 0, reason: 'the card can only act on a real bound state');
    });

    testWidgets('338-9 Send when bound sends exactly once', (tester) async {
      var sent = 0;
      IdentityKeyUpload291.boundDevice291.value = 'bound';
      final popped = Completer<bool?>();
      await _open(tester,
          onSend: () async {
            sent++;
            return 'ok';
          },
          popped: popped);
      await tester.tap(find.byKey(const ValueKey('rebind338_send')));
      await tester.pumpAndSettle();
      expect(sent, 1);
      expect(await popped.future, isTrue);
    });

    testWidgets('338-10 the card says what it does and that nothing is sent yet', (tester) async {
      IdentityKeyUpload291.boundDevice291.value = 'bound';
      await _open(tester, onSend: () async => 'ok');
      expect(find.text(L.t.reRegisterWhat338), findsOneWidget);
      expect(find.text(L.t.reRegisterNothingSent338), findsOneWidget);
      expect(find.text(L.t.send326), findsOneWidget);
      expect(find.text(L.t.refuse326), findsOneWidget);
    });
  });

  group('338 · where it is wired', () {
    test('338-11 the service keeps the state and the forced path', () {
      final src = File(_svc).readAsStringSync();
      expect(src, contains('boundDevice291'));
      expect(src, contains("boundDevice291.value = 'bound';"));
      expect(src, contains('bool force = false'));
      expect(src, contains("if (force && _settled[id] == 'bound') _settled.remove(id);"));
    });

    test('338-12 the Security page watches it and opens the consent card', () {
      final src = File(_screen).readAsStringSync();
      expect(src, contains('Rebind338.watch'));
      expect(src, contains('Rebind338.needsRow(state)'));
      expect(src, contains('Rebind338Sheet.show(context)'));
      expect(src, contains('L.t.notRegistered338'));
    });

    test('338-13 the forced path is wired to the real service, once', () {
      final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(deps, contains('IdentityKeyUpload291.reRegister338 ='));
      expect(deps, contains("maybeUpload(reason: 'owner', force: true)"));
      expect(deps, contains('wireRebind338();'));
    });

    test('338-14 the words exist in both languages', () {
      expect(File('lib/l10n/app_en.arb').readAsStringSync(), contains('"notRegistered338"'));
      expect(File('lib/l10n/app_ur.arb').readAsStringSync(), contains('"notRegistered338"'));
      final gen = File('lib/l10n/gen/app_localizations.dart').readAsStringSync();
      for (final k in [
        'notRegistered338',
        'notRegisteredWhy338',
        'reRegisterPhone338',
        'reRegisterWhat338',
        'reRegisterNothingSent338',
      ]) {
        expect(gen, contains('String get $k;'), reason: k);
      }
    });

    test('338-15 the pins follow the constants', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}

/// A tiny witness: counts the sends, and gives the card something to await.
class _T {
  _T({required this.sent});
  final void Function() sent;
}

/// Pumps the consent card and returns what it popped with.
Future<void> _open(WidgetTester tester,
    {required Future<String> Function() onSend, Completer<bool?>? popped}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final r = await Rebind338Sheet.show(context, onSend: onSend);
              if (popped != null && !popped.isCompleted) popped.complete(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
