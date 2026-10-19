import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/widgets/call_palette.dart';

/// WhatsApp-style audio-call header: large centered avatar, peer name and the
/// live status (ringing state or call timer) in WhatsApp call colors.
class CallHeader extends StatelessWidget {
  final CallSession session;
  final String statusText;

  const CallHeader({
    super.key,
    required this.session,
    required this.statusText,
  });

  static Color statusColorFor(CallSession session) => switch (session.state) {
        CallState.connected => CallPalette.green,
        CallState.reconnecting => CallPalette.amber,
        CallState.failed || CallState.rejected => CallPalette.red,
        _ => CallPalette.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AccountAvatar(name: session.peerName, radius: 78, iconSize: 56),
        const SizedBox(height: 28),
        Text(
          session.peerName.isEmpty ? 'LocalLink user' : session.peerName,
          style: const TextStyle(
            color: CallPalette.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          statusText,
          style: TextStyle(
            color: statusColorFor(session),
            fontSize: 17,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
