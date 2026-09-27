import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' hide CallState;

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
    final incoming = session.direction == CallDirection.incoming &&
        session.state == CallState.ringing;

    if (incoming) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FloatingActionButton(
              heroTag: 'reject-call',
              backgroundColor: Theme.of(context).colorScheme.error,
              onPressed: () async {
                try {
                  await controller.rejectIncoming();
                } catch (_) {}
              },
              child: const Icon(Icons.call_end),
            ),
            FloatingActionButton(
              heroTag: 'accept-call',
              backgroundColor: Theme.of(context).colorScheme.primary,
              onPressed: () async {
                try {
                  await controller.acceptIncoming();
                } catch (_) {}
              },
              child: const Icon(Icons.call),
            ),
          ],
        ),
      );
    }

    if (!session.isFinished) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton.filledTonal(
              iconSize: 28,
              onPressed: () async {
                try {
                  await controller.toggleMute();
                } catch (_) {}
              },
              icon: Icon(session.muted ? Icons.mic_off : Icons.mic),
              tooltip: 'Mute',
            ),
            IconButton.filledTonal(
              iconSize: 28,
              onPressed: session.directMode
                  ? () async {
                      try {
                        await controller.toggleVideo();
                      } catch (_) {}
                    }
                  : null,
              icon: Icon(
                  session.videoEnabled ? Icons.videocam : Icons.videocam_off),
              tooltip: 'Video',
            ),
            FloatingActionButton(
              heroTag: 'hangup-call',
              backgroundColor: Theme.of(context).colorScheme.error,
              onPressed: () async {
                try {
                  await controller.endCall();
                } catch (_) {}
              },
              child: const Icon(Icons.call_end),
            ),
            IconButton.filledTonal(
              iconSize: 28,
              onPressed: () async {
                try {
                  await controller.toggleSpeaker();
                } catch (_) {}
              },
              icon: Icon(
                  session.speakerOn ? Icons.volume_up : Icons.phone_in_talk),
              tooltip: 'Speaker',
            ),
            if (session.directMode && session.videoEnabled)
              IconButton.filledTonal(
                iconSize: 28,
                onPressed: () async {
                  try {
                    await controller.switchCamera();
                  } catch (_) {}
                },
                icon: const Icon(Icons.cameraswitch),
                tooltip: 'Switch camera',
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: FilledButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Close'),
      ),
    );
  }
}
