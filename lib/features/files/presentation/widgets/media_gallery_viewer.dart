import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/files/domain/file_size_rule.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';
import 'package:locallink/features/messaging/presentation/screens/forward_screen.dart'
    show runForwardFlow;
import 'package:locallink/features/storage/presentation/media_message_actions.dart';

import 'chat_video_player.dart';
import 'media_grid.dart';
import 'prepare_ring.dart';
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

  /// Bundle 207 (G4): the files road, so a page can open a file that is on
  /// this phone even when no chat tile opened it (set at app start).
  static FileTransferRepositoryContract? files;

  /// Bundle 207 (G4): opens [item]'s saved file for viewing (locks a plain
  /// file first). Null = not on this phone.
  static Future<GalleryItem?> prepare(GalleryItem item) async {
    final a = item.attachment;
    final f = files;
    if (a == null || f == null) return null;
    var local = a.localPath ?? '';
    if (local.isEmpty) return null;
    if (!await File(local).exists() &&
        !(await File('$local.enc').exists())) {
      return null;
    }
    if (!await f.isProtectedLocalFile(local)) {
      local = await f.protectLegacyLocalFile(local);
    }
    final ext = a.originalName.contains('.')
        ? '.${a.originalName.split('.').last}'
        : '.bin';
    final key = '$local|$ext';
    final locked = local;
    final view = await MediaViewCache.instance.acquire(
      key,
      () => f.materializeForDisplay(locked, extension: ext),
      delete: f.deleteLocalFile,
    );
    return GalleryItem(
        id: item.id,
        video: item.video,
        path: view,
        viewKey: key,
        attachment: a);
  }

  /// Can [item] be opened here (file saved on this phone)?
  static bool canPrepare(GalleryItem item) =>
      files != null && (item.attachment?.localPath ?? '').isNotEmpty;

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
  final Set<String> _preparing = <String>{};
  final Set<String> _notHere = <String>{};
  bool _gone = false;
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

  /// Bundle 207 (G4): open the page's file myself ("Preparing…").
  void _prepareItem(GalleryItem item) {
    if (_preparing.contains(item.id) || _notHere.contains(item.id)) return;
    _preparing.add(item.id);
    () async {
      GalleryItem? ready;
      try {
        ready = await MediaGalleryViewer.prepare(item);
      } catch (error) {
        AppLogger.warning('MEDIA_VIEWER_PREPARE_FAILED', detail: '$error');
      }
      final key = ready?.viewKey;
      if (_gone) {
        if (key != null) MediaViewCache.instance.release(key);
        return;
      }
      if (key != null) _held.add(key);
      setState(() {
        _preparing.remove(item.id);
        final i = _items.indexWhere((x) => x.id == item.id);
        if (ready == null || i < 0) {
          _notHere.add(item.id);
        } else {
          _items[i] = ready;
        }
      });
      AppLogger.info('MEDIA_VIEWER_PREPARED', detail: 'ok=${ready != null}');
    }();
  }

  @override
  void dispose() {
    _gone = true;
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
                  itemBuilder: (context, i) => _page(_items[i], active: i == _index),
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
            // Bundle 207 (M2, mock 207 page 4): Forward / Save / ⋮.
            if (!review && _current?.attachment != null) ..._actions(),
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

  GalleryItem? get _current =>
      _index >= 0 && _index < _items.length ? _items[_index] : null;

  /// Bundle 207 (M2): Forward (when chats can be listed), Save (received
  /// file on this phone, Android 10+), ⋮ = File info.
  List<Widget> _actions() {
    final a = _current!.attachment!;
    final canSave = MediaMessageActions.savable([a], mine: false).isNotEmpty;
    return [
      if (ForwardHub.instance != null)
        IconButton(
          key: const Key('media_gallery_forward'),
          tooltip: 'Forward',
          icon: const Icon(Icons.shortcut_rounded, color: Colors.white),
          onPressed: () {
            MediaMessageActions.markOpened([a]);
            unawaited(runForwardFlow(
                context, [ForwardItem(text: '', attachments: [a])]));
          },
        ),
      if (canSave)
        IconButton(
          key: const Key('media_gallery_save'),
          tooltip: 'Save to phone',
          icon: const Icon(Icons.download_rounded, color: Colors.white),
          onPressed: () => unawaited(MediaMessageActions.save(context, [a])),
        ),
      PopupMenuButton<String>(
        key: const Key('media_gallery_more'),
        icon: const Icon(Icons.more_vert, color: Colors.white),
        onSelected: (_) => _showInfo(a),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'info', child: Text('File info')),
        ],
      ),
    ];
  }

  void _showInfo(Attachment a) {
    unawaited(showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('File info'),
        content: Text(
            '${a.originalName}\n${FileSizeRule.sizeLabel(a.size)}'
            '${widget.subtitle.isEmpty ? '' : '\n${widget.subtitle}'}',
            key: const Key('media_gallery_info')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    ));
  }

  void _keepStripInView(int i) {
    if (!_strip.hasClients) return;
    // Bundle 207 (M2): bigger pictures in the strip.
    const step = 58.0;
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
          height: 76,
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
        width: 52,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
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

  Widget _page(GalleryItem item, {bool active = true}) {
    final path = item.path;
    if (path == null &&
        !_notHere.contains(item.id) &&
        MediaGalleryViewer.canPrepare(item)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_gone) _prepareItem(item);
      });
      return Stack(fit: StackFit.expand, children: [
        Opacity(
          opacity: .35,
          child: MediaThumbFill(
              attachmentId: item.attachment?.id ?? '',
              fallback: const SizedBox.shrink()),
        ),
        // Bundle 208 (D5): only the percent in a ring that fills up (was a
        // spinner + "Preparing…" + a small line).
        Center(
          child: PrepareRing(
            path: item.attachment?.localPath ?? '',
            ringKey: const Key('media_gallery_prepare_ring'),
            pctKey: const Key('media_gallery_prepare_pct'),
          ),
        ),
      ]);
    }
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
    // Bundle 207 (I, mock 207 page 4): the video fills the screen and plays
    // by itself; swiping away pauses it; it stays on the last frame.
    return ChatVideoPlayer(
      key: ValueKey<String>('media_gallery_video:${item.id}'),
      path: path,
      cacheKey: a?.id ?? path,
      sizeBytes: a?.size ?? 0,
      hintWidth: a?.width ?? 0,
      hintHeight: a?.height ?? 0,
      page: true,
      active: active,
      onRetainFile: key == null
          ? null
          : () => MediaViewCache.instance.retain(key),
      onReleaseFile: key == null
          ? null
          : (_) => MediaViewCache.instance.release(key),
    );
  }
}
