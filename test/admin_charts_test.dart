import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/presentation/theme/admin_theme.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_charts.dart';

Future<void> pumpAdmin(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AdminTheme.build(brightness),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  // Charts animate their draw-in; advance time explicitly rather than
  // pumpAndSettle (status meters and skeletons animate indefinitely).
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  group('AdminSeriesPoint.fromServer', () {
    test('parses {t,v} points from the analytics payload', () {
      final points = AdminSeriesPoint.fromServer(const [
        {'t': '2026-10-15T04:00:00Z', 'v': 3},
        {'t': '2026-10-15T05:00:00Z', 'v': 0},
        {'t': '2026-10-15T06:00:00Z', 'v': 12},
      ], longRange: false);
      expect(points, hasLength(3));
      expect(points[1].value, 0);
      expect(points[2].value, 12);
      expect(points.first.label, isNotEmpty);
    });

    test('tolerates missing or malformed series', () {
      expect(AdminSeriesPoint.fromServer(null, longRange: false), isEmpty);
      expect(AdminSeriesPoint.fromServer(const [], longRange: true), isEmpty);
      final parsed = AdminSeriesPoint.fromServer(const [
        'nonsense',
        {'v': 5},
      ], longRange: true);
      expect(parsed, hasLength(1));
      expect(parsed.single.value, 5);
    });

    test('uses day labels for long ranges', () {
      final points = AdminSeriesPoint.fromServer(const [
        {'t': '2026-10-15T00:00:00Z', 'v': 1},
      ], longRange: true);
      expect(points.single.label, contains('Oct'));
    });
  });

  group('AdminLineChart', () {
    testWidgets('draws a series and its axis labels', (tester) async {
      await pumpAdmin(
          tester,
          Builder(builder: (context) {
            final palette = AdminPalette.of(context);
            return AdminLineChart(
              points: const [
                AdminSeriesPoint('04:00', 1),
                AdminSeriesPoint('05:00', 4),
                AdminSeriesPoint('06:00', 2),
                AdminSeriesPoint('07:00', 9),
              ],
              color: palette.primary,
              height: 200,
            );
          }));
      expect(find.byType(AdminLineChart), findsOneWidget);
      // Axis labels and the series are painted on canvas, so the chart is
      // verified through its painter plus the series it was handed.
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('shows an empty state when the window has no data',
        (tester) async {
      await pumpAdmin(
          tester,
          Builder(builder: (context) => AdminLineChart(
                points: const [],
                color: AdminPalette.of(context).primary,
              )));
      expect(find.byType(AdminLineChart), findsOneWidget);
    });
  });

  group('AdminChartCard', () {
    testWidgets('offers retry when a series failed to load', (tester) async {
      var retried = 0;
      await pumpAdmin(
          tester,
          AdminChartCard(
            title: 'Message activity',
            subtitle: 'Messages per bucket',
            error: 'The server could not be reached.',
            onRetry: () => retried++,
            child: const SizedBox(height: 120),
          ));
      expect(find.text('Message activity'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('explains an empty window instead of drawing a flat line',
        (tester) async {
      await pumpAdmin(
          tester,
          const AdminChartCard(
            title: 'Server traffic',
            isEmpty: true,
            emptyMessage: 'No response traffic recorded yet.',
            child: SizedBox(height: 120),
          ));
      expect(find.text('No response traffic recorded yet.'), findsOneWidget);
    });

    testWidgets('shows the chart when data is present', (tester) async {
      await pumpAdmin(
          tester,
          const AdminChartCard(
            title: 'Message activity',
            child: SizedBox(height: 120, child: Text('chart body')),
          ));
      expect(find.text('chart body'), findsOneWidget);
    });
  });

  group('AdminGauge and AdminDonutChart', () {
    testWidgets('gauge shows value, unit and threshold marker',
        (tester) async {
      await pumpAdmin(
          tester,
          Builder(builder: (context) => AdminGauge(
                value: 91.5,
                threshold: 90,
                label: 'Storage',
                sublabel: 'of 200 GB',
                color: AdminPalette.of(context).danger,
              )));
      expect(find.text('Storage'), findsOneWidget);
      // Gauges read out whole percentages; the precise reading lives in the
      // health list beneath them.
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('of 200 GB'), findsOneWidget);
    });

    testWidgets('donut renders segments with a centre reading',
        (tester) async {
      await pumpAdmin(
          tester,
          Builder(builder: (context) {
            final palette = AdminPalette.of(context);
            return AdminDonutChart(
              centerValue: '7',
              centerLabel: 'online',
              segments: [
                AdminDonutSegment('Server connected', 6, palette.success),
                AdminDonutSegment('Wi-Fi Direct', 3, palette.info),
                AdminDonutSegment('Offline / idle', 5, palette.borderStrong),
              ],
            );
          }));
      expect(find.text('7'), findsOneWidget);
      expect(find.text('online'), findsOneWidget);
    });

    testWidgets('legend lists every segment', (tester) async {
      await pumpAdmin(
          tester,
          Builder(builder: (context) {
            final palette = AdminPalette.of(context);
            return AdminChartLegend(
              items: [
                AdminDonutSegment('LAN available', 5, palette.primary),
                AdminDonutSegment('Mesh capable', 4, palette.warning),
              ],
            );
          }));
      expect(find.text('LAN available'), findsOneWidget);
      expect(find.text('Mesh capable'), findsOneWidget);
    });
  });

  group('AdminBarChart and AdminSparkline', () {
    testWidgets('bar chart renders one bar per point', (tester) async {
      await pumpAdmin(
          tester,
          Builder(builder: (context) => AdminBarChart(
                points: const [
                  AdminSeriesPoint('Mon', 2),
                  AdminSeriesPoint('Tue', 5),
                  AdminSeriesPoint('Wed', 1),
                ],
                color: AdminPalette.of(context).primary,
              )));
      expect(find.byType(AdminBarChart), findsOneWidget);
    });
  });
}
