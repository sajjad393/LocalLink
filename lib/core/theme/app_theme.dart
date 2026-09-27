import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

class LocalLinkTheme {
  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brightness == Brightness.dark
          ? const Color(0xFF6F86FF)
          : const Color(0xFF3956E8),
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: base.textTheme.copyWith(
        headlineLarge: LocalLinkTypography.pageTitle,
        titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        titleMedium: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(LocalLinkRadius.xl)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
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
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LocalLinkRadius.md)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: LocalLinkSpacing.lg, vertical: 2)),
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
