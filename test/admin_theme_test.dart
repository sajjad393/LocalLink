import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/presentation/theme/admin_theme.dart';

void main() {
  group('number and size formatting', () {
    test('scales large values', () {
      expect(adminFormatNumber(0), '0');
      expect(adminFormatNumber(19), '19');
      expect(adminFormatNumber(4210), '4210');
      expect(adminFormatNumber(12500), '12.5K');
      expect(adminFormatNumber(2400000), '2.4M');
      expect(adminFormatNumber(3100000000), '3.1B');
    });

    test('keeps fractional readings readable', () {
      expect(adminFormatNumber(91.5), '91.5');
      expect(adminFormatNumber(null), '—');
    });

    test('formats byte sizes', () {
      expect(adminFormatBytes(512), '512 B');
      expect(adminFormatBytes(2048), '2.0 KB');
      expect(adminFormatBytes(5242880), '5.0 MB');
      expect(adminFormatBytes(209715200), '200.0 MB');
      expect(adminFormatBytes(2147483648), '2.00 GB');
      expect(adminFormatBytes(null), '—');
    });

    test('formats relative time from server timestamps', () {
      final now = DateTime.utc(2026, 10, 15, 8);
      expect(adminRelativeTime('2026-10-15T07:59:40Z', now: now), 'just now');
      expect(adminRelativeTime('2026-10-15T07:45:00Z', now: now), '15m ago');
      expect(adminRelativeTime('2026-10-15T05:00:00Z', now: now), '3h ago');
      expect(adminRelativeTime('2026-10-12T08:00:00Z', now: now), '3d ago');
      expect(adminRelativeTime('2026-08-15T08:00:00Z', now: now), '2mo ago');
      expect(adminRelativeTime(null), '—');
      expect(adminRelativeTime('not-a-date'), '—');
    });

    test('labels analytics buckets by window length', () {
      final bucket = DateTime.utc(2026, 10, 15, 13).toIso8601String();
      expect(adminBucketLabel(bucket, longRange: true),
          matches(RegExp(r'^Oct 15$')));
      expect(adminBucketLabel(bucket, longRange: false),
          matches(RegExp(r'^\d{2}:00$')));
      expect(adminBucketLabel('nonsense', longRange: false), 'nonsense');
    });
  });

  group('status and severity styles', () {
    late AdminPalette light;
    late AdminPalette dark;

    setUp(() {
      light = AdminPalette.light;
      dark = AdminPalette.dark;
    });

    test('maps every health status to a distinct visual treatment', () {
      final healthy = AdminStatusStyle.of('healthy', light);
      final warning = AdminStatusStyle.of('warning', light);
      final critical = AdminStatusStyle.of('critical', light);
      final offline = AdminStatusStyle.of('offline', light);
      final unknown = AdminStatusStyle.of('nonsense', light);

      expect(healthy.foreground, light.success);
      expect(warning.foreground, light.warning);
      expect(critical.foreground, light.danger);
      expect(offline.foreground, light.textSecondary);
      expect(offline.label, 'Offline');
      expect(unknown.foreground, light.textTertiary);
      expect(unknown.label, 'Unknown');
      expect(healthy.label, 'Healthy');
      expect(critical.label, 'Critical');
    });

    test('maps severities', () {
      expect(AdminSeverityStyle.of('critical', light).foreground, light.danger);
      expect(AdminSeverityStyle.of('warning', light).foreground, light.warning);
      expect(AdminSeverityStyle.of('info', light).foreground, light.info);
    });

    test('light and dark palettes define different surfaces', () {
      expect(light.background, isNot(dark.background));
      expect(light.textPrimary, isNot(dark.textPrimary));
    });
  });

  group('breakpoints', () {
    test('classify widths', () {
      expect(AdminBreakpoints.isDesktop(1440), isTrue);
      expect(AdminBreakpoints.isLaptop(1100), isTrue);
      expect(AdminBreakpoints.isTablet(800), isTrue);
      expect(AdminBreakpoints.isCompact(600), isTrue);
      expect(AdminBreakpoints.isDesktop(900), isFalse);
    });
  });

  testWidgets('AdminTheme.build produces a themed Material surface',
      (tester) async {
    Future<void> pumpWith(Brightness brightness) async {
      await tester.pumpWidget(MaterialApp(
        theme: AdminTheme.build(brightness),
        home: const Scaffold(body: SizedBox()),
      ));
      // MaterialApp animates between themes, so let the transition finish.
      await tester.pump(const Duration(milliseconds: 400));
    }

    await pumpWith(Brightness.light);
    var context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(AdminPalette.isDark(context), isFalse);
    expect(AdminPalette.of(context).surface, AdminPalette.light.surface);

    await pumpWith(Brightness.dark);
    context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(AdminPalette.isDark(context), isTrue);
    expect(AdminPalette.of(context).surface, AdminPalette.dark.surface);
  });
}
