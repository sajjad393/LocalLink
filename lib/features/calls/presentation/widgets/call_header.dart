import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

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
    final initials = session.peerName.isEmpty ? '?' : session.peerName[0].toUpperCase();
    return Column(
      children: [
        CircleAvatar(radius: 46, child: Text(initials)),
        const SizedBox(height: 18),
        Text(session.peerName, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(statusText),
      ],
    );
  }
}
