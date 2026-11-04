import 'dart:io';

import 'package:flutter/material.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/files/presentation/widgets/media_gallery_viewer.dart';
import 'package:locallink/features/files/presentation/widgets/media_grid.dart';

/// Bundle 202 (mock F1/F2): files picked but not sent yet - small pictures
/// (44 px) for photos / videos, an icon + name for documents, an X on each,
/// and "+" to add more. Tap a picture = full-screen "Ready to send" review
/// with swipe and Remove.
class PendingAttachmentStrip extends StatelessWidget {
  final List<PickedFile> attachments;
  final ValueChanged<int> onRemove;

  /// "+" at the end (pick more). Null = no "+".
  final VoidCallback? onAdd;

  const PendingAttachmentStrip({
    super.key,
    required this.attachments,
    required this.onRemove,
    this.onAdd,
  });

  static bool _isPhoto(PickedFile f) =>
      f.contentType.toLowerCase().startsWith('image/');

  static bool _isVideo(PickedFile f) =>
      f.contentType.toLowerCase().startsWith('video/') || isVideoName(f.name);

  static bool isVisual(PickedFile f) => _isPhoto(f) || _isVideo(f);

  /// "Tickets.pdf" -> "Tickets".
  static String _shortName(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  void _review(BuildContext context, int index) {
    final visual = <int>[];
    for (var i = 0; i < attachments.length; i++) {
      if (isVisual(attachments[i])) visual.add(i);
    }
    final start = visual.indexOf(index);
    if (start < 0) return;
    // The viewer reports positions in its ORIGINAL list; files removed
    // earlier (lower in this strip) shift the later ones down by one.
    final gone = List<bool>.filled(visual.length, false);
    MediaGalleryViewer.open(
      context,
      items: [for (final i in visual) GalleryItem.fromPicked(attachments[i])],
      initialIndex: start,
      onRemove: (k) {
        var shift = 0;
        for (var j = 0; j < visual.length; j++) {
          if (gone[j] && visual[j] < visual[k]) shift++;
        }
        gone[k] = true;
        onRemove(visual[k] - shift);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('pending_strip'),
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        children: [
          for (var i = 0; i < attachments.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _item(context, colors, i),
          ],
          if (onAdd != null) ...[
            const SizedBox(width: 6),
            InkWell(
              key: const Key('pending_strip_add'),
              borderRadius: BorderRadius.circular(8),
              onTap: onAdd,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outline),
                ),
                child: Icon(Icons.add, color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _item(BuildContext context, ColorScheme colors, int i) {
    final f = attachments[i];
    final Widget box;
    if (isVisual(f)) {
      final video = _isVideo(f);
      box = GestureDetector(
        key: ValueKey<String>('pending_thumb:$i'),
        onTap: () => _review(context, i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(color: colors.surfaceContainerHighest),
              if (!video)
                Image.file(File(f.path),
                    fit: BoxFit.cover,
                    cacheWidth: 132,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Icon(Icons.image_outlined,
                        color: colors.onSurfaceVariant))
              else
                const ColoredBox(
                  color: Color(0xFF2A2F3A),
                  child: Center(
                    child: Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 26),
                  ),
                ),
            ]),
          ),
        ),
      );
    } else {
      box = Container(
        key: ValueKey<String>('pending_file:$i'),
        width: 44,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
              f.contentType.toLowerCase().startsWith('audio/')
                  ? Icons.mic_rounded
                  : Icons.description_outlined,
              size: 20,
              color: colors.onSurfaceVariant),
          Text(_shortName(f.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant)),
        ]),
      );
    }
    return Stack(clipBehavior: Clip.none, children: [
      box,
      Positioned(
        right: -4,
        top: -4,
        child: GestureDetector(
          key: ValueKey<String>('pending_remove:$i'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onRemove(i),
          child: Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: colors.inverseSurface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.surface, width: 1.5),
            ),
            child: Icon(Icons.close, size: 11, color: colors.onInverseSurface),
          ),
        ),
      ),
    ]);
  }
}
