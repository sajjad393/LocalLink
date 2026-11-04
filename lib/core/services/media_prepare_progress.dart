import 'package:flutter/foundation.dart';

/// Bundle 208 (D4): how far a file is with getting ready to show - the
/// lock step (an old plain file is locked first) and the open step (the
/// locked file is unlocked into a view copy). Keyed by the locked file's
/// path, so the chat bubble and the viewer show the same number. No change
/// to the files contract: the protection service reports here.
class MediaPrepareProgress {
  MediaPrepareProgress._();

  static final MediaPrepareProgress instance = MediaPrepareProgress._();

  final Map<String, _Slot> _slots = <String, _Slot>{};
  final Set<String> _locked = <String>{};

  /// 0..1 (null = started, no number yet) for [protectedPath].
  ValueListenable<double?> watch(String protectedPath) =>
      _slots.putIfAbsent(protectedPath, _Slot.new);

  /// Both keys a screen can know: the saved path, and its `.enc` twin
  /// (before an old plain file is locked).
  List<ValueListenable<double?>> watchPath(String path) => [
        watch(path),
        if (!path.endsWith('.enc')) watch('$path.enc'),
      ];

  double? fractionFor(String path) {
    final a = _slots[path]?.value;
    final b = path.endsWith('.enc') ? null : _slots['$path.enc']?.value;
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }

  /// The lock step of [protectedPath]: counts as the first half.
  void reportLock(String protectedPath, int done, int total) {
    _locked.add(protectedPath);
    _set(protectedPath, total <= 0 ? 0 : 0.5 * done / total);
  }

  /// The open step: the whole bar, or the second half after a lock step.
  void reportOpen(String protectedPath, int done, int total) {
    final f = total <= 0 ? 1.0 : done / total;
    _set(protectedPath, _locked.contains(protectedPath) ? 0.5 + 0.5 * f : f);
  }

  void _set(String key, double value) {
    final slot = _slots.putIfAbsent(key, _Slot.new);
    final v = value.clamp(0.0, 1.0);
    // Only whole percents redraw the screen.
    final old = slot.value;
    if (old != null && (old * 100).floor() == (v * 100).floor()) return;
    slot.value = v;
  }

  /// Ready (or failed): the number goes away.
  void done(String protectedPath) {
    _locked.remove(protectedPath);
    final slot = _slots[protectedPath];
    if (slot == null) return;
    slot.value = null;
    if (!slot.listened) _slots.remove(protectedPath);
  }

  /// Bundle 208 (D5): "45%".
  static String label(double fraction) =>
      '${(fraction.clamp(0.0, 1.0) * 100).floor()}%';

  @visibleForTesting
  void resetForTest() {
    _slots.clear();
    _locked.clear();
  }
}

class _Slot extends ValueNotifier<double?> {
  _Slot() : super(null);

  bool get listened => hasListeners;
}
