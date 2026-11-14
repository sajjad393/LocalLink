import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/l10n/l10n.dart';

List<String> get _months255 => [
  L.t.jan, L.t.feb, L.t.mar, L.t.apr, L.t.may, L.t.jun,
  L.t.jul, L.t.aug, L.t.sep, L.t.oct, L.t.nov, L.t.dec,
];
List<String> get _days255 => [L.t.mon, L.t.tue, L.t.wed, L.t.thu, L.t.fri, L.t.sat, L.t.sun];

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
  if (days == 0) return L.t.today;
  if (days == 1) return L.t.yesterday;
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
