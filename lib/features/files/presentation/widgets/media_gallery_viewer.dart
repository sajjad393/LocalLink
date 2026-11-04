import 'dart:io';

import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';

import 'chat_video_player.dart';
import 'media_grid.dart';
import 'media_tile_look.dart';
import 'media_view_cache.dart';

/// Bundle 202: one page of the swipe viewer.
class GalleryItem {
  const GalleryItem({
    required this.id,
    required this.video,
    this.path,
    this.viewKey,
    this.attachment,
  });

  /// A photo / video of a message. Uses the view the chat already opened
  /// (null path = not downloaded / not opened yet).
  factory GalleryItem.fromAttachment(Attachment a) {
    final view = MediaGalleryRegistry.of(a.id);
    return GalleryItem(
      id: a.id,
      video: isVideoAttachment(a),
      path: view?.path,
      viewKey: view?.viewKey,
      attachment: a,
    );
  }

  /// A picked file before sending (plain file on this phone).
  factory GalleryItem.fromPicked(PickedFile f) => GalleryItem(
        id: f.path,
        video: f.contentType.toLowerCase().startsWith('video/') ||
            isVideoName(f.name),
        path: f.path,
      );

  final String id;
  final bool video;
  final String? path;
  final String? viewKey;
  final Attachment? attachment;
}

/// Bundle 202 (mock B1): full screen "Sajjad · 2 of 7", swipe left / right,
/// small pictures at the bottom, pinch to zoom photos. Videos use the
/// normal chat player. With [onRemove] it is the "Ready to send" review
/// (mock F2): a Remove button takes the shown file out.
class MediaGalleryViewer extends StatefulWidget {
  const MediaGalleryViewer({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.title = '',
    this.subtitle = '',
    this.onRemove,
  });

  final List<GalleryItem> items;
  final int initialIndex;
  final String title;
  final String subtitle;

  /// Review before sending: index into the ORIGINAL [items] list.
  final ValueChanged<int>? onRemove;

  static Future<void> open(
    BuildContext context, {
    required List<GalleryItem> items,
    int initialIndex = 0,
    String title = '',
    String subtitle = '',
    ValueChanged<int>? onRemove,
  }) {
    if (items.isEmpty) return Future<void>.value();
    return Navigator.of(context).push<void>(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, __, ___) => MediaGalleryViewer(
        items: items,
        initialIndex: initialIndex,
        title: title,
        subtitle: subtitle,
        onRemove: onRemove,
      ),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
  }

  /// "2 of 7" (+ " · 4:12 PM").
  static String counter(int index, int count, String subtitle) =>
      '${index + 1} of $count${subtitle.isEmpty ? '' : ' · $subtitle'}';

  @override
  State<MediaGalleryViewer> createState() => _MediaGalleryViewerState();
}

class _MediaGalleryViewerState extends State<MediaGalleryViewer> {
  late final PageController _pages;
  late final List<GalleryItem> _items;
  late final List<int> _origin;
  late int _index;
  final List<String> _held = <String>[];
  final ScrollController _strip = ScrollController();

  @override
  void initState() {
    super.initState();
    _items = List<GalleryItem>.of(widget.items);
    _origin = List<int>.generate(_items.length, (i) => i);
    _index = widget.initialIndex.clamp(0, _items.length - 1);
    _pages = PageController(initialPage: _index);
    // Keep the decrypted views alive while the viewer shows them, even if
    // the chat behind scrolls them away.
    for (final item in _items) {
      final key = item.viewKey;
      if (key != null && MediaViewCache.instance.peek(key) != null) {
        MediaViewCache.instance.retain(key);
        _held.add(key);
      }
    }
  }

  @override
  void dispose() {
    for (final key in _held) {
      MediaViewCache.instance.release(key);
    }
    _pages.dispose();
    _strip.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i == _index || i < 0 || i >= _items.length) return;
    _pages.jumpToPage(i);
  }

  void _remove() {
    final cb = widget.onRemove;
    if (cb == null || _items.isEmpty) return;
    final i = _index;
    cb(_origin[i]);
    setState(() {
      _items.removeAt(i);
      _origin.removeAt(i);
      if (_index >= _items.length) _index = _items.length - 1;
    });
    if (_items.isEmpty) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final count = _items.length;
    final review = widget.onRemove != null;
    final title = review ? 'Ready to send' : widget.title;
    return Scaffold(
      key: const Key('media_gallery_viewer'),
      backgroundColor: Colors.black,
      body: count == 0
          ? const SizedBox.shrink()
          : Stack(children: [
              Positioned.fill(
                child: PageView.builder(
                  key: const Key('media_gallery_pages'),
                  controller: _pages,
                  itemCount: count,
                  onPageChanged: (i) {
                    setState(() => _index = i);
                    _keepStripInView(i);
                  },
                  itemBuilder: (context, i) => _page(_items[i]),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _topBar(title, count, review),
              ),
              if (count > 1)
                Positioned(left: 0, right: 0, bottom: 0, child: _stripBar()),
            ]),
    );
  }

  Widget _topBar(String title, int count, bool review) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 14),
          child: Row(children: [
            IconButton(
              key: const Key('media_gallery_back'),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title.isNotEmpty)
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  Text(
                    MediaGalleryViewer.counter(_index, count, widget.subtitle),
                    key: const Key('media_gallery_counter'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (review)
              TextButton.icon(
                key: const Key('media_gallery_remove'),
                onPressed: _remove,
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                label: const Text('Remove', style: TextStyle(color: Colors.white)),
              ),
          ]),
        ),
      ),
    );
  }

  void _keepStripInView(int i) {
    if (!_strip.hasClients) return;
    const step = 50.0;
    final target = (i * step) - (_strip.position.viewportDimension - step) / 2;
    _strip.animateTo(
      target.clamp(0.0, _strip.position.maxScrollExtent),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Widget _stripBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Center(
            child: ListView.builder(
              key: const Key('media_gallery_strip'),
              controller: _strip,
              shrinkWrap: true,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _items.length,
              itemBuilder: (_, i) => _stripThumb(i),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stripThumb(int i) {
    final item = _items[i];
    final on = i == _index;
    final path = item.path;
    final Widget pic = !item.video && path != null
        ? Image.file(File(path),
            fit: BoxFit.cover,
            cacheWidth: 120,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF2A2F3A)))
        : MediaThumbFill(attachmentId: item.attachment?.id ?? '', cacheWidth: 120);
    return GestureDetector(
      key: ValueKey<String>('media_gallery_thumb:$i'),
      onTap: () => _go(i),
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: on ? Colors.white : Colors.transparent, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Opacity(
            opacity: on ? 1 : .6,
            child: Stack(fit: StackFit.expand, children: [
              pic,
              if (item.video)
                const Center(
                  child: Icon(Icons.play_arrow_rounded,
                      size: 18, color: Colors.white),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _page(GalleryItem item) {
    final path = item.path;
    if (path == null) {
      return Stack(fit: StackFit.expand, children: [
        Opacity(
          opacity: .35,
          child: MediaThumbFill(
              attachmentId: item.attachment?.id ?? '',
              fallback: const SizedBox.shrink()),
        ),
        const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.download_rounded, color: Colors.white70, size: 40),
            SizedBox(height: 8),
            Text('Not downloaded yet',
                key: Key('media_gallery_not_ready'),
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ]),
        ),
      ]);
    }
    if (!item.video) {
      return InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: Image.file(
            File(path),
            key: ValueKey<String>('media_gallery_photo:${item.id}'),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48),
          ),
        ),
      );
    }
    final a = item.attachment;
    final key = item.viewKey;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: FittedBox(
          fit: BoxFit.contain,
          child: MediaTileLook(
            topGap: 0,
            child: ChatVideoPlayer(
              key: ValueKey<String>('media_gallery_video:${item.id}'),
              path: path,
              cacheKey: a?.id ?? path,
              sizeBytes: a?.size ?? 0,
              hintWidth: a?.width ?? 0,
              hintHeight: a?.height ?? 0,
              onRetainFile: key == null
                  ? null
                  : () => MediaViewCache.instance.retain(key),
              onReleaseFile: key == null
                  ? null
                  : (_) => MediaViewCache.instance.release(key),
            ),
          ),
        ),
      ),
    );
  }
}
