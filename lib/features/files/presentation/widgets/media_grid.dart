import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';

import 'media_tile_look.dart';

/// Bundle 202: true for a video file (by type or by name).
bool isVideoAttachment(Attachment a) {
  if (a.isImage) return false;
  final mime = a.contentType.toLowerCase();
  if (mime.startsWith('video/')) return true;
  return isVideoName(a.originalName);
}

/// Bundle 202: video by file name (picked files may have no type).
bool isVideoName(String name) {
  final n = name.toLowerCase();
  return n.endsWith('.mp4') ||
      n.endsWith('.m4v') ||
      n.endsWith('.mov') ||
      n.endsWith('.3gp') ||
      n.endsWith('.webm') ||
      n.endsWith('.mkv');
}

/// Bundle 202: photos and videos go in the grid; documents and voice notes
/// stay as rows under it.
bool isGridMedia(Attachment a) => a.isImage || isVideoAttachment(a);

/// Bundle 202: "📷 7 photos", "🎥 2 videos", "📷 2 photos, 1 video" for a
/// message with 2+ photos / videos. Null = 0 or 1 (old words stay).
String? mediaCountLabel(List<Attachment> attachments) {
  var photos = 0;
  var videos = 0;
  for (final a in attachments) {
    if (a.isImage) {
      photos++;
    } else if (isVideoAttachment(a)) {
      videos++;
    }
  }
  if (photos + videos < 2) return null;
  String n(int c, String one) => '$c $one${c == 1 ? '' : 's'}';
  if (videos == 0) return '📷 ${n(photos, 'photo')}';
  if (photos == 0) return '🎥 ${n(videos, 'video')}';
  return '📷 ${n(photos, 'photo')}, ${n(videos, 'video')}';
}

/// Bundle 202: "5 photos, 1 video, 1 file" (forward card). Empty kinds left out.
String mediaSummary(List<Attachment> attachments) {
  var photos = 0, videos = 0, voice = 0, files = 0;
  for (final a in attachments) {
    if (a.isImage) {
      photos++;
    } else if (isVideoAttachment(a)) {
      videos++;
    } else if (a.contentType.toLowerCase().startsWith('audio/')) {
      voice++;
    } else {
      files++;
    }
  }
  String n(int c, String one) => '$c $one${c == 1 ? '' : 's'}';
  return [
    if (photos > 0) n(photos, 'photo'),
    if (videos > 0) n(videos, 'video'),
    if (voice > 0) n(voice, 'voice message'),
    if (files > 0) n(files, 'file'),
  ].join(', ');
}

/// Bundle 202: decrypted views the chat already shows (attachment id ->
/// view path + cache key), so the swipe viewer opens them at once. Filled by
/// AttachmentTile while it is on screen.
class MediaGalleryRegistry {
  MediaGalleryRegistry._();

  static final Map<String, ({String path, String viewKey})> _views =
      <String, ({String path, String viewKey})>{};

  static void put(String id, String path, String viewKey) {
    if (id.isEmpty) return;
    final old = _views[id];
    if (old != null && old.path == path && old.viewKey == viewKey) return;
    if (_views.length >= 300 && old == null) _views.remove(_views.keys.first);
    _views[id] = (path: path, viewKey: viewKey);
  }

  static void drop(String id, String path) {
    if (_views[id]?.path == path) _views.remove(id);
  }

  static ({String path, String viewKey})? of(String id) => _views[id];

  @visibleForTesting
  static void debugReset() => _views.clear();
}

/// Bundle 202: small pictures kept for every photo / video (bundle 197b),
/// cached for this run. Used by grid squares of videos, the reply grid and
/// the viewer strip.
class MediaThumbs {
  MediaThumbs._();

  static final Map<String, String> _found = <String, String>{};

  @visibleForTesting
  static Future<String?> Function(String id)? debugLoader;

  @visibleForTesting
  static void debugReset() {
    _found.clear();
    debugLoader = null;
  }

  static String? cached(String id) => _found[id];

  static Future<String?> load(String id) async {
    final hit = _found[id];
    if (hit != null) return hit;
    String? path;
    try {
      final loader = debugLoader;
      if (loader != null) {
        path = await loader(id);
      } else if (MediaStorageService.instance.configured) {
        path = await MediaStorageService.instance.thumbView(id);
      }
    } catch (_) {
      path = null;
    }
    if (path == null || path.isEmpty) return null;
    if (_found.length >= 200) _found.remove(_found.keys.first);
    _found[id] = path;
    return path;
  }
}

/// Bundle 202: the small picture of [attachmentId], filling its box (cover).
/// Nothing found = [fallback].
class MediaThumbFill extends StatefulWidget {
  const MediaThumbFill({
    super.key,
    required this.attachmentId,
    this.fallback,
    this.cacheWidth = 240,
  });

  final String attachmentId;
  final Widget? fallback;
  final int cacheWidth;

  @override
  State<MediaThumbFill> createState() => _MediaThumbFillState();
}

class _MediaThumbFillState extends State<MediaThumbFill> {
  String? _path;
  int _ask = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MediaThumbFill old) {
    super.didUpdateWidget(old);
    if (old.attachmentId != widget.attachmentId) _load();
  }

  void _load() {
    final id = widget.attachmentId;
    _path = MediaThumbs.cached(id);
    if (_path != null || id.isEmpty) return;
    final ask = ++_ask;
    unawaited(MediaThumbs.load(id).then((p) {
      if (p != null && mounted && ask == _ask) setState(() => _path = p);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    final fallback = widget.fallback ??
        const ColoredBox(color: Color(0xFF2A2F3A));
    if (path == null) return fallback;
    return Image.file(
      File(path),
      key: ValueKey<String>('media_thumb:${widget.attachmentId}'),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      cacheWidth: widget.cacheWidth,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

/// Bundle 202 (mock A2-A6): WhatsApp-style grid of 2+ photos / videos of ONE
/// message. 2 = side by side, 3 = one wide on top + two below, 4 = 2x2,
/// 5+ = 2x2 with "+N" on the 4th square. Squares come from [cellBuilder]
/// (a compact AttachmentTile), so every square keeps its own ring,
/// download arrow, "Waiting" and retry.
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.cellBuilder,
    this.width = maxWidth,
    this.gap = 2,
    this.radius = const BorderRadius.all(Radius.circular(15)),
    this.overlay,
    this.onMore,
  });

  static const double maxWidth = 250;

  final List<Attachment> items;
  final Widget Function(BuildContext context, Attachment item, Size cell, int index)
      cellBuilder;
  final double width;
  final double gap;
  final BorderRadius radius;

  /// Drawn bottom-right on the grid (time + ticks).
  final Widget? overlay;

  /// Tap on "+N" (opens the viewer at the 4th item).
  final VoidCallback? onMore;

  /// Squares shown for [count] items (max 4).
  static int shown(int count) => math.min(count, 4);

  /// "+N" number (hidden items beyond the 4 squares), 0 = none.
  static int more(int count) => count > 4 ? count - 4 : 0;

  /// Size of each shown square, in order (for tests and the bubble).
  static List<Size> cellSizes(int count, double width, {double gap = 2}) {
    final half = (width - gap) / 2;
    if (count <= 1) return <Size>[Size(width, width * .75)];
    if (count == 2) return <Size>[Size(half, half), Size(half, half)];
    if (count == 3) {
      return <Size>[Size(width, half), Size(half, half), Size(half, half)];
    }
    return List<Size>.filled(4, Size(half, half));
  }

  @override
  Widget build(BuildContext context) {
    final n = items.length;
    final sizes = cellSizes(n, width, gap: gap);
    final extra = more(n);
    Widget cell(int i) {
      final size = sizes[i];
      Widget child = SizedBox(
        width: size.width,
        height: size.height,
        child: cellBuilder(context, items[i], size, i),
      );
      if (i == 3 && extra > 0) {
        child = Stack(children: [
          child,
          Positioned.fill(
            child: GestureDetector(
              key: const Key('media_grid_more'),
              behavior: HitTestBehavior.opaque,
              onTap: onMore,
              child: ColoredBox(
                color: Colors.black45,
                child: Center(
                  child: Text('+$extra',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ]);
      }
      return child;
    }

    final g = SizedBox(width: gap, height: gap);
    final Widget body;
    if (n == 2) {
      body = Row(mainAxisSize: MainAxisSize.min, children: [cell(0), g, cell(1)]);
    } else if (n == 3) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        cell(0),
        g,
        Row(mainAxisSize: MainAxisSize.min, children: [cell(1), g, cell(2)]),
      ]);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [cell(0), g, cell(1)]),
        g,
        Row(mainAxisSize: MainAxisSize.min, children: [cell(2), g, cell(3)]),
      ]);
    }
    return MediaTileLook(
      topGap: 0,
      radius: BorderRadius.zero,
      freeCorner: overlay != null,
      child: ClipRRect(
        key: ValueKey<String>('media_grid:$n'),
        borderRadius: radius,
        child: Stack(children: [
          body,
          if (overlay != null) Positioned(right: 6, bottom: 5, child: overlay!),
        ]),
      ),
    );
  }
}

/// Bundle 202 (mock C1): time + ticks on the picture - white on a soft shade.
class MediaTimeChip extends StatelessWidget {
  const MediaTimeChip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        key: const Key('media_time_chip'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .32),
          borderRadius: BorderRadius.circular(9),
        ),
        child: child,
      ),
    );
  }
}

/// Bundle 202 (mock D1/D2/E1): small 2x2 of a message's photos / videos
/// (reply bar, quote, forward card). 1 item = one picture; 3 = one wide on
/// top + two; 5+ = "+N" on the 4th.
class MediaMiniGrid extends StatelessWidget {
  const MediaMiniGrid({
    super.key,
    required this.items,
    this.size = 40,
    this.radius = 6,
  });

  final List<Attachment> items;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final n = items.length;
    const gap = 1.0;
    final half = (size - gap) / 2;
    Widget pic(Attachment a, double w, double h, {int plus = 0}) => SizedBox(
          width: w,
          height: h,
          child: Stack(fit: StackFit.expand, children: [
            MediaThumbFill(attachmentId: a.id, cacheWidth: 120),
            if (isVideoAttachment(a) && plus == 0)
              const Center(
                child: Icon(Icons.play_arrow_rounded,
                    size: 14,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
              ),
            if (plus > 0)
              ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Text('+$plus',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: size < 44 ? 9.5 : 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        );
    final Widget body;
    if (n <= 1) {
      body = pic(items.first, size, size);
    } else if (n == 2) {
      body = Row(mainAxisSize: MainAxisSize.min, children: [
        pic(items[0], half, size),
        const SizedBox(width: gap),
        pic(items[1], half, size),
      ]);
    } else if (n == 3) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        pic(items[0], size, half),
        const SizedBox(height: gap),
        Row(mainAxisSize: MainAxisSize.min, children: [
          pic(items[1], half, half),
          const SizedBox(width: gap),
          pic(items[2], half, half),
        ]),
      ]);
    } else {
      final extra = MediaGrid.more(n);
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          pic(items[0], half, half),
          const SizedBox(width: gap),
          pic(items[1], half, half),
        ]),
        const SizedBox(height: gap),
        Row(mainAxisSize: MainAxisSize.min, children: [
          pic(items[2], half, half),
          const SizedBox(width: gap),
          pic(items[3], half, half, plus: extra),
        ]),
      ]);
    }
    return ClipRRect(
      key: ValueKey<String>('media_mini_grid:$n'),
      borderRadius: BorderRadius.circular(radius),
      child: body,
    );
  }
}
