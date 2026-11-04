import 'dart:io';

import 'package:crypto/crypto.dart' as crypto_lib;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' show getDatabasesPath;

import 'package:locallink/core/services/app_logger.dart';

/// Bundle 204: the picture code inside the signed profile card.
///
/// `llav1:<first 16 hex of sha256>:<size in bytes>` goes in `avatar_url`
/// (already part of the signed text, so old phones still check the card and
/// simply ignore the code). Empty = no picture (letter avatar).
class ProfilePhotoCode {
  const ProfilePhotoCode(this.hash, this.size);

  final String hash;
  final int size;

  static const String prefix = 'llav1';

  /// The picker makes about 30-80 KB (512 px, quality 78).
  static const int pickMaxSide = 512;
  static const int pickQuality = 78;

  /// Bigger pictures are not sent phone to phone (server only).
  static const int maxNearbyBytes = 200 * 1024;

  /// What a phone takes from the server for a friend.
  static const int maxServerBytes = 2 * 1024 * 1024;

  static final RegExp _code = RegExp(r'^llav1:([0-9a-f]{16}):([0-9]{1,9})$');
  static final RegExp _fileId = RegExp(r'^av[0-9a-f]{16}$');

  String get code => '$prefix:$hash:$size';

  static String hashOf(List<int> bytes) =>
      crypto_lib.sha256.convert(bytes).toString().substring(0, 16);

  static String make(List<int> bytes) => '$prefix:${hashOf(bytes)}:${bytes.length}';

  static ProfilePhotoCode? parse(String? code) {
    final m = _code.firstMatch((code ?? '').trim());
    if (m == null) return null;
    final size = int.parse(m.group(2)!);
    if (size <= 0) return null;
    return ProfilePhotoCode(m.group(1)!, size);
  }

  /// True when [bytes] are the picture of this code.
  bool matches(List<int> bytes) =>
      bytes.length == size && hashOf(bytes) == hash;

  bool get nearbyOk => size <= maxNearbyBytes;

  /// Phone-to-phone file: id `av<hash>`, message id `avatar-<user id>`.
  String get fileId => 'av$hash';
  static bool isFileId(String id) => _fileId.hasMatch(id);
  static String hashOfFileId(String id) => id.substring(2);
  static String messageIdFor(String userId) => '$messagePrefix$userId';
  static const String messagePrefix = 'avatar-';
  static bool isMessageId(String id) => id.startsWith(messagePrefix);
  static String userOfMessageId(String id) => id.substring(messagePrefix.length);
}

/// Bundle 204: "send me your picture" asks, max 3 per friend per 10 minutes
/// (both ways: the asker and the owner use it).
class ProfilePhotoLimiter {
  ProfilePhotoLimiter({this.max = 3, this.window = const Duration(minutes: 10)});

  final int max;
  final Duration window;
  final Map<String, List<int>> _times = <String, List<int>>{};

  bool allow(String key, int nowMs) {
    final list = _times.putIfAbsent(key, () => <int>[]);
    list.removeWhere((t) => nowMs - t >= window.inMilliseconds);
    if (list.length >= max) return false;
    list.add(nowMs);
    return true;
  }

  @visibleForTesting
  void clear() => _times.clear();
}

/// Bundle 204: friends' pictures on this phone, one small JPEG per picture
/// code: `<db folder>/avatars/<hash>.jpg`. Like [GroupPhotoBook].
///
/// The user -> code list comes from the signed cards ([remember]); the
/// picture comes from the friend's phone (Nearby) or the server.
class PeerPhotoBook extends ChangeNotifier {
  PeerPhotoBook._();

  /// Tests: a second phone's book in the same test.
  @visibleForTesting
  PeerPhotoBook.forTest(String dir) : _dir = dir;

  static final PeerPhotoBook instance = PeerPhotoBook._();

  String? _dir;
  final Map<String, bool> _exists = <String, bool>{};

  /// user id -> code, device id -> user id.
  final Map<String, ProfilePhotoCode> _codes = <String, ProfilePhotoCode>{};
  final Map<String, String> _users = <String, String>{};

  /// Tests: use [dir] (or null = no pictures at all).
  @visibleForTesting
  void debugUse(String? dir) {
    _dir = dir;
    _exists.clear();
    _codes.clear();
    _users.clear();
    _ownUser = null;
  }

  String? get folder => _dir;

  Future<void> init() async {
    if (_dir != null) return;
    try {
      final root = await getDatabasesPath();
      final dir = Directory(p.join(root, 'avatars'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir.path;
      notifyListeners();
    } catch (error) {
      AppLogger.warning('PEER_PHOTO_DIR_FAILED', detail: '$error');
    }
  }

  String? _path(String hash) {
    final dir = _dir;
    if (dir == null || !RegExp(r'^[0-9a-f]{16}$').hasMatch(hash)) return null;
    return p.join(dir, '$hash.jpg');
  }

  /// A card said: this user (on this phone [deviceId]) has picture [code]
  /// ('' = no picture). True when the code changed.
  bool remember(String userId, String deviceId, String code) {
    if (userId.isEmpty) return false;
    if (deviceId.isNotEmpty) _users[deviceId] = userId;
    final next = ProfilePhotoCode.parse(code);
    final old = _codes[userId];
    if (next == null) {
      if (old == null) return false;
      _codes.remove(userId);
      notifyListeners();
      return true;
    }
    if (old?.code == next.code) return false;
    _codes[userId] = next;
    notifyListeners();
    return true;
  }

  ProfilePhotoCode? codeOf(String userId) => _codes[userId];

  String? userOfDevice(String deviceId) => _users[deviceId];

  /// The picture of [id] (user id or device id) when it is on this phone
  /// (null = show the letter).
  File? fileFor(String id) {
    final code = _codes[id] ?? _codes[_users[id] ?? ''];
    if (code == null) return null;
    return fileForHash(code.hash);
  }

  /// The file of [hash] if it is there, read fresh from the disk (for the
  /// notification code, which may run in another isolate).
  Future<File?> freshFileForHash(String hash) async {
    await init();
    final path = _path(hash);
    if (path == null) return null;
    final f = File(path);
    return await f.exists() ? f : null;
  }

  File? fileForHash(String hash) {
    final path = _path(hash);
    if (path == null) return null;
    final known = _exists[path];
    if (known != null) return known ? File(path) : null;
    final there = File(path).existsSync();
    _exists[path] = there;
    return there ? File(path) : null;
  }

  /// The card has a code but the picture is not here yet.
  bool needs(String userId) {
    final code = _codes[userId];
    return code != null && fileForHash(code.hash) == null;
  }

  /// Saves [bytes] when they are the picture of [code]. False = refused.
  Future<bool> put(ProfilePhotoCode code, List<int> bytes,
      {int maxBytes = ProfilePhotoCode.maxServerBytes}) async {
    final path = _path(code.hash);
    if (path == null) return false;
    if (bytes.length > maxBytes || !code.matches(bytes)) {
      AppLogger.warning('PEER_PHOTO_BAD', detail: 'bytes=${bytes.length}');
      return false;
    }
    try {
      await File(path).writeAsBytes(bytes, flush: true);
      _exists[path] = true;
      notifyListeners();
      return true;
    } catch (error) {
      AppLogger.warning('PEER_PHOTO_SAVE_FAILED', detail: '$error');
      return false;
    }
  }

  /// My own picture (so "You" rows in groups show it too). Kept as
  /// `avatars/<hash>.jpg` like a friend's; [sweep] keeps it.
  String? _ownUser;
  Future<void> setOwn(String userId, String deviceId, List<int>? bytes) async {
    if (userId.isEmpty) return;
    if (bytes == null || bytes.isEmpty) {
      _ownUser = userId;
      remember(userId, deviceId, '');
      return;
    }
    final code = ProfilePhotoCode.parse(ProfilePhotoCode.make(bytes))!;
    _ownUser = userId;
    if (fileForHash(code.hash) == null) await put(code, bytes);
    remember(userId, deviceId, code.code);
  }

  /// Unfriend / block: that person's picture leaves this phone (the code
  /// stays, so it comes back if you become friends again).
  void dropPicture(String userId) {
    final code = _codes[userId];
    if (code == null) return;
    final path = _path(code.hash);
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    _exists[path] = false;
    notifyListeners();
  }

  /// Drops pictures no card points to (own picture [keepHash] stays).
  void sweep({String? keepHash}) {
    final dir = _dir;
    if (dir == null) return;
    final keep = <String>{
      for (final c in _codes.values) c.hash,
      if (keepHash != null) keepHash,
      if (_codes[_ownUser ?? ''] != null) _codes[_ownUser]!.hash,
    };
    try {
      for (final f in Directory(dir).listSync()) {
        final name = p.basename(f.path);
        if (!name.endsWith('.jpg')) continue;
        if (keep.contains(name.substring(0, name.length - 4))) continue;
        f.deleteSync();
        _exists[f.path] = false;
      }
    } catch (_) {}
  }
}
