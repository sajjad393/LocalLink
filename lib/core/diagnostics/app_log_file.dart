import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:locallink/core/diagnostics/log_rules.dart';

/// Bundle 180: every AppLogger line also goes to LinkUp's own log file, with
/// full details (the user chose "keep everything" for testing). Written at
/// most once per second; nothing extra is printed to logcat.
class AppLogFile {
  AppLogFile._();

  static final AppLogFile instance = AppLogFile._();
  static const MethodChannel _channel = MethodChannel('locallink/logs');

  /// Lines kept in memory until the folder is known.
  static const int earlyCap = 2000;
  static const int maxDetail = 4000;

  String? _dir;
  String _engine = 'ui';
  final List<String> _pending = <String>[];
  Timer? _timer;
  int _lastPruneSlot = -1;

  String? get dir => _dir;

  /// [engine] = ui (the app screen) or bg (no-screen engine).
  Future<void> start({required String engine}) async {
    _engine = engine;
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('info');
      final dir = info?['dir']?.toString() ?? '';
      if (dir.isNotEmpty) useDir(dir, engine: engine);
    } catch (_) {/* no native side (tests): stay in memory */}
  }

  @visibleForTesting
  void useDir(String dir, {required String engine}) {
    _dir = dir;
    _engine = engine;
    if (_pending.isNotEmpty) _schedule();
  }

  void add(String level, String event, String? detail, {DateTime? now}) {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    _pending.add(encodeLine(t, level, event, detail));
    if (_dir == null) {
      if (_pending.length > earlyCap) {
        _pending.removeRange(0, _pending.length - earlyCap);
      }
      return;
    }
    _schedule();
  }

  /// `epochMs|L|EVENT|details` - one line, never cut short.
  static String encodeLine(int epochMs, String level, String event, String? detail) {
    String clean(String v) =>
        v.replaceAll('\r', '').replaceAll('\n', r' \n ').trim();
    var d = clean(detail ?? '');
    if (d.length > maxDetail) d = '${d.substring(0, maxDetail)}...';
    final e = clean(event).replaceAll('|', '/');
    return '$epochMs|$level|$e|$d';
  }

  void _schedule() {
    _timer ??= Timer(const Duration(seconds: 1), () {
      _timer = null;
      flushNow();
    });
  }

  void flushNow({DateTime? now}) {
    final dir = _dir;
    if (dir == null || _pending.isEmpty) return;
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final slot = LogRules.slotOf(ms);
    final text = '${_pending.join('\n')}\n';
    _pending.clear();
    try {
      Directory(dir).createSync(recursive: true);
      File('$dir/app-$_engine-$slot.log')
          .writeAsStringSync(text, mode: FileMode.append);
      if (slot != _lastPruneSlot) {
        _lastPruneSlot = slot;
        LogRules.prune(dir, slot);
      }
    } catch (_) {}
  }

  /// Account reset / log out: every log file goes (they can hold messages).
  Future<void> clearAll() async {
    _pending.clear();
    _timer?.cancel();
    _timer = null;
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {}
    final dir = _dir;
    if (dir == null) return;
    try {
      for (final e in Directory(dir).listSync()) {
        if (e is File && LogRules.slotFromName(e.uri.pathSegments.last) != null) {
          e.deleteSync();
        }
      }
    } catch (_) {}
  }

  @visibleForTesting
  List<String> get pendingForTest => List<String>.unmodifiable(_pending);

  @visibleForTesting
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _dir = null;
    _engine = 'ui';
    _lastPruneSlot = -1;
  }
}
