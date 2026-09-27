import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:locallink/core/security/secure_storage_service.dart';

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

  final SecureStorageService secureStorage;
  final AesGcm _aes = AesGcm.with256bits();
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
    final plaintext = await source.readAsBytes();
    final box = await _aes.encrypt(plaintext, secretKey: await _key(), aad: utf8.encode(_magic));
    final encoded = <int>[
      ...utf8.encode(_magic),
      box.nonce.length,
      box.mac.bytes.length,
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ];
    final part = File('${output.path}$protectedPartSuffix');
    await part.writeAsBytes(encoded, flush: true);
    try {
      if (await output.exists()) await output.delete();
      await part.rename(output.path);
    } catch (_) {
      try { await part.delete(); } catch (_) {}
      rethrow;
    }
  }

  Future<String> materializeForView(String protectedPath, {String extension = '.bin'}) async {
    final input = File(protectedPath);
    _assertLocalProtectedPath(input.path);
    if (!await input.exists()) throw StateError('protected file does not exist');
    final bytes = await input.readAsBytes();
    final magic = utf8.encode(_magic);
    if (bytes.length < magic.length + 2 ||
        bytes.sublist(0, magic.length).join(',') != magic.join(',')) {
      throw const FormatException('invalid protected local file');
    }
    var offset = magic.length;
    final nonceLength = bytes[offset++];
    final macLength = bytes[offset++];
    if (nonceLength < 8 || macLength < 12 || bytes.length <= offset + nonceLength + macLength) {
      throw const FormatException('invalid protected local file envelope');
    }
    final nonce = bytes.sublist(offset, offset + nonceLength); offset += nonceLength;
    final mac = bytes.sublist(offset, offset + macLength); offset += macLength;
    final cipherText = bytes.sublist(offset);
    final plain = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: await _key(),
      aad: utf8.encode(_magic),
    );
    // Always materialize decrypted views into the dedicated attachment view
    // directory, never beside a native direct-file backing object.
    final databaseRoot = await getDatabasesPath();
    final root = Directory('$databaseRoot/attachments');
    await root.create(recursive: true);
    final id = List<int>.generate(12, (_) => _random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final normalizedExtension = _safeViewExtension(extension);
    final view = File('${root.path}/$viewPrefix$id$normalizedExtension');
    await view.writeAsBytes(plain, flush: true);
    return view.path;
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
