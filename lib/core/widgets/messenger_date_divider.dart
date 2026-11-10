import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

const _months255 = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _days255 = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Bundle 255 B3: one label for chat day chips (direct + group). "9/11/2026"
/// read like 11 September, so: Today / Yesterday / "Mon 2 Nov" (last 6 days)
/// / "9 Nov" (this year) / "9 Nov 2025".
String chatDayLabel255(DateTime date, DateTime now) {
  final d = DateTime(date.year, date.month, date.day);
  final n = DateTime(now.year, now.month, now.day);
  final days = DateTime.utc(n.year, n.month, n.day)
      .difference(DateTime.utc(d.year, d.month, d.day))
      .inDays;
  final dm = '${d.day} ${_months255[d.month - 1]}';
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 1 && days <= 6) return '${_days255[d.weekday - 1]} $dm';
  if (d.year == n.year) return dm;
  return '$dm ${d.year}';
}

/// Messenger-style date separator: a small pill on the elevated surface,
/// matching the divider used by the direct chat screen ("Today" / d/m/y).
class MessengerDateDivider extends StatelessWidget {
  final DateTime date;

  const MessengerDateDivider({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final label = chatDayLabel255(date, DateTime.now());
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
