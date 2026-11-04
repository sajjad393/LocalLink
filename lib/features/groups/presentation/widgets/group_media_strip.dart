import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/files/presentation/widgets/chat_photo.dart';
import 'package:locallink/features/storage/presentation/storage_screen.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';
import 'package:locallink/features/storage/domain/media_clean_policy.dart';

/// Bundle G5 (mock d1): "MEDIA, LINKS AND DOCS · 24" in Group info - the
/// newest 3 photos / videos and a "+21" tile. A photo opens big; a video,
/// the "+21" tile or the label open the group's files page (the same page
/// as Settings › Storage › this chat).
class GroupMediaStrip extends StatefulWidget {
  const GroupMediaStrip({
    super.key,
    required this.groupId,
    required this.onOpenAll,
    required this.onOpenFile,
    this.load,
    this.thumb,
  });

  final String groupId;
  final void Function(List<MediaFile> files) onOpenAll;
  final void Function(MediaFile file, List<MediaFile> files) onOpenFile;

  /// Tests: the files (default = the phone's media list).
  final Future<List<MediaFile>> Function()? load;

  /// Tests: small picture path of a file (default = the storage thumbs).
  final Future<String?> Function(String fileId)? thumb;

  /// The group's files on this phone, newest first.
  static List<MediaFile> filesOf(Iterable<MediaFile> all, String groupId) =>
      all
          .where((f) => f.isGroup && f.chatId == groupId && !f.removed)
          .toList()
        ..sort((a, b) {
          final t = b.messageAt.compareTo(a.messageAt);
          return t != 0 ? t : a.fileId.compareTo(b.fileId);
        });

  @override
  State<GroupMediaStrip> createState() => _GroupMediaStripState();
}

class _GroupMediaStripState extends State<GroupMediaStrip> {
  List<MediaFile> _files = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final load = widget.load ??
          () async {
            final s = MediaStorageService.instance;
            return s.configured ? await s.scan() : const <MediaFile>[];
          };
      final files = GroupMediaStrip.filesOf(await load(), widget.groupId);
      if (mounted) setState(() => _files = files);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    if (files.isEmpty) return const SizedBox.shrink();
    final visual = files
        .where((f) => f.kind == MediaKind.photo || f.kind == MediaKind.video)
        .toList();
    final shown = visual.take(files.length > 4 ? 3 : 4).toList();
    final more = files.length - shown.length;
    return Column(
      key: const ValueKey('group_media_strip'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          key: const ValueKey('group_media_label'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpenAll(files),
          child: MessengerGroupLabel('Media, links and docs · ${files.length}',
              top: 4),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: SizedBox(
            height: 70,
            child: Row(
              children: [
                for (final f in shown) ...[
                  _Tile(
                    key: ValueKey('group_media_${f.fileId}'),
                    file: f,
                    thumb: widget.thumb ?? MediaStorageService.instance.thumbView,
                    onTap: () => widget.onOpenFile(f, files),
                  ),
                  const SizedBox(width: 6),
                ],
                if (more > 0)
                  GestureDetector(
                    key: const ValueKey('group_media_more'),
                    onTap: () => widget.onOpenAll(files),
                    child: Container(
                      width: 70,
                      height: 70,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFECECF2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('+$more',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF5B5C64))),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({super.key, required this.file, required this.thumb, required this.onTap});

  final MediaFile file;
  final Future<String?> Function(String fileId) thumb;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  String? _path;

  @override
  void initState() {
    super.initState();
    unawaited(widget.thumb(widget.file.fileId).then((v) {
      if (mounted && v != null) setState(() => _path = v);
    }).catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final path = _path;
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 70,
          height: 70,
          child: Stack(fit: StackFit.expand, children: [
            if (path != null)
              Image.file(File(path), fit: BoxFit.cover)
            else
              ColoredBox(
                color: colors.surfaceContainerHighest,
                child: Icon(
                    widget.file.kind == MediaKind.video
                        ? Icons.videocam_outlined
                        : Icons.image_outlined,
                    color: colors.onSurfaceVariant),
              ),
            if (widget.file.kind == MediaKind.video)
              const Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white70, size: 26)),
          ]),
        ),
      ),
    );
  }
}

/// Bundle G5: the group's files page (chat ⋮ "Media, links and docs",
/// the "+21" tile). Same page as Settings › Storage › this chat.
Future<void> openGroupMedia(BuildContext context,
    {required String groupId, required String name, List<MediaFile>? files}) async {
  final service = MediaStorageService.instance;
  var list = files;
  if (list == null) {
    try {
      list = GroupMediaStrip.filesOf(
          service.configured ? await service.scan() : const <MediaFile>[], groupId);
    } catch (_) {
      list = const <MediaFile>[];
    }
  }
  if (!context.mounted) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
        builder: (_) =>
            ChatStorageScreen(service: service, chatName: name, files: list!)),
  );
}

/// A photo from the strip opens big; anything else opens the files page.
Future<void> openGroupMediaFile(BuildContext context, MediaFile f,
    {required String groupId, required String name, required List<MediaFile> files}) async {
  if (f.kind != MediaKind.photo) {
    await openGroupMedia(context, groupId: groupId, name: name, files: files);
    return;
  }
  final service = MediaStorageService.instance;
  String? view;
  try {
    view = await service.viewOf(f);
  } catch (_) {}
  if (view == null || !context.mounted) return;
  final path = view;
  await Navigator.push<void>(context,
      MaterialPageRoute(builder: (_) => ChatPhotoViewer(path: path, title: f.name)));
  service.dropView(path);
}
