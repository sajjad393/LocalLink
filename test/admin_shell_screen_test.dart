import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:locallink/features/admin/presentation/theme/admin_theme.dart';

import 'admin_test_support.dart';

const _session = AdminSession(
  token: 'test-token',
  expiresAt: '2099-01-01T00:00:00Z',
  adminId: 'admin-1',
  username: 'sajjad',
  role: 'owner',
);

Future<void> pumpShell(
  WidgetTester tester, {
  String role = 'owner',
  Size size = const Size(1500, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final api = LocalLinkApi(LocalStore(), WebSocketService());
  await tester.pumpWidget(MaterialApp(
    theme: AdminTheme.build(Brightness.light),
    home: AdminShellScreen(
      api: api,
      repository: FakeAdminRepository(),
      session: AdminSession(
        token: 'test-token',
        expiresAt: _session.expiresAt,
        adminId: _session.adminId,
        username: _session.username,
        role: role,
      ),
      viewMode: AppViewModeCubit(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('desktop shell shows grouped navigation and the top bar',
      (tester) async {
    await pumpShell(tester);

    // Grouped sidebar
    expect(find.text('OPERATIONS'), findsOneWidget);
    expect(find.text('CONNECTIVITY'), findsOneWidget);
    expect(find.text('TRUST & COMPLIANCE'), findsOneWidget);
    expect(find.text('PLATFORM'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Network & Mesh'), findsOneWidget);
    expect(find.text('Audit Log'), findsOneWidget);

    // Breadcrumb + chrome affordances
    expect(find.text('Administration / Dashboard'), findsOneWidget);
    expect(find.text('Overview'), findsWidgets); // page title and subtitle
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.byTooltip('Refresh data'), findsOneWidget);
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);

    // No drawer hamburger while the sidebar is pinned
    expect(find.byIcon(Icons.menu), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('owner-only modules respect the admin role', (tester) async {
    await pumpShell(tester, role: 'owner');
    expect(find.text('Admin Settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    await pumpShell(tester, role: 'auditor');
    expect(find.text('Admin Settings'), findsNothing);
    expect(find.text('Users'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact widths fall back to a drawer', (tester) async {
    await pumpShell(tester, size: const Size(700, 1400));

    expect(find.byIcon(Icons.menu), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('OPERATIONS'), findsWidgets);

    await tester.tap(find.text('Audit Log'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Administration / Audit Log'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('global search finds modules and switches to them',
      (tester) async {
    await pumpShell(tester);

    await tester.enterText(find.byType(TextField).first, 'device');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Results for "device"'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'Devices'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Administration / Devices'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('global search reports when nothing matches', (tester) async {
    await pumpShell(tester);

    await tester.enterText(find.byType(TextField).first, 'zzzz');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('No module matches that term'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('notification centre lists real security events',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Login failed'), findsWidgets);
    expect(find.text('Audit log'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('theme toggle switches the admin surface to dark',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byTooltip('Switch to light theme'), findsOneWidget);
    final context = tester.element(find.byType(Scaffold).first);
    expect(AdminPalette.isDark(context), isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('profile menu exposes identity, role and account actions',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byTooltip('Account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('sajjad'), findsWidgets);
    expect(find.text('Owner'), findsWidgets);
    expect(find.text('View as User'), findsOneWidget);
    expect(find.text('Follow app theme'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a dashboard quick action switches the shell module',
      (tester) async {
    await pumpShell(tester, size: const Size(1500, 3600));

    expect(find.text('Quick actions'), findsOneWidget);
    await tester.tap(find.text('System health'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Administration / Diagnostics'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
