import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

import 'package:locallink/features/calls/data/models/call_session.dart';

class CallQualityCard extends StatelessWidget {
  final CallSession session;

  const CallQualityCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final sample = session.qualitySample;
    final details = <String>[];
    if (sample?.rttMs != null) details.add('RTT ${sample!.rttMs!.round()} ms');
    if (sample?.jitterMs != null) details.add('Jitter ${sample!.jitterMs!.round()} ms');
    if (sample?.packetLossPercent != null) {
      details.add('Loss ${sample!.packetLossPercent!.toStringAsFixed(1)}%');
    }
    if (session.recoveryAttempts > 0) {
      details.add('Recoveries ${session.recoveryAttempts}');
    }
    if (!session.signalingConnected) details.add('Signaling offline');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LocalLinkRadius.md),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Text(
            'Connection: ${session.quality.label}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              details.join(' • '),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
