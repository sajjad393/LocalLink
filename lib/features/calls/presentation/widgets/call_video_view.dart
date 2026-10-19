import 'package:flutter/material.dart';

import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/widgets/call_palette.dart';

/// WhatsApp-style video layer: the most relevant stream fills the screen,
/// the caller's own camera sits as a small rounded bubble in the top-right.
///
/// Layout rules:
///  * peer camera on  -> remote stream fills the screen, own preview bubbles
///  * only own camera -> own preview fills the screen
///  * peer camera off -> keeps the last-allocated surface behind a dark cover
///    (handled by the caller — the screen shows the avatar header instead)
class CallVideoView extends StatelessWidget {
  final CallSession session;

  const CallVideoView({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final remoteId = session.remoteVideoTextureId;
    final localId = session.localVideoTextureId;
    final showRemote = session.peerVideoActive && remoteId != null;
    final showLocalFull =
        !showRemote && session.videoEnabled && localId != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        if (showRemote)
          _CoverTexture(textureId: remoteId!,
              rotation: session.remoteVideoRotation)
        else if (showLocalFull)
          _CoverTexture(textureId: localId!,
              rotation: session.localVideoRotation),
        if (session.videoEnabled && localId != null && showRemote)
          Positioned(
            top: 14,
            right: 14,
            width: 106,
            height: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: Colors.black,
                child: _CoverTexture(
                textureId: localId,
                rotation: session.localVideoRotation,
              ),
              ),
            ),
          ),
        if (!showRemote && !showLocalFull)
          const Center(
            child: Icon(Icons.videocam_off_rounded,
                color: CallPalette.textSecondary, size: 56),
          ),
      ],
    );
  }
}

class _CoverTexture extends StatelessWidget {
  final int textureId;
  final int rotation;

  const _CoverTexture({required this.textureId, this.rotation = 0});

  @override
  Widget build(BuildContext context) {
    // Native feed is 640x360 (16:9); cover-crop like WhatsApp video calls,
    // undoing the capture-side sensor rotation first.
    final quarterTurns = (rotation ~/ 90) & 3;
    final sideways = quarterTurns.isOdd;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: sideways ? 360 : 640,
        height: sideways ? 640 : 360,
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: Texture(textureId: textureId),
        ),
      ),
    );
  }
}
