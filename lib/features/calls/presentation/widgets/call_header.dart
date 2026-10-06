import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';

class CallHeader extends StatelessWidget {
  final CallSession session;
  final String statusText;

  const CallHeader({
    super.key,
    required this.session,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (session.state) {
      CallState.connected => Theme.of(context).colorScheme.primary,
      CallState.reconnecting => Theme.of(context).colorScheme.tertiary,
      CallState.failed || CallState.rejected => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AccountAvatar(name: session.peerName, radius: 52),
        const SizedBox(height: LocalLinkSpacing.lg),
        Text(
          session.peerName.isEmpty ? 'LocalLink user' : session.peerName,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: LocalLinkSpacing.xs),
        Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
