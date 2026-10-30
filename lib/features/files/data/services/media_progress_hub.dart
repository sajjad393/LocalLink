import 'package:flutter/foundation.dart';

/// Bytes done / total for one message's media transfer.
@immutable
class MediaProgress {
  const MediaProgress({required this.done, required this.total});

  final int done;
  final int total;

  double get fraction =>
      total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0).toDouble();

  @override
  bool operator ==(Object other) =>
      other is MediaProgress && other.done == done && other.total == total;

  @override
  int get hashCode => Object.hash(done, total);
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

  void update(String messageId, {required int done, required int total}) {
    if (messageId.isEmpty || total <= 0) return;
    final slot = _slots.putIfAbsent(messageId, () => _Slot(this, messageId));
    slot.value = MediaProgress(done: done.clamp(0, total), total: total);
  }

  void clear(String messageId) {
    final slot = _slots[messageId];
    if (slot == null) return;
    slot.value = null;
    if (slot.listeners == 0) _slots.remove(messageId);
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
