import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/security/sensitive_file_protection_service.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 147: reuses decrypted view copies of chat media.
///
/// Before, every photo/video bubble decrypted its whole file each time it
/// scrolled into view and deleted the copy when it scrolled off, so scrolling
/// back decrypted again (and the image cache never hit because every copy got
/// a new name). Now a view is decrypted once, shared by everyone showing the
/// same file (bubble, full screen, mini player, picture-in-picture), and kept
/// while in use plus [idleRetention] afterwards. Cached views are "pinned" so
/// the background sweep never deletes a file that is still on screen.
class MediaViewCache {
  MediaViewCache({
    this.maxBytes = 150 * 1024 * 1024,
    this.idleRetention = SensitiveFileProtectionService.viewRetention,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  static final MediaViewCache instance = MediaViewCache();

  final int maxBytes;
  final Duration idleRetention;
  final DateTime Function() _now;

  final LinkedHashMap<String, _ViewEntry> _entries =
      LinkedHashMap<String, _ViewEntry>();
  final Map<String, Future<String>> _inFlight = <String, Future<String>>{};
  Timer? _sweepTimer;

  @visibleForTesting
  int get length => _entries.length;

  @visibleForTesting
  int refsOf(String key) => _entries[key]?.refs ?? 0;

  /// Path of a cached view, or null. Does not take a reference.
  String? peek(String key) => _entries[key]?.path;

  /// Returns a decrypted view for [key] and takes one reference. The first
  /// caller runs [materialize]; callers arriving meanwhile share its result.
  /// [delete] removes the view file once it is evicted.
  Future<String> acquire(
    String key,
    Future<String> Function() materialize, {
    required Future<void> Function(String path) delete,
  }) async {
    // No file check here: this cache is the only one deleting views, and the
    // background sweep skips pinned (cached) views.
    final hit = _entries[key];
    if (hit != null) {
      hit.refs++;
      hit.lastUsed = _now();
      _entries.remove(key);
      _entries[key] = hit; // most recently used last
      return hit.path;
    }
    // NB: the cleanup must not return the removed future — whenComplete
    // would then wait on itself forever.
    final path = await (_inFlight[key] ??=
        _load(key, materialize, delete).whenComplete(() {
      _inFlight.remove(key);
    }));
    final entry = _entries[key];
    if (entry != null && entry.path == path) {
      entry.refs++;
      entry.lastUsed = _now();
    }
    return path;
  }

  Future<String> _load(String key, Future<String> Function() materialize,
      Future<void> Function(String path) delete) async {
    final started = _now();
    final path = await materialize();
    final entry = _ViewEntry(path: path, delete: delete)..lastUsed = _now();
    _entries[key] = entry;
    SensitiveFileProtectionService.pinnedViews.add(path);
    AppLogger.info('MEDIA_VIEW_READY',
        detail: 'key=${_short(key)} '
            'ms=${_now().difference(started).inMilliseconds}');
    // Size only matters for the budget; measured in the background.
    unawaited(File(path).length().then((b) {
      entry.bytes = b;
    }, onError: (Object _) {}));
    _scheduleSweep();
    return path;
  }

  /// Takes one more reference on a view that is already cached (e.g. a
  /// video that starts playing and may outlive its bubble).
  void retain(String key) {
    final entry = _entries[key];
    if (entry == null) return;
    entry.refs++;
    entry.lastUsed = _now();
  }

  /// Gives back one reference taken by [acquire] or [retain].
  void release(String key) {
    final entry = _entries[key];
    if (entry == null) return;
    if (entry.refs > 0) entry.refs--;
    entry.lastUsed = _now();
    _scheduleSweep();
  }

  /// Deletes views nobody uses that idled past [idleRetention], then the
  /// least recently used unused views while over [maxBytes].
  Future<void> evict() async {
    final now = _now();
    for (final key in _entries.keys.toList()) {
      final e = _entries[key]!;
      if (e.refs == 0 && now.difference(e.lastUsed) >= idleRetention) {
        _drop(key);
      }
    }
    var total = _entries.values.fold<int>(0, (sum, e) => sum + e.bytes);
    for (final key in _entries.keys.toList()) {
      if (total <= maxBytes) break;
      final e = _entries[key]!;
      if (e.refs > 0) continue;
      total -= e.bytes;
      _drop(key);
    }
    if (_entries.isEmpty) {
      _sweepTimer?.cancel();
      _sweepTimer = null;
    }
  }

  /// Account reset: the files are wiped elsewhere; forget them all.
  void forgetAll() {
    for (final e in _entries.values) {
      SensitiveFileProtectionService.pinnedViews.remove(e.path);
    }
    _entries.clear();
  }

  /// Drops every unused view now.
  Future<void> clearUnused() async {
    for (final key in _entries.keys.toList()) {
      if (_entries[key]!.refs == 0) _drop(key);
    }
  }

  void _drop(String key, {bool deleteFile = true}) {
    final e = _entries.remove(key);
    if (e == null) return;
    SensitiveFileProtectionService.pinnedViews.remove(e.path);
    if (deleteFile) {
      unawaited(e.delete(e.path).catchError((Object _) {}));
    }
  }

  void _scheduleSweep() {
    _sweepTimer ??= Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(evict());
    });
  }

  @visibleForTesting
  void resetForTest() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    for (final e in _entries.values) {
      SensitiveFileProtectionService.pinnedViews.remove(e.path);
    }
    _entries.clear();
    _inFlight.clear();
  }

  static String _short(String key) {
    final name = key.split('/').last;
    return name.length > 18 ? name.substring(name.length - 18) : name;
  }
}

class _ViewEntry {
  _ViewEntry({required this.path, required this.delete});
  final String path;
  int bytes = 0;
  final Future<void> Function(String path) delete;
  int refs = 0;
  DateTime lastUsed = DateTime.fromMillisecondsSinceEpoch(0);
}
