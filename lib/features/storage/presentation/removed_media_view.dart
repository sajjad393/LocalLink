import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_player.dart';
import 'package:locallink/features/files/presentation/widgets/media_frame.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';
import 'package:locallink/features/storage/domain/media_clean_policy.dart';
import 'package:locallink/features/files/presentation/widgets/media_tile_look.dart';

/// Bundle 197b: shown in the bubble when LinkUp's copy of a photo / video /
/// document / voice note was removed to save space (auto or by hand).
/// The message stays; a tap restores (sender) or explains (receiver).
class RemovedMediaView extends StatefulWidget {
  const RemovedMediaView({
    super.key,
    required this.attachment,
    required this.mine,
    this.senderName,
    this.onRestored,
    this.service,
    this.cell,
  });

  static const String label = 'Removed to save space';

  final Attachment attachment;
  final bool mine;
  final String? senderName;
  final VoidCallback? onRestored;
  final MediaStorageService? service;

  /// Bundle 202: square in a media grid (fixed size, no gap, no corners).
  final Size? cell;

  /// V4: "This photo / video / file is no longer on your phone."
  static String goneMine(MediaKind kind) => switch (kind) {
        MediaKind.photo => 'This photo is no longer on your phone.',
        MediaKind.video => 'This video is no longer on your phone.',
        _ => 'This file is no longer on your phone.',
      };

  /// V5: receiver.
  static String goneTheirs(String? sender) {
    final name = (sender ?? '').trim();
    return 'Removed to save space. Ask ${name.isEmpty ? 'the sender' : name} to send it again.';
  }

  @override
  State<RemovedMediaView> createState() => _RemovedMediaViewState();
}

class _RemovedMediaViewState extends State<RemovedMediaView> {
  String? _thumb;
  bool _busy = false;
  bool? _alive;

  MediaStorageService get _service => widget.service ?? MediaStorageService.instance;
  MediaKind get _kind => mediaKindOf(
      contentType: widget.attachment.contentType,
      name: widget.attachment.originalName,
      isImage: widget.attachment.isImage);

  @override
  void initState() {
    super.initState();
    if (_kind == MediaKind.photo || _kind == MediaKind.video) {
      unawaited(_loadThumb());
    }
    // Mock 5: my photo still in my Gallery looks normal (no label).
    if (widget.mine && (MediaBook.instance.of(widget.attachment.id)?.hasSource ?? false)) {
      _alive = _service.linkAliveCached(widget.attachment.id);
      if (_alive == null) unawaited(_checkLink());
    }
  }

  Future<void> _loadThumb() async {
    final path = await _service.thumbView(widget.attachment.id);
    if (mounted && path != null) setState(() => _thumb = path);
  }

  Future<void> _checkLink() async {
    final alive = await _service.linkAlive(widget.attachment.id);
    if (mounted) setState(() => _alive = alive);
  }

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    RemovedTap result;
    try {
      result = await _service.tapRemoved(widget.attachment, mine: widget.mine);
    } catch (_) {
      result = RemovedTap.gone;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case RemovedTap.restored:
        widget.onRestored?.call();
      case RemovedTap.openedSaved:
        break;
      case RemovedTap.gone:
        if (widget.mine) setState(() => _alive = false);
        LinkToast.maybeOn(messenger, widget.mine
                ? RemovedMediaView.goneMine(_kind)
                : RemovedMediaView.goneTheirs(widget.senderName), kind: LinkToastKind.info);
    }
  }

  String _clock(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _chip() => Container(
        key: const Key('removed_media_chip'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .62), borderRadius: BorderRadius.circular(12)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 15, color: Colors.white),
          SizedBox(width: 5),
          Flexible(
            child: Text(RemovedMediaView.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Widget _visual() {
    final a = widget.attachment;
    final frame = widget.cell ?? MediaFrame.fit(a.width, a.height);
    final looksNormal = widget.mine && _alive == true;
    final thumb = _thumb;
    Widget picture = thumb == null
        ? const ColoredBox(key: Key('removed_media_placeholder'), color: Color(0xFF2A2F3A))
        : Image.file(File(thumb), key: const Key('removed_media_thumb'), fit: BoxFit.cover, gaplessPlayback: true);
    if (thumb != null && !looksNormal) {
      picture = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: .25), BlendMode.darken),
          child: picture,
        ),
      );
    }
    final booked = MediaBook.instance.of(a.id)?.mediaMs ?? 0;
    final ms = booked > 0 ? booked : (VideoInfoCache.peek(a.id)?.durationMs ?? 0);
    return Container(
      margin: EdgeInsets.only(top: MediaTileLook.topOf(context, fallback: 6)),
      child: ClipRRect(
        borderRadius: MediaTileLook.radiusOf(context),
        child: SizedBox(
          width: frame.width,
          height: frame.height,
          child: Material(
            color: const Color(0xFF2A2F3A),
            child: InkWell(
              onTap: _tap,
              child: Stack(fit: StackFit.expand, children: [
                picture,
                if (_kind == MediaKind.video)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: VideoChip(
                        icon: Icons.play_arrow_rounded,
                        label: ms > 0 ? _clock(ms) : 'Video'),
                  ),
                if (looksNormal && _kind == MediaKind.video)
                  const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 52)),
                if (!looksNormal) Positioned(left: 8, right: 8, bottom: 8, child: Align(alignment: Alignment.bottomLeft, child: _chip())),
                if (_busy) const Center(child: CircularProgressIndicator(strokeWidth: 3)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context) {
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final voice = _kind == MediaKind.voice;
    return Material(
      color: voice ? Colors.transparent : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _tap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Icon(voice ? Icons.mic_none_rounded : Icons.insert_drive_file, color: grey),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!voice)
                  Text(widget.attachment.originalName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: grey)),
                Row(key: const Key('removed_media_row'), children: [
                  Icon(Icons.cloud_off_rounded, size: 12, color: grey),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(RemovedMediaView.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: grey)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_kind == MediaKind.photo || _kind == MediaKind.video) return _visual();
    return Container(margin: const EdgeInsets.only(top: 8), child: _row(context));
  }
}

/// P3: small "✓ Saved" mark on a photo / video I saved to my phone.
class SavedMark extends StatelessWidget {
  const SavedMark({super.key});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('saved_mark'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_rounded, size: 12, color: Colors.white),
          SizedBox(width: 3),
          Text('Saved', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );
}
