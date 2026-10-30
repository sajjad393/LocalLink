import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

class LocalLinkTheme {
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: LocalLinkBrand.gradientStart,
      brightness: brightness,
    ).copyWith(
      // Brand identity (blue → cyan) carried by the scheme itself, so every
      // button, FAB, indicator and selection follows the LocalLink gradient
      // family instead of a generic Material seed palette.
      primary: dark ? const Color(0xFF8EA6FF) : LocalLinkBrand.gradientStart,
      secondary: dark ? const Color(0xFF5EEAE3) : const Color(0xFF0BB5AC),
      tertiary: dark ? const Color(0xFF23E0D8) : const Color(0xFF23A0B5),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    final divider = scheme.outlineVariant.withValues(alpha: brightness == Brightness.dark ? 0.6 : 0.72);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: base.textTheme.copyWith(
        // Every level must carry an explicit color: colorless replacements
        // render as opaque white in the light theme (invisible on white
        // surfaces) while dark mode masks the issue. See theme_audit golden.
        headlineLarge:
            LocalLinkTypography.pageTitle.copyWith(color: scheme.onSurface),
        titleLarge: TextStyle(
            color: scheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.2),
        titleMedium: TextStyle(
            color: scheme.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.2),
        titleSmall: TextStyle(
            color: scheme.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.25),
        bodyLarge:
            TextStyle(color: scheme.onSurface, fontSize: 16, height: 1.4),
        bodyMedium:
            TextStyle(color: scheme.onSurface, fontSize: 14, height: 1.4),
        bodySmall: TextStyle(
            color: scheme.onSurfaceVariant, fontSize: 12, height: 1.35),
        labelLarge: TextStyle(
            color: scheme.onSurface, fontSize: 14, fontWeight: FontWeight.w700),
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
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: dark ? 0.22 : 0.12),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: scheme.onSurfaceVariant),
        ),
        labelTextStyle: WidgetStatePropertyAll(
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
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: brightness == Brightness.dark ? 0.58 : 0.62),
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
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: 0.35)
              : null,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LocalLinkSpacing.xl),
        ),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);
}
