import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

class LocalLinkTheme {
  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brightness == Brightness.dark
          ? const Color(0xFF7C90FF)
          : const Color(0xFF4664E8),
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    final divider = scheme.outlineVariant.withOpacity(brightness == Brightness.dark ? 0.6 : 0.72);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: base.textTheme.copyWith(
        headlineLarge: LocalLinkTypography.pageTitle,
        titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2),
        titleMedium: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.2),
        titleSmall: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.4),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.4),
        bodySmall: const TextStyle(fontSize: 12, height: 1.35),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: MaterialStatePropertyAll(
          base.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.xl),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withOpacity(brightness == Brightness.dark ? 0.58 : 0.62),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LocalLinkSpacing.lg,
          vertical: LocalLinkSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          ),
          side: BorderSide(color: divider),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.md),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size.square(LocalLinkSizes.iconButton)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.md),
        ),
      ),
      dividerTheme: DividerThemeData(color: divider, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: LocalLinkSpacing.sm,
        contentPadding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.lg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LocalLinkRadius.lg)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LocalLinkRadius.pill)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);
}
