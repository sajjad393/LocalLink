import 'dart:io';

/// Bundle 180: same rules as LogFilePolicy.kt - one file per 10 minutes,
/// only the last hour kept, max 10 MB in total.
class LogRules {
  const LogRules._();

  static const int slotMs = 10 * 60 * 1000;
  static const Duration keep = Duration(hours: 1);
  static const int keepSlots = 6;
  static const int maxTotalBytes = 10 * 1024 * 1024;

  static final RegExp _name = RegExp(r'^(native|app-[a-z]+)-(\d+)\.log$');

  static int slotOf(int epochMs) => epochMs <= 0 ? 0 : epochMs ~/ slotMs;

  /// Slot from a log file name, or null if it is not one of ours.
  static int? slotFromName(String name) {
    final m = _name.firstMatch(name);
    return m == null ? null : int.tryParse(m.group(2)!);
  }

  static bool isNativeFile(String name) => name.startsWith('native-');

  /// Names to delete: older than the kept hour, then the oldest until the
  /// total is under [maxTotalBytes]. The current slot is never deleted.
  static List<String> filesToDelete(
      List<({String name, int slot, int size})> files, int nowSlot) {
    final out = <String>[];
    final keepList = <({String name, int slot, int size})>[];
    for (final f in files) {
      if (f.slot < nowSlot - keepSlots) {
        out.add(f.name);
      } else {
        keepList.add(f);
      }
    }
    var total = keepList.fold<int>(0, (a, f) => a + f.size);
    keepList.sort((a, b) => a.slot.compareTo(b.slot));
    for (final f in keepList) {
      if (total <= maxTotalBytes) break;
      if (f.slot >= nowSlot) continue;
      out.add(f.name);
      total -= f.size;
    }
    return out;
  }

  static void prune(String dir, int nowSlot) {
    try {
      final files = <({String name, int slot, int size})>[];
      for (final e in Directory(dir).listSync()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        final slot = slotFromName(name);
        if (slot == null) continue;
        files.add((name: name, slot: slot, size: e.lengthSync()));
      }
      for (final name in filesToDelete(files, nowSlot)) {
        try {
          File('$dir/$name').deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }
}
