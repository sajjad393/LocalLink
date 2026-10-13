import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

/// Messenger-style date separator: a small pill on the elevated surface,
/// matching the divider used by the direct chat screen ("Today" / d/m/y).
class MessengerDateDivider extends StatelessWidget {
  final DateTime date;

  const MessengerDateDivider({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = now.year == date.year && now.month == date.month && now.day == date.day
        ? 'Today'
        : '${date.day}/${date.month}/${date.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LocalLinkSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LocalLinkSpacing.md,
            vertical: LocalLinkSpacing.xs,
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
      ),
    );
  }
}
