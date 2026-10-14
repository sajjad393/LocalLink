import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:locallink/features/admin/presentation/theme/admin_theme.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_components.dart';

import 'admin_test_support.dart';

/// The dashboard is a long scrolling surface; tests run on a tall desktop
/// viewport so every section is laid out and can be asserted on.
Future<List<String>> pumpDashboard(WidgetTester tester, AdminBloc bloc,
    {Size size = const Size(1500, 2800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final navigated = <String>[];
  await tester.pumpWidget(MaterialApp(
    theme: AdminTheme.build(Brightness.light),
    home: BlocProvider.value(
      value: bloc,
      child: Scaffold(
        body: AdminDashboardScreen(onNavigate: navigated.add),
      ),
    ),
  ));
  // Frame 1 renders the dashboard, the post-frame callback starts the fetch,
  // and the following pumps deliver the resolved futures. pumpAndSettle is
  // never used because skeleton placeholders animate continuously.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 900));
  return navigated;
}

void main() {
  testWidgets('renders every required dashboard section', (tester) async {
    final bloc = AdminBloc(FakeAdminRepository(), adminRole: 'owner');
    addTearDown(bloc.close);

    await pumpDashboard(tester, bloc);

    // Header and section structure
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Activity analytics'), findsOneWidget);
    expect(find.text('Server health'), findsOneWidget);
    expect(find.text('Live network'), findsOneWidget);
    expect(find.text('Security overview'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Privacy boundary'), findsOneWidget);

    // Metric area uses real summary values
    expect(find.text('Total users'), findsOneWidget);
    expect(find.text('19'), findsWidgets);
    expect(find.text('Registered devices'), findsOneWidget);
    expect(find.text('Active calls'), findsOneWidget);
    expect(find.text('200.0 MB'), findsOneWidget);

    // Health, security and activity content from the server payloads
    expect(find.text('Storage'), findsWidgets);
    expect(find.text('Critical'), findsWidgets);
    expect(find.textContaining('critical alert'), findsWidgets);
    expect(find.text('FAILED LOGINS 24H'), findsOneWidget);
    // Appears in the security card and again in the merged activity feed.
    expect(find.text('Login failed'), findsWidgets);
    expect(find.text('Device registered'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changing the analytics window reloads the series',
      (tester) async {
    final repository = FakeAdminRepository();
    final bloc = AdminBloc(repository, adminRole: 'owner');
    addTearDown(bloc.close);

    await pumpDashboard(tester, bloc);
    expect(repository.lastAnalyticsRange, '24h');

    await tester.tap(find.text('7D'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.lastAnalyticsRange, '7d');
    expect(bloc.state.analyticsRange, '7d');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('respects the role when listing quick actions', (tester) async {
    final ownerBloc = AdminBloc(FakeAdminRepository(), adminRole: 'owner');
    addTearDown(ownerBloc.close);
    await pumpDashboard(tester, ownerBloc);
    // The overview header repeats the user-management entry point for owners.
    expect(find.text('Manage users'), findsWidgets);
    expect(find.text('Create backup'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    final auditorBloc = AdminBloc(FakeAdminRepository(), adminRole: 'auditor');
    addTearDown(auditorBloc.close);
    await pumpDashboard(tester, auditorBloc);
    expect(find.text('Manage users'), findsNothing);
    expect(find.text('Create backup'), findsNothing);
    expect(find.text('Audit log'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quick actions hand the target module back to the shell',
      (tester) async {
    final bloc = AdminBloc(FakeAdminRepository(), adminRole: 'owner');
    addTearDown(bloc.close);

    final navigated = await pumpDashboard(tester, bloc);
    await tester.tap(find.text('System health'));
    await tester.pump();
    expect(navigated, contains('Diagnostics'));

    await tester.tap(find.text('Open Network Topology').first);
    await tester.pump();
    expect(navigated, contains('Network & Mesh'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed section surfaces an error state with a retry',
      (tester) async {
    final repository = FakeAdminRepository(failEndpoints: {'health'});
    final bloc = AdminBloc(repository, adminRole: 'owner');
    addTearDown(bloc.close);

    await pumpDashboard(tester, bloc);

    expect(find.byType(AdminErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an expired admin session never renders stale dashboard values',
      (tester) async {
    final bloc = AdminBloc(FakeAdminRepository(unauthorized: true), adminRole: 'owner');
    addTearDown(bloc.close);

    await pumpDashboard(tester, bloc);

    expect(bloc.state.sessionExpired, isTrue);
    // Metric labels render at zero, but no server value may appear.
    expect(find.text('19'), findsNothing);
    expect(find.text('200.0 MB'), findsNothing);
    expect(find.text('Login failed'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
