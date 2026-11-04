import 'package:flutter/foundation.dart';

/// Bytes done / total for one message's media transfer.
@immutable
class MediaProgress {
  const MediaProgress(
      {required this.done, required this.total, this.paused = false});

  final int done;
  final int total;

  /// Bundle 179 (1.6): waiting for a voice call to end ("Sends after the call").
  final bool paused;

  double get fraction =>
      total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0).toDouble();

  @override
  bool operator ==(Object other) =>
      other is MediaProgress &&
      other.done == done &&
      other.total == total &&
      other.paused == paused;

  @override
  int get hashCode => Object.hash(done, total, paused);
}

/// Bundle 150: live Wi-Fi transfer progress per message id.
///
/// The phone already reports `file_progress` (receiver: bytes/total, sender:
/// acked/total chunks). This keeps the latest value per message so the chat
/// bubble can draw a real blue ring instead of a spinner. Entries go away
/// when the transfer finishes, fails, is cancelled or expires.
class MediaProgressHub {
  MediaProgressHub._();

  static final MediaProgressHub instance = MediaProgressHub._();

  final Map<String, _Slot> _slots = <String, _Slot>{};

  /// Listenable for [messageId]; value is null until a number is known.
  ValueListenable<MediaProgress?> watch(String messageId) =>
      _slots.putIfAbsent(messageId, () => _Slot(this, messageId));

  MediaProgress? peek(String messageId) => _slots[messageId]?.value;

  // ---- Bundle 203 (6): one ring per file -------------------------------

  /// A group file travels as `<fileId>.g<8hex>`; the ring belongs to fileId.
  static String baseFileId(String id) {
    final m = RegExp(r'^(.+)\.g[0-9a-f]{8}$').firstMatch(id);
    return m == null ? id : m.group(1)!;
  }

  static String fileKey(String messageId, String fileId) =>
      '$messageId|${baseFileId(fileId)}';

  /// Listenable for ONE file of [messageId].
  ValueListenable<MediaProgress?> watchFile(String messageId, String fileId) {
    final key = fileKey(messageId, fileId);
    return _slots.putIfAbsent(key, () => _Slot(this, key));
  }

  MediaProgress? peekFile(String messageId, String fileId) =>
      _slots[fileKey(messageId, fileId)]?.value;

  /// True when some file of [messageId] has its own live number.
  bool hasFileProgress(String messageId) {
    final prefix = '$messageId|';
    for (final e in _slots.entries) {
      if (e.key.startsWith(prefix) && e.value.value != null) return true;
    }
    return false;
  }

  void update(String messageId,
      {required int done, required int total, String? fileId}) {
    if (messageId.isEmpty || total <= 0) return;
    if (fileId != null && fileId.isNotEmpty) {
      _set(fileKey(messageId, fileId), done, total);
    }
    _set(messageId, done, total);
  }

  void _set(String key, int done, int total) {
    final slot = _slots.putIfAbsent(key, () => _Slot(this, key));
    slot.value = MediaProgress(
        done: done.clamp(0, total),
        total: total,
        paused: slot.value?.paused ?? false);
  }

  /// Bundle 179 (1.6): the file waits for a voice call to end (or goes again).
  void setPaused(String messageId, bool paused, {String? fileId}) {
    if (messageId.isEmpty) return;
    if (fileId != null && fileId.isNotEmpty) {
      _pause(fileKey(messageId, fileId), paused);
    }
    _pause(messageId, paused);
  }

  void _pause(String key, bool paused) {
    final slot = _slots.putIfAbsent(key, () => _Slot(this, key));
    final old = slot.value;
    if (old == null && !paused) return;
    if (!paused && old != null && old.total <= 0) {
      slot.value = null; // no number yet: back to the turning ring
      return;
    }
    slot.value = MediaProgress(
        done: old?.done ?? 0, total: old?.total ?? 0, paused: paused);
  }

  /// No [fileId]: the whole message (all its files). With [fileId]: only
  /// that file; the message ring follows another file still going.
  void clear(String messageId, {String? fileId}) {
    if (fileId != null && fileId.isNotEmpty) {
      _clearKey(fileKey(messageId, fileId));
      final prefix = '$messageId|';
      MediaProgress? other;
      for (final e in _slots.entries) {
        if (e.key.startsWith(prefix) && e.value.value != null) {
          other = e.value.value;
          break;
        }
      }
      if (other == null) {
        _clearKey(messageId);
      } else {
        _slots[messageId]?.value = other;
      }
      return;
    }
    final prefix = '$messageId|';
    for (final key in _slots.keys.where((k) => k.startsWith(prefix)).toList()) {
      _clearKey(key);
    }
    _clearKey(messageId);
  }

  void _clearKey(String key) {
    final slot = _slots[key];
    if (slot == null) return;
    slot.value = null;
    if (slot.listeners == 0) _slots.remove(key);
  }

  void _maybeDrop(_Slot slot) {
    if (slot.listeners == 0 && slot.value == null) {
      if (identical(_slots[slot.id], slot)) _slots.remove(slot.id);
    }
  }

  @visibleForTesting
  int get slotCount => _slots.length;

  @visibleForTesting
  void resetForTest() => _slots.clear();
}

class _Slot extends ValueNotifier<MediaProgress?> {
  _Slot(this.hub, this.id) : super(null);

  final MediaProgressHub hub;
  final String id;
  int listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners = listeners > 0 ? listeners - 1 : 0;
    super.removeListener(listener);
    hub._maybeDrop(this);
  }
}
