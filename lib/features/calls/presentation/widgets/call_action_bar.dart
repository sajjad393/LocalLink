import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' hide CallState;
import 'package:locallink/features/calls/data/models/call_session.dart';

class CallActionBar extends StatelessWidget {
  final CallBloc controller;
  final CallSession session;

  const CallActionBar({
    super.key,
    required this.controller,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final incoming = session.direction == CallDirection.incoming && session.state == CallState.ringing;

    if (incoming) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.xxl, LocalLinkSpacing.md, LocalLinkSpacing.xxl, LocalLinkSpacing.xxl),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallAction(
              label: 'Decline',
              icon: Icons.call_end_rounded,
              background: colors.errorContainer,
              foreground: colors.onErrorContainer,
              onPressed: () async {
                try { await controller.rejectIncoming(); } catch (_) {}
              },
            ),
            _CallAction(
              label: 'Answer',
              icon: Icons.call_rounded,
              background: colors.primaryContainer,
              foreground: colors.onPrimaryContainer,
              onPressed: () async {
                try { await controller.acceptIncoming(); } catch (_) {}
              },
            ),
          ],
        ),
      );
    }

    if (!session.isFinished) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.lg, LocalLinkSpacing.md, LocalLinkSpacing.lg, LocalLinkSpacing.xxl),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: LocalLinkSpacing.lg,
          runSpacing: LocalLinkSpacing.md,
          children: [
            _CallIconAction(
              label: session.muted ? 'Unmute' : 'Mute',
              icon: session.muted ? Icons.mic_off : Icons.mic,
              onPressed: () async { try { await controller.toggleMute(); } catch (_) {} },
            ),
            _CallIconAction(
              label: session.videoEnabled ? 'Camera off' : 'Camera',
              icon: session.videoEnabled ? Icons.videocam_off : Icons.videocam,
              enabled: session.directMode,
              onPressed: () async { try { await controller.toggleVideo(); } catch (_) {} },
            ),
            _CallAction(
              label: 'End',
              icon: Icons.call_end_rounded,
              background: colors.error,
              foreground: colors.onError,
              onPressed: () async { try { await controller.endCall(); } catch (_) {} },
            ),
            _CallIconAction(
              label: session.speakerOn ? 'Speaker off' : 'Speaker',
              icon: session.speakerOn ? Icons.volume_up : Icons.phone_in_talk,
              onPressed: () async { try { await controller.toggleSpeaker(); } catch (_) {} },
            ),
            if (session.directMode && session.videoEnabled)
              _CallIconAction(
                label: 'Switch camera',
                icon: Icons.cameraswitch,
                onPressed: () async { try { await controller.switchCamera(); } catch (_) {} },
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(LocalLinkSpacing.xxl),
      child: FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
    );
  }
}

class _CallIconAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool enabled;

  const _CallIconAction({required this.label, required this.icon, required this.onPressed, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            iconSize: 26,
            onPressed: enabled ? () => onPressed() : null,
            icon: Icon(icon),
          ),
          const SizedBox(height: 3),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Future<void> Function() onPressed;

  const _CallAction({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: background, foregroundColor: foreground, iconSize: 30),
          onPressed: () => onPressed(),
          icon: Icon(icon),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
