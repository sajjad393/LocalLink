// Bundle 218e: what she sees — the join cards, the stuck cards, the
// Profile phone note, the admin "Joined from offline" line.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/profile_screen.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/presentation/screens/admin_users_screen.dart';
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/home/presentation/widgets/join_cards218.dart';
import 'package:locallink/features/messaging/data/services/not_on_server_218.dart';

import 'admin_test_support.dart';
import 'support/g211_fakes.dart';

class _Store extends Store211 {
  final settings = <String, String>{};
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
}

class _Account implements AccountRepositoryContract {
  @override
  Future<AccountProfileLoadResult> loadProfile() async => const AccountProfileLoadResult(
      cached: LocalProfile(
          userId: 'u-real-1',
          username: 'sumaira',
          displayName: 'Sumaira',
          phoneNumber: '03001234567'));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Transfer implements AccountTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _app(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: Column(children: [child]))));

void main() {
  setUp(() {
    OfflineAccountSyncService.resetForTest();
    NotOnServer218.instance.resetForTest();
  });
  tearDown(() {
    OfflineAccountSyncService.resetForTest();
    NotOnServer218.instance.resetForTest();
    JoinNotice218.changed.value = 0;
  });

  group('done card (U-1 / U-2)', () {
    test('the 3 texts, word for word', () {
      expect(JoinCard218.doneText(kind: 'plain', name: 'sumaira'),
          'Your account is on the server now. Your chats stay on this phone.');
      expect(JoinCard218.doneText(kind: 'renamed', name: 'sumaira37', was: 'sumaira'),
          '@sumaira was taken, so you are @sumaira37. Your chats stay on this phone.');
      expect(JoinCard218.doneText(kind: 'linked', name: 'sumaira'),
          'This phone joined your account @sumaira. Your chats stay on this phone.');
      expect(JoinCard218.doneText(kind: 'renamed', name: 'sumaira37'),
          'You are @sumaira37 on the server now. Your chats stay on this phone.',
          reason: 'the old renamed notice alone (no "was")');
    });

    testWidgets('title, phone line, Account + OK', (tester) async {
      var ok = 0, account = 0;
      await tester.pumpWidget(_app(JoinCard218.done(
          kind: 'plain',
          name: 'sumaira',
          phoneLocalOnly: true,
          onAccount: () => account++,
          onOk: () => ok++)));
      expect(find.byKey(const ValueKey('join218_done')), findsOneWidget);
      expect(find.text("You're on the server now"), findsOneWidget);
      expect(find.byKey(const ValueKey('join218_phone_line')), findsOneWidget);
      expect(find.text('Your phone number stays on this phone only.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('join218_ok')));
      await tester.tap(find.byKey(const ValueKey('join218_account')));
      expect(ok, 1);
      expect(account, 1);
    });

    testWidgets('no phone line unless the number is local only', (tester) async {
      await tester.pumpWidget(_app(JoinCard218.done(
          kind: 'linked', name: 'sumaira', onAccount: () {}, onOk: () {})));
      expect(find.byKey(const ValueKey('join218_phone_line')), findsNothing);
    });

    testWidgets('look: 16 sides, 36 icon circle, title 15 w600, body 13', (tester) async {
      await tester.pumpWidget(_app(JoinCard218.done(
          kind: 'plain', name: 'sumaira', onAccount: () {}, onOk: () {})));
      final title = tester.widget<Text>(find.text("You're on the server now"));
      expect(title.style!.fontSize, 15);
      expect(title.style!.fontWeight, FontWeight.w600);
      final body = tester.widget<Text>(find.textContaining('Your chats stay'));
      expect(body.style!.fontSize, 13);
      expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
      final card = tester.getRect(find.byKey(const ValueKey('join218_done')));
      final screen = tester.getRect(find.byType(Scaffold));
      expect(card.left - screen.left, 0, reason: 'margin is inside the card widget');
    });
  });

  group('recovery card', () {
    testWidgets('read-only code, Copy, I saved it', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      var saved = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => JoinCard218.recovery(
                      code: 'K7QM-2XPA-9TRD', context: context, onSaved: () => saved++)))));
      expect(find.byKey(const ValueKey('join218_recovery')), findsOneWidget);
      expect(find.text('K7QM-2XPA-9TRD'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
      await tester.tap(find.byKey(const ValueKey('join218_copy')));
      await tester.pump();
      expect(copied, ['K7QM-2XPA-9TRD']);
      expect(find.text('Copied'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('join218_saved')));
      expect(saved, 1);
    });
  });

  group('stuck cards (U-3)', () {
    testWidgets('phone already linked to @owner; Try again runs once with a spinner',
        (tester) async {
      final tries = <String>[];
      await tester.pumpWidget(_app(JoinCard218.stuck(
          block: 'device:@ali',
          onTry: (code) async {
            tries.add(code);
            await Future<void>.delayed(const Duration(milliseconds: 50));
          })));
      expect(find.byKey(const ValueKey('join218_stuck_device')), findsOneWidget);
      expect(find.textContaining('already linked to @ali on the server'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('join218_try')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('join218_try')));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tries, ['']);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('no proof of the same phone → "another account"', (tester) async {
      await tester.pumpWidget(_app(JoinCard218.stuck(block: 'device', onTry: (_) async {})));
      expect(find.textContaining('already linked to another account on the server'),
          findsOneWidget);
    });

    testWidgets('pairing: the typed code goes to Try again', (tester) async {
      final tries = <String>[];
      await tester.pumpWidget(
          _app(JoinCard218.stuck(block: 'pairing', onTry: (c) async => tries.add(c))));
      expect(find.byKey(const ValueKey('join218_stuck_pairing')), findsOneWidget);
      expect(find.text('The server needs a pairing code'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('join218_pair_field')), ' 1234 ');
      await tester.tap(find.byKey(const ValueKey('join218_try')));
      await tester.pump();
      expect(tries, ['1234']);
      expect(tester.getSize(find.byKey(const ValueKey('join218_pair_field'))).height, 44);
    });
  });

  group('Home wiring (source)', () {
    final src = File('lib/features/home/presentation/screens/home_screen.dart').readAsStringSync();
    test('cards first on Chats; the stuck card replaces the offline banner', () {
      expect(src, contains('..._joinCards218(),'));
      expect(src, contains('JoinCard218.stuck(block: _block218, onTry: _tryAgain218)'));
      expect(src, contains('else if (widget.store.isOfflinePending && _offlineBannerVisible)'));
      expect(src, contains('sync.tryAgainFromCard218(pairingCode: pairingCode)'));
      expect(src, contains('JoinNotice218.changed.addListener(_onJoinChanged218)'));
      expect(src, contains('JoinNotice218.changed.removeListener(_onJoinChanged218)'));
      expect(src, contains("join = {'kind': 'renamed', 'name': renamed, 'was': ''};"));
      expect(src, contains('_renamedAccountNotice'));
      expect(src.indexOf('..._joinCards218(),'),
          lessThan(src.indexOf("const MessengerGroupLabel('Conversations', top: 12)")));
    });
    test('OK and I saved it clear their settings', () {
      expect(src, contains('writeSetting(OfflineAccountSyncService.joinNoticeKey, \'\')'));
      expect(src, contains('.writeSetting(OfflineAccountSyncService.joinRecoveryKey, \'\')'));
    });
  });

  group('Profile note (U-4)', () {
    Future<_Store> pumpProfile(WidgetTester tester, {String localOnly = ''}) async {
      final store = _Store();
      if (localOnly.isNotEmpty) store.settings[LocalLinkApi.phoneLocalOnlyKey218] = localOnly;
      final mem = MemStorage211();
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: ProfileScreen(
        accountRepository: _Account(),
        api: Api211(),
        store: store,
        transferRepository: _Transfer(),
        adminCapability: capability211(mem),
      )));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return store;
    }

    testWidgets('shown when the number is the local-only one; typing hides it',
        (tester) async {
      await pumpProfile(tester, localOnly: '03001234567');
      expect(find.byKey(const ValueKey('profile_phone_local_note')), findsOneWidget);
      expect(find.text('Used by another account. Saved on this phone only.'), findsOneWidget);
      final field = find.ancestor(
          of: find.text('03001234567'), matching: find.byType(TextField));
      final border = tester.widget<TextField>(field).decoration!.enabledBorder
          as OutlineInputBorder;
      expect(border.borderSide.color, const Color(0xFFF79009));
      expect(border.borderSide.width, 1.6);
      await tester.enterText(field, '03219999999');
      await tester.pump();
      expect(find.byKey(const ValueKey('profile_phone_local_note')), findsNothing);
    });

    testWidgets('not shown otherwise', (tester) async {
      await pumpProfile(tester);
      expect(find.byKey(const ValueKey('profile_phone_local_note')), findsNothing);
    });
  });

  group('Admin app user sheet (A-5)', () {
    Future<void> openSheet(WidgetTester tester, Map<String, dynamic> user) async {
      final bloc = AdminBloc(FakeAdminRepository(), adminRole: 'owner');
      addTearDown(bloc.close);
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showUserSheet216(context, user),
                      child: const Text('open')))),
        ),
      ));
      await tester.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('the blue line only when joined_offline_at is set', (tester) async {
      await openSheet(tester, {
        'id': 'u-real-1',
        'username': 'sumaira',
        'display_name': 'Sumaira',
        'devices': 1,
        'online_devices': 1,
        'joined_offline_at': '2026-11-05T10:00:00Z',
      });
      expect(find.byKey(const ValueKey('a218_joined_offline')), findsOneWidget);
      expect(find.text('Joined from offline · 5 Nov 2026'), findsOneWidget);
      final t = tester.widget<Text>(find.text('Joined from offline · 5 Nov 2026'));
      expect(t.style!.fontSize, 12);
      expect(t.style!.fontWeight, FontWeight.w500);
    });

    testWidgets('no line for a normal account', (tester) async {
      await openSheet(tester, {'id': 'u2', 'username': 'ali', 'devices': 1});
      expect(find.byKey(const ValueKey('a218_joined_offline')), findsNothing);
    });

    test('date format', () {
      expect(joinedOffline218('2026-11-05T10:00:00Z'), '5 Nov 2026');
      expect(joinedOffline218(''), '');
      expect(joinedOffline218(null), '');
    });
  });
}
