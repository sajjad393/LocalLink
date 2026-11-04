/// Bundle 207 (G3): a plain file that is being read for sending (copied
/// into its send copy) is "held". Locking it (`.enc`) still works, but the
/// plain file is only deleted after the last hold ends, so a send never
/// loses its file in the middle.
class FileInUse {
  FileInUse._();

  static final Map<String, int> _holds = <String, int>{};
  static final Map<String, List<Future<void> Function()>> _after =
      <String, List<Future<void> Function()>>{};

  static bool isHeld(String path) => (_holds[path] ?? 0) > 0;

  /// Runs [work] while [path] is held.
  static Future<T> hold<T>(String path, Future<T> Function() work) async {
    _holds[path] = (_holds[path] ?? 0) + 1;
    try {
      return await work();
    } finally {
      final left = (_holds[path] ?? 1) - 1;
      if (left <= 0) {
        _holds.remove(path);
        final jobs = _after.remove(path) ?? const [];
        for (final job in jobs) {
          try {
            await job();
          } catch (_) {}
        }
      } else {
        _holds[path] = left;
      }
    }
  }

  /// Runs [action] now, or when the last hold on [path] ends.
  static Future<void> whenFree(
      String path, Future<void> Function() action) async {
    if (!isHeld(path)) {
      await action();
      return;
    }
    (_after[path] ??= <Future<void> Function()>[]).add(action);
  }

  /// Tests only.
  static void debugReset() {
    _holds.clear();
    _after.clear();
  }
}
