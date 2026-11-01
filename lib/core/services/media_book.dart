import 'dart:async';
import 'package:flutter/foundation.dart';

/// Bundle 197b: what this phone knows about one media file (local only,
/// never sent to the other phone). Keyed by the attachment / file id.
@immutable
class MediaState {
  final String fileId;

  /// Our small picture (encrypted file `attachments/thumbs/<id>.jpg.enc`).
  final String? thumbPath;

  /// Video length (for the "0:42" chip on a removed video).
  final int mediaMs;

  /// Sender only: the Gallery "keep access" link of the picked file.
  final String? sourceUri;

  /// Last time the file was really opened (viewer, play, open, save,
  /// forward). Null = never.
  final DateTime? openedAt;

  /// When LinkUp's own copy was removed (auto clean-up or by hand).
  final DateTime? removedAt;

  /// Receiver: the copy saved to the phone (Gallery / Download).
  final String? savedUri;

  const MediaState({
    required this.fileId,
    this.thumbPath,
    this.mediaMs = 0,
    this.sourceUri,
    this.openedAt,
    this.removedAt,
    this.savedUri,
  });

  bool get isRemoved => removedAt != null;
  bool get isSaved => (savedUri ?? '').isNotEmpty;
  bool get hasThumb => (thumbPath ?? '').isNotEmpty;
  bool get hasSource => (sourceUri ?? '').isNotEmpty;

  MediaState copyWith({
    String? thumbPath,
    int? mediaMs,
    String? sourceUri,
    DateTime? openedAt,
    DateTime? removedAt,
    bool clearRemoved = false,
    String? savedUri,
    bool clearSaved = false,
  }) =>
      MediaState(
        fileId: fileId,
        thumbPath: thumbPath ?? this.thumbPath,
        mediaMs: mediaMs ?? this.mediaMs,
        sourceUri: sourceUri ?? this.sourceUri,
        openedAt: openedAt ?? this.openedAt,
        removedAt: clearRemoved ? null : (removedAt ?? this.removedAt),
        savedUri: clearSaved ? null : (savedUri ?? this.savedUri),
      );

  Map<String, Object?> toRow() => {
        'file_id': fileId,
        'thumb_path': thumbPath,
        'media_ms': mediaMs,
        'source_uri': sourceUri,
        'opened_at': openedAt?.toUtc().toIso8601String(),
        'removed_at': removedAt?.toUtc().toIso8601String(),
        'saved_uri': savedUri,
      };

  static MediaState? fromRow(Map<String, Object?> row) {
    final id = row['file_id']?.toString() ?? '';
    if (id.isEmpty) return null;
    DateTime? time(Object? v) {
      final s = v?.toString() ?? '';
      return s.isEmpty ? null : DateTime.tryParse(s);
    }

    String? text(Object? v) {
      final s = v?.toString() ?? '';
      return s.isEmpty ? null : s;
    }

    return MediaState(
      fileId: id,
      thumbPath: text(row['thumb_path']),
      mediaMs: int.tryParse(row['media_ms']?.toString() ?? '') ?? 0,
      sourceUri: text(row['source_uri']),
      openedAt: time(row['opened_at']),
      removedAt: time(row['removed_at']),
      savedUri: text(row['saved_uri']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaState &&
      other.fileId == fileId &&
      other.thumbPath == thumbPath &&
      other.mediaMs == mediaMs &&
      other.sourceUri == sourceUri &&
      other.openedAt == openedAt &&
      other.removedAt == removedAt &&
      other.savedUri == savedUri;

  @override
  int get hashCode => Object.hash(
      fileId, thumbPath, mediaMs, sourceUri, openedAt, removedAt, savedUri);
}

typedef MediaStateWriter = Future<void> Function(Map<String, Object?> row);
typedef MediaStateDeleter = Future<void> Function(List<String> ids);

/// Bundle 197b: in-memory copy of the `media_state` table (DB v27), loaded
/// once when the database opens. Chat bubbles listen to it so a clean-up,
/// a restore or a save redraws them at once.
class MediaBook extends ChangeNotifier {
  MediaBook();

  static final MediaBook instance = MediaBook();

  final Map<String, MediaState> _states = <String, MediaState>{};
  MediaStateWriter? _write;
  MediaStateDeleter? _delete;

  /// Called with Gallery links that are no longer used by any message
  /// (set by the storage service: releases the Android permission).
  void Function(List<String> uris)? onReleaseLinks;

  /// Set by the storage service: an outgoing file was staged (sender) -
  /// make its small picture.
  void Function(String fileId, String path, String contentType, String name)? onStaged;

  /// Bundle 197b: the sender's staged copy is ready. Keeps the Gallery link
  /// (when the picker gave one) and asks for a small picture.
  void staged(String fileId, String? sourceUri, String path, String contentType, String name) {
    if (fileId.isEmpty) return;
    if ((sourceUri ?? '').isNotEmpty && of(fileId)?.sourceUri != sourceUri) {
      unawaited(setSource(fileId, sourceUri!));
    }
    try {
      onStaged?.call(fileId, path, contentType, name);
    } catch (_) {}
  }

  /// Group send: the pending file id becomes the server's file id.
  Future<void> rename(String fromId, String toId) async {
    if (fromId.isEmpty || toId.isEmpty || fromId == toId) return;
    final old = _states[fromId];
    if (old == null) return;
    final cur = _states[toId];
    await _put(MediaState(
      fileId: toId,
      thumbPath: cur?.thumbPath ?? old.thumbPath,
      mediaMs: (cur?.mediaMs ?? 0) > 0 ? cur!.mediaMs : old.mediaMs,
      sourceUri: cur?.sourceUri ?? old.sourceUri,
      openedAt: cur?.openedAt ?? old.openedAt,
      removedAt: cur?.removedAt,
      savedUri: cur?.savedUri,
    ));
    _states.remove(fromId);
    try {
      await _delete?.call([fromId]);
    } catch (_) {}
  }

  void load(
    List<Map<String, Object?>> rows, {
    MediaStateWriter? write,
    MediaStateDeleter? delete,
  }) {
    _states.clear();
    for (final row in rows) {
      final state = MediaState.fromRow(row);
      if (state != null) _states[state.fileId] = state;
    }
    _write = write;
    _delete = delete;
    notifyListeners();
  }

  void resetMemory() {
    _states.clear();
    notifyListeners();
  }

  MediaState? of(String fileId) => _states[fileId];
  bool isRemoved(String fileId) => _states[fileId]?.isRemoved ?? false;
  bool isSaved(String fileId) => _states[fileId]?.isSaved ?? false;
  Iterable<MediaState> get all => _states.values;
  int get length => _states.length;

  Future<void> _put(MediaState next) async {
    final old = _states[next.fileId];
    if (old == next) return;
    _states[next.fileId] = next;
    notifyListeners();
    try {
      await _write?.call(next.toRow());
    } catch (_) {}
  }

  MediaState _base(String fileId) =>
      _states[fileId] ?? MediaState(fileId: fileId);

  /// Opened for real. Written at most once a minute per file.
  Future<void> markOpened(String fileId, {DateTime? now}) async {
    if (fileId.isEmpty) return;
    final at = (now ?? DateTime.now()).toUtc();
    final last = _states[fileId]?.openedAt;
    if (last != null && at.difference(last).abs() < const Duration(minutes: 1)) {
      return;
    }
    await _put(_base(fileId).copyWith(openedAt: at));
  }

  Future<void> markRemoved(String fileId, {DateTime? now}) async {
    if (fileId.isEmpty) return;
    await _put(_base(fileId)
        .copyWith(removedAt: (now ?? DateTime.now()).toUtc()));
  }

  Future<void> clearRemoved(String fileId, {DateTime? now}) async {
    if (fileId.isEmpty || !isRemoved(fileId)) return;
    await _put(_base(fileId).copyWith(
        clearRemoved: true, openedAt: (now ?? DateTime.now()).toUtc()));
  }

  Future<void> setThumb(String fileId, String path, {int mediaMs = 0}) async {
    if (fileId.isEmpty || path.isEmpty) return;
    await _put(_base(fileId).copyWith(
        thumbPath: path, mediaMs: mediaMs > 0 ? mediaMs : null));
  }

  Future<void> setSource(String fileId, String uri) async {
    if (fileId.isEmpty || uri.isEmpty) return;
    await _put(_base(fileId).copyWith(sourceUri: uri));
  }

  Future<void> setSaved(String fileId, String uri, {DateTime? now}) async {
    if (fileId.isEmpty || uri.isEmpty) return;
    await _put(_base(fileId)
        .copyWith(savedUri: uri, openedAt: (now ?? DateTime.now()).toUtc()));
  }

  Future<void> clearSaved(String fileId) async {
    if (!isSaved(fileId)) return;
    await _put(_base(fileId).copyWith(clearSaved: true));
  }

  /// The message is gone: forget its files. Returns the small-picture paths
  /// to delete; Gallery links no other file uses go to [onReleaseLinks].
  /// The saved copy in the Gallery / Download folder is never touched.
  Future<List<String>> forget(Iterable<String> fileIds) async {
    final ids = fileIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return <String>[];
    final thumbs = <String>[];
    final links = <String>{};
    for (final id in ids) {
      final state = _states.remove(id);
      if (state == null) continue;
      if (state.hasThumb) thumbs.add(state.thumbPath!);
      if (state.hasSource) links.add(state.sourceUri!);
    }
    final stillUsed = {
      for (final s in _states.values)
        if (s.hasSource) s.sourceUri!,
    };
    links.removeAll(stillUsed);
    notifyListeners();
    try {
      await _delete?.call(ids.toList(growable: false));
    } catch (_) {}
    if (links.isNotEmpty) {
      try {
        onReleaseLinks?.call(links.toList(growable: false));
      } catch (_) {}
    }
    return thumbs;
  }
}
