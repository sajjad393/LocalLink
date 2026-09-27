import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as legacy;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

/// Owns the encrypted local database lifecycle.
///
/// A single SQLCipher database key is generated once and stored in Android
/// Keystore-backed flutter_secure_storage. Existing plaintext databases are
/// copied into a new encrypted database and atomically replaced after a
/// successful verification reopen.
class DatabaseEncryptionService {
  static const _keyName = 'locallink_db_key_v1';
  static const _migrationMarker = 'locallink_db_cipher_migration_v1';

  final SecureStorageService secureStorage;

  const DatabaseEncryptionService({SecureStorageService? secureStorage})
      : secureStorage = secureStorage ?? const SecureStorageService();

  Future<String> _ensureKey() async {
    final existing = await secureStorage.read(key: _keyName);
    if (existing != null && _validKey(existing)) return existing;
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final encoded = base64UrlEncode(bytes).replaceAll('=', '');
    await secureStorage.write(key: _keyName, value: encoded);
    return encoded;
  }

  bool _validKey(String value) {
    try {
      var v = value;
      while (v.length % 4 != 0) v += '=';
      return base64Url.decode(v).length == 32;
    } catch (_) {
      return false;
    }
  }

  Future<cipher.Database> open({
    required String path,
    required int version,
    required cipher.OnDatabaseCreateFn onCreate,
    required cipher.OnDatabaseVersionChangeFn onUpgrade,
  }) async {
    final key = await _ensureKey();
    final file = File(path);
    final sourcePath = '$path.plaintext-source';
    final targetPath = '$path.cipher-migrating';
    final backupPath = '$path.plaintext-backup';

    // Remove stale plaintext migration artifacts once the encrypted database is
    // already present. The encrypted DB is authoritative in this state.
    if (await file.exists()) {
      if (await File(sourcePath).exists()) await File(sourcePath).delete();
      if (await File(backupPath).exists()) await File(backupPath).delete();
      if (await File(targetPath).exists()) await File(targetPath).delete();
    }

    // Recover a migration interrupted after the plaintext DB was renamed.
    // Never leave a source DB stranded merely because the process was killed.
    if (!await file.exists() && await File(targetPath).exists()) {
      try {
        final recovery = await cipher.openDatabase(targetPath, password: key, readOnly: true);
        await recovery.rawQuery('PRAGMA user_version');
        await recovery.close();
        if (await File(sourcePath).exists()) await File(sourcePath).delete();
        await File(targetPath).rename(path);
      } catch (_) {
        if (!await file.exists() && await File(sourcePath).exists()) {
          await File(sourcePath).rename(path);
        }
        if (await File(targetPath).exists()) await File(targetPath).delete();
      }
    } else if (!await file.exists() && await File(sourcePath).exists()) {
      await File(sourcePath).rename(path);
    } else if (!await file.exists() && await File(backupPath).exists()) {
      // A completed encryption swap may have been interrupted before deletion
      // of the temporary plaintext backup. Restore it as the source so the
      // normal plaintext->SQLCipher migration can be retried safely.
      await File(backupPath).rename(path);
    }
    if (await file.exists() && await _looksLikePlaintextSqlite(file)) {
      await _migratePlaintext(path, key, version, onCreate, onUpgrade);
    }
    final db = await cipher.openDatabase(
      path,
      password: key,
      version: version,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
    // A successful authenticated query proves the key matches the database.
    await db.rawQuery('PRAGMA user_version');
    await secureStorage.write(key: _migrationMarker, value: '1');
    return db;
  }

  Future<bool> _looksLikePlaintextSqlite(File file) async {
    try {
      final bytes = await file.openRead(0, 16).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      const header = 'SQLite format 3\u0000';
      return bytes.length >= header.length &&
          utf8.decode(bytes.take(header.length).toList(), allowMalformed: true) == header;
    } catch (_) {
      return false;
    }
  }

  Future<void> _migratePlaintext(
    String path,
    String password,
    int version,
    cipher.OnDatabaseCreateFn onCreate,
    cipher.OnDatabaseVersionChangeFn onUpgrade,
  ) async {
    final sourcePath = '$path.plaintext-source';
    final targetPath = '$path.cipher-migrating';
    final backupPath = '$path.plaintext-backup';
    final source = File(path);
    final target = File(targetPath);
    if (await target.exists()) await target.delete();
    if (await File(sourcePath).exists()) await File(sourcePath).delete();
    await source.rename(sourcePath);

    legacy.Database? plain;
    cipher.Database? encrypted;
    try {
      plain = await legacy.openDatabase(sourcePath, readOnly: true);
      final versionRows = await plain.rawQuery('PRAGMA user_version');
      final oldVersion = versionRows.isEmpty ? 0 : (versionRows.first['user_version'] as int? ?? 0);
      if (oldVersion > version) {
        throw StateError('database version $oldVersion is newer than supported version $version');
      }
      encrypted = await cipher.openDatabase(targetPath, password: password, version: 1);

      final schemaRows = await plain.rawQuery(
        "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE sql IS NOT NULL AND type IN ('table','index','trigger','view') ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 WHEN 'trigger' THEN 2 ELSE 3 END, name",
      );

      final tables = schemaRows.where((r) => r['type'] == 'table' && r['name'] != 'sqlite_sequence').toList();
      final indexes = schemaRows.where((r) => r['type'] == 'index').toList();
      final triggers = schemaRows.where((r) => r['type'] == 'trigger').toList();
      final views = schemaRows.where((r) => r['type'] == 'view').toList();

      for (final row in tables) {
        final sql = row['sql']?.toString();
        if (sql == null || sql.isEmpty) continue;
        await encrypted.execute(sql);
        final name = row['name']!.toString();
        final rows = await plain.query(name);
        for (final data in rows) {
          await encrypted.insert(name, data, conflictAlgorithm: cipher.ConflictAlgorithm.replace);
        }
      }
      for (final row in views) {
        final sql = row['sql']?.toString();
        if (sql != null && sql.isNotEmpty) await encrypted.execute(sql);
      }
      for (final row in indexes) {
        final sql = row['sql']?.toString();
        if (sql != null && sql.isNotEmpty && !sql.contains('sqlite_autoindex')) {
          await encrypted.execute(sql);
        }
      }
      for (final row in triggers) {
        final sql = row['sql']?.toString();
        if (sql != null && sql.isNotEmpty) await encrypted.execute(sql);
      }
      // Apply the same incremental application migrations that an ordinary
      // database open would have executed from the plaintext DB version.
      if (oldVersion < version) {
        await onUpgrade(encrypted, oldVersion, version);
      }
      await encrypted.execute('PRAGMA user_version=$version');
      await encrypted.close();
      encrypted = null;
      await plain.close();
      plain = null;

      final verify = await cipher.openDatabase(targetPath, password: password, readOnly: true);
      await verify.rawQuery('SELECT name FROM sqlite_master LIMIT 1');
      await verify.close();

      if (await File(backupPath).exists()) await File(backupPath).delete();
      await File(sourcePath).rename(backupPath);
      await File(targetPath).rename(path);
      await File(backupPath).delete();
    } catch (_) {
      try { await encrypted?.close(); } catch (_) {}
      try { await plain?.close(); } catch (_) {}
      if (await File(path).exists()) await File(path).delete();
      if (await File(sourcePath).exists()) await File(sourcePath).rename(path);
      if (await File(targetPath).exists()) await File(targetPath).delete();
      rethrow;
    }
  }
}
