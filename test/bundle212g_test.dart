import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_block_users_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_blocked_list_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_panel_screen.dart';

import 'admin_test_support.dart';
import 'support/g211_fakes.dart';

class _Factory implements AdminRepositoryFactory {
  @override
  AdminRepositoryContract create(String token) => FakeAdminRepository();
}

/// Bundle 212 (H1 g, E1/E5): the Admin panel card "Block users (all phones)".
void main() {
  setUp(AdminBlockBook.instance.resetForTest);

  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mem = MemStorage211();
    final cap = capability211(mem);
    await cap.store.save(oldSession211());
    final view = AppViewModeCubit()
      ..setServerConnected(false)
      ..setAdminCapability(true);
    addTearDown(view.close);
    await tester.pumpWidget(MaterialApp(
      home: AdminPanelScreen(
        api: Api211(),
        store: Store211(),
        repositoryFactory: _Factory(),
        session: oldSession211(),
        viewMode: view,
        adminCapability: cap,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> show(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  testWidgets('card: status line + 3 rows; not ready says connect once', (tester) async {
    await pumpPanel(tester);
    await show(tester, find.byKey(const ValueKey('admin_block_card')));
    expect(find.text('Block users (all phones)'), findsOneWidget);
    expect(find.text('Block or unblock a user'), findsOneWidget);
    expect(find.text('Blocked by admin'), findsOneWidget);
    expect(find.text('Blocked on this phone'), findsOneWidget);
    expect(find.text('Connect to the server once to turn on offline blocking'), findsOneWidget);
    expect(find.text('Local moderation'), findsNothing);
    await close(tester);
  });

  testWidgets('pick row opens the picker', (tester) async {
    await pumpPanel(tester);
    await show(tester, find.byKey(const ValueKey('admin_block_pick')));
    await tester.tap(find.byKey(const ValueKey('admin_block_pick')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AdminBlockUsersScreen), findsOneWidget);
    await close(tester);
  });

  testWidgets('blocked-by-admin row opens the list', (tester) async {
    await pumpPanel(tester);
    await show(tester, find.byKey(const ValueKey('admin_block_list')));
    await tester.tap(find.byKey(const ValueKey('admin_block_list')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AdminBlockedListScreen), findsOneWidget);
    await close(tester);
  });

  test('panel: nearby Block goes to everyone, map shows blocked + expand', () {
    final s = File('lib/features/admin/presentation/screens/admin_panel_screen.dart').readAsStringSync();
    expect(s, contains('onPressed: () => _networkBlock(d, block: true)'));
    expect(s, contains('blocked: _adminBlocked(d)'));
    expect(s, contains('onExpand: () => _openFullMap(devices, online)'));
    // falls back to the old block on this phone until offline blocking is ready
    expect(s, contains('if (block) return _confirmBlock(d);'));
  });
}
