import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/calls/presentation/widgets/call_palette.dart';
import 'package:locallink/features/calls/presentation/widgets/swipe_to_answer_button.dart';

/// Bundle 174 (approved call mock): the incoming VOICE call screen body.
///
/// Photo with a soft ring, name, "Incoming call", the bouncing green
/// swipe-up button in the middle and a small red Decline at the bottom left.
/// (The "LocalLink voice call" header above it stays in the call screen.)
class IncomingVoiceCallBody extends StatelessWidget {
  const IncomingVoiceCallBody({
    super.key,
    required this.peerName,
    required this.statusText,
    required this.onAnswer,
    required this.onDecline,
    this.peerId,
  });

  final String peerName;

  /// Bundle 204: the caller's phone id (their picture, big).
  final String? peerId;
  final String statusText;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    // Small phones: a smaller photo and a shorter swipe so nothing is cut.
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight.isFinite ? c.maxHeight : 900.0;
      final r = h < 620 ? 52.0 : 78.0;
      final base = r * 2 + 24 + 28 + 36 + 10 + 22 + 20 + 72 + 100;
      final distance = (h - base - 16).clamp(50.0, 140.0).toDouble();
      final column = _column(r, distance);
      if (h >= base + 16 + 50) return column;
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: c.maxWidth.isFinite ? c.maxWidth : 400,
          height: base + 66,
          child: column,
        ),
      );
    });
  }

  Widget _column(double radius, double distance) {
    return Column(
      children: [
        const Spacer(),
        Container(
          key: const Key('incoming_photo_ring'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: AccountAvatar(name: peerName, radius: radius, iconSize: radius * .72, peerId: peerId),
        ),
        const SizedBox(height: 28),
        Text(
          peerName.isEmpty ? 'LinkUp user' : peerName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: CallPalette.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          statusText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: CallPalette.textSecondary,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(flex: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: SizedBox(
            width: double.infinity,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                SwipeToAnswerButton(
                  distance: distance,
                  onAnswer: onAnswer,
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        color: CallPalette.red,
                        shape: const CircleBorder(),
                        child: InkWell(
                          key: const Key('incoming_decline'),
                          customBorder: const CircleBorder(),
                          onTap: onDecline,
                          child: const SizedBox(
                            width: 56,
                            height: 56,
                            child: Icon(Icons.call_end_rounded,
                                color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Decline',
                        style: TextStyle(
                            color: CallPalette.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
