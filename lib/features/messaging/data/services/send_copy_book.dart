import 'dart:convert';
import 'dart:io';

import 'package:locallink/core/services/file_in_use.dart';

import '../../../../core/security/sensitive_file_protection_service.dart';
import '../../../../core/services/app_logger.dart';

/// Bundle 203 (3): ONE fixed open copy per file that is being sent
/// (`.send-<fileId><ext>` beside the saved file). Every retry hands the SAME
/// path to the phone's sender, so a file continues where it stopped instead
/// of starting again from 0. The 5-minute `.view-` sweep never touches it; it
/// goes when the file is sent / cancelled / its message is deleted, or after
/// 7 days ([SensitiveFileProtectionService.sendRetention]).
class SendCopyBook {
  SendCopyBook._();
  static final SendCopyBook instance = SendCopyBook._();

  final Map<String, String> _paths = <String, String>{};

  static String safeId(String fileId) {
    final s = fileId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return s.length > 80 ? s.substring(0, 80) : s;
  }

  static String extFor(String originalName) {
    final dot = originalName.lastIndexOf('.');
    if (dot < 0 || dot == originalName.length - 1) return '.bin';
    final e = originalName.substring(dot + 1);
    return RegExp(r'^[A-Za-z0-9]{1,10}$').hasMatch(e)
        ? '.${e.toLowerCase()}'
        : '.bin';
  }

  /// The fixed copy path for [fileId] next to [localPath].
  static String copyPathFor(String localPath, String fileId, String name) {
    final file = File(localPath);
    final dir = file.parent.path;
    return '$dir/${SensitiveFileProtectionService.sendPrefix}'
        '${safeId(fileId)}${extFor(name)}';
  }

  /// The path to hand to the sender for this file. [open] makes a fresh
  /// open copy of a locked (`.enc`) file (the `.view-` copy maker).
  Future<String> pathFor({
    required String localPath,
    required String fileId,
    required String originalName,
    required Future<String> Function(String locked, String ext) open,
  }) async {
    if (localPath.isEmpty || fileId.isEmpty) return localPath;
    final target = copyPathFor(localPath, fileId, originalName);
    final have = File(target);
    try {
      if (await have.exists() && await have.length() > 0) {
        _paths[fileId] = target;
        AppLogger.info('DIRECT_FILE_SEND_COPY',
            detail: 'file=${_short(fileId)} reuse=true');
        return target;
      }
    } catch (_) {}
    final plain = File(localPath);
    final locked = localPath.endsWith('.enc') ? localPath : '$localPath.enc';
    try {
      final part = '$target.part';
      if (await plain.exists() && !localPath.endsWith('.enc')) {
        // Bundle 207 (G3): the plain file is not deleted while it is copied.
        await FileInUse.hold(localPath, () => plain.copy(part));
      } else if (await File(locked).exists()) {
        final view = await open(locked, extFor(originalName));
        try {
          await File(view).rename(part);
        } on FileSystemException {
          await File(view).copy(part);
          try {
            await File(view).delete();
          } catch (_) {}
        }
      } else {
        return localPath;
      }
      await File(part).rename(target);
      _paths[fileId] = target;
      AppLogger.info('DIRECT_FILE_SEND_COPY',
          detail: 'file=${_short(fileId)} reuse=false');
      return target;
    } catch (error, stackTrace) {
      AppLogger.error('DIRECT_FILE_SEND_COPY_FAILED',
          error: error, stackTrace: stackTrace, detail: 'file=${_short(fileId)}');
      try {
        await File('$target.part').delete();
      } catch (_) {}
      // Old way as a fallback (still works, may restart after a sweep).
      if (await plain.exists()) return localPath;
      if (await File(locked).exists()) {
        try {
          return await open(locked, extFor(originalName));
        } catch (_) {}
      }
      return localPath;
    }
  }

  /// The file is done / cancelled / deleted: remove its open copy.
  Future<bool> drop(String fileId) async {
    final path = _paths.remove(fileId);
    if (path == null) return false;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
      AppLogger.info('DIRECT_FILE_SEND_COPY_DELETED',
          detail: 'file=${_short(fileId)}');
      return true;
    } catch (_) {
      return false;
    }
  }

  String? knownPath(String fileId) => _paths[fileId];

  static String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);
}

/// Bundle 203 (4): files the friend already has (no second send) and files
/// the phone is still sending (no second hand-over).
class DirectFilesDoneBook {
  DirectFilesDoneBook({
    required this.read,
    required this.write,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const settingKey = 'direct_files_done';
  static const maxEntries = 500;
  static const keep = Duration(days: 7);
  static const stillSendingFor = Duration(minutes: 10);

  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final DateTime Function() _now;

  Map<String, int>? _done;
  final Map<String, DateTime> _sending = <String, DateTime>{};

  Future<Map<String, int>> _load() async {
    final have = _done;
    if (have != null) return have;
    final map = <String, int>{};
    try {
      final raw = await read(settingKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final ms = v is int ? v : int.tryParse('$v');
            if (ms != null) map['$k'] = ms;
          });
        }
      }
    } catch (_) {}
    _done = map;
    _trim(map);
    return map;
  }

  void _trim(Map<String, int> map) {
    final cut = _now().subtract(keep).millisecondsSinceEpoch;
    map.removeWhere((_, ms) => ms < cut);
    if (map.length > maxEntries) {
      final keys = map.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in keys.take(map.length - maxEntries)) {
        map.remove(e.key);
      }
    }
  }

  Future<void> _save(Map<String, int> map) async {
    try {
      await write(settingKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<bool> isDone(String fileId) async =>
      (await _load()).containsKey(fileId);

  bool isSending(String fileId) {
    final at = _sending[fileId];
    if (at == null) return false;
    if (_now().difference(at) > stillSendingFor) {
      _sending.remove(fileId);
      return false;
    }
    return true;
  }

  void markSending(String fileId) => _sending[fileId] = _now();

  void sendingEnded(String fileId) => _sending.remove(fileId);

  Future<void> markDone(String fileId) async {
    _sending.remove(fileId);
    final map = await _load();
    map[fileId] = _now().millisecondsSinceEpoch;
    _trim(map);
    await _save(map);
  }

  /// The friend asked again (tap to download): send it fresh.
  Future<void> clear(String fileId) async {
    _sending.remove(fileId);
    final map = await _load();
    if (map.remove(fileId) != null) await _save(map);
  }
}
