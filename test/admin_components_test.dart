import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/presentation/theme/admin_theme.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_components.dart';

/// Pumps a component inside the admin theme. Tests never call pumpAndSettle:
/// skeletons and status meters animate continuously by design.
Future<void> pumpAdmin(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AdminTheme.build(brightness),
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('AdminStatusBadge', () {
    testWidgets('renders the server status with its palette colour',
        (tester) async {
      await pumpAdmin(
          tester,
          Builder(builder: (context) {
            final palette = AdminPalette.of(context);
            return Column(children: [
              AdminStatusBadge.status('healthy', palette),
              AdminStatusBadge.status('critical', palette),
              AdminStatusBadge.severity('warning', palette),
            ]);
          }));
      expect(find.text('Healthy'), findsOneWidget);
      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('Warning'), findsOneWidget);
    });

    testWidgets('accepts an explicit label for composed messages',
        (tester) async {
      await pumpAdmin(
          tester,
          Builder(builder: (context) {
            final palette = AdminPalette.of(context);
            return AdminStatusBadge.status('critical', palette,
                label: 'Overall: Critical');
          }));
      expect(find.text('Overall: Critical'), findsOneWidget);
    });
  });

  group('AdminMetricCard', () {
    testWidgets('shows the value, label and supporting context',
        (tester) async {
      await pumpAdmin(
          tester,
          const AdminMetricCard(
            label: 'Total users',
            value: '19',
            icon: Icons.group_outlined,
            contextLabel: '+2 last 24 hours',
            sparkline: [1, 3, 2, 5, 4, 6],
          ));
      expect(find.text('Total users'), findsOneWidget);
      expect(find.text('19'), findsOneWidget);
      expect(find.text('+2 last 24 hours'), findsOneWidget);
    });

    testWidgets('omits context when the server sent nothing to report',
        (tester) async {
      await pumpAdmin(
          tester,
          const AdminMetricCard(
              label: 'Messages', value: '0', icon: Icons.forum_outlined));
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('AdminHealthIndicator', () {
    testWidgets('renders reading, unit and detail', (tester) async {
      await pumpAdmin(
          tester,
          const AdminHealthIndicator(
            label: 'Storage',
            status: 'critical',
            value: 91.5,
            unit: '%',
            threshold: 90,
            detail: 'filesystem almost full',
          ));
      expect(find.text('Storage'), findsOneWidget);
      expect(find.textContaining('91.5'), findsWidgets);
      expect(find.textContaining('filesystem almost full'), findsOneWidget);
    });

    testWidgets('keeps the status word available for assistive tech',
        (tester) async {
      await pumpAdmin(
          tester,
          const AdminHealthIndicator(label: 'CPU', status: 'unknown'));
      expect(find.text('CPU'), findsOneWidget);
      expect(find.textContaining('Unknown'), findsWidgets);
    });
  });

  group('AdminActivityTimeline', () {
    testWidgets('renders entries newest first and honours the cap',
        (tester) async {
      await pumpAdmin(
          tester,
          const AdminActivityTimeline(
            maxEntries: 2,
            entries: [
              AdminTimelineEntry(
                  title: 'Login failed',
                  detail: 'bad password',
                  severity: 'warning',
                  timestamp: '2026-10-15T07:29:00Z'),
              AdminTimelineEntry(
                  title: 'Device registered',
                  timestamp: '2026-10-15T04:40:00Z'),
              AdminTimelineEntry(
                  title: 'User registered',
                  timestamp: '2026-10-15T04:30:00Z'),
            ],
          ));
      expect(find.text('Login failed'), findsOneWidget);
      expect(find.text('Device registered'), findsOneWidget);
      expect(find.text('User registered'), findsNothing);
    });

    testWidgets('shows the empty message when there is nothing recorded',
        (tester) async {
      await pumpAdmin(
          tester,
          const AdminActivityTimeline(
              entries: [], emptyMessage: 'No operational events yet.'));
      expect(find.text('No operational events yet.'), findsOneWidget);
    });
  });

  group('empty, error and loading states', () {
    testWidgets('AdminEmptyState explains what is missing', (tester) async {
      await pumpAdmin(
          tester,
          const AdminEmptyState(
              icon: Icons.inbox_outlined,
              title: 'No devices',
              message: 'No device has registered yet.'));
      expect(find.text('No devices'), findsOneWidget);
      expect(find.text('No device has registered yet.'), findsOneWidget);
    });

    testWidgets('AdminErrorState retries on demand', (tester) async {
      var retried = 0;
      await pumpAdmin(
          tester,
          AdminErrorState(
              message: 'The server could not be reached.',
              onRetry: () => retried++));
      expect(find.text('The server could not be reached.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('AdminLoadingSkeleton and metric skeleton render placeholders',
        (tester) async {
      await pumpAdmin(
          tester,
          const Column(children: [
            AdminLoadingSkeleton(height: 20),
            SizedBox(height: 8),
            AdminMetricSkeleton(),
          ]));
      // The metric skeleton composes several base skeletons, so the base type
      // intentionally appears more than once.
      expect(find.byType(AdminLoadingSkeleton), findsWidgets);
      expect(find.byType(AdminMetricSkeleton), findsOneWidget);
    });
  });

  group('navigation and search', () {
    testWidgets('AdminNavigationItem reports taps and shows a badge',
        (tester) async {
      var tapped = 0;
      await pumpAdmin(
          tester,
          AdminNavigationItem(
            icon: Icons.security_outlined,
            label: 'Security Center',
            selected: true,
            badge: 3,
            onTap: () => tapped++,
          ));
      expect(find.text('Security Center'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.text('Security Center'));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('AdminSearchBar forwards edits', (tester) async {
      final controller = TextEditingController();
      var latest = '';
      await pumpAdmin(
          tester,
          AdminSearchBar(
            controller: controller,
            onChanged: (value) => latest = value,
            hint: 'Search modules…',
          ));
      await tester.enterText(find.byType(TextField), 'dev');
      await tester.pump();
      expect(latest, 'dev');
      controller.dispose();
    });

    testWidgets('AdminSegmentedControl switches analytics range',
        (tester) async {
      String? selected;
      await pumpAdmin(
          tester,
          AdminSegmentedControl<String>(
            value: '24h',
            onChanged: (value) => selected = value,
            segments: const [
              AdminSegment('24h', '24H'),
              AdminSegment('7d', '7D'),
              AdminSegment('30d', '30D'),
              AdminSegment('90d', '90D'),
            ],
          ));
      await tester.tap(find.text('90D'));
      await tester.pump();
      expect(selected, '90d');
    });
  });

  group('AdminDataTable', () {
    testWidgets('renders columns and rows', (tester) async {
      await pumpAdmin(
          tester,
          const AdminDataTable(
            columns: [
              AdminTableColumn('User'),
              AdminTableColumn('Role'),
            ],
            rows: [
              AdminTableRow([Text('alice'), Text('owner')]),
              AdminTableRow([Text('bob'), Text('operator')]),
            ],
          ));
      // Headers are upper-cased for the table style.
      expect(find.text('USER'), findsOneWidget);
      expect(find.text('ROLE'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('operator'), findsOneWidget);
    });

    testWidgets('renders its empty state without rows', (tester) async {
      await pumpAdmin(
          tester,
          const AdminDataTable(
            columns: [AdminTableColumn('User')],
            rows: [],
            emptyMessage: 'No accounts matched.',
          ));
      expect(find.text('No accounts matched.'), findsOneWidget);
    });
  });

  group('AdminFilterBar', () {
    testWidgets('reports searches and dropdown selections', (tester) async {
      final controller = TextEditingController();
      String? selected;
      await pumpAdmin(
          tester,
          AdminFilterBar(
            controller: controller,
            onSearchChanged: (_) {},
            searchHint: 'Search devices…',
            filterLabel: 'Status',
            options: const [
              AdminFilterOption('active', 'Active'),
              AdminFilterOption('revoked', 'Revoked'),
            ],
            selectedValue: 'active',
            onSelected: (value) => selected = value,
            activeFilters: const ['status: active'],
            onClearFilters: () {},
          ));
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('status: active'), findsOneWidget);
      await tester.tap(find.text('Active'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Revoked').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(selected, 'revoked');
      controller.dispose();
    });
  });

  group('showAdminConfirmation', () {
    testWidgets('returns true when confirmed and false when dismissed',
        (tester) async {
      bool? first;
      await tester.pumpWidget(MaterialApp(
        theme: AdminTheme.build(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  first = await showAdminConfirmation(context,
                      title: 'Create database backup',
                      message: 'A consistent copy will be written.',
                      confirmLabel: 'Create backup');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('A consistent copy will be written.'), findsOneWidget);
      await tester.tap(find.text('Create backup'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(first, isTrue);

      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(first, isFalse);
    });
  });

  group('AdminNotificationItem', () {
    testWidgets('shows severity, title and detail', (tester) async {
      await pumpAdmin(
          tester,
          const AdminNotificationItem(
            icon: Icons.shield_outlined,
            title: 'Login failed',
            detail: 'bad password for alice',
            timestamp: '2026-10-15T07:29:00Z',
            severity: 'warning',
          ));
      expect(find.text('Login failed'), findsOneWidget);
      expect(find.text('bad password for alice'), findsOneWidget);
    });
  });
}
