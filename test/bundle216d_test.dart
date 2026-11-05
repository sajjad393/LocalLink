// Bundle 216d: admin home (hero, map card, tool menus) and the live lock /
// unlock when the server goes and comes back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_panel_screen.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';

import 'support/g211_fakes.dart';

class _Factory implements AdminRepositoryFactory {
  @override
  AdminRepositoryContract create(String token) => const UiCheckRepository216();
}

void main() {
  setUp(AdminUiCheck216.resetForTest);

  Future<AppViewModeCubit> pump(WidgetTester tester, {required bool online}) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mem = MemStorage211();
    final cap = capability211(mem);
    await cap.store.save(oldSession211());
    final view = AppViewModeCubit()
      ..setServerConnected(online)
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
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    return view;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('online: hero, map card and the tool menus', (tester) async {
    await pump(tester, online: true);
    expect(find.byKey(const ValueKey('a216_hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('a216_map_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('a216_offline_banner')), findsNothing);
    for (final w in ['Users', 'Devices', 'Sessions', 'Calls', 'Recovery', 'Security']) {
      expect(find.text(w), findsWidgets, reason: w);
    }
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('server lost → lock; back → green banner for 3 s', (tester) async {
    final view = await pump(tester, online: true);
    view.setServerConnected(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('a216_offline_banner')), findsOneWidget);
    expect(find.text('No server right now'), findsOneWidget);
    view.setServerConnected(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('a216_offline_banner')), findsNothing);
    expect(find.text('Server is back. Tools unlocked.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('a216_back_banner')), findsNothing);
    await close(tester);
  });

  testWidgets('offline from the start: tools locked, offline tools stay', (tester) async {
    await pump(tester, online: false);
    expect(find.byKey(const ValueKey('a216_offline_banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_block_card')), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
    await close(tester);
  });
}
