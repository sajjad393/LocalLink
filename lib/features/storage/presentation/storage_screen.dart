import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/files/presentation/widgets/chat_photo.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';
import 'package:locallink/features/storage/domain/media_clean_policy.dart';

/// Colours of the bar / legend (mock 12).
const Map<MediaKind, Color> kStorageColors = {
  MediaKind.photo: Color(0xFF1E5BFF),
  MediaKind.video: Color(0xFF22C3D6),
  MediaKind.document: Color(0xFFF2A93B),
  MediaKind.voice: Color(0xFF9B6BF0),
};

const Map<MediaKind, String> kStorageNames = {
  MediaKind.photo: 'Photos',
  MediaKind.video: 'Videos',
  MediaKind.document: 'Documents',
  MediaKind.voice: 'Voice',
};

/// Chat / group names for the Storage screen (key = `d:<id>` / `g:<id>`).
Future<Map<String, String>> loadStorageNames(LocalStore store) async {
  final out = <String, String>{};
  try {
    for (final d in await store.localDevices()) {
      out['d:${d.id}'] = d.name.isEmpty ? 'LinkUp user' : d.name;
    }
  } catch (_) {}
  try {
    for (final g in await store.groups()) {
      out['g:${g['id']}'] = g['name']?.toString() ?? 'Group';
    }
  } catch (_) {}
  return out;
}

String storageLastCleanLabel(DateTime at, int count, int bytes, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = at.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final time = '$h:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'}';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final dayText = diff == 0 ? 'today' : (diff == 1 ? 'yesterday' : '${local.day} ${months[local.month - 1]}');
  final what = count == 0 ? 'nothing removed' : '$count ${count == 1 ? 'file' : 'files'}, ${formatStorageBytes(bytes)}';
  return 'Last clean-up: $dayText, $time · $what';
}

/// U1: Settings › THIS PHONE › Storage row.
class StorageSettingsRow extends StatefulWidget {
  const StorageSettingsRow({super.key, required this.store, this.service});
  final LocalStore store;
  final MediaStorageService? service;

  @override
  State<StorageSettingsRow> createState() => _StorageSettingsRowState();
}

class _StorageSettingsRowState extends State<StorageSettingsRow> {
  static int? _cachedBytes;
  static DateTime? _cachedAt;
  int? _bytes = _cachedBytes;

  MediaStorageService get _service => widget.service ?? MediaStorageService.instance;

  @override
  void initState() {
    super.initState();
    final at = _cachedAt;
    if (at == null || DateTime.now().difference(at) > const Duration(minutes: 1)) {
      unawaited(_count());
    }
  }

  Future<void> _count() async {
    try {
      final summary = await _service.summary();
      _cachedBytes = summary.total;
      _cachedAt = DateTime.now();
      if (mounted) setState(() => _bytes = summary.total);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return MessengerSettingsRow(
      key: const ValueKey('settings_storage'),
      icon: Icons.sd_storage_outlined,
      title: 'Storage',
      subtitle: bytes == null ? 'Checking…' : 'LinkUp uses ${formatStorageBytes(bytes)}',
      onTap: () async {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => StorageScreen(service: _service, names: () => loadStorageNames(widget.store)),
          ),
        );
        _cachedAt = null;
        if (mounted) unawaited(_count());
      },
    );
  }
}

/// U2: Settings › Storage.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key, required this.service, required this.names});
  final MediaStorageService service;
  final Future<Map<String, String>> Function() names;

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  List<MediaFile>? _files;
  PhoneStorage _phone = const PhoneStorage(0, 0);
  Map<String, String> _names = const {};

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onService);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.service.removeListener(_onService);
    super.dispose();
  }

  void _onService() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final results = await Future.wait<Object>([
      widget.service.scan(),
      widget.service.phoneStorage(),
      widget.names(),
    ]);
    if (!mounted) return;
    setState(() {
      _files = results[0] as List<MediaFile>;
      _phone = results[1] as PhoneStorage;
      _names = results[2] as Map<String, String>;
    });
  }

  String _nameOf(ChatStorage c) =>
      _names['${c.isGroup ? 'g' : 'd'}:${c.chatId}'] ?? (c.isGroup ? 'Group' : 'LinkUp user');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final files = _files;
    final summary = files == null ? null : StorageSummary.of(files);
    final service = widget.service;
    final last = service.lastCleanAt;
    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: files == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _card(context, summary!),
                  MessengerListGroup(children: [
                    MessengerSettingsRow(
                      key: const ValueKey('storage_auto_switch'),
                      icon: Icons.cloud_off_rounded,
                      title: 'Free up space automatically',
                      subtitle:
                          'When the phone is more than 70% full, remove photos, videos and documents not opened for 10 days. Voice notes stay.',
                      trailing: Switch(
                        key: const ValueKey('storage_auto_switch_toggle'),
                        value: service.autoClean,
                        onChanged: (v) => service.setAutoClean(v),
                      ),
                      onTap: () => service.setAutoClean(!service.autoClean),
                    ),
                  ]),
                  if (last != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                      child: Text(
                        storageLastCleanLabel(last, service.lastCleanCount, service.lastCleanBytes),
                        key: const ValueKey('storage_last_clean'),
                        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  if (summary.chats.isNotEmpty) ...[
                    const MessengerGroupLabel('Chats, biggest first'),
                    MessengerListGroup(dividerIndent: 72, children: [
                      for (final c in summary.chats)
                        ListTile(
                          key: ValueKey('storage_chat_${c.chatId}'),
                          leading: CircleAvatar(
                            backgroundColor: colors.primary,
                            child: Text(
                              _nameOf(c).isEmpty ? '?' : _nameOf(c).characters.first.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                          title: Text(_nameOf(c), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(c.isGroup ? 'Group' : 'Chat'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(formatStorageBytes(c.bytes),
                                style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant)),
                            Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                          ]),
                          onTap: () async {
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatStorageScreen(
                                  service: service,
                                  chatName: _nameOf(c),
                                  files: StorageSummary.filesOf(files, c.chatId, c.isGroup),
                                ),
                              ),
                            );
                            if (mounted) unawaited(_load());
                          },
                        ),
                    ]),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _card(BuildContext context, StorageSummary summary) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = summary.total;
    return MessengerListGroup(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('LinkUp on this phone', style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(formatStorageBytes(total),
              key: const ValueKey('storage_total'),
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: total <= 0
                  ? ColoredBox(color: colors.surfaceContainerHighest)
                  : Row(children: [
                      for (final k in MediaKind.values)
                        if (summary.byKind[k]! > 0)
                          Expanded(
                            flex: (summary.byKind[k]! * 1000 ~/ total).clamp(1, 1000),
                            child: ColoredBox(color: kStorageColors[k]!),
                          ),
                    ]),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [
            for (final k in MediaKind.values)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: kStorageColors[k], borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Text('${kStorageNames[k]} ${formatStorageBytes(summary.byKind[k]!)}', style: text.bodySmall),
              ]),
          ]),
          if (_phone.known) ...[
            const SizedBox(height: 10),
            Text('Phone: ${_phone.usedPercent}% full · ${formatStorageBytes(_phone.free)} free',
                key: const ValueKey('storage_phone_line'),
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ]),
      ),
    ]);
  }
}

/// U3: one chat's files, biggest first. Hold to pick, then delete.
class ChatStorageScreen extends StatefulWidget {
  const ChatStorageScreen({super.key, required this.service, required this.chatName, required this.files});
  final MediaStorageService service;
  final String chatName;
  final List<MediaFile> files;

  @override
  State<ChatStorageScreen> createState() => _ChatStorageScreenState();
}

class _ChatStorageScreenState extends State<ChatStorageScreen> {
  late final List<MediaFile> _files = List.of(widget.files);
  MediaKind? _filter;
  final Set<String> _picked = <String>{};

  List<MediaFile> get _shown => _filter == null ? _files : _files.where((f) => f.kind == _filter).toList();
  int get _pickedBytes => _files.where((f) => _picked.contains(f.fileId)).fold(0, (s, f) => s + f.bytes);
  int get _total => _files.fold(0, (s, f) => s + f.bytes);

  void _toggle(MediaFile f) => setState(() {
        if (!_picked.remove(f.fileId)) _picked.add(f.fileId);
      });

  Future<void> _open(MediaFile f) async {
    if (f.kind != MediaKind.photo) {
      _toggle(f);
      return;
    }
    final files = widget.service;
    String? view;
    try {
      view = await files.viewOf(f);
    } catch (_) {}
    if (view == null || !mounted) return;
    unawaited(MediaBook.instance.markOpened(f.fileId));
    final path = view;
    await Navigator.push<void>(
        context, MaterialPageRoute(builder: (_) => ChatPhotoViewer(path: path, title: f.name)));
    files.dropView(path);
  }

  Future<void> _delete() async {
    final picked = _files.where((f) => _picked.contains(f.fileId)).toList();
    if (picked.isEmpty) return;
    final ok = await showDeleteFilesSheet(context, count: picked.length, bytes: _pickedBytes, peerName: widget.chatName);
    if (ok != true || !mounted) return;
    await widget.service.deleteManual(picked);
    if (!mounted) return;
    setState(() {
      _files.removeWhere((f) => _picked.contains(f.fileId));
      _picked.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selecting = _picked.isNotEmpty;
    final shown = _shown;
    return Scaffold(
      appBar: selecting
          ? AppBar(
              leading: IconButton(
                  key: const ValueKey('storage_select_close'),
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_picked.clear)),
              title: Text('${_picked.length}', key: const ValueKey('storage_select_count')),
            )
          : AppBar(title: Text('${widget.chatName} · ${formatStorageBytes(_total)}')),
      body: Column(children: [
        if (!selecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Biggest first. Tap to open, hold to pick.',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final entry in <MediaKind?, String>{
              null: 'All',
              MediaKind.photo: 'Photos',
              MediaKind.video: 'Videos',
              MediaKind.document: 'Docs',
              MediaKind.voice: 'Voice',
            }.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: ValueKey('storage_chip_${entry.value}'),
                  label: Text(entry.value),
                  selected: _filter == entry.key,
                  onSelected: (_) => setState(() => _filter = entry.key),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final f = shown[i];
              final on = _picked.contains(f.fileId);
              return _StorageCell(
                key: ValueKey('storage_cell_${f.fileId}'),
                file: f,
                picked: on,
                selecting: selecting,
                service: widget.service,
                onTap: () => selecting ? _toggle(f) : _open(f),
                onLongPress: () => _toggle(f),
              );
            },
          ),
        ),
        if (selecting)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('storage_delete_button'),
                  style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
                  onPressed: _delete,
                  child: Text(
                      'Delete ${_picked.length} ${_picked.length == 1 ? 'file' : 'files'} (${formatStorageBytes(_pickedBytes)})'),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _StorageCell extends StatefulWidget {
  const _StorageCell({
    super.key,
    required this.file,
    required this.picked,
    required this.selecting,
    required this.service,
    required this.onTap,
    required this.onLongPress,
  });
  final MediaFile file;
  final bool picked;
  final bool selecting;
  final MediaStorageService service;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_StorageCell> createState() => _StorageCellState();
}

class _StorageCellState extends State<_StorageCell> {
  String? _thumb;

  @override
  void initState() {
    super.initState();
    if (widget.file.kind == MediaKind.photo || widget.file.kind == MediaKind.video) {
      unawaited(widget.service.thumbView(widget.file.fileId).then((v) {
        if (mounted && v != null) setState(() => _thumb = v);
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final f = widget.file;
    final thumb = _thumb;
    final Widget base;
    if (thumb != null) {
      base = Image.file(File(thumb), fit: BoxFit.cover);
    } else {
      final icon = switch (f.kind) {
        MediaKind.photo => Icons.image_outlined,
        MediaKind.video => Icons.videocam_outlined,
        MediaKind.document => Icons.insert_drive_file_outlined,
        MediaKind.voice => Icons.mic_none_rounded,
      };
      base = ColoredBox(
        color: colors.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: colors.onSurfaceVariant),
            if (f.kind == MediaKind.document)
              Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5)),
          ]),
        ),
      );
    }
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(fit: StackFit.expand, children: [
          base,
          if (widget.picked) ColoredBox(color: colors.primary.withValues(alpha: .25)),
          if (f.kind == MediaKind.video)
            const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 30)),
          if (widget.selecting)
            Positioned(
              right: 5,
              top: 5,
              child: Icon(widget.picked ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: widget.picked ? colors.primary : Colors.white, size: 20),
            ),
          Positioned(
            left: 5,
            bottom: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
              child: Text(formatStorageBytes(f.bytes),
                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// U4: "Delete 3 files?" (mock 15).
Future<bool?> showDeleteFilesSheet(BuildContext context,
    {required int count, required int bytes, required String peerName}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;
      Widget point(String text) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 10),
                child: Container(
                    width: 6, height: 6, decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle)),
              ),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ]),
          );
      final files = count == 1 ? 'file' : 'files';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Delete $count $files?',
                key: const ValueKey('storage_delete_title'),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            point('The $files ${count == 1 ? 'is' : 'are'} deleted from this phone (${formatStorageBytes(bytes)}).'),
            point('The messages stay in the chat with a small picture and "Removed to save space".'),
            point('$peerName still has ${count == 1 ? 'a' : 'their'} copy. Photos you saved to your Gallery stay.'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('storage_delete_confirm'),
                style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Delete files'),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const ValueKey('storage_delete_cancel'),
                onPressed: () => Navigator.pop(sheetContext, false),
                child: const Text('Cancel'),
              ),
            ),
          ]),
        ),
      );
    },
  );
}
