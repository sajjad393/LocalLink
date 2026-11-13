import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/profile_screen.dart';
import 'package:locallink/features/recovery/presentation/screens/recovery_code_286.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';

import 'support/g211_fakes.dart';

/// Bundle 295 (F + E): the profile screen while it loads, and the gap under
/// the recovery password box.
class _Store extends Store211 {
  final settings = <String, String>{};
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
}

class _Account implements AccountRepositoryContract {
  _Account(this.saved);
  final LocalProfile? saved;
  final Completer<AccountProfileLoadResult> slow = Completer<AccountProfileLoadResult>();

  @override
  Future<LocalProfile?> cachedProfile() async => saved;

  // The server sync + refresh (6 s each when the server is off).
  @override
  Future<AccountProfileLoadResult> loadProfile() => slow.future;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _RcAccounts implements AccountRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Transfer implements AccountTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _sajjad = LocalProfile(userId: 'u-295', username: 'sajjad', displayName: 'Sajjad', phoneNumber: '03001234567');
const _noName = LocalProfile(userId: 'u-295', username: 'sumaira', displayName: '', phoneNumber: '03001234567');

void main() {
  setUp(LinkToastHub.reset);

  Future<_Account> pumpProfile(WidgetTester tester, LocalProfile? saved) async {
    final account = _Account(saved);
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: ProfileScreen(
      accountRepository: account,
      api: Api211(),
      store: _Store(),
      transferRepository: _Transfer(),
      adminCapability: capability211(MemStorage211()),
    )));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return account;
  }

  Future<void> finish(WidgetTester tester, _Account account, LocalProfile? p) async {
    account.slow.complete(AccountProfileLoadResult(cached: p));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  BrandButton290 saveButton(WidgetTester tester) =>
      tester.widget<BrandButton290>(find.byKey(const ValueKey('profile284_save')));

  testWidgets('F1 the saved profile shows at once, the slow load runs behind', (tester) async {
    final account = await pumpProfile(tester, _sajjad);
    expect(account.slow.isCompleted, isFalse);
    expect(find.text('Sajjad'), findsWidgets);
    expect(find.text('@sajjad'), findsOneWidget);
    expect(find.text('LinkUp user'), findsNothing);
    expect(find.byKey(const ValueKey('profile295_shimmer_header')), findsNothing);
    expect(find.byKey(const ValueKey('profile295_shimmer_fields')), findsNothing);
    expect(saveButton(tester).onPressed, isNotNull);
    await finish(tester, account, _sajjad);
    expect(find.text('@sajjad'), findsOneWidget);
  });

  testWidgets('F2 nothing saved yet -> shimmer, no "LinkUp user", no letter L', (tester) async {
    final account = await pumpProfile(tester, null);
    expect(find.byKey(const ValueKey('profile295_shimmer_header')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile295_shimmer_fields')), findsOneWidget);
    expect(find.text('LinkUp user'), findsNothing);
    expect(find.text('L'), findsNothing);
    expect(saveButton(tester).onPressed, isNull, reason: 'nothing to save while loading');
    await finish(tester, account, _sajjad);
    expect(find.byKey(const ValueKey('profile295_shimmer_header')), findsNothing);
    expect(find.byKey(const ValueKey('profile295_shimmer_fields')), findsNothing);
    expect(find.text('@sajjad'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('F2b reduce motion: still grey shapes, the screen settles', (tester) async {
    final account = _Account(null);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(420, 1600), disableAnimations: true),
      child: MaterialApp(
          home: ProfileScreen(
        accountRepository: account,
        api: Api211(),
        store: _Store(),
        transferRepository: _Transfer(),
        adminCapability: capability211(MemStorage211()),
      )),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('profile295_shimmer_header')), findsOneWidget);
    account.slow.complete(const AccountProfileLoadResult(cached: _sajjad));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('F3 no display name -> username without @, the grey @ line stays', (tester) async {
    final account = await pumpProfile(tester, _noName);
    expect(find.text('sumaira'), findsWidgets);
    expect(find.text('@sumaira'), findsOneWidget);
    expect(find.text('LinkUp user'), findsNothing);
    await finish(tester, account, _noName);
    expect(find.text('@sumaira'), findsOneWidget);
  });

  test('E the recovery password box has a 10 px gap above "Show my code"', () {
    final src = File('lib/features/recovery/presentation/screens/recovery_code_286.dart').readAsStringSync();
    expect(src, contains("SizedBox(key: ValueKey('rc295-gap'), height: 10)"));
  });

  testWidgets('E the button no longer touches the box (10 px)', (tester) async {
    final s = _Store();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => RecoveryCode286.open(context, store: s, accounts: _RcAccounts()),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final gap = find.byKey(const ValueKey('rc295-gap'));
    expect(gap, findsOneWidget);
    expect(tester.getSize(gap).height, 10);
    final box = tester.getRect(find.byKey(const ValueKey('rc286-password')));
    final button = tester.getRect(find.text('Show my code'));
    expect(button.top - box.bottom, greaterThanOrEqualTo(10));
  });
}
