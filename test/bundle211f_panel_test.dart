import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/data/services/admin_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_panel_screen.dart';

import 'admin_test_support.dart';
import 'support/g211_fakes.dart';

/// The server says this admin sign-in is gone.
class _Repo401 extends FakeAdminRepository {
  @override
  Future<Map<String, dynamic>> summary() async =>
      throw const AdminRequestException(401, 'Admin session expired');
}

class _Factory implements AdminRepositoryFactory {
  final AdminRepositoryContract repo;
  _Factory(this.repo);
  @override
  AdminRepositoryContract create(String token) => repo;
}

void main() {
  group('211 B5 sign-in ended by the server', () {
    Future<(MemStorage211, AppViewModeCubit)> pump(WidgetTester tester,
        {required bool online}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final mem = MemStorage211();
      final cap = capability211(mem);
      await cap.store.save(oldSession211());
      final view = AppViewModeCubit()
        ..setServerConnected(online)
        ..setAdminCapability(true);
      addTearDown(view.close);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('home')),
      ));
      nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => AdminPanelScreen(
          api: Api211(),
          store: Store211(),
          repositoryFactory: _Factory(_Repo401()),
          session: oldSession211(),
          viewMode: view,
          adminCapability: cap,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      return (mem, view);
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    // Bundle 214: no "sign in again" - the phone asks for a new admin
    // session by itself. With no answer the session is kept.
    testWidgets('online + 401, no answer: kept, panel closes, plain message',
        (tester) async {
      final (mem, view) = await pump(tester, online: true);
      expect(mem.data['locallink_admin_session_token'], 'tok-1');
      expect(view.state.adminCapable, isTrue);
      expect(find.byType(AdminPanelScreen), findsNothing);
      expect(find.text('Admin tools are not available right now'), findsOneWidget);
      expect(find.textContaining('Sign in again'), findsNothing);
      await close(tester);
    });

    testWidgets('offline: never signed out', (tester) async {
      final (mem, view) = await pump(tester, online: false);
      expect(mem.data['locallink_admin_session_token'], 'tok-1');
      expect(view.state.adminCapable, isTrue);
      expect(find.byType(AdminPanelScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('admin_switch_button')), findsOneWidget);
      await close(tester);
    });
  });
}
