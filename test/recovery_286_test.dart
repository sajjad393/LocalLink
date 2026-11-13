import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/screens/recovery_code_286.dart';

import 'support/g211_fakes.dart';

/// Bundle 286: recovery code card on Home, Settings row, password + code screens.
const _code = 'K7QM2-XPA9T-RC4WN-E8D3F';

class _Store extends Store211 {
  final settings = <String, String>{};
  String? code;
  String user;
  Map<String, dynamic>? mirror;
  _Store({this.code = _code, this.user = 'sajjad'});

  @override
  String? get username => user;
  @override
  String? get localRecoveryCode => code;
  @override
  Map<String, dynamic>? get offlineLoginAccount => mirror;
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  Future<void> updateLocalRecoveryCode(String recoveryCode) async => code = recoveryCode;
  @override
  Future<String> rotateLocalRecoveryCode() async => code = 'LOCAL-NEW00-CODE0-AAAAA';
}

class _Accounts implements AccountRepositoryContract {
  bool online = false;
  @override
  Future<String> rotateRecoveryCode() async {
    if (!online) throw const SocketException('offline');
    return 'SERVR-NEW00-CODE0-BBBBB';
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Map<String, dynamic> _mirrorFor(String user, String password) {
  final salt = Uint8List.fromList(List<int>.generate(PasswordKdf.saltLength, (i) => i + 3));
  return {
    'username': user,
    'pwd_salt': PasswordKdf.b64(salt),
    'pwd_hash': PasswordKdf.b64(PasswordKdf.derive(password, salt)),
  };
}

Future<void> _pumpCard(WidgetTester tester, _Store store, {DateTime? now}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(
      body: ListView(children: [
        RecoveryHomeCard286(store: store, accounts: _Accounts(), clock: now == null ? null : () => now),
        const Text('My links'),
      ]),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500)); // card slides in
}

void main() {
  setUp(() => AppLogFile.instance.resetForTest());

  group('flags', () {
    test('new account -> fresh card; saved -> none; another account does not inherit saved', () async {
      final s = _Store();
      expect(await RecoveryCode286.cardKind(s), RecoveryCardKind286.notSaved);
      await RecoveryFlags286.markNew(s);
      expect(await RecoveryCode286.cardKind(s), RecoveryCardKind286.fresh);
      await RecoveryFlags286.markSaved(s, from: 'button');
      expect(await RecoveryCode286.cardKind(s), isNull);
      s.user = 'zain_ali';
      expect(await RecoveryCode286.cardKind(s), RecoveryCardKind286.notSaved);
    });

    test('Later hides the card for 1 day, then it is back (not fresh any more)', () async {
      final s = _Store();
      await RecoveryFlags286.markNew(s);
      final t0 = DateTime(2026, 11, 14, 10);
      await RecoveryFlags286.later(s, now: t0);
      expect(await RecoveryCode286.cardKind(s, now: t0.add(const Duration(hours: 23))), isNull);
      expect(await RecoveryCode286.cardKind(s, now: t0.add(const Duration(hours: 24, minutes: 1))),
          RecoveryCardKind286.notSaved);
    });

    test('no code on this phone -> "Make a recovery code"', () async {
      expect(await RecoveryCode286.cardKind(_Store(code: '')), RecoveryCardKind286.noCode);
      expect(await RecoveryCode286.cardKind(_Store(user: '')), isNull);
    });

    test('password checked with the copy saved on this phone (works offline)', () async {
      final s = _Store();
      expect(await RecoveryCode286.checkPassword(s, 'secret-123'), 'no_copy');
      s.mirror = _mirrorFor('sajjad', 'secret-123');
      expect(await RecoveryCode286.checkPassword(s, 'secret-123'), 'ok');
      expect(await RecoveryCode286.checkPassword(s, 'secret-124'), 'wrong');
      expect(await RecoveryCode286.checkPassword(s, ''), 'wrong');
      s.mirror = _mirrorFor('someone', 'secret-123');
      expect(await RecoveryCode286.checkPassword(s, 'secret-123'), 'no_copy');
    });

    test('make a new code: server first, else on this phone; not saved any more', () async {
      final s = _Store();
      final a = _Accounts();
      await RecoveryFlags286.markSaved(s, from: 'button');
      expect(await RecoveryCode286.makeNew(a, s), 'LOCAL-NEW00-CODE0-AAAAA');
      expect(await RecoveryFlags286.isSaved(s), isFalse);
      a.online = true;
      expect(await RecoveryCode286.makeNew(a, s), 'SERVR-NEW00-CODE0-BBBBB');
      expect(s.code, 'SERVR-NEW00-CODE0-BBBBB');
    });
  });

  group('Home card', () {
    testWidgets('new account: hidden code, Show, WhatsApp, I saved it -> slides away + toast; no x', (tester) async {
      final s = _Store();
      await RecoveryFlags286.markNew(s);
      await _pumpCard(tester, s);
      expect(find.text('Save your recovery code'), findsOneWidget);
      expect(find.text('If you lose this phone, it is the only way back into @sajjad.'), findsOneWidget);
      expect(find.text(_code), findsNothing);
      expect(find.text('Save on WhatsApp'), findsOneWidget);
      expect(find.text('I saved it'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.text(_code), findsOneWidget);
      // Above My links.
      expect(tester.getTopLeft(find.text('Save your recovery code')).dy,
          lessThan(tester.getTopLeft(find.text('My links')).dy));

      await tester.tap(find.byKey(const ValueKey('rc286-saved')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Save your recovery code'), findsNothing);
      expect(find.text('Recovery code saved'), findsOneWidget);
      expect(await RecoveryFlags286.isSaved(s), isTrue);
      final logs = AppLogFile.instance.pendingForTest.join('\n');
      expect(logs, contains('RECOVERY_CARD'));
      expect(logs, isNot(contains(_code)), reason: 'logs never hold the code');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('existing account: Show my code + Later; Later hides it', (tester) async {
      final s = _Store();
      await _pumpCard(tester, s);
      expect(find.text('You have not saved it yet. Keep it safe in case this phone is lost.'), findsOneWidget);
      expect(find.text('Show my code'), findsOneWidget);
      expect(find.text('Save on WhatsApp'), findsNothing);
      await tester.tap(find.text('Later'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Save your recovery code'), findsNothing);
    });

    testWidgets('no code: Make my code', (tester) async {
      await _pumpCard(tester, _Store(code: ''));
      expect(find.text('Make a recovery code'), findsOneWidget);
      expect(find.text('Make my code'), findsOneWidget);
    });

    testWidgets('hidden while another Home card shows', (tester) async {
      final s = _Store();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RecoveryHomeCard286(store: s, accounts: _Accounts(), hidden: true)),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Save your recovery code'), findsNothing);
    });
  });

  group('screens', () {
    testWidgets('wrong password: red line, code stays hidden; right one shows the code screen', (tester) async {
      final s = _Store()..mirror = _mirrorFor('sajjad', 'secret-123');
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => RecoveryCode286.open(context, store: s, accounts: _Accounts()),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Enter your password'), findsOneWidget);
      expect(find.text('Only you should see your recovery code.'), findsOneWidget);
      expect(find.text('Works without the server too.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('rc286-password')), 'wrong-pass');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Show my code'));
        await Future<void>.delayed(const Duration(seconds: 3));
      });
      await tester.pump();
      expect(find.text(RecoveryPasswordScreen286.wrongText), findsOneWidget);
      expect(find.text(_code), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('rc286-password')), 'secret-123');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Show my code'));
        await Future<void>.delayed(const Duration(seconds: 3));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Your recovery code'), findsOneWidget);
      expect(find.text('Saved on this phone'), findsOneWidget);
      expect(find.text('@sajjad'), findsOneWidget);
      expect(find.text(_code), findsOneWidget, reason: 'shown after the password');
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Use it on Forgot password if this phone is lost. Works offline.'), findsOneWidget);
      expect(find.text('Never share it. LinkUp and the admin never ask for it.'), findsOneWidget);

      await tester.tap(find.text('Make a new code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Your old code stops working.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rc286-new-yes')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('LOCAL-NEW00-CODE0-AAAAA'), findsOneWidget);
      final logs = AppLogFile.instance.pendingForTest.join('\n');
      expect(logs, contains('RECOVERY_VIEW'));
      expect(logs, isNot(contains(_code)));
      expect(logs, isNot(contains('LOCAL-NEW00-CODE0-AAAAA')));
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Settings row: Not saved (orange) / Saved (green)', (tester) async {
      final s = _Store();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RecoveryRow286(store: s, accounts: _Accounts())),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Recovery code'), findsOneWidget);
      expect(find.text('Your way back in if this phone is lost'), findsOneWidget);
      expect(find.byKey(const ValueKey('rc286-tag-not-saved')), findsOneWidget);
      await RecoveryFlags286.markSaved(s, from: 'test');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('rc286-tag-saved')), findsOneWidget);
    });
  });

  test('source: wired into Home, Settings, Profile, Create account', () {
    String read(String p) => File(p).readAsStringSync();
    final home = read('lib/features/home/presentation/screens/home_screen.dart');
    final cards = home.substring(home.indexOf('List<Widget> _joinCards218()'));
    expect(cards.substring(0, cards.indexOf('];')), contains('RecoveryHomeCard286('));
    final account = read('lib/features/account/presentation/screens/account_center_screen.dart');
    expect(account, contains('RecoveryRow286('));
    expect(account, isNot(contains('account_recovery_note')));
    expect(account.indexOf('RecoveryRow286('), lessThan(account.indexOf("title: 'Backup and restore'")));
    final profile = read('lib/features/account/presentation/screens/profile_screen.dart');
    expect(profile, contains('RecoveryCode286.open('));
    expect(profile, isNot(contains('A recovery code is already configured')));
    final setup = read('lib/features/authentication/presentation/screens/setup_screen.dart');
    expect('RecoveryFlags286.markNew('.allMatches(setup).length, 2);
  });
}

