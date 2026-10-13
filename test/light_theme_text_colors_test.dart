// Regression guard for the "invisible white text in light theme" bug.
//
// The shared theme overrides replaced framework TextTheme styles with
// colorless TextStyles. Those render as opaque white in the light theme
// (invisible on white surfaces) while dark mode masks the issue. Every
// overridden style must carry an explicit, theme-aware color.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/theme/app_theme.dart';

void main() {
  test('every overridden text style carries an explicit color', () {
    for (final theme in [LocalLinkTheme.light(), LocalLinkTheme.dark()]) {
      final styles = <String, TextStyle?>{
        'headlineLarge': theme.textTheme.headlineLarge,
        'titleLarge': theme.textTheme.titleLarge,
        'titleMedium': theme.textTheme.titleMedium,
        'titleSmall': theme.textTheme.titleSmall,
        'bodyLarge': theme.textTheme.bodyLarge,
        'bodyMedium': theme.textTheme.bodyMedium,
        'bodySmall': theme.textTheme.bodySmall,
        'labelLarge': theme.textTheme.labelLarge,
      };
      for (final entry in styles.entries) {
        expect(entry.value?.color, isNotNull,
            reason:
                '${entry.key} of ${theme.brightness} must not be colorless');
      }
    }
  });

  test('light theme body text contrasts with the surface color', () {
    final theme = LocalLinkTheme.light();
    final surface = theme.scaffoldBackgroundColor;
    for (final style in [
      theme.textTheme.bodyLarge,
      theme.textTheme.bodyMedium,
      theme.textTheme.titleLarge,
      theme.textTheme.headlineLarge,
    ]) {
      expect(style!.color!.a, greaterThan(0.9),
          reason: 'text must be opaque');
      expect(style.color!.toARGB32(), isNot(surface.toARGB32()),
          reason: 'text must not match the background');
      final distance = (style.color!.r - surface.r).abs() +
          (style.color!.g - surface.g).abs() +
          (style.color!.b - surface.b).abs();
      expect(distance, greaterThan(0.5),
          reason: 'text must visibly contrast with the scaffold background');
    }
  });
}
