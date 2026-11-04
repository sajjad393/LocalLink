import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/files/presentation/widgets/media_gallery_viewer.dart';
import 'package:locallink/features/files/presentation/widgets/media_grid.dart';
import 'package:locallink/features/files/presentation/widgets/media_tile_look.dart';

/// Builds one attachment tile; [cell] / [onOpen] set = grid square.
typedef BubbleTileBuilder = Widget Function(Attachment attachment,
    {Size? cell, VoidCallback? onOpen});

/// Bundle 202 (mock A1-A6, C1/C2): the picture part of a bubble, shared by
/// the 1-to-1 and group bubbles.
///
/// Photos / videos = one picture (real shape, as before) or the grid.
/// Documents / voice notes = rows under it. "Tight" bubbles (with pictures)
/// have a 3 px edge; the time sits ON the picture when there is no caption
/// and no document row.
class BubbleMedia {
  BubbleMedia._(this.visual, this.rows, this.timeOnMedia);

  factory BubbleMedia.of(List<Attachment> attachments, {required bool hasCaption}) {
    final visual = <Attachment>[];
    final rows = <Attachment>[];
    for (final a in attachments) {
      (isGridMedia(a) ? visual : rows).add(a);
    }
    return BubbleMedia._(
        visual, rows, visual.isNotEmpty && rows.isEmpty && !hasCaption);
  }

  final List<Attachment> visual;
  final List<Attachment> rows;

  /// Time + ticks drawn on the picture (white on a soft shade).
  final bool timeOnMedia;

  /// The bubble has photos / videos: 3 px edge, caption under the pictures.
  bool get tight => visual.isNotEmpty;

  /// Bubble padding: 3 px for picture bubbles, the old padding otherwise.
  static EdgeInsets padding({required bool tight, required double extraBottom}) =>
      tight
          ? EdgeInsets.fromLTRB(3, 3, 3, 3 + extraBottom)
          : EdgeInsets.fromLTRB(LocalLinkSpacing.md, LocalLinkSpacing.sm,
              LocalLinkSpacing.md, LocalLinkSpacing.xs + extraBottom);

  /// Caption: keeps 12 px from the bubble edge (3 + 9).
  static Widget caption(Widget body) =>
      Padding(padding: const EdgeInsets.fromLTRB(9, 5, 9, 0), child: body);

  /// Small text in the header (name, "Forwarded"): away from the edge.
  static Widget headerLine(Widget child) =>
      Padding(padding: const EdgeInsets.fromLTRB(9, 3, 9, 1), child: child);

  /// Footer under a caption / document row.
  static Widget footer(Widget child) =>
      Padding(padding: const EdgeInsets.only(right: 6, bottom: 1), child: child);

  /// Width of the grid in a bubble at most [bubbleMaxWidth] wide.
  static double gridWidth(double bubbleMaxWidth) =>
      math.min(MediaGrid.maxWidth, bubbleMaxWidth - 6);

  /// Corners of the picture: 15 (bubble 18 minus the 3 px edge), small
  /// where something sits next to it (header above, rows below) and at the
  /// bubble's tail corner.
  BorderRadius radius({required bool isMine, required bool hasHeader}) {
    const round = Radius.circular(LocalLinkRadius.chat - 3);
    const small = Radius.circular(4);
    final top = hasHeader ? small : round;
    final bottomFree = timeOnMedia;
    return BorderRadius.only(
      topLeft: top,
      topRight: top,
      bottomLeft: bottomFree ? (isMine ? round : small) : small,
      bottomRight: bottomFree ? (isMine ? small : round) : small,
    );
  }

  /// The children for BubbleContent.media.
  List<Widget> build(
    BuildContext context, {
    required BubbleTileBuilder tile,
    required bool isMine,
    required bool hasHeader,
    required double bubbleMaxWidth,
    required Widget Function() timeOverlay,
    required String viewerTitle,
    required String viewerSubtitle,
  }) {
    if (!tight) return [for (final a in rows) tile(a)];
    final r = radius(isMine: isMine, hasHeader: hasHeader);
    final out = <Widget>[];
    if (visual.length == 1) {
      Widget one = MediaTileLook(
          topGap: 0,
          radius: r,
          freeCorner: timeOnMedia,
          child: tile(visual.first));
      if (timeOnMedia) {
        one = Stack(children: [
          one,
          Positioned(
              right: 6, bottom: 5, child: MediaTimeChip(child: timeOverlay())),
        ]);
      }
      out.add(one);
    } else {
      void open(int i) => MediaGalleryViewer.open(
            context,
            items: [for (final a in visual) GalleryItem.fromAttachment(a)],
            initialIndex: i,
            title: viewerTitle,
            subtitle: viewerSubtitle,
          );
      out.add(MediaGrid(
        items: visual,
        width: gridWidth(bubbleMaxWidth),
        radius: r,
        overlay: timeOnMedia ? MediaTimeChip(child: timeOverlay()) : null,
        onMore: () => open(3),
        cellBuilder: (_, a, size, i) =>
            tile(a, cell: size, onOpen: () => open(i)),
      ));
    }
    for (final a in rows) {
      out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3), child: tile(a)));
    }
    return out;
  }
}
