import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/l10n/l10n.dart';

class CallQualityCard extends StatelessWidget {
  final CallSession session;

  const CallQualityCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final sample = session.qualitySample;
    final details = <String>[];
    if (sample?.rttMs != null) details.add(L.t.msDelay(sample!.rttMs!.round()));
    if (sample?.jitterMs != null) details.add(L.t.msJitter(sample!.jitterMs!.round()));
    if (sample?.packetLossPercent != null) details.add(L.t.packetLoss(sample!.packetLossPercent!.toStringAsFixed(1)));
    if (session.recoveryAttempts > 0) details.add(L.t.recoveryAttempts(session.recoveryAttempts));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.lg),
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.network_check, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: LocalLinkSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t.connectionQuality, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(session.quality.label),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(details.join(' • '), style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
