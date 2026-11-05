import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/data/services/admin_role_service.dart';
import 'package:locallink/features/admin/data/services/admin_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_panel_screen.dart';

import 'admin_test_support.dart';
import 'support/b214_fakes.dart';
import 'support/g211_fakes.dart';

String _src(String p) => File(p).readAsStringSync();

class _Repo401 extends FakeAdminRepository {
  @override
  Future<Map<String, dynamic>> summary() async =>
      throw const AdminRequestException(401, 'Admin session expired');
}

/// The old token gets 401; a new token works.
class _Factory implements AdminRepositoryFactory {
  final tokens = <String>[];
  @override
  AdminRepositoryContract create(String token) {
    tokens.add(token);
    return token == 'tok-1' ? _Repo401() : FakeAdminRepository();
  }
}

/// Bundle 214 (F6): the panel's admin session ended on the server → the
/// phone gets a new one by itself (no "sign in again"); source scans.
void main() {
  tearDown(AdminRoleService.resetForTest);

  Future<(MemStorage211, AppViewModeCubit, _Factory)> pump(
      WidgetTester tester, FakeRoleServer214 server) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mem = MemStorage211();
    final cap = capability211(mem);
    await cap.store.saveAccount('u-saj');
    await cap.store.save(oldSession211());
    final view = AppViewModeCubit()
      ..setServerConnected(true)
      ..setAdminCapability(true);
    addTearDown(view.close);
    final settings = <String, String>{};
    AdminRoleService.instance = AdminRoleService(
      capability: cap,
      read: (k) async => settings[k],
      write: (k, v) async => settings[k] = v,
      accountId: () => 'u-saj',
      signedOut: () async => false,
      server: server,
      setCapable: view.setAdminCapability,
    );
    final factory = _Factory();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Text('home')),
    ));
    nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => AdminPanelScreen(
        api: Api211(),
        store: Store211(),
        repositoryFactory: factory,
        session: oldSession211(),
        viewMode: view,
        adminCapability: cap,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    return (mem, view, factory);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('still admin: a new session, the panel opens again with it', (tester) async {
    final server = FakeRoleServer214()..session = session214(token: 'dev-tok-2');
    final (mem, view, factory) = await pump(tester, server);
    expect(server.tokensSent, ['tok-1']);
    expect(find.byType(AdminPanelScreen), findsOneWidget);
    expect(tester.widget<AdminPanelScreen>(find.byType(AdminPanelScreen)).session.token,
        'dev-tok-2');
    expect(factory.tokens, ['tok-1', 'dev-tok-2']);
    expect(mem.data['locallink_admin_session_token'], 'dev-tok-2');
    expect(view.state.adminCapable, isTrue);
    expect(find.textContaining('Sign in again'), findsNothing);
    await close(tester);
  });

  testWidgets('not admin any more: cleared, panel closes, plain message', (tester) async {
    final server = FakeRoleServer214()..mode = 'not_admin';
    final (mem, view, _) = await pump(tester, server);
    expect(find.byType(AdminPanelScreen), findsNothing);
    expect(find.text('You are no longer an admin'), findsOneWidget);
    expect(mem.data.containsKey('locallink_admin_session_token'), isFalse);
    expect(view.state.adminCapable, isFalse);
    await close(tester);
  });

  testWidgets('server gives no answer: kept, panel closes', (tester) async {
    final server = FakeRoleServer214()..mode = 'down';
    final (mem, _, _) = await pump(tester, server);
    expect(find.byType(AdminPanelScreen), findsNothing);
    expect(find.text('Admin tools are not available right now'), findsOneWidget);
    expect(mem.data['locallink_admin_session_token'], 'tok-1');
    await close(tester);
  });

  test('sources: no admin login left; Kotlin frames; old sign-ins ended on connect', () {
    expect(File('lib/features/admin/presentation/screens/admin_login_screen.dart').existsSync(),
        isFalse);
    expect(File('lib/features/admin/domain/admin_login_error.dart').existsSync(), isFalse);
    for (final dir in ['lib']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = f.readAsStringSync();
        expect(s.contains('AdminLoginScreen'), isFalse, reason: f.path);
        expect(s.contains('Sign in to Admin'), isFalse, reason: f.path);
        expect(s.contains('Sign out of Admin'), isFalse, reason: f.path);
      }
    }
    final kt = _src('android/app/src/main/kotlin/com/sajjad/locallink/mesh/MeshBlockPolicy.kt');
    expect(kt, contains('const val ADMIN_BADGE_DIGEST: String = "admin_badge_digest"'));
    expect(kt, contains('const val ADMIN_BADGE_RECORDS: String = "admin_badge_records"'));
    expect(kt, contains('|| isAdminBadge(type)'));
    final deps = _src('lib/app/app_dependencies.dart');
    expect(deps, contains('adminCapability.sendPendingRevoke('));
    final cap = _src('lib/features/admin/data/services/admin_capability_service.dart');
    expect(cap, isNot(contains('Future<bool> signOut(')));
    final panel = _src('lib/features/admin/presentation/screens/admin_panel_screen.dart');
    expect(panel, contains("roles.refresh(reason: 'panel_401')"));
    expect(panel, contains('nav.pushReplacement('));
  });
}
