import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' show sha256;

import 'package:locallink/features/groups/data/group_nearby_files.dart';

/// Bundle 209: the sha256 of a plain file, read in parts in a background
/// isolate (a 50 MB video does not freeze the screen). '' when the file
/// is missing, too big or can't be read - that file is then not passed on
/// by other members (it still goes from the writer, like before).
class GroupFileHash {
  GroupFileHash._();

  /// Tests can swap the worker (no isolates in fake time).
  static Future<String> Function(String path) worker = _inIsolate;

  static Future<String> ofFile(String path, {int? size}) async {
    if (path.isEmpty) return '';
    if (size != null && (size < 0 || size > GroupFileWire.maxBytes)) return '';
    try {
      final out = await worker(path);
      return GroupNearbyFile.validSha(out) ? out : '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> _inIsolate(String path) =>
      Isolate.run(() => hashNow(path));

  /// Reads [path] in parts and returns its sha256 ('' on any problem).
  static Future<String> hashNow(String path) async {
    final file = File(path);
    if (!await file.exists()) return '';
    final length = await file.length();
    if (length > GroupFileWire.maxBytes) return '';
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
