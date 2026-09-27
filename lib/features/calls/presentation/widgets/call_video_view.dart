import 'package:flutter/material.dart';

class CallVideoView extends StatelessWidget {
  final int? localTextureId;
  final int? remoteTextureId;

  const CallVideoView({super.key, this.localTextureId, this.remoteTextureId});

  @override
  Widget build(BuildContext context) {
    if (remoteTextureId == null && localTextureId == null) {
      return const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (remoteTextureId != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Texture(textureId: remoteTextureId!),
            )
          else
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.videocam_off, size: 48),
            ),
          if (localTextureId != null)
            Positioned(
              right: 16,
              top: 16,
              width: 120,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.black),
                  child: Texture(textureId: localTextureId!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
