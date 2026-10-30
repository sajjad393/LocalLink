import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Encrypts app-managed local files at rest with an Android Keystore-backed
/// storage key. Plaintext material is created only as an explicit temporary
/// view copy and is never used as the durable attachment path.
class SensitiveFileProtectionService {
  static const _keyName = 'locallink_local_file_key_v1';
  static const _magic = 'LLFILE1';
  static const protectedPartSuffix = '.enc.part';
  static const plaintextPartSuffix = '.plain.part';
  static const viewPrefix = '.view-';
  static const Duration viewRetention = Duration(minutes: 5);
  static const Duration stalePlaintextRetention = Duration(minutes: 5);
  static const Duration staleProtectedTempRetention = Duration(hours: 1);

  /// Bundle 147: decrypted view copies currently in use (the media view
  /// cache keeps this up to date). The cleanup sweep skips them.
  static final Set<String> pinnedViews = <String>{};

  @visibleForTesting
  static Future<void> encryptFileForTest(String source, String part, List<int> key) =>
      Isolate.run(() => _encryptFileWorker(source, part, key, _magic));

  @visibleForTesting
  static Future<void> decryptFileForTest(String protected, String view, List<int> key) =>
      Isolate.run(() => _decryptFileWorker(protected, view, key, _magic));

  final SecureStorageService secureStorage;
  final Random _random = Random.secure();

  SensitiveFileProtectionService({SecureStorageService? secureStorage})
      : secureStorage = secureStorage ?? const SecureStorageService();

  Future<SecretKey> _key() async {
    var value = await secureStorage.read(key: _keyName);
    if (value == null || value.isEmpty) {
      final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
      value = base64UrlEncode(bytes).replaceAll('=', '');
      await secureStorage.write(key: _keyName, value: value);
    }
    try {
      var raw = value;
      while (raw.length % 4 != 0) raw += '=';
      final bytes = base64Url.decode(raw);
      if (bytes.length != 32) throw const FormatException('invalid local file key');
      return SecretKey(bytes);
    } catch (_) {
      throw StateError('stored local file encryption key is invalid');
    }
  }

  Future<void> protectFile(String plaintextPath, String protectedPath) async {
    final source = File(plaintextPath);
    final output = File(protectedPath);
    if (!await source.exists()) throw StateError('local source file does not exist');
    _assertLocalProtectedPath(source.path);
    _assertLocalProtectedPath(output.path);
    final keyBytes = await (await _key()).extractBytes();
    final part = '${output.path}$protectedPartSuffix';
    // Bundle 147: encryption is CPU-heavy pure Dart; it runs off the UI
    // thread so sending a photo/video never freezes the screen.
    await _runOffUi('encrypt', () => Isolate.run(
        () => _encryptFileWorker(source.path, part, keyBytes, _magic)),
        () => _encryptFileWorker(source.path, part, keyBytes, _magic));
    try {
      if (await output.exists()) await output.delete();
      await File(part).rename(output.path);
    } catch (_) {
      try { await File(part).delete(); } catch (_) {}
      rethrow;
    }
  }

  Future<String> materializeForView(String protectedPath, {String extension = '.bin'}) async {
    final input = File(protectedPath);
    _assertLocalProtectedPath(input.path);
    if (!await input.exists()) throw StateError('protected file does not exist');
    final keyBytes = await (await _key()).extractBytes();
    // Always materialize decrypted views into the dedicated attachment view
    // directory, never beside a native direct-file backing object.
    final databaseRoot = await getDatabasesPath();
    final root = Directory('$databaseRoot/attachments');
    await root.create(recursive: true);
    final id = List<int>.generate(12, (_) => _random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final normalizedExtension = _safeViewExtension(extension);
    final view = '${root.path}/$viewPrefix$id$normalizedExtension';
    // Bundle 147: the whole-file decrypt ran on the UI thread (0.1 s per MB
    // even on a fast CPU) every time a photo/video bubble scrolled into view.
    await _runOffUi('decrypt', () => Isolate.run(
        () => _decryptFileWorker(input.path, view, keyBytes, _magic)),
        () => _decryptFileWorker(input.path, view, keyBytes, _magic));
    return view;
  }

  /// Runs [isolated]; if the isolate itself cannot start (never expected on
  /// Android) the same work runs inline. Errors from the work (bad file,
  /// wrong key, auth failure) are rethrown unchanged.
  Future<void> _runOffUi(String what, Future<void> Function() isolated,
      Future<void> Function() inline) async {
    final started = DateTime.now();
    try {
      await isolated();
    } on FormatException {
      rethrow;
    } on StateError {
      rethrow;
    } on SecretBoxAuthenticationError {
      rethrow;
    } on FileSystemException {
      rethrow;
    } catch (error) {
      AppLogger.warning('MEDIA_${what.toUpperCase()}_FALLBACK', detail: '$error');
      await inline();
    }
    final ms = DateTime.now().difference(started).inMilliseconds;
    if (ms > 300) AppLogger.info('MEDIA_${what.toUpperCase()}_SLOW', detail: 'ms=$ms');
  }

  /// Removes decrypted views and temporary plaintext artifacts that may survive
  /// a force-kill. Durable protected attachments are never removed by this method.
  Future<void> cleanupSensitiveArtifacts(Directory directory, {DateTime? now}) async {
    try {
      if (!await directory.exists()) return;
      final cutoff = (now ?? DateTime.now()).subtract(viewRetention);
      final plainCutoff = (now ?? DateTime.now()).subtract(stalePlaintextRetention);
      final protectedCutoff = (now ?? DateTime.now()).subtract(staleProtectedTempRetention);
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.path.split(Platform.pathSeparator).last;
        try {
          // Bundle 147: views still on screen / playing (view cache, mini
          // player, picture-in-picture) are never swept from under them.
          if (pinnedViews.contains(entry.path)) continue;
          final modified = await entry.lastModified();
          if (name.startsWith(viewPrefix) && modified.isBefore(cutoff)) {
            await entry.delete();
          } else if (name.endsWith(plaintextPartSuffix) && modified.isBefore(plainCutoff)) {
            await entry.delete();
          } else if (name.endsWith(protectedPartSuffix) && modified.isBefore(protectedCutoff)) {
            await entry.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Backward-compatible alias retained for callers that only need view cleanup.
  Future<void> cleanupViewCopies(Directory directory) => cleanupSensitiveArtifacts(directory);

  void _assertLocalProtectedPath(String path) {
    final value = File(path).absolute;
    final normalized = value.path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    final parent = normalized.substring(0, normalized.lastIndexOf('/'));
    final name = normalized.substring(normalized.lastIndexOf('/') + 1);
    if (segments.contains('..') || segments.contains('.') || normalized.contains('\u0000')) {
      throw StateError('invalid local protected path');
    }
    final allowed = parent.endsWith('/attachments') ||
        parent.contains('/attachments/') ||
        parent.endsWith('/files/locallink_direct_files') ||
        parent.contains('/files/locallink_direct_files/');
    if (!allowed) throw StateError('local file is outside protected application storage');
    if (name.isEmpty || name == '.' || name == '..') throw StateError('invalid local protected filename');
  }

  String _safeViewExtension(String extension) {
    final normalized = extension.startsWith('.') ? extension : '.$extension';
    if (!RegExp(r'^\.[A-Za-z0-9]{1,10}$').hasMatch(normalized)) return '.bin';
    return normalized.toLowerCase();
  }

  Future<bool> isProtected(String path) async {
    try { _assertLocalProtectedPath(path); } catch (_) { return false; }
    try {
      final bytes = await File(path).openRead(0, _magic.length).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final magic = utf8.encode(_magic);
      return bytes.length == magic.length && bytes.join(',') == magic.join(',');
    } catch (_) {
      return false;
    }
  }
}

// ---- Bundle 147: isolate workers (top-level so they can run in Isolate.run).
// The on-disk format is unchanged:
// magic | nonce length | mac length | nonce | mac | cipher text.

Future<void> _encryptFileWorker(
    String sourcePath, String partPath, List<int> keyBytes, String magicText) async {
  final plaintext = await File(sourcePath).readAsBytes();
  final magic = utf8.encode(magicText);
  final box = await AesGcm.with256bits()
      .encrypt(plaintext, secretKey: SecretKey(keyBytes), aad: magic);
  final out = BytesBuilder(copy: false)
    ..add(magic)
    ..addByte(box.nonce.length)
    ..addByte(box.mac.bytes.length)
    ..add(box.nonce)
    ..add(box.mac.bytes)
    ..add(box.cipherText);
  await File(partPath).writeAsBytes(out.takeBytes(), flush: true);
}

Future<void> _decryptFileWorker(
    String protectedPath, String viewPath, List<int> keyBytes, String magicText) async {
  final bytes = await File(protectedPath).readAsBytes();
  final magic = utf8.encode(magicText);
  if (bytes.length < magic.length + 2) {
    throw const FormatException('invalid protected local file');
  }
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) throw const FormatException('invalid protected local file');
  }
  var offset = magic.length;
  final nonceLength = bytes[offset++];
  final macLength = bytes[offset++];
  if (nonceLength < 8 || macLength < 12 || bytes.length <= offset + nonceLength + macLength) {
    throw const FormatException('invalid protected local file envelope');
  }
  final nonce = Uint8List.sublistView(bytes, offset, offset + nonceLength);
  offset += nonceLength;
  final mac = Uint8List.sublistView(bytes, offset, offset + macLength);
  offset += macLength;
  final cipherText = Uint8List.sublistView(bytes, offset);
  final plain = await AesGcm.with256bits().decrypt(
    SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
    secretKey: SecretKey(keyBytes),
    aad: magic,
  );
  await File(viewPath).writeAsBytes(plain, flush: true);
}
