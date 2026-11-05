import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/presentation/widgets/account_switch_sheet.dart';
import 'package:locallink/features/home/presentation/screens/messenger_settings_screen.dart';

import 'support/b212_fakes.dart';
import 'support/b214_fakes.dart';

String _src(String p) => File(p).readAsStringSync();

/// Bundle 214 (F5): Gmail-style switch only (me / Admin), Settings has no
/// Admin section, a normal user's photo tap opens Account.
void main() {
  setUp(() => AdminBadgeBook.instance.resetForTest());
  tearDown(() => AdminBadgeBook.instance.resetForTest());

  Future<List<AccountSwitchChoice>> sheet(WidgetTester tester,
      {bool blocked = false, bool online = true}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picks = <AccountSwitchChoice>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountSwitchSheet(
          userName: 'sajjad',
          userPeerId: null,
          session: session214(role: 'operator'),
          current: AccountSwitchPlace.user,
          online: online,
          blocked: blocked,
          onPick: picks.add,
        ),
      ),
    ));
    await tester.pump();
    return picks;
  }

  testWidgets('Admin row: crown + level, no Sign in / Sign out', (tester) async {
    final picks = await sheet(tester);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Operator'), findsOneWidget);
    expect(find.descendant(
            of: find.byKey(const ValueKey('switch_admin')),
            matching: find.byKey(const ValueKey('admin_crown'))),
        findsOneWidget);
    expect(find.textContaining('Sign'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('switch_admin')));
    expect(picks, [AccountSwitchChoice.admin]);
    expect(AccountSwitchChoice.values, [AccountSwitchChoice.user, AccountSwitchChoice.admin]);
  });

  testWidgets('my account blocked by admin: Admin row off', (tester) async {
    final picks = await sheet(tester, blocked: true);
    expect(find.text('Your account is blocked by admin'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('switch_admin')));
    expect(picks, isEmpty);
  });

  testWidgets('Settings tag "Admin · Owner" only while my card is on', (tester) async {
    final server = (await tester.runAsync(Keys212.make))!;
    final on = (await tester.runAsync(() => card214(server, user: 'u-me')))!;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsAdminTag())));
    expect(find.byKey(const ValueKey('settings_admin_tag')), findsNothing);
    AdminBadgeBook.instance
      ..setSelf(userId: 'u-me', deviceId: 'dev-me')
      ..put(AdminBadge.fromBlob(on)!);
    await tester.pump();
    expect(find.text('Admin · Owner'), findsOneWidget);
  });

  test('Settings: no Admin section, photo → sheet for admins, Account for others', () {
    final s = _src('lib/features/home/presentation/screens/messenger_settings_screen.dart');
    expect(s, isNot(contains("MessengerGroupLabel('Admin')")));
    expect(s, isNot(contains("ValueKey('settings_admin_section')")));
    expect(s, isNot(contains('AdminLoginScreen')));
    expect(s, isNot(contains("'Admin panel'")));
    expect(s, contains('onTap: () => _photoTap(context),'));
    expect(s, contains('final session = await adminCapability.readValidSession();'));
    expect(s, contains('await _openAccount(ctx);'));
    expect(s, contains('const SettingsAdminTag()'));
    // The card itself still opens Account (one way in).
    expect(s, contains('onTap: () => _openAccount(context),'));
    final sheetSrc = _src('lib/features/admin/presentation/widgets/account_switch_sheet.dart');
    expect(sheetSrc, isNot(contains('Sign in to Admin')));
    expect(sheetSrc, isNot(contains('Sign out of Admin')));
    expect(sheetSrc, isNot(contains('AdminLoginScreen')));
    expect(sheetSrc, contains('blocked: AdminBlockBook.instance.selfBlocked'));
    // Admin panel top bar switch stays (back to my chats).
    final panel = _src('lib/features/admin/presentation/screens/admin_panel_screen.dart');
    expect(panel, contains("ValueKey('admin_switch_button')"));
  });
}
