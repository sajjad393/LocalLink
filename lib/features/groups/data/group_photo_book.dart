import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' show getDatabasesPath;

import 'package:locallink/core/services/app_logger.dart';

/// Bundle G2: group photos on this phone, one small JPEG per group and
/// version: `<db folder>/group_photos/<group id>_<version>.jpg`.
///
/// The server keeps the photo (max 256 KB); the version number comes with
/// the group, so a phone downloads it once per change.
class GroupPhotoBook extends ChangeNotifier {
  GroupPhotoBook._();

  static final GroupPhotoBook instance = GroupPhotoBook._();

  String? _dir;
  final Map<String, bool> _exists = {};
  final Set<String> _loading = {};

  /// Tests: use [dir] (or null = no photos at all).
  @visibleForTesting
  void debugUse(String? dir) {
    _dir = dir;
    _exists.clear();
    _loading.clear();
  }

  Future<void> init() async {
    if (_dir != null) return;
    try {
      final root = await getDatabasesPath();
      final dir = Directory(p.join(root, 'group_photos'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir.path;
      notifyListeners();
    } catch (error) {
      AppLogger.warning('GROUP_PHOTO_DIR_FAILED', detail: '$error');
    }
  }

  String? _path(String groupId, int version) {
    final dir = _dir;
    if (dir == null || groupId.isEmpty || version <= 0) return null;
    final safe = groupId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return p.join(dir, '${safe}_$version.jpg');
  }

  /// The photo file when it is on this phone (null = show the gradient).
  File? fileFor(String groupId, int version) {
    final path = _path(groupId, version);
    if (path == null) return null;
    final known = _exists[path];
    if (known != null) return known ? File(path) : null;
    final there = File(path).existsSync();
    _exists[path] = there;
    return there ? File(path) : null;
  }

  /// Saves [bytes] as this version and drops older versions.
  Future<File?> put(String groupId, int version, List<int> bytes) async {
    final path = _path(groupId, version);
    if (path == null) return null;
    try {
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      _exists[path] = true;
      _dropOlder(groupId, version);
      notifyListeners();
      return file;
    } catch (error) {
      AppLogger.warning('GROUP_PHOTO_SAVE_FAILED', detail: '$error');
      return null;
    }
  }

  /// Downloads the photo once when this version is missing.
  Future<void> ensure(String groupId, int version,
      Future<List<int>?> Function() download) async {
    if (version <= 0) {
      _dropOlder(groupId, 1 << 30);
      return;
    }
    final path = _path(groupId, version);
    if (path == null || fileFor(groupId, version) != null) return;
    if (!_loading.add(path)) return;
    try {
      final bytes = await download();
      if (bytes != null && bytes.isNotEmpty) {
        await put(groupId, version, bytes);
        AppLogger.info('GROUP_PHOTO_DOWNLOADED',
            detail: 'v=$version bytes=${bytes.length}');
      }
    } catch (error) {
      AppLogger.warning('GROUP_PHOTO_DOWNLOAD_FAILED', detail: '$error');
    } finally {
      _loading.remove(path);
    }
  }

  void _dropOlder(String groupId, int keep) {
    final dir = _dir;
    if (dir == null) return;
    final safe = groupId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    try {
      for (final f in Directory(dir).listSync()) {
        final name = p.basename(f.path);
        if (!name.startsWith('${safe}_') || !name.endsWith('.jpg')) continue;
        final v = int.tryParse(
            name.substring(safe.length + 1, name.length - 4));
        if (v != null && v < keep) {
          f.deleteSync();
          _exists[f.path] = false;
        }
      }
    } catch (_) {}
  }

  /// "Delete group": the photo goes too.
  void forget(String groupId) {
    _dropOlder(groupId, 1 << 30);
    notifyListeners();
  }
}
