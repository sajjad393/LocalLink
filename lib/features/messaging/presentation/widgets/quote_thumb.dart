import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';

/// Bundle 199: the small square picture in a reply box (photo / video).
///
/// Uses the small picture Bundle 197b already keeps for every photo and
/// video (also after "Removed to save space"). Nothing new is sent between
/// phones: each phone looks up its own copy of the original message.
/// Nothing found = no picture (text only, as before).
class QuoteThumb extends StatefulWidget {
  const QuoteThumb({
    super.key,
    required this.attachmentId,
    required this.video,
    this.size = 40,
  });

  final String attachmentId;
  final bool video;
  final double size;

  /// The first photo / video of [attachments], or null (text, voice, file).
  static QuoteThumb? forAttachments(List<Attachment> attachments,
      {Key? key, double size = 40}) {
    if (attachments.isEmpty) return null;
    final kind = replyKindFor(attachments);
    if (kind != 'photo' && kind != 'video') return null;
    final id = attachments.first.id;
    if (id.isEmpty) return null;
    return QuoteThumb(
        key: key ?? ValueKey<String>('quote_thumb:$id'),
        attachmentId: id,
        video: kind == 'video',
        size: size);
  }

  /// Found pictures for this run (id -> plain jpg), so a rebuilt list shows
  /// them at once. Capped.
  static final Map<String, String> _found = <String, String>{};

  @visibleForTesting
  static Future<String?> Function(String id)? debugLoader;

  @visibleForTesting
  static void debugReset() {
    _found.clear();
    debugLoader = null;
  }

  @override
  State<QuoteThumb> createState() => _QuoteThumbState();
}

class _QuoteThumbState extends State<QuoteThumb> {
  String? _path;
  int _ask = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(QuoteThumb old) {
    super.didUpdateWidget(old);
    if (old.attachmentId != widget.attachmentId) _load();
  }

  void _load() {
    final id = widget.attachmentId;
    _path = QuoteThumb._found[id];
    if (_path != null) return;
    final ask = ++_ask;
    unawaited(() async {
      String? path;
      try {
        final loader = QuoteThumb.debugLoader;
        if (loader != null) {
          path = await loader(id);
        } else if (MediaStorageService.instance.configured) {
          path = await MediaStorageService.instance.thumbView(id);
        }
      } catch (_) {
        path = null;
      }
      if (path == null || path.isEmpty) return;
      if (QuoteThumb._found.length >= 120) {
        QuoteThumb._found.remove(QuoteThumb._found.keys.first);
      }
      QuoteThumb._found[id] = path;
      if (mounted && ask == _ask) setState(() => _path = path);
    }());
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null) return const SizedBox.shrink();
    final s = widget.size;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: s,
          height: s,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(path),
                key: const ValueKey('quote_thumb_image'),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: (s * 3).round(),
                errorBuilder: (_, __, ___) => ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest),
              ),
              if (widget.video)
                const Center(
                  child: Icon(Icons.play_arrow_rounded,
                      key: ValueKey('quote_thumb_play'),
                      size: 18,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
