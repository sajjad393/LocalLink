import 'package:flutter/material.dart';

import 'package:locallink/features/calls/bloc/call_bloc.dart' hide CallState;
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/widgets/call_palette.dart';

/// WhatsApp-style call controls.
///
/// Incoming ringing: green Answer + red Decline circles with labels.
/// In-call (identical on both the caller and the receiver side): a dark pill
/// with mute and speaker and a large red End button.
/// Bundle 248: the camera button is back (hidden since bundle 97) for a
/// connected nearby call (Wi-Fi Direct / LAN). The receive side ("Switch to
/// video call?") is unchanged.
class CallActionBar extends StatelessWidget {
  final CallBloc controller;
  final CallSession session;

  const CallActionBar({
    super.key,
    required this.controller,
    required this.session,
  });

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final incoming = session.direction == CallDirection.incoming &&
        session.state == CallState.ringing;

    if (incoming) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallCircleButton(
              icon: Icons.call_end_rounded,
              background: CallPalette.red,
              foreground: Colors.white,
              size: 68,
              label: 'Decline',
              onPressed: () => _run(controller.rejectIncoming),
            ),
            _CallCircleButton(
              icon: Icons.call_rounded,
              background: CallPalette.green,
              foreground: Colors.white,
              size: 68,
              label: 'Answer',
              onPressed: () => _run(controller.acceptIncoming),
            ),
          ],
        ),
      );
    }

    if (session.isFinished) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text(
            'Close',
            style:
                TextStyle(color: CallPalette.textSecondary, fontSize: 15),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 26),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: CallPalette.pill,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallToggleButton(
              icon: session.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              active: session.muted,
              tooltip: session.muted ? 'Unmute' : 'Mute',
              onPressed: () => _run(controller.toggleMute),
            ),
            _CallToggleButton(
              icon: session.speakerOn
                  ? Icons.volume_up_rounded
                  : Icons.phone_in_talk_rounded,
              active: session.speakerOn,
              tooltip: session.speakerOn ? 'Speaker off' : 'Speaker on',
              onPressed: () => _run(controller.toggleSpeaker),
            ),
            if (showVideoButton248(session))
              _CallToggleButton(
                key: const Key('call_video_toggle_248'),
                icon: session.videoEnabled
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                active: session.videoEnabled,
                tooltip: session.videoEnabled ? 'Turn camera off' : 'Turn camera on',
                // Errors show as the call screen's snackbar (CallBloc error).
                onPressed: () => _run(controller.toggleVideo),
              ),
            _CallCircleButton(
              icon: Icons.call_end_rounded,
              background: CallPalette.red,
              foreground: Colors.white,
              size: 60,
              label: null,
              onPressed: () => _run(controller.endCall),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bundle 248: the camera button shows only in a connected nearby call.
bool showVideoButton248(CallSession session) =>
    session.state == CallState.connected && session.directMode && !session.isFinished;

class _CallCircleButton extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;
  final String? label;
  final Future<void> Function() onPressed;

  const _CallCircleButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.size,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: foreground, size: size * 0.44),
        ),
      ),
    );
    if (label == null) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 10),
        Text(
          label!,
          style: const TextStyle(color: CallPalette.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}

class _CallToggleButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool enabled;
  final String tooltip;
  final Future<void> Function() onPressed;

  const _CallToggleButton({
    super.key,
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final background =
        active ? CallPalette.controlActive : CallPalette.controlInactive;
    final foreground =
        active ? CallPalette.controlActiveIcon : Colors.white;
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(icon, color: foreground, size: 25),
            ),
          ),
        ),
      ),
    );
  }
}
