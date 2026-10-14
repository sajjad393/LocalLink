import 'package:flutter/material.dart';

/// Centralised, semantic design tokens for the LocalLink administration
/// surface. Widgets must never hard-code colours — they read the palette that
/// matches the active brightness so light and dark stay in step.
@immutable
class AdminPalette {
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceRaised;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color primarySoft;
  final Color onPrimary;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color hover;
  final Color selected;
  final Color sidebar;
  final Color topbar;
  final Color chartGrid;
  final Color shadow;

  const AdminPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceRaised,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.primarySoft,
    required this.onPrimary,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.hover,
    required this.selected,
    required this.sidebar,
    required this.topbar,
    required this.chartGrid,
    required this.shadow,
  });

  static const light = AdminPalette(
    background: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF2F4F7),
    surfaceRaised: Color(0xFFFFFFFF),
    border: Color(0xFFE2E6EC),
    borderStrong: Color(0xFFCFD6E0),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF5B6472),
    textTertiary: Color(0xFF8B93A1),
    primary: Color(0xFF1E5BFF),
    primarySoft: Color(0xFFE8EEFF),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF0F7B52),
    successSoft: Color(0xFFE4F5EC),
    warning: Color(0xFF9A5B06),
    warningSoft: Color(0xFFFDF1DD),
    danger: Color(0xFFB42318),
    dangerSoft: Color(0xFFFDEBE9),
    info: Color(0xFF0B5FA5),
    infoSoft: Color(0xFFE7F1FB),
    hover: Color(0x0A111827),
    selected: Color(0x141E5BFF),
    sidebar: Color(0xFFFFFFFF),
    topbar: Color(0xFFFFFFFF),
    chartGrid: Color(0xFFE8EBF0),
    shadow: Color(0x14101828),
  );

  static const dark = AdminPalette(
    background: Color(0xFF0D1014),
    surface: Color(0xFF151920),
    surfaceMuted: Color(0xFF1B2029),
    surfaceRaised: Color(0xFF1D222B),
    border: Color(0xFF262C36),
    borderStrong: Color(0xFF343C48),
    textPrimary: Color(0xFFE8EDF4),
    textSecondary: Color(0xFF9CA6B5),
    textTertiary: Color(0xFF6B7686),
    primary: Color(0xFF5B8CFF),
    primarySoft: Color(0xFF1D2740),
    onPrimary: Color(0xFF08111F),
    success: Color(0xFF3ED598),
    successSoft: Color(0xFF14301F),
    warning: Color(0xFFE9A94F),
    warningSoft: Color(0xFF33260F),
    danger: Color(0xFFF0776C),
    dangerSoft: Color(0xFF361A18),
    info: Color(0xFF6FAEF0),
    infoSoft: Color(0xFF12273B),
    hover: Color(0x14FFFFFF),
    selected: Color(0x1F5B8CFF),
    sidebar: Color(0xFF11151B),
    topbar: Color(0xFF11151B),
    chartGrid: Color(0xFF232932),
    shadow: Color(0x40000000),
  );

  static AdminPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}

/// Spacing rhythm for the admin surface. A 4pt base keeps dense operational
/// layouts consistent without the oversized gaps of the consumer app.
abstract final class AdminSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const page = 24.0;
  static const section = 20.0;
}

/// Corner radii — deliberately restrained so panels read as software, not as a
/// collection of floating pills.
abstract final class AdminRadius {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 12.0;
  static const pill = 999.0;
}

abstract final class AdminSizes {
  static const sidebar = 248.0;
  static const sidebarCompact = 76.0;
  static const topbar = 60.0;
  static const metricCardMinWidth = 216.0;
  static const panelMinWidth = 340.0;
}

/// Layout breakpoints. Desktop keeps a permanent sidebar, laptops a compact
/// rail, tablets a drawer, and phones a single-column flow.
abstract final class AdminBreakpoints {
  static const desktop = 1240.0;
  static const laptop = 1000.0;
  static const tablet = 720.0;

  static bool isDesktop(double width) => width >= desktop;
  static bool isLaptop(double width) => width >= laptop && width < desktop;
  static bool isTablet(double width) => width >= tablet && width < laptop;
  static bool isCompact(double width) => width < tablet;
}

/// Typography for the admin surface. Sizes are intentionally smaller than the
/// consumer app: information density is the point.
abstract final class AdminText {
  static const metricValue = TextStyle(
      fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.1);
  static const metricLabel = TextStyle(
      fontSize: 12.5, fontWeight: FontWeight.w500, letterSpacing: 0.1, height: 1.2);
  static const pageTitle =
      TextStyle(fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.2);
  static const sectionTitle =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1);
  static const cardTitle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontSize: 13.5, height: 1.45);
  static const bodyStrong =
      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4);
  static const caption = TextStyle(fontSize: 12, height: 1.35);
  static const label = TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, height: 1.2);
  static const tableHeader = TextStyle(
      fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3);
  static const mono = TextStyle(
      fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()], height: 1.4);
}

/// Builds the Flutter theme used by the admin surface for either brightness.
abstract final class AdminTheme {
  static ThemeData build(Brightness brightness) {
    final palette = brightness == Brightness.dark
        ? AdminPalette.dark
        : AdminPalette.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      secondary: palette.info,
      onSecondary: palette.onPrimary,
      error: palette.danger,
      onError: palette.onPrimary,
      surface: palette.surface,
      onSurface: palette.textPrimary,
    );

    TextStyle apply(TextStyle style) => style.copyWith(color: palette.textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.surface,
      dividerColor: palette.border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
        displaySmall: apply(AdminText.metricValue),
        titleLarge: apply(AdminText.pageTitle),
        titleMedium: apply(AdminText.sectionTitle),
        titleSmall: apply(AdminText.cardTitle),
        bodyMedium: apply(AdminText.body),
        bodySmall: apply(AdminText.caption).copyWith(color: palette.textSecondary),
        labelLarge: apply(AdminText.bodyStrong),
        labelMedium: apply(AdminText.label).copyWith(color: palette.textSecondary),
        labelSmall: apply(AdminText.label).copyWith(color: palette.textTertiary),
      ),
      iconTheme: IconThemeData(color: palette.textSecondary, size: 20),
      dividerTheme: DividerThemeData(
          color: palette.border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminRadius.lg),
          side: BorderSide(color: palette.border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.topbar,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: AdminSizes.topbar,
        shape: Border(bottom: BorderSide(color: palette.border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: palette.surfaceMuted,
        hintStyle: AdminText.body.copyWith(color: palette.textTertiary),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AdminSpace.md, vertical: AdminSpace.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminRadius.sm),
          borderSide: BorderSide(color: palette.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          textStyle: AdminText.bodyStrong,
          padding: const EdgeInsets.symmetric(
              horizontal: AdminSpace.lg, vertical: AdminSpace.md),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AdminRadius.sm)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          textStyle: AdminText.bodyStrong,
          padding: const EdgeInsets.symmetric(
              horizontal: AdminSpace.md, vertical: AdminSpace.sm),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.borderStrong),
          textStyle: AdminText.bodyStrong,
          padding: const EdgeInsets.symmetric(
              horizontal: AdminSpace.lg, vertical: AdminSpace.md),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AdminRadius.sm)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.textSecondary,
          highlightColor: palette.hover,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AdminRadius.sm)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceMuted,
        side: BorderSide(color: palette.border),
        labelStyle: AdminText.caption.copyWith(
            color: palette.textSecondary, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AdminRadius.pill)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: brightness == Brightness.dark
              ? const Color(0xFF2A313B)
              : const Color(0xFF1F2733),
          borderRadius: BorderRadius.circular(AdminRadius.xs),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            brightness == Brightness.dark ? palette.surfaceRaised : const Color(0xFF1F2733),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AdminRadius.sm)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminRadius.lg),
          side: BorderSide(color: palette.border),
        ),
        titleTextStyle: AdminText.sectionTitle.copyWith(color: palette.textPrimary),
        contentTextStyle: AdminText.body.copyWith(color: palette.textSecondary),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(palette.borderStrong),
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: palette.sidebar,
        indicatorColor: palette.selected,
      ),
    );
  }
}

/// Semantic status presentation (used by badges, health rows and timelines).
@immutable
class AdminStatusStyle {
  final Color foreground;
  final Color background;
  final String label;

  const AdminStatusStyle(this.foreground, this.background, this.label);

  static AdminStatusStyle of(String status, AdminPalette palette) {
    switch (status.toLowerCase()) {
      case 'healthy':
      case 'ok':
      case 'active':
      case 'online':
      case 'connected':
      case 'success':
        return AdminStatusStyle(palette.success, palette.successSoft, 'Healthy');
      case 'warning':
      case 'warn':
      case 'degraded':
      case 'pending':
        return AdminStatusStyle(palette.warning, palette.warningSoft, 'Warning');
      case 'critical':
      case 'error':
      case 'failed':
        return AdminStatusStyle(palette.danger, palette.dangerSoft, 'Critical');
      case 'offline':
      case 'disconnected':
      case 'revoked':
        return AdminStatusStyle(
            palette.textSecondary, palette.surfaceMuted, 'Offline');
      default:
        return AdminStatusStyle(
            palette.textTertiary, palette.surfaceMuted, 'Unknown');
    }
  }
}

/// Severity presentation for security events and activity entries.
@immutable
class AdminSeverityStyle {
  final Color foreground;
  final Color background;
  final IconData icon;

  const AdminSeverityStyle(this.foreground, this.background, this.icon);

  static AdminSeverityStyle of(String severity, AdminPalette palette) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return AdminSeverityStyle(
            palette.danger, palette.dangerSoft, Icons.error_outline);
      case 'warning':
        return AdminSeverityStyle(
            palette.warning, palette.warningSoft, Icons.warning_amber_rounded);
      default:
        return AdminSeverityStyle(
            palette.info, palette.infoSoft, Icons.info_outline);
    }
  }
}

/// Formats a metric value using the scale the server sent.
String adminFormatNumber(num? value) {
  if (value == null) return '—';
  final v = value.toDouble();
  if (v.isNaN) return '—';
  if (v.abs() >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}B';
  if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v.abs() >= 10000) return '${(v / 1000).toStringAsFixed(1)}K';
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}

/// Byte sizes for storage and database readings.
String adminFormatBytes(num? value) {
  if (value == null) return '—';
  final v = value.toDouble();
  if (v < 1024) return '${v.toStringAsFixed(0)} B';
  if (v < 1048576) return '${(v / 1024).toStringAsFixed(1)} KB';
  if (v < 1073741824) return '${(v / 1048576).toStringAsFixed(1)} MB';
  if (v < 1099511627776) return '${(v / 1073741824).toStringAsFixed(2)} GB';
  return '${(v / 1099511627776).toStringAsFixed(2)} TB';
}

/// Compact relative time ("4m ago") for feeds and health stamps.
String adminRelativeTime(String? isoTimestamp, {DateTime? now}) {
  if (isoTimestamp == null || isoTimestamp.isEmpty) return '—';
  final parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return '—';
  final reference = (now ?? DateTime.now()).toUtc();
  final difference = reference.difference(parsed.toUtc());
  if (difference.isNegative) return 'just now';
  if (difference.inSeconds < 45) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 30) return '${difference.inDays}d ago';
  if (difference.inDays < 365) return '${(difference.inDays / 30).floor()}mo ago';
  return '${(difference.inDays / 365).floor()}y ago';
}

/// Formats an ISO bucket timestamp for chart axes.
String adminBucketLabel(String isoTimestamp, {required bool longRange}) {
  final parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return isoTimestamp;
  final local = parsed.toLocal();
  if (longRange) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[local.month - 1]} ${local.day}';
  }
  final hh = local.hour.toString().padLeft(2, '0');
  return '$hh:00';
}
