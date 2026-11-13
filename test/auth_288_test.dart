import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/presentation/screens/setup_screen.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';

import 'support/g211_fakes.dart';

/// Bundle 288: Log in / Create account - ONE loading, red error card, rules.
class _Auth implements AuthenticationRepositoryContract {
  Completer<void>? gate;
  Object? fail;

  @override
  String generateUniqueDeviceName() => 'phone-288';

  @override
  Future<void> prepareForAuthentication({required String deviceName}) async {
    if (fail != null) throw fail!;
    gate = Completer<void>();
    await gate!.future;
    throw const ServerProblem256('stop');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<_Auth> _pump(WidgetTester tester, {bool register = false, Object? fail}) async {
  final auth = _Auth()..fail = fail;
  await tester.binding.setSurfaceSize(const Size(400, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: SetupScreen(
      authentication: auth,
      accountRepository: _Fake.account,
      store: _Fake.store,
      api: _Fake.api,
      onSaved: () async {},
      recoveryRepository: _Fake.recovery,
      transferRepository: _Fake.transfer,
      restorationService: _Fake.restore,
      initialRegisterMode: register,
    ),
  ));
  await tester.pump();
  return auth;
}

void main() {
  testWidgets('Log in: faded until filled, then ONE loading inside the button', (tester) async {
    final auth = await _pump(tester);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log in to your account'), findsOneWidget);
    expect(find.text('New here? Create an account', findRichText: true), findsOneWidget);
    BrandButton290 button() => tester.widget(find.byKey(const ValueKey('auth288-submit')));
    expect(button().onPressed, isNull, reason: 'faded until both fields are filled');

    await tester.enterText(find.byKey(const ValueKey('auth288-username')), 'sajjad');
    await tester.enterText(find.byKey(const ValueKey('auth288-password')), 'secret123');
    await tester.pump();
    expect(find.textContaining('/32'), findsNothing, reason: 'no 6/32 counter');
    expect(button().onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('auth288-submit')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'only one loading');
    expect(find.text('Signing you in…'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('auth288-submit')), matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
        reason: 'the loading is inside the button');
    // Fields and links can't be used while it runs.
    expect(tester.widget<TextField>(find.byKey(const ValueKey('auth288-username'))).enabled, isFalse);
    expect(tester.widget<LinkAltLine290>(find.byKey(const ValueKey('auth288-switch'))).onTap, isNull);
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('forgot-password-222'))).onPressed, isNull);

    auth.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('wrong password: red card above the fields, password border red', (tester) async {
    await _pump(tester, fail: const ServerProblem256('That username and password do not match.'));
    await tester.enterText(find.byKey(const ValueKey('auth288-username')), 'sajjad');
    await tester.enterText(find.byKey(const ValueKey('auth288-password')), 'wrongpass');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('auth288-submit')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('auth288-error')), findsOneWidget);
    expect(find.text('That username and password do not match.'), findsOneWidget);
    final card = tester.getRect(find.byKey(const ValueKey('auth288-error')));
    final user = tester.getRect(find.byKey(const ValueKey('auth288-username')));
    expect(card.bottom, lessThan(user.top), reason: 'card is above the fields');
    final fields = tester.widgetList<LinkField290>(find.byType(LinkField290)).toList();
    expect(fields[0].error, isFalse);
    expect(fields[1].error, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Create account: title, rule ticks, strength bar, one loading', (tester) async {
    await _pump(tester, register: true);
    expect(find.widgetWithText(AppBar, 'Create account'), findsOneWidget);
    expect(find.text('Register'), findsNothing);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Pick a username your friends know'), findsOneWidget);
    expect(find.text('Have an account? Log in', findRichText: true), findsOneWidget);
    LinkRule290 rule(String t) => tester.widget(find.widgetWithText(LinkRule290, t));
    expect(rule('3–32 letters, numbers, . _ -').ok, isFalse);
    expect(rule('At least 8 characters').ok, isFalse);

    await tester.enterText(find.byKey(const ValueKey('auth288-username')), 'zain_ali');
    await tester.enterText(find.byKey(const ValueKey('auth288-password')), 'Zain2026!x');
    await tester.pump();
    expect(rule('3–32 letters, numbers, . _ -').ok, isTrue);
    expect(rule('At least 8 characters').ok, isTrue);
    expect(find.byKey(const ValueKey('link290-strength')), findsOneWidget);
    expect(find.text('Strong'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auth288-submit')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Creating your account…'), findsOneWidget);
  });

  test('source: the second spinner row is gone', () {
    final s = File('lib/features/authentication/presentation/screens/setup_screen.dart').readAsStringSync();
    expect(s, isNot(contains('_stage256(')));
    expect(s, isNot(contains('maxLength: 32,\n                  autocorrect')));
    expect(s, contains("'Creating your account…' : 'Signing you in…'"));
  });

  test('password strength words', () {
    expect(linkPasswordWord290(linkPasswordScore290('abc')), 'Weak');
    expect(linkPasswordWord290(linkPasswordScore290('abcdefgh1')), 'Fair');
    expect(linkPasswordWord290(linkPasswordScore290('Abcdefgh1')), 'Good');
    expect(linkPasswordWord290(linkPasswordScore290('Zain2026!x')), 'Strong');
  });
}

// Fakes: the screen only keeps these until the user is signed in.
class _Account implements AccountRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Recovery implements RecoveryRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Transfer implements AccountTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Restore implements AccountRestorationRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

abstract final class _Fake {
  static final account = _Account();
  static final store = Store211();
  static final api = Api211();
  static final recovery = _Recovery();
  static final transfer = _Transfer();
  static final restore = _Restore();
}
