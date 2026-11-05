import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/widgets/account_switch_sheet.dart';

import 'admin_test_support.dart';
import 'support/g211_fakes.dart';

String _src(String p) => File(p).readAsStringSync();

class _Factory214 implements AdminRepositoryFactory {
  final AdminRepositoryContract repo;
  _Factory214(this.repo);
  @override
  AdminRepositoryContract create(String token) => repo;
}

void _view(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<List<AccountSwitchChoice>> _sheet(WidgetTester tester,
    {AdminSession? session,
    bool online = true,
    AccountSwitchPlace current = AccountSwitchPlace.user}) async {
  _view(tester);
  final picks = <AccountSwitchChoice>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AccountSwitchSheet(
        userName: 'sajjad',
        userPeerId: null,
        session: session,
        current: current,
        online: online,
        onPick: picks.add,
      ),
    ),
  ));
  await tester.pump();
  return picks;
}

void main() {
  // Bundle 214: rewritten - me / Admin only (no Sign in / Sign out rows).
  group('211 C sheet rows', () {
    testWidgets('admin: me + Admin, tick on me, no sign-in/out rows', (tester) async {
      final picks = await _sheet(tester, session: oldSession211());
      expect(find.text('sajjad'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.byKey(const ValueKey('switch_admin_signout')), findsNothing);
      expect(find.byKey(const ValueKey('switch_admin_signin')), findsNothing);
      expect(find.textContaining('Sign out'), findsNothing);
      expect(find.textContaining('Sign in'), findsNothing);
      final userTile = find.byKey(const ValueKey('switch_user'));
      expect(find.descendant(of: userTile, matching: find.byIcon(Icons.check_circle)),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('switch_admin')));
      await tester.tap(find.byKey(const ValueKey('switch_user')));
      expect(picks, [AccountSwitchChoice.admin, AccountSwitchChoice.user]);
    });

    testWidgets('admin and offline: Admin still there (offline tools)',
        (tester) async {
      await _sheet(tester,
          session: oldSession211(), online: false, current: AccountSwitchPlace.admin);
      expect(find.text('Owner · Offline tools only · block, app version'), findsOneWidget);
      final adminTile = find.byKey(const ValueKey('switch_admin'));
      expect(find.descendant(of: adminTile, matching: find.byIcon(Icons.check_circle)),
          findsOneWidget);
    });

    testWidgets('not admin: only me (online or offline)', (tester) async {
      for (final online in [true, false]) {
        final picks = await _sheet(tester, online: online);
        expect(find.byKey(const ValueKey('switch_admin')), findsNothing);
        expect(find.byKey(const ValueKey('switch_admin_signin')), findsNothing);
        expect(find.byKey(const ValueKey('switch_admin_offline')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('switch_user')));
        expect(picks, [AccountSwitchChoice.user]);
      }
    });
  });

  group('211 C flow', () {
    testWidgets('Admin opens the panel with no password', (tester) async {
      _view(tester);
      final mem = MemStorage211();
      final cap = capability211(mem);
      await cap.store.save(oldSession211());
      final view = AppViewModeCubit()..setServerConnected(false);
      addTearDown(view.close);
      final deps = AccountSwitchDeps(
        api: Api211(),
        store: Store211(),
        viewMode: view,
        adminCapability: cap,
        repositoryFactory: _Factory214(FakeAdminRepository()),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () => showAccountSwitchSheet(context,
                  deps: deps, current: AccountSwitchPlace.user),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('switch_sheet')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('switch_admin')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(view.state.adminCapable, isTrue);
      expect(find.byKey(const ValueKey('admin_switch_button')), findsOneWidget);
      expect(mem.data['locallink_admin_session_token'], 'tok-1');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('211 C sources', () {
    test('Settings photo opens the sheet; Admin AppBar has the switch', () {
      final settings = _src(
          'lib/features/home/presentation/screens/messenger_settings_screen.dart');
      expect(settings, contains("ValueKey('settings_avatar_switch')"));
      expect(settings, contains('current: AccountSwitchPlace.user);')); // Bundle 214
      // the card still opens Account
      expect(settings, contains('onTap: () => _openAccount(context),'));
      final panel = _src(
          'lib/features/admin/presentation/screens/admin_panel_screen.dart');
      expect(panel, contains("ValueKey('admin_switch_button')"));
      expect(panel, contains('current: AccountSwitchPlace.admin'));
      // Bundle 214: no login screen; the photo opens the sheet for admins.
      expect(File('lib/features/admin/presentation/screens/admin_login_screen.dart').existsSync(), isFalse);
    });

    test('opening Admin needs no password', () {
      final sheet = _src(
          'lib/features/admin/presentation/widgets/account_switch_sheet.dart');
      expect(sheet, contains('await openAdminPanel(nav, deps, session);'));
      expect(sheet, contains('if (current == AccountSwitchPlace.admin) nav.pop();'));
    });
  });
}
