import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/core/storage/database_config.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:locallink/core/storage/database_encryption_service.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/call_quality.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/features/calls/data/transport/network_policy.dart';

class LocalStore {
  static const int _dbVersion = DatabaseConfig.version;
  static const String _tokenKey = 'locallink_device_token';
  static const String _recoveryRequestSecretKey =
      'locallink_recovery_request_secret';

  late Database _db;
  bool _databaseOpened = false;
  final DatabaseEncryptionService _databaseEncryption;
  final SecureStorageService _secureStorage;
  final StreamController<String> _deletedMessageIds =
      StreamController<String>.broadcast();

  LocalStore(
      {SecureStorageService? secureStorage,
      DatabaseEncryptionService? databaseEncryption})
      : _secureStorage = secureStorage ?? const SecureStorageService(),
        _databaseEncryption = databaseEncryption ??
            DatabaseEncryptionService(secureStorage: secureStorage);
  String? _serverAddress;
  String? _deviceId;
  String? _deviceName;
  String? _deviceToken;
  String? _accountId;
  String? _username;
  String? _syncCursor;
  String? _serverId;
  String? _serverFingerprint;
  AdminWifiRadioPolicy? _adminUserWifiRadioPolicy;
  AdminWifiRadioPolicy? _adminDeviceWifiRadioPolicy;
  int _adminUserPolicyVersion = 0;
  int _adminDevicePolicyVersion = 0;
  String _adminPolicyUpdatedAt = '';

  String? get serverAddress => _serverAddress;
  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;
  String? get deviceToken => _deviceToken;
  String? get accountId => _accountId;
  String? get username => _username;
  String? get syncCursor => _syncCursor;
  String? get serverId => _serverId;
  String? get serverFingerprint => _serverFingerprint;
  EffectiveNetworkPolicy get effectiveNetworkPolicy =>
      EffectiveNetworkPolicy.evaluate(
        wifiRadioPolicy:
            _adminDeviceWifiRadioPolicy ?? _adminUserWifiRadioPolicy,
      );
  AdminWifiRadioPolicy? get adminUserWifiRadioPolicy =>
      _adminUserWifiRadioPolicy;
  AdminWifiRadioPolicy? get adminDeviceWifiRadioPolicy =>
      _adminDeviceWifiRadioPolicy;
  String get wifiRadioPolicySource => effectiveNetworkPolicy.wifiRadioSource;
  int get adminUserPolicyVersion => _adminUserPolicyVersion;
  int get adminDevicePolicyVersion => _adminDevicePolicyVersion;
  String get adminPolicyUpdatedAt => _adminPolicyUpdatedAt;

  Stream<String> get deletedMessageIds => _deletedMessageIds.stream;

  Future<void> init() async {
    if (_databaseOpened) return;
    final dbPath = p.join(await getDatabasesPath(), DatabaseConfig.name);
    _db = await _databaseEncryption.open(
      path: dbPath,
      version: _dbVersion,
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _upgradeTo2(db);
        if (oldVersion < 3) await _upgradeTo3(db);
        if (oldVersion < 4) await _upgradeTo4(db);
        if (oldVersion < 5) await _upgradeTo5(db);
        if (oldVersion < 6) await _upgradeTo6(db);
        if (oldVersion < 7) await _upgradeTo7(db);
        if (oldVersion < 8) await _upgradeTo8(db);
        if (oldVersion < 9) await _upgradeTo9(db);
        if (oldVersion < 10) await _upgradeTo10(db);
        if (oldVersion < 11) await _upgradeTo11(db);
        if (oldVersion < 12) await _upgradeTo12(db);
        if (oldVersion < 13) await _upgradeTo13(db);
        if (oldVersion < 14) await _upgradeTo14(db);
        if (oldVersion < 15) await _upgradeTo15(db);
        if (oldVersion < 16) await _upgradeTo16(db);
        if (oldVersion < 17) await _upgradeTo17(db);
        if (oldVersion < 18) await _upgradeTo18(db);
        if (oldVersion < 20) await _upgradeTo20(db);
      },
    );
    _databaseOpened = true;
    await _loadSettings();
    await _migrateLegacySharedPreferences();
  }

  Future<void> _createSchema(Database db) async {
    await db
        .execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('''CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      sender_id TEXT NOT NULL,
      recipient_id TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL,
      delivered_at TEXT,
      server_seq INTEGER NOT NULL DEFAULT 0,
      is_read INTEGER NOT NULL DEFAULT 0,
      read_at TEXT
    )''');
    await db.execute(
        'CREATE INDEX idx_messages_conversation ON messages(sender_id, recipient_id, created_at, id)');
    await db.execute(
        'CREATE INDEX idx_messages_server_seq ON messages(server_seq)');
    await db.execute(
        'CREATE TABLE groups (id TEXT PRIMARY KEY, name TEXT NOT NULL, owner_id TEXT NOT NULL, created_at TEXT NOT NULL)');
    await db.execute('''CREATE TABLE group_members (
      group_id TEXT NOT NULL,
      device_id TEXT NOT NULL,
      role TEXT NOT NULL,
      joined_at TEXT NOT NULL,
      name TEXT NOT NULL DEFAULT '',
      PRIMARY KEY(group_id, device_id)
    )''');
    await db.execute('''CREATE TABLE group_messages (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL,
      server_seq INTEGER NOT NULL DEFAULT 0,
      is_read INTEGER NOT NULL DEFAULT 0,
      read_at TEXT
    )''');
    await db.execute(
        'CREATE INDEX idx_group_messages_group ON group_messages(group_id, server_seq)');
    await db.execute('''CREATE TABLE outbox (
      id TEXT PRIMARY KEY,
      recipient_id TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL,
      attempt_count INTEGER NOT NULL DEFAULT 0,
      last_attempt_at TEXT
    )''');
    await _upgradeTo3(db);
    await _upgradeTo4(db);
    await _upgradeTo5(db);
    await _upgradeTo6(db);
    await _upgradeTo7(db);
    await _upgradeTo8(db);
    await _upgradeTo9(db);
    await _upgradeTo10(db);
    await _upgradeTo11(db);
    await _upgradeTo12(db);
    await _upgradeTo13(db);
    await _upgradeTo14(db);
    await _upgradeTo15(db);
    await _upgradeTo16(db);
    await _upgradeTo17(db);
    await _upgradeTo18(db);
    await _upgradeTo20(db);
  }

  Future<void> _upgradeTo2(Database db) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS groups (id TEXT PRIMARY KEY, name TEXT NOT NULL, owner_id TEXT NOT NULL, created_at TEXT NOT NULL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS group_members (group_id TEXT NOT NULL, device_id TEXT NOT NULL, role TEXT NOT NULL, joined_at TEXT NOT NULL, name TEXT NOT NULL DEFAULT \'\', PRIMARY KEY(group_id, device_id))');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS group_messages (id TEXT PRIMARY KEY, group_id TEXT NOT NULL, sender_id TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL, server_seq INTEGER NOT NULL DEFAULT 0)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_group_messages_group ON group_messages(group_id, server_seq)');
  }

  Future<void> _upgradeTo3(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS message_attachments (
      message_id TEXT NOT NULL, file_id TEXT NOT NULL,
      original_name TEXT NOT NULL, content_type TEXT NOT NULL,
      size INTEGER NOT NULL DEFAULT 0, sha256 TEXT NOT NULL DEFAULT '',
      width INTEGER NOT NULL DEFAULT 0, height INTEGER NOT NULL DEFAULT 0,
      is_image INTEGER NOT NULL DEFAULT 0, download_url TEXT,
      thumbnail_url TEXT, local_path TEXT, position INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(message_id, file_id)
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_message_attachments_file ON message_attachments(file_id)');
    await db.execute('''CREATE TABLE IF NOT EXISTS group_message_attachments (
      group_message_id TEXT NOT NULL, file_id TEXT NOT NULL,
      original_name TEXT NOT NULL, content_type TEXT NOT NULL,
      size INTEGER NOT NULL DEFAULT 0, sha256 TEXT NOT NULL DEFAULT '',
      width INTEGER NOT NULL DEFAULT 0, height INTEGER NOT NULL DEFAULT 0,
      is_image INTEGER NOT NULL DEFAULT 0, download_url TEXT,
      thumbnail_url TEXT, local_path TEXT, position INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(group_message_id, file_id)
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_group_message_attachments_file ON group_message_attachments(file_id)');
    await db.execute('''CREATE TABLE IF NOT EXISTS pending_attachments (
      id TEXT PRIMARY KEY, message_id TEXT NOT NULL, local_path TEXT NOT NULL,
      original_name TEXT NOT NULL, content_type TEXT NOT NULL, size INTEGER NOT NULL,
      remote_file_id TEXT, created_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pending_attachments_message ON pending_attachments(message_id)');
  }

  Future<void> _upgradeTo4(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS group_outbox (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL,
      attempt_count INTEGER NOT NULL DEFAULT 0,
      last_attempt_at TEXT
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_group_outbox_created ON group_outbox(created_at, id)');
    await db.execute('''CREATE TABLE IF NOT EXISTS pending_group_attachments (
      id TEXT PRIMARY KEY,
      message_id TEXT NOT NULL,
      local_path TEXT NOT NULL,
      original_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size INTEGER NOT NULL,
      remote_file_id TEXT,
      created_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pending_group_attachments_message ON pending_group_attachments(message_id)');
  }

  Future<void> _upgradeTo5(Database db) async {
    await db.execute("""CREATE TABLE IF NOT EXISTS calls (
      id TEXT PRIMARY KEY,
      caller_id TEXT NOT NULL,
      callee_id TEXT NOT NULL,
      status TEXT NOT NULL,
      started_at TEXT NOT NULL,
      answered_at TEXT,
      ended_at TEXT,
      duration_seconds INTEGER NOT NULL DEFAULT 0,
      end_reason TEXT NOT NULL DEFAULT ''
    )""");
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_calls_started ON calls(started_at DESC, id DESC)');
  }

  Future<void> _upgradeTo6(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS call_quality_samples (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      call_id TEXT NOT NULL,
      sampled_at TEXT NOT NULL,
      connection_state TEXT NOT NULL,
      transport_state TEXT NOT NULL,
      rtt_ms REAL,
      jitter_ms REAL,
      packets_lost INTEGER NOT NULL DEFAULT 0,
      packets_received INTEGER NOT NULL DEFAULT 0,
      packet_loss_percent REAL,
      quality TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_call_quality_call_time ON call_quality_samples(call_id, sampled_at DESC)');
  }

  Future<void> _upgradeTo7(Database db) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS peer_keys (peer_id TEXT PRIMARY KEY, shared_key TEXT NOT NULL, updated_at TEXT NOT NULL)');
  }

  Future<void> _upgradeTo8(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS direct_files (
      file_id TEXT PRIMARY KEY,
      message_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      local_path TEXT NOT NULL,
      original_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL DEFAULT '',
      received_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_direct_files_message ON direct_files(message_id)');
  }

  Future<void> _upgradeTo9(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS known_devices (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      platform TEXT NOT NULL,
      created_at TEXT NOT NULL,
      last_seen_at TEXT NOT NULL,
      network_status TEXT NOT NULL DEFAULT 'red',
      server_connected INTEGER NOT NULL DEFAULT 0,
      internet_available INTEGER NOT NULL DEFAULT 0,
      wifi_direct_connected INTEGER NOT NULL DEFAULT 0,
      status_updated_at TEXT NOT NULL DEFAULT ''
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_known_devices_status ON known_devices(network_status, status_updated_at)');
  }

  Future<void> _upgradeTo10(Database db) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS identity_peers (peer_id TEXT PRIMARY KEY, public_key TEXT NOT NULL, updated_at TEXT NOT NULL)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_identity_peers_updated ON identity_peers(updated_at)');
  }

  Future<void> _upgradeTo11(Database db) async {
    await db.execute('ALTER TABLE outbox ADD COLUMN network_body TEXT');
  }

  Future<void> _upgradeTo12(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS profile_cache (
      user_id TEXT PRIMARY KEY,
      username TEXT NOT NULL,
      display_name TEXT NOT NULL,
      avatar_url TEXT NOT NULL DEFAULT '',
      local_avatar_path TEXT NOT NULL DEFAULT '',
      avatar_updated_at TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL
    )''');
  }

  Future<void> _upgradeTo13(Database db) async {
    // Phase 32 keeps the local known-device cache compatible; account device
    // records are fetched from the authenticated server endpoint.
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_known_devices_name ON known_devices(name COLLATE NOCASE)');
  }

  Future<void> _upgradeTo14(Database db) async {
    // Phase 33 stores the trusted LocalLink server identity separately from
    // the server URL. This is public pinning metadata, not a secret.
    // It lets first-time pairing detect silent server identity changes.
  }

  Future<void> _upgradeTo15(Database db) async {
    // Phase 39 keeps account-owned file metadata locally for metadata-first
    // restoration. File bytes remain remote until explicitly downloaded.
    await db.execute('''CREATE TABLE IF NOT EXISTS restored_files (
      id TEXT PRIMARY KEY,
      original_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL DEFAULT '',
      width INTEGER NOT NULL DEFAULT 0,
      height INTEGER NOT NULL DEFAULT 0,
      is_image INTEGER NOT NULL DEFAULT 0,
      download_url TEXT NOT NULL,
      thumbnail_url TEXT NOT NULL DEFAULT '',
      restored_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_restored_files_name ON restored_files(original_name COLLATE NOCASE)');
  }

  Future<void> _upgradeTo16(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS directory_profiles (
      user_id TEXT PRIMARY KEY, device_id TEXT NOT NULL DEFAULT '', username TEXT NOT NULL DEFAULT '',
      display_name TEXT NOT NULL DEFAULT '', phone_number TEXT NOT NULL DEFAULT '', avatar_url TEXT NOT NULL DEFAULT '',
      profile_version INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT '', signing_public_key TEXT NOT NULL DEFAULT '', identity_public_key TEXT NOT NULL DEFAULT '',
      signature TEXT NOT NULL DEFAULT '', phone_visibility TEXT NOT NULL DEFAULT 'contacts',
      discoverable_by_phone INTEGER NOT NULL DEFAULT 1, discoverable_by_name INTEGER NOT NULL DEFAULT 1,
      directory_sync_enabled INTEGER NOT NULL DEFAULT 1, source TEXT NOT NULL DEFAULT 'mesh', synced_at TEXT NOT NULL DEFAULT ''
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_directory_profiles_name ON directory_profiles(display_name COLLATE NOCASE)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_directory_profiles_phone ON directory_profiles(phone_number)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_directory_profiles_device ON directory_profiles(device_id)');
    await db.execute(
        "CREATE TABLE IF NOT EXISTS contacts (user_id TEXT PRIMARY KEY, device_id TEXT NOT NULL DEFAULT '', added_at TEXT NOT NULL)");
    await db.execute(
        'CREATE TABLE IF NOT EXISTS blocked_users (user_id TEXT PRIMARY KEY, blocked_at TEXT NOT NULL)');
    await db.execute(
        "CREATE TABLE IF NOT EXISTS directory_sync_state (peer_id TEXT PRIMARY KEY, last_sync_at TEXT NOT NULL DEFAULT '', last_profile_version INTEGER NOT NULL DEFAULT 0)");
    await db.execute(
        'CREATE TABLE IF NOT EXISTS directory_seen (sync_id TEXT PRIMARY KEY, seen_at TEXT NOT NULL)');
    final cols = await db.rawQuery('PRAGMA table_info(profile_cache)');
    final names = {for (final c in cols) c['name']?.toString() ?? ''};
    final additions = <String, String>{
      'phone_number': "TEXT NOT NULL DEFAULT ''",
      'profile_version': 'INTEGER NOT NULL DEFAULT 0',
      'phone_visibility': "TEXT NOT NULL DEFAULT 'contacts'",
      'discoverable_by_phone': 'INTEGER NOT NULL DEFAULT 1',
      'discoverable_by_name': 'INTEGER NOT NULL DEFAULT 1',
      'directory_sync_enabled': 'INTEGER NOT NULL DEFAULT 1',
    };
    for (final e in additions.entries) {
      if (!names.contains(e.key))
        await db.execute(
            'ALTER TABLE profile_cache ADD COLUMN ${e.key} ${e.value}');
    }
  }

  Future<void> _upgradeTo17(Database db) async {
    final messageColumns = await db.rawQuery('PRAGMA table_info(messages)');
    final messageNames = {
      for (final row in messageColumns) row['name']?.toString() ?? ''
    };
    if (!messageNames.contains('is_read')) {
      await db.execute(
        'ALTER TABLE messages ADD COLUMN is_read INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!messageNames.contains('read_at')) {
      await db.execute('ALTER TABLE messages ADD COLUMN read_at TEXT');
    }

    final groupColumns = await db.rawQuery('PRAGMA table_info(group_messages)');
    final groupNames = {
      for (final row in groupColumns) row['name']?.toString() ?? ''
    };
    if (!groupNames.contains('is_read')) {
      await db.execute(
        'ALTER TABLE group_messages ADD COLUMN is_read INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!groupNames.contains('read_at')) {
      await db.execute('ALTER TABLE group_messages ADD COLUMN read_at TEXT');
    }

    await db.execute('''CREATE TABLE IF NOT EXISTS notification_state (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      message_id TEXT NOT NULL,
      notification_id INTEGER NOT NULL,
      notified_at TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notification_state_conversation '
      'ON notification_state(kind, conversation_id, notified_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notification_state_message '
      'ON notification_state(message_id)',
    );
  }

  Future<void> _upgradeTo18(Database db) async {
    const tables = [
      'message_attachments',
      'group_message_attachments',
      'restored_files'
    ];
    const additions = <String, String>{
      'crypto_version': "TEXT NOT NULL DEFAULT ''",
      'crypto_scope': "TEXT NOT NULL DEFAULT ''",
      'crypto_key_version': 'INTEGER NOT NULL DEFAULT 0',
      'crypto_nonce': 'TEXT',
      'crypto_mac': 'TEXT',
      'thumbnail_crypto_nonce': 'TEXT',
      'thumbnail_crypto_mac': 'TEXT',
    };
    for (final table in tables) {
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      final names = {for (final c in cols) c['name']?.toString() ?? ''};
      for (final entry in additions.entries) {
        if (!names.contains(entry.key)) {
          await db.execute(
              'ALTER TABLE $table ADD COLUMN ${entry.key} ${entry.value}');
        }
      }
    }
  }

  Future<void> _upgradeTo20(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(call_quality_samples)');
    final names = {for (final c in cols) c['name']?.toString() ?? ''};
    if (names.contains('ice_connection_state') &&
        !names.contains('transport_state')) {
      await db.execute(
          'ALTER TABLE call_quality_samples RENAME COLUMN ice_connection_state TO transport_state');
    } else if (!names.contains('transport_state')) {
      await db.execute(
          "ALTER TABLE call_quality_samples ADD COLUMN transport_state TEXT NOT NULL DEFAULT 'unknown'");
    }
  }

  Future<void> _loadSettings() async {
    final rows = await _db.query('settings');
    final values = <String, String>{
      for (final row in rows)
        if (row['key'] != null && row['value'] != null)
          row['key']!.toString(): row['value']!.toString(),
    };
    _serverAddress = values['server_address'];
    _deviceId = values['device_id'];
    _deviceName = values['device_name'];
    _syncCursor = values['sync_cursor'];
    _deviceToken = await _secureStorage.read(key: _tokenKey);
    _accountId = values['account_id'];
    _username = values['username'];
    _serverId = values['server_id'];
    _serverFingerprint = values['server_fingerprint'];
    _adminUserWifiRadioPolicy = AdminWifiRadioPolicyX.fromStorage(
        values['admin_user_wifi_radio_policy']);
    _adminDeviceWifiRadioPolicy = AdminWifiRadioPolicyX.fromStorage(
        values['admin_device_wifi_radio_policy']);
    _adminUserPolicyVersion =
        int.tryParse(values['admin_user_policy_version'] ?? '') ?? 0;
    _adminDevicePolicyVersion =
        int.tryParse(values['admin_device_policy_version'] ?? '') ?? 0;
    _adminPolicyUpdatedAt = values['admin_policy_updated_at'] ?? '';
  }

  Future<void> _migrateLegacySharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('legacy_migrated_v1') == true) return;
    final legacyServer = prefs.getString('server_address');
    final legacyId = prefs.getString('device_id');
    final legacyName = prefs.getString('device_name');
    final legacyToken = prefs.getString('device_token');
    if (_serverAddress == null && legacyServer != null) {
      await saveConfiguration(
          server: legacyServer,
          id: legacyId ?? generateDeviceId(),
          name: legacyName ?? 'Local Device');
    }
    if (_deviceToken == null && legacyToken != null && legacyToken.isNotEmpty) {
      await _secureStorage.write(key: _tokenKey, value: legacyToken);
      _deviceToken = legacyToken;
    }
    final legacyOutbox = prefs.getString('outbox');
    if (legacyOutbox != null) {
      try {
        for (final encoded in _decodeList(legacyOutbox)) {
          final item = Map<String, dynamic>.from(encoded as Map);
          if (item['id'] != null &&
              item['recipient_id'] != null &&
              item['body'] != null &&
              item['created_at'] != null) {
            await addOutbox(item);
          }
        }
      } catch (_) {}
    }
    final migratedMessageKeys =
        prefs.getKeys().where((k) => k.startsWith('messages_')).toList();
    for (final key in migratedMessageKeys) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        for (final encoded in _decodeList(raw)) {
          await saveMessage(
              Message.fromJson(Map<String, dynamic>.from(encoded as Map)));
        }
      } catch (_) {}
    }

    // Legacy SharedPreferences contained a bearer token and other persisted
    // connection state in plaintext app preferences. Once migration succeeds,
    // remove those legacy copies so the sensitive credential is not retained.
    for (final key in [
      'server_address',
      'device_id',
      'device_name',
      'device_token',
      'outbox',
      ...migratedMessageKeys,
    ]) {
      await prefs.remove(key);
    }
    await prefs.setBool('legacy_migrated_v1', true);
  }

  List<dynamic> _decodeList(String raw) {
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded : const [];
  }

  Future<bool> isConfigured() async =>
      _serverAddress != null &&
      _deviceId != null &&
      _deviceName != null &&
      _deviceToken != null &&
      _deviceToken!.isNotEmpty;

  Future<void> trustServer(
      {required String serverId, required String fingerprint}) async {
    _serverId = serverId.trim();
    _serverFingerprint = fingerprint.trim().toUpperCase();
    await _putSetting('server_id', _serverId!);
    await _putSetting('server_fingerprint', _serverFingerprint!);
  }

  Future<void> clearServerTrust() async {
    _serverId = null;
    _serverFingerprint = null;
    await _db.delete('settings',
        where: 'key IN (?,?)', whereArgs: ['server_id', 'server_fingerprint']);
  }

  Future<void> saveConfiguration(
      {required String server,
      required String id,
      required String name,
      String? token,
      String? accountId,
      String? username}) async {
    _serverAddress = server.trim();
    _deviceId = id.trim();
    _deviceName = name.trim();
    await _putSetting('server_address', _serverAddress!);
    await _putSetting('device_id', _deviceId!);
    await _putSetting('device_name', _deviceName!);
    if (accountId != null && accountId.trim().isNotEmpty) {
      _accountId = accountId.trim();
      await _putSetting('account_id', _accountId!);
    }
    if (username != null && username.trim().isNotEmpty) {
      _username = username.trim();
      await _putSetting('username', _username!);
    }
    if (token != null && token.isNotEmpty) {
      _deviceToken = token;
      await _secureStorage.write(key: _tokenKey, value: token);
    }
  }

  Future<void> clearConfiguration() async {
    _serverAddress = null;
    _deviceId = null;
    _deviceName = null;
    _deviceToken = null;
    _accountId = null;
    _username = null;
    _syncCursor = null;
    _serverId = null;
    _serverFingerprint = null;
    await _db.transaction((txn) async {
      for (final table in [
        'settings',
        'messages',
        'outbox',
        'group_outbox',
        'message_attachments',
        'direct_files',
        'pending_attachments',
        'pending_group_attachments',
        'group_message_attachments',
        'group_messages',
        'group_members',
        'groups',
        'calls',
        'call_quality_samples',
        'restored_files',
        'profile_cache',
        'directory_profiles',
        'contacts',
        'blocked_users',
        'directory_sync_state',
        'directory_seen',
        'notification_state'
      ]) {
        await txn.delete(table);
      }
    });
    try {
      final root = await getDatabasesPath();
      final attachmentsDir = Directory(p.join(root, 'attachments'));
      if (await attachmentsDir.exists())
        await attachmentsDir.delete(recursive: true);
    } catch (_) {}
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _recoveryRequestSecretKey);
  }

  Future<void> saveProfile(LocalProfile profile) async {
    await _db.insert('profile_cache', profile.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setPendingProfileUpdate(String displayName, String username,
      {String phoneNumber = '',
      String phoneVisibility = 'contacts',
      bool discoverableByPhone = true,
      bool discoverableByName = true,
      bool directorySyncEnabled = true}) async {
    await _putSetting(
        'pending_profile_update',
        jsonEncode({
          'display_name': displayName,
          'username': username,
          'phone_number': phoneNumber,
          'phone_visibility': phoneVisibility,
          'discoverable_by_phone': discoverableByPhone,
          'discoverable_by_name': discoverableByName,
          'directory_sync_enabled': directorySyncEnabled,
        }));
  }

  Future<Map<String, dynamic>?> pendingProfileUpdate() async {
    final rows = await _db.query('settings',
        columns: ['value'],
        where: 'key=?',
        whereArgs: ['pending_profile_update'],
        limit: 1);
    if (rows.isEmpty) return null;
    try {
      final value = jsonDecode(rows.first['value']?.toString() ?? '');
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingProfileUpdate() async => _db.delete('settings',
      where: 'key=?', whereArgs: ['pending_profile_update']);

  Future<void> saveRecoveryRequest(
      {required String requestId,
      required String requestSecret,
      required String deviceId}) async {
    await _putSetting('recovery_request',
        jsonEncode({'request_id': requestId, 'device_id': deviceId}));
    await _secureStorage.write(
        key: _recoveryRequestSecretKey, value: requestSecret);
  }

  Future<Map<String, dynamic>?> recoveryRequest() async {
    final rows = await _db.query('settings',
        columns: ['value'],
        where: 'key=?',
        whereArgs: ['recovery_request'],
        limit: 1);
    if (rows.isEmpty) return null;
    try {
      final value = jsonDecode(rows.first['value']?.toString() ?? '');
      if (value is! Map) return null;
      final out = Map<String, dynamic>.from(value);
      final secret = await _secureStorage.read(key: _recoveryRequestSecretKey);
      if (secret == null || secret.isEmpty) return null;
      out['request_secret'] = secret;
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearRecoveryRequest() async {
    await _db
        .delete('settings', where: 'key=?', whereArgs: ['recovery_request']);
    await _secureStorage.delete(key: _recoveryRequestSecretKey);
  }

  Future<String?> pendingProfileAvatarPath() async {
    final rows = await _db.query('settings',
        columns: ['value'],
        where: 'key=?',
        whereArgs: ['pending_profile_avatar'],
        limit: 1);
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  Future<void> setPendingProfileAvatarPath(String path) async =>
      _putSetting('pending_profile_avatar', path);

  Future<void> clearPendingProfileAvatarPath() async => _db.delete('settings',
      where: 'key=?', whereArgs: ['pending_profile_avatar']);

  Future<String> pendingProfileAvatarFilePath(String extension) async {
    final dir = await getDatabasesPath();
    return p.join(dir, 'profile_avatar_pending$extension');
  }

  Future<LocalProfile?> profile() async {
    final rows = await _db.query('profile_cache', limit: 1);
    return rows.isEmpty
        ? null
        : LocalProfile.fromJson(Map<String, dynamic>.from(rows.first));
  }

  Future<void> clearProfile() async => _db.delete('profile_cache');

  Future<String> profileAvatarPath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, 'profile_avatar');
  }

  Future<void> saveProfileAvatarPath(String path) async {
    final id = _accountId;
    if (id == null || id.isEmpty) return;
    await _db.update('profile_cache', {'local_avatar_path': path},
        where: 'user_id=?', whereArgs: [id]);
  }

  Future<void> saveDirectoryProfile(Map<String, dynamic> profile) async {
    final row = Map<String, dynamic>.from(profile);
    for (final key in [
      'discoverable_by_phone',
      'discoverable_by_name',
      'directory_sync_enabled'
    ]) {
      final v = row[key];
      row[key] = v == true || v?.toString() == '1' ? 1 : 0;
    }
    row['synced_at'] ??= DateTime.now().toUtc().toIso8601String();
    await _db.insert('directory_profiles', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> directoryProfile(String userId) async {
    final rows = await _db.query('directory_profiles',
        where: 'user_id=?', whereArgs: [userId], limit: 1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<Map<String, dynamic>?> directoryProfileByDeviceId(
      String deviceId) async {
    final rows = await _db.query('directory_profiles',
        where: 'device_id=?', whereArgs: [deviceId], limit: 1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<Map<String, dynamic>?> directoryProfileByPhone(String phone) async {
    final rows = await _db.query('directory_profiles',
        where: 'phone_number=?', whereArgs: [phone], limit: 1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<List<Map<String, dynamic>>> searchDirectoryByName(
          String query) async =>
      _db.query('directory_profiles',
          where: 'display_name LIKE ? OR username LIKE ?',
          whereArgs: ['%$query%', '%$query%'],
          orderBy: 'display_name COLLATE NOCASE ASC',
          limit: 50);
  Future<List<Map<String, dynamic>>> directoryProfiles() async =>
      _db.query('directory_profiles', orderBy: 'updated_at DESC');
  Future<void> addContact(String userId, String deviceId) async => _db.insert(
      'contacts',
      {
        'user_id': userId,
        'device_id': deviceId,
        'added_at': DateTime.now().toUtc().toIso8601String()
      },
      conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> removeContact(String userId) =>
      _db.delete('contacts', where: 'user_id=?', whereArgs: [userId]);
  Future<bool> isContact(String userId) async => (await _db.query('contacts',
          where: 'user_id=?', whereArgs: [userId], limit: 1))
      .isNotEmpty;
  Future<List<Map<String, dynamic>>> contacts() async => _db.rawQuery(
      'SELECT p.* FROM contacts c JOIN directory_profiles p ON p.user_id=c.user_id ORDER BY p.display_name COLLATE NOCASE ASC');
  Future<void> blockUser(String userId) async {
    await _db.insert(
        'blocked_users',
        {
          'user_id': userId,
          'blocked_at': DateTime.now().toUtc().toIso8601String()
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    await removeContact(userId);
  }

  Future<void> unblockUser(String userId) =>
      _db.delete('blocked_users', where: 'user_id=?', whereArgs: [userId]);
  Future<bool> isBlocked(String userId) async =>
      (await _db.query('blocked_users',
              where: 'user_id=?', whereArgs: [userId], limit: 1))
          .isNotEmpty;
  Future<bool> isBlockedPeer(String peerId) async {
    if (peerId.isEmpty) return false;
    if (await isBlocked(peerId)) return true;
    final rows = await _db.rawQuery(
        'SELECT 1 FROM blocked_users b JOIN directory_profiles p ON p.user_id=b.user_id WHERE p.device_id=? LIMIT 1',
        [peerId]);
    return rows.isNotEmpty;
  }

  Future<void> saveDirectorySyncState(String peerId, String at, int version) =>
      _db.insert(
          'directory_sync_state',
          {
            'peer_id': peerId,
            'last_sync_at': at,
            'last_profile_version': version
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
  Future<bool> hasSeenDirectorySync(String syncId) async =>
      (await _db.query('directory_seen',
              where: 'sync_id=?', whereArgs: [syncId], limit: 1))
          .isNotEmpty;
  Future<void> markDirectorySyncSeen(String syncId) async {
    await _db.insert(
        'directory_seen',
        {
          'sync_id': syncId,
          'seen_at': DateTime.now().toUtc().toIso8601String()
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await _db.delete('directory_seen', where: 'seen_at < ?', whereArgs: [
      DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 24))
          .toIso8601String()
    ]);
  }

  Future<void> saveSyncCursor(String cursor) async {
    if (cursor.isEmpty) return;
    _syncCursor = cursor;
    await _putSetting('sync_cursor', cursor);
  }

  Future<void> clearSyncCursor() async {
    _syncCursor = null;
    await _db.delete('settings', where: 'key=?', whereArgs: ['sync_cursor']);
  }

  String generateDeviceId() {
    final random = Random.secure();
    final suffix = List<int>.generate(16, (_) => random.nextInt(16))
        .map((n) => n.toRadixString(16))
        .join();
    return 'android-$suffix';
  }

  Future<void> addOutbox(Map<String, dynamic> item) async => _db.insert(
        'outbox',
        {
          'id': item['id'],
          'recipient_id': item['recipient_id'],
          'body': item['body'] ?? '',
          'created_at': item['created_at'],
          'status': item['status'] ?? 'queued',
          'attempt_count': item['attempt_count'] ?? 0,
          'last_attempt_at': item['last_attempt_at'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Map<String, dynamic>>> outbox() =>
      _db.query('outbox', orderBy: 'created_at ASC, id ASC');

  Future<String?> outboxNetworkBody(String id) async {
    final rows = await _db.query(
      'outbox',
      columns: ['network_body'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final value = rows.isEmpty ? null : rows.first['network_body']?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setOutboxNetworkBody(String id, String body) async {
    await _db.update(
      'outbox',
      {'network_body': body},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateOutboxStatus(String id, String status) async {
    final rows = await _db.query('outbox',
        columns: ['status'], where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final effectiveStatus = _mergeMessageStatus(
        rows.first['status']?.toString() ?? 'queued', status);
    await _db.update(
      'outbox',
      {
        'status': effectiveStatus,
        'last_attempt_at': DateTime.now().toUtc().toIso8601String()
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> markOutboxAttempt(String id) async => _db.rawUpdate(
        "UPDATE outbox SET status='sending',attempt_count=attempt_count+1,last_attempt_at=? WHERE id=?",
        [DateTime.now().toUtc().toIso8601String(), id],
      );

  Future<void> removeOutbox(String id) async =>
      _db.delete('outbox', where: 'id=?', whereArgs: [id]);

  Future<void> addGroupOutbox(Map<String, dynamic> item) async => _db.insert(
        'group_outbox',
        {
          'id': item['id'],
          'group_id': item['group_id'],
          'body': item['body'] ?? '',
          'created_at': item['created_at'],
          'status': item['status'] ?? 'queued',
          'attempt_count': item['attempt_count'] ?? 0,
          'last_attempt_at': item['last_attempt_at'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Map<String, dynamic>>> groupOutbox() =>
      _db.query('group_outbox', orderBy: 'created_at ASC, id ASC');

  Future<void> updateGroupOutboxStatus(String id, String status) async {
    final rows = await _db.query('group_outbox',
        columns: ['status'], where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final current = rows.first['status']?.toString() ?? 'queued';
    final effective = _mergeMessageStatus(current, status);
    await _db.update(
      'group_outbox',
      {
        'status': effective,
        'last_attempt_at': DateTime.now().toUtc().toIso8601String()
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> markGroupOutboxAttempt(String id) async => _db.rawUpdate(
        "UPDATE group_outbox SET status='sending',attempt_count=attempt_count+1,last_attempt_at=? WHERE id=?",
        [DateTime.now().toUtc().toIso8601String(), id],
      );

  Future<void> removeGroupOutbox(String id) async =>
      _db.delete('group_outbox', where: 'id=?', whereArgs: [id]);

  Future<void> addPendingAttachment(
          {required String id,
          required String messageId,
          required PickedFile file}) async =>
      _db.insert(
        'pending_attachments',
        {
          'id': id,
          'message_id': messageId,
          'local_path': file.path,
          'original_name': file.name,
          'content_type': file.contentType,
          'size': file.size,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Map<String, dynamic>>> pendingAttachments(String messageId) =>
      _db.query(
        'pending_attachments',
        where: 'message_id=?',
        whereArgs: [messageId],
        orderBy: 'created_at ASC,id ASC',
      );

  Future<void> setPendingRemoteFile(String id, String remoteFileId) async =>
      _db.update('pending_attachments', {'remote_file_id': remoteFileId},
          where: 'id=?', whereArgs: [id]);
  Future<void> removePendingAttachments(String messageId) async =>
      _db.delete('pending_attachments',
          where: 'message_id=?', whereArgs: [messageId]);

  Future<void> addPendingGroupAttachment(
          {required String id,
          required String messageId,
          required PickedFile file}) async =>
      _db.insert(
        'pending_group_attachments',
        {
          'id': id,
          'message_id': messageId,
          'local_path': file.path,
          'original_name': file.name,
          'content_type': file.contentType,
          'size': file.size,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Map<String, dynamic>>> pendingGroupAttachments(
          String messageId) =>
      _db.query(
        'pending_group_attachments',
        where: 'message_id=?',
        whereArgs: [messageId],
        orderBy: 'created_at ASC,id ASC',
      );

  Future<void> setPendingGroupRemoteFile(
          String id, String remoteFileId) async =>
      _db.update('pending_group_attachments', {'remote_file_id': remoteFileId},
          where: 'id=?', whereArgs: [id]);
  Future<void> removePendingGroupAttachments(String messageId) async =>
      _db.delete('pending_group_attachments',
          where: 'message_id=?', whereArgs: [messageId]);

  Future<void> setMessageAttachmentLocalPath(
          String messageId, String fileId, String path) async =>
      _db.update('message_attachments', {'local_path': path},
          where: 'message_id=? AND file_id=?', whereArgs: [messageId, fileId]);

  Future<void> saveDirectFile({
    required String fileId,
    required String messageId,
    required String senderId,
    required String localPath,
    required String originalName,
    required String contentType,
    required int size,
    required String sha256,
  }) async {
    await _db.insert(
        'direct_files',
        {
          'file_id': fileId,
          'message_id': messageId,
          'sender_id': senderId,
          'local_path': localPath,
          'original_name': originalName,
          'content_type': contentType,
          'size': size,
          'sha256': sha256,
          'received_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> directFile(String fileId) async {
    final rows = await _db.query('direct_files',
        where: 'file_id=?', whereArgs: [fileId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateMessageAttachment({
    required String messageId,
    required String fileId,
    String? path,
    String? sha256,
    int? size,
  }) async {
    final values = <String, dynamic>{};
    if (path != null && path.isNotEmpty) values['local_path'] = path;
    if (sha256 != null && sha256.isNotEmpty) values['sha256'] = sha256;
    if (size != null && size >= 0) values['size'] = size;
    if (values.isEmpty) return;
    await _db.update('message_attachments', values,
        where: 'message_id=? AND file_id=?', whereArgs: [messageId, fileId]);
  }

  Future<List<String>> pendingLocalPaths() async {
    final rows = await _db.rawQuery(
        'SELECT local_path FROM pending_attachments UNION ALL SELECT local_path FROM pending_group_attachments');
    return rows
        .map((r) => r['local_path']?.toString())
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();
  }

  Future<void> setGroupAttachmentLocalPath(
          String messageId, String fileId, String path) async =>
      _db.update('group_message_attachments', {'local_path': path},
          where: 'group_message_id=? AND file_id=?',
          whereArgs: [messageId, fileId]);

  Future<void> saveMessage(Message message) async {
    var effectiveStatus = message.status;
    var effectiveDeliveredAt = message.deliveredAt;
    var effectiveServerSeq = message.serverSeq;
    var effectiveRead = message.senderId == _deviceId ? 1 : 0;
    String? effectiveReadAt;

    final existing = await _db.query(
      'messages',
      columns: ['status', 'delivered_at', 'server_seq', 'is_read', 'read_at'],
      where: 'id=?',
      whereArgs: [message.id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final current = existing.first;
      effectiveStatus = _mergeMessageStatus(
        current['status']?.toString() ?? 'queued',
        message.status,
      );
      effectiveDeliveredAt ??= current['delivered_at']?.toString();
      final currentServerSeq =
          int.tryParse(current['server_seq']?.toString() ?? '') ?? 0;
      if (currentServerSeq > effectiveServerSeq)
        effectiveServerSeq = currentServerSeq;
      final currentRead =
          current['is_read']?.toString() == '1' || current['is_read'] == true;
      if (currentRead) effectiveRead = 1;
      effectiveReadAt = current['read_at']?.toString();
    }

    await _db.insert(
      'messages',
      {
        'id': message.id,
        'sender_id': message.senderId,
        'recipient_id': message.recipientId,
        'body': message.body,
        'created_at': message.createdAt.toUtc().toIso8601String(),
        'status': effectiveStatus,
        'delivered_at': effectiveDeliveredAt,
        'server_seq': effectiveServerSeq,
        'is_read': effectiveRead,
        'read_at': effectiveReadAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    for (var i = 0; i < message.attachments.length; i++) {
      final a = message.attachments[i];
      await _db.rawInsert(
        '''INSERT INTO message_attachments(message_id,file_id,original_name,content_type,size,sha256,width,height,is_image,download_url,thumbnail_url,local_path,crypto_version,crypto_scope,crypto_key_version,crypto_nonce,crypto_mac,thumbnail_crypto_nonce,thumbnail_crypto_mac,position)
           VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT(message_id,file_id) DO UPDATE SET
           original_name=excluded.original_name,content_type=excluded.content_type,size=excluded.size,sha256=excluded.sha256,
           width=excluded.width,height=excluded.height,is_image=excluded.is_image,download_url=excluded.download_url,
           thumbnail_url=excluded.thumbnail_url,local_path=COALESCE(excluded.local_path,message_attachments.local_path),
           crypto_version=excluded.crypto_version,crypto_scope=excluded.crypto_scope,crypto_key_version=excluded.crypto_key_version,crypto_nonce=excluded.crypto_nonce,crypto_mac=excluded.crypto_mac,thumbnail_crypto_nonce=excluded.thumbnail_crypto_nonce,thumbnail_crypto_mac=excluded.thumbnail_crypto_mac,position=excluded.position''',
        [
          message.id,
          a.id,
          a.originalName,
          a.contentType,
          a.size,
          a.sha256,
          a.width,
          a.height,
          a.isImage ? 1 : 0,
          a.downloadUrl,
          a.thumbnailUrl,
          a.localPath,
          a.cryptoVersion,
          a.cryptoScope,
          a.cryptoKeyVersion,
          a.cryptoNonce,
          a.cryptoMac,
          a.thumbnailCryptoNonce,
          a.thumbnailCryptoMac,
          i
        ],
      );
    }
  }

  Future<List<Attachment>> _attachmentsForMessage(String messageId) async {
    final rows = await _db.query('message_attachments',
        where: 'message_id=?', whereArgs: [messageId], orderBy: 'position ASC');
    return rows
        .map((r) => Attachment.fromJson({
              'id': r['file_id'],
              'original_name': r['original_name'],
              'content_type': r['content_type'],
              'size': r['size'],
              'sha256': r['sha256'],
              'width': r['width'],
              'height': r['height'],
              'is_image': r['is_image'] == 1,
              'download_url': r['download_url'],
              'thumbnail_url': r['thumbnail_url'],
              'crypto_version': r['crypto_version'],
              'crypto_scope': r['crypto_scope'],
              'crypto_key_version': r['crypto_key_version'],
              'crypto_nonce': r['crypto_nonce'],
              'crypto_mac': r['crypto_mac'],
              'thumbnail_crypto_nonce': r['thumbnail_crypto_nonce'],
              'thumbnail_crypto_mac': r['thumbnail_crypto_mac'],
            }, localPath: r['local_path']?.toString()))
        .toList();
  }

  Future<List<Message>> messagesFor(String otherId) async {
    final self = _deviceId;
    if (self == null) return [];
    final rows = await _db.query(
      'messages',
      where:
          '((sender_id=? AND recipient_id=?) OR (sender_id=? AND recipient_id=?))',
      whereArgs: [self, otherId, otherId, self],
      orderBy: 'created_at ASC, id ASC',
    );
    final out = <Message>[];
    for (final r in rows) {
      final m = Message.fromDb(r);
      final atts = await _attachmentsForMessage(m.id);
      out.add(Message(
          id: m.id,
          senderId: m.senderId,
          recipientId: m.recipientId,
          body: m.body,
          createdAt: m.createdAt,
          status: m.status,
          deliveredAt: m.deliveredAt,
          serverSeq: m.serverSeq,
          attachments: atts));
    }
    return out;
  }

  Future<void> resetDerivedEncryptionState() async {
    await _db.delete('peer_keys');
    await _db.update('outbox', {'network_body': null},
        where: "status NOT IN ('delivered')");
  }

  Future<void> savePeerKey(String peerId, String sharedKey) async => _db.insert(
        'peer_keys',
        {
          'peer_id': peerId,
          'shared_key': sharedKey,
          'updated_at': DateTime.now().toUtc().toIso8601String()
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<Map<String, String>> peerKeys() async {
    final rows = await _db.query('peer_keys');
    return {
      for (final row in rows)
        if (row['peer_id'] != null && row['shared_key'] != null)
          row['peer_id']!.toString(): row['shared_key']!.toString(),
    };
  }

  Future<void> saveDevice(Device device) async => _db.insert(
        'known_devices',
        {
          'id': device.id,
          'name': device.name,
          'platform': device.platform,
          'created_at': device.createdAt,
          'last_seen_at': device.lastSeenAt,
          'network_status': device.networkStatus.apiValue,
          'server_connected': device.serverConnected ? 1 : 0,
          'wifi_direct_connected': device.wifiDirectConnected ? 1 : 0,
          'status_updated_at': device.statusUpdatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<Device?> deviceById(String deviceId) async {
    final rows = await _db.query(
      'known_devices',
      where: 'id=?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return Device.fromJson({
        'id': rows.first['id'],
        'name': rows.first['name'],
        'platform': rows.first['platform'],
        'created_at': rows.first['created_at'],
        'last_seen_at': rows.first['last_seen_at'],
        'network_status': rows.first['network_status'],
        'server_connected': rows.first['server_connected'] == 1,
        'wifi_direct_connected': rows.first['wifi_direct_connected'] == 1,
        'status_updated_at': rows.first['status_updated_at'],
      });
    }

    final profile = await directoryProfileByDeviceId(deviceId);
    if (profile == null) return null;
    final row = profile;
    final now = DateTime.now().toUtc().toIso8601String();
    return Device(
      id: deviceId,
      name: (row['display_name']?.toString().trim().isNotEmpty == true)
          ? row['display_name'].toString().trim()
          : (row['username']?.toString().trim().isNotEmpty == true)
              ? row['username'].toString().trim()
              : deviceId,
      platform: 'android',
      createdAt: row['updated_at']?.toString() ?? now,
      lastSeenAt: row['updated_at']?.toString() ?? now,
    );
  }

  Future<List<Device>> localDevices() async {
    final rows = await _db.query('known_devices',
        orderBy: 'name COLLATE NOCASE, id ASC');
    return rows
        .map((row) => Device.fromJson({
              'id': row['id'],
              'name': row['name'],
              'platform': row['platform'],
              'created_at': row['created_at'],
              'last_seen_at': row['last_seen_at'],
              'network_status': row['network_status'],
              'server_connected': row['server_connected'] == 1,
              'wifi_direct_connected': row['wifi_direct_connected'] == 1,
              'status_updated_at': row['status_updated_at'],
            }))
        .toList();
  }

  Future<void> saveCall(CallRecord call) async {
    final existing =
        await _db.query('calls', where: 'id=?', whereArgs: [call.id], limit: 1);
    if (existing.isEmpty) {
      await _db.insert('calls', call.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }
    final current = CallRecord.fromDb(existing.first);
    int rank(String status) {
      switch (status) {
        case 'connected':
          return 3;
        case 'rejected':
        case 'ended':
        case 'missed':
        case 'canceled':
        case 'failed':
          return 4;
        case 'ringing':
        default:
          return 1;
      }
    }

    final nextRank = rank(call.status);
    final currentRank = rank(current.status);
    final effective = nextRank > currentRank
        ? call
        : CallRecord(
            id: current.id,
            callerId: current.callerId,
            calleeId: current.calleeId,
            status: current.status,
            startedAt: current.startedAt,
            answeredAt: current.answeredAt ?? call.answeredAt,
            endedAt: current.endedAt ?? call.endedAt,
            durationSeconds: current.durationSeconds > call.durationSeconds
                ? current.durationSeconds
                : call.durationSeconds,
            endReason: current.endReason.isNotEmpty
                ? current.endReason
                : call.endReason,
          );
    await _db.insert('calls', effective.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<CallRecord>> calls() async {
    final rows = await _db.query('calls',
        orderBy: 'started_at DESC, id DESC', limit: 200);
    return rows.map(CallRecord.fromDb).toList();
  }

  Future<void> saveCallQualitySample(CallQualitySample sample) async =>
      _db.insert('call_quality_samples', sample.toDb());

  Future<CallQualitySample?> latestCallQualitySample(String callId) async {
    final rows = await _db.query('call_quality_samples',
        where: 'call_id=?',
        whereArgs: [callId],
        orderBy: 'sampled_at DESC, id DESC',
        limit: 1);
    return rows.isEmpty ? null : CallQualitySample.fromDb(rows.first);
  }

  Future<List<CallQualitySample>> callQualitySamples(String callId,
      {int limit = 120}) async {
    final rows = await _db.query('call_quality_samples',
        where: 'call_id=?',
        whereArgs: [callId],
        orderBy: 'sampled_at ASC, id ASC',
        limit: limit);
    return rows.map(CallQualitySample.fromDb).toList();
  }

  Future<bool> messageExists(String id) async {
    final rows = await _db.query('messages',
        columns: ['id'], where: 'id=?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }

  Future<Message?> messageById(String id) async {
    final rows =
        await _db.query('messages', where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final message = Message.fromDb(rows.first);
    final attachments = await _attachmentsForMessage(message.id);
    return Message(
      id: message.id,
      senderId: message.senderId,
      recipientId: message.recipientId,
      body: message.body,
      createdAt: message.createdAt,
      status: message.status,
      deliveredAt: message.deliveredAt,
      serverSeq: message.serverSeq,
      attachments: attachments,
    );
  }

  Future<List<Message>> unreadMessagesForConversation(String otherId) async {
    final self = _deviceId;
    if (self == null || otherId.isEmpty) return [];
    final rows = await _db.query(
      'messages',
      where: 'sender_id=? AND recipient_id=? AND is_read=0',
      whereArgs: [otherId, self],
      orderBy: 'created_at ASC, id ASC',
    );
    final out = <Message>[];
    for (final row in rows) {
      final message = Message.fromDb(row);
      out.add(
        message.copyWithMessageAttachments(
          await _attachmentsForMessage(message.id),
        ),
      );
    }
    return out;
  }

  Future<List<Message>> unreadIncomingMessages({int limit = 100}) async {
    final self = _deviceId;
    if (self == null) return [];
    final rows = await _db.query(
      'messages',
      where: 'sender_id != ? AND recipient_id = ? AND is_read=0',
      whereArgs: [self, self],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    final out = <Message>[];
    for (final row in rows) {
      final message = Message.fromDb(row);
      out.add(
        message.copyWithMessageAttachments(
          await _attachmentsForMessage(message.id),
        ),
      );
    }
    return out;
  }

  Future<List<String>> unreadDirectConversationIds({int limit = 100}) async {
    final self = _deviceId;
    if (self == null) return [];
    final rows = await _db.rawQuery(
      '''SELECT DISTINCT sender_id AS conversation_id FROM messages
         WHERE sender_id != ? AND recipient_id = ? AND is_read = 0
         ORDER BY conversation_id ASC LIMIT ?''',
      [self, self, limit],
    );
    return rows
        .map((row) => row['conversation_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<void> markMessageRead(String id) async {
    if (id.isEmpty || _deviceId == null) return;
    await _db.update(
      'messages',
      {
        'is_read': 1,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=? AND recipient_id=?',
      whereArgs: [id, _deviceId],
    );
  }

  Future<void> deleteMessage(String id) async {
    if (id.isEmpty) return;
    await _db.transaction((txn) async {
      await txn.delete(
        'message_attachments',
        where: 'message_id=?',
        whereArgs: [id],
      );
      await txn.delete('messages', where: 'id=?', whereArgs: [id]);
      await txn.delete(
        'pending_attachments',
        where: 'message_id=?',
        whereArgs: [id],
      );
      await txn.delete('outbox', where: 'id=?', whereArgs: [id]);
      // Leave notification_state until the notification layer receives the
      // deletion event. That layer owns Android notification cancellation.
    });
    if (!_deletedMessageIds.isClosed) _deletedMessageIds.add(id);
  }

  Future<void> markNotificationShown({
    required String kind,
    required String conversationId,
    required String messageId,
    required int notificationId,
  }) async {
    final id = '$kind:$messageId';
    await _db.insert(
      'notification_state',
      {
        'id': id,
        'kind': kind,
        'conversation_id': conversationId,
        'message_id': messageId,
        'notification_id': notificationId,
        'notified_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeNotificationStateForMessage(String messageId) async {
    if (messageId.isEmpty) return;
    await _db.delete(
      'notification_state',
      where: 'message_id=?',
      whereArgs: [messageId],
    );
  }

  Future<bool> notificationStateMatches({
    required String kind,
    required String conversationId,
    required String messageId,
    required int notificationId,
  }) async {
    if (kind.isEmpty ||
        conversationId.isEmpty ||
        messageId.isEmpty ||
        notificationId <= 0) {
      return false;
    }
    final rows = await _db.query(
      'notification_state',
      columns: ['id'],
      where:
          'kind=? AND conversation_id=? AND message_id=? AND notification_id=?',
      whereArgs: [kind, conversationId, messageId, notificationId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> notificationStates() async =>
      _db.query('notification_state', orderBy: 'notified_at ASC, id ASC');

  Future<void> clearNotificationState() => _db.delete('notification_state');

  Future<void> cleanupNotificationState() async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 30))
        .toIso8601String();
    await _db.delete(
      'notification_state',
      where: 'notified_at < ?',
      whereArgs: [cutoff],
    );
  }

  String _mergeMessageStatus(String current, String incoming) {
    int rank(String value) {
      switch (value) {
        case 'delivered':
        case 'direct_delivered':
          return 4;
        case 'sent':
          return 3;
        case 'sending':
          return 2;
        case 'queued':
        default:
          return 1;
      }
    }

    return rank(incoming) >= rank(current) ? incoming : current;
  }

  Future<List<Message>> messagesForParticipants(
      Set<String> participantIds) async {
    if (participantIds.isEmpty) return [];
    final placeholders = List.filled(participantIds.length, '?').join(',');
    final ids = participantIds.toList();
    final rows = await _db.rawQuery(
      'SELECT * FROM messages WHERE sender_id IN ($placeholders) OR recipient_id IN ($placeholders) ORDER BY created_at ASC, id ASC',
      [...ids, ...ids],
    );
    final out = <Message>[];
    for (final r in rows) {
      final m = Message.fromDb(r);
      out.add(Message(
        id: m.id,
        senderId: m.senderId,
        recipientId: m.recipientId,
        body: m.body,
        createdAt: m.createdAt,
        status: m.status,
        deliveredAt: m.deliveredAt,
        serverSeq: m.serverSeq,
        attachments: await _attachmentsForMessage(m.id),
      ));
    }
    return out;
  }

  Future<void> saveMessageBody(String id, String body) async {
    if (body.isEmpty) return;
    await _db.update('messages', {'body': body},
        where: 'id=?', whereArgs: [id]);
  }

  Future<void> updateMessageStatus(String id,
      {String? status, String? deliveredAt}) async {
    final rows = await _db.query('messages',
        columns: ['status', 'delivered_at'],
        where: 'id=?',
        whereArgs: [id],
        limit: 1);
    if (rows.isEmpty) return;
    final current = rows.first['status']?.toString() ?? 'queued';
    final values = <String, dynamic>{};
    if (status != null) values['status'] = _mergeMessageStatus(current, status);
    if (deliveredAt != null &&
        (status == null ||
            _mergeMessageStatus(current, status) == status ||
            (status == 'delivered' || status == 'direct_delivered'))) {
      values['delivered_at'] = deliveredAt;
    }
    if (values.isNotEmpty)
      await _db.update('messages', values, where: 'id=?', whereArgs: [id]);
  }

  Future<void> saveGroup(Map<String, dynamic> g) async => _db.insert(
        'groups',
        {
          'id': g['id'],
          'name': g['name'],
          'owner_id': g['owner_id'],
          'created_at': g['created_at']
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<LocalGroup>> localGroups() async {
    final rows = await _db.query('groups', orderBy: 'name COLLATE NOCASE');
    return rows
        .map((r) => LocalGroup.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<List<String>> deleteGroupLocal(String groupId) async {
    final localPaths = <String>[];
    await _db.transaction((txn) async {
      final outboxRows = await txn.query('group_outbox',
          columns: ['id'], where: 'group_id=?', whereArgs: [groupId]);
      final outboxMessageIds = outboxRows
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();
      final messageRows = await txn.query('group_messages',
          columns: ['id'], where: 'group_id=?', whereArgs: [groupId]);
      final messageIds = messageRows
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();
      final allPendingIds = {...outboxMessageIds, ...messageIds}.toList();
      if (allPendingIds.isNotEmpty) {
        final placeholders = List.filled(allPendingIds.length, '?').join(',');
        final pending = await txn.query('pending_group_attachments',
            columns: ['local_path'],
            where: 'message_id IN ($placeholders)',
            whereArgs: allPendingIds);
        for (final row in pending) {
          final path = row['local_path']?.toString();
          if (path != null && path.isNotEmpty) localPaths.add(path);
        }
        await txn.delete('pending_group_attachments',
            where: 'message_id IN ($placeholders)', whereArgs: allPendingIds);
      }
      final cached = await txn.query(
        'group_message_attachments',
        columns: ['local_path'],
        where:
            'group_message_id IN (SELECT id FROM group_messages WHERE group_id=?) AND local_path IS NOT NULL AND local_path != '
            '',
        whereArgs: [groupId],
      );
      for (final row in cached) {
        final path = row['local_path']?.toString();
        if (path != null && path.isNotEmpty) localPaths.add(path);
      }
      await txn
          .delete('group_outbox', where: 'group_id=?', whereArgs: [groupId]);
      await txn.delete('group_message_attachments',
          where:
              'group_message_id IN (SELECT id FROM group_messages WHERE group_id=?)',
          whereArgs: [groupId]);
      await txn
          .delete('group_messages', where: 'group_id=?', whereArgs: [groupId]);
      await txn
          .delete('group_members', where: 'group_id=?', whereArgs: [groupId]);
      await txn.delete('groups', where: 'id=?', whereArgs: [groupId]);
    });
    return localPaths;
  }

  Future<List<Map<String, dynamic>>> groups() =>
      _db.query('groups', orderBy: 'name COLLATE NOCASE');

  Future<void> saveGroupMember(Map<String, dynamic> m) async => _db.insert(
        'group_members',
        {
          'group_id': m['group_id'],
          'device_id': m['device_id'],
          'role': m['role'] ?? 'member',
          'joined_at': m['joined_at'] ?? '',
          'name': m['name'] ?? ''
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Map<String, dynamic>>> groupMembers(String groupId) =>
      _db.query('group_members',
          where: 'group_id=?',
          whereArgs: [groupId],
          orderBy: 'name COLLATE NOCASE');

  Future<void> deleteGroupMemberLocal(String groupId, String deviceId) async =>
      _db.delete('group_members',
          where: 'group_id=? AND device_id=?', whereArgs: [groupId, deviceId]);

  Future<void> saveGroupMessage(Map<String, dynamic> m) async {
    final gm = Map<String, dynamic>.from(m);
    var effectiveRead = gm['sender_id'] == _deviceId ? 1 : 0;
    String? effectiveReadAt;
    final existing = await _db.query(
      'group_messages',
      columns: ['is_read', 'read_at'],
      where: 'id=?',
      whereArgs: [gm['id']],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final row = existing.first;
      if (row['is_read'] == 1 || row['is_read'] == true) effectiveRead = 1;
      effectiveReadAt = row['read_at']?.toString();
    }
    if (gm['is_read'] == 1 || gm['is_read'] == true) effectiveRead = 1;
    if (gm['read_at']?.toString().trim().isNotEmpty == true) {
      effectiveReadAt = gm['read_at'].toString();
    }
    await _db.insert(
      'group_messages',
      {
        'id': gm['id'],
        'group_id': gm['group_id'],
        'sender_id': gm['sender_id'],
        'body': gm['body'] ?? '',
        'created_at': gm['created_at'],
        'server_seq': gm['server_seq'] ?? 0,
        'is_read': effectiveRead,
        'read_at': effectiveReadAt
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final attachments = gm['attachments'] as List? ?? [];
    for (var i = 0; i < attachments.length; i++) {
      final a =
          Attachment.fromJson(Map<String, dynamic>.from(attachments[i] as Map));
      await _db.rawInsert(
        '''INSERT INTO group_message_attachments(group_message_id,file_id,original_name,content_type,size,sha256,width,height,is_image,download_url,thumbnail_url,local_path,crypto_version,crypto_scope,crypto_key_version,crypto_nonce,crypto_mac,thumbnail_crypto_nonce,thumbnail_crypto_mac,position)
           VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT(group_message_id,file_id) DO UPDATE SET
           original_name=excluded.original_name,content_type=excluded.content_type,size=excluded.size,sha256=excluded.sha256,
           width=excluded.width,height=excluded.height,is_image=excluded.is_image,download_url=excluded.download_url,
           thumbnail_url=excluded.thumbnail_url,local_path=COALESCE(excluded.local_path,group_message_attachments.local_path),
           crypto_version=excluded.crypto_version,crypto_scope=excluded.crypto_scope,crypto_key_version=excluded.crypto_key_version,crypto_nonce=excluded.crypto_nonce,crypto_mac=excluded.crypto_mac,thumbnail_crypto_nonce=excluded.thumbnail_crypto_nonce,thumbnail_crypto_mac=excluded.thumbnail_crypto_mac,position=excluded.position''',
        [
          gm['id'],
          a.id,
          a.originalName,
          a.contentType,
          a.size,
          a.sha256,
          a.width,
          a.height,
          a.isImage ? 1 : 0,
          a.downloadUrl,
          a.thumbnailUrl,
          a.localPath,
          a.cryptoVersion,
          a.cryptoScope,
          a.cryptoKeyVersion,
          a.cryptoNonce,
          a.cryptoMac,
          a.thumbnailCryptoNonce,
          a.thumbnailCryptoMac,
          i
        ],
      );
    }
  }

  Future<List<Map<String, dynamic>>> groupMessages(String groupId) async {
    final rows = await _db.query('group_messages',
        where: 'group_id=?',
        whereArgs: [groupId],
        orderBy: 'server_seq ASC,id ASC');
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final atts = await _db.query('group_message_attachments',
          where: 'group_message_id=?',
          whereArgs: [row['id']],
          orderBy: 'position ASC');
      final copy = Map<String, dynamic>.from(row);
      copy['attachments'] = atts
          .map((r) => Attachment.fromJson({
                'id': r['file_id'],
                'original_name': r['original_name'],
                'content_type': r['content_type'],
                'size': r['size'],
                'sha256': r['sha256'],
                'width': r['width'],
                'height': r['height'],
                'is_image': r['is_image'] == 1,
                'download_url': r['download_url'],
                'thumbnail_url': r['thumbnail_url'],
                'crypto_version': r['crypto_version'],
                'crypto_scope': r['crypto_scope'],
                'crypto_key_version': r['crypto_key_version'],
                'crypto_nonce': r['crypto_nonce'],
                'crypto_mac': r['crypto_mac'],
                'thumbnail_crypto_nonce': r['thumbnail_crypto_nonce'],
                'thumbnail_crypto_mac': r['thumbnail_crypto_mac'],
              }, localPath: r['local_path']?.toString())
                  .toJson())
          .toList();
      out.add(copy);
    }
    return out;
  }

  Future<List<GroupMessage>> unreadGroupMessages(String groupId) async {
    final self = _deviceId;
    if (self == null || groupId.isEmpty) return [];
    final rows = await _db.query(
      'group_messages',
      where: 'group_id=? AND sender_id != ? AND is_read=0',
      whereArgs: [groupId, self],
      orderBy: 'created_at ASC, id ASC',
    );
    return _groupMessagesFromRows(rows);
  }

  Future<List<GroupMessage>> unreadGroupMessagesAll({int limit = 100}) async {
    final self = _deviceId;
    if (self == null) return [];
    final rows = await _db.rawQuery(
      '''SELECT gm.* FROM group_messages gm
         JOIN groups g ON g.id = gm.group_id
         WHERE gm.sender_id != ? AND gm.is_read=0
         ORDER BY gm.created_at ASC, gm.id ASC LIMIT ?''',
      [self, limit],
    );
    return _groupMessagesFromRows(rows);
  }

  Future<List<String>> unreadGroupConversationIds({int limit = 100}) async {
    final self = _deviceId;
    if (self == null) return [];
    final rows = await _db.rawQuery(
      '''SELECT DISTINCT gm.group_id AS conversation_id FROM group_messages gm
         JOIN groups g ON g.id = gm.group_id
         WHERE gm.sender_id != ? AND gm.is_read = 0
         ORDER BY conversation_id ASC LIMIT ?''',
      [self, limit],
    );
    return rows
        .map((row) => row['conversation_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<GroupMessage?> groupMessageById(String id) async {
    if (id.isEmpty) return null;
    final rows = await _db.query(
      'group_messages',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (await _groupMessagesFromRows(rows)).first;
  }

  Future<void> markGroupMessageRead(String id) async {
    if (id.isEmpty || _deviceId == null) return;
    await _db.update(
      'group_messages',
      {
        'is_read': 1,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=? AND sender_id != ?',
      whereArgs: [id, _deviceId],
    );
  }

  Future<LocalGroup?> groupById(String groupId) async {
    final rows = await _db.query(
      'groups',
      where: 'id=?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalGroup.fromJson(Map<String, dynamic>.from(rows.first));
  }

  Future<List<GroupMessage>> _groupMessagesFromRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final out = <GroupMessage>[];
    for (final row in rows) {
      final attachments = await _db.query(
        'group_message_attachments',
        where: 'group_message_id=?',
        whereArgs: [row['id']],
        orderBy: 'position ASC',
      );
      final data = Map<String, dynamic>.from(row);
      data['attachments'] = attachments
          .map(
            (r) => Attachment.fromJson(
              {
                'id': r['file_id'],
                'original_name': r['original_name'],
                'content_type': r['content_type'],
                'size': r['size'],
                'sha256': r['sha256'],
                'width': r['width'],
                'height': r['height'],
                'is_image': r['is_image'] == 1,
                'download_url': r['download_url'],
                'thumbnail_url': r['thumbnail_url'],
                'crypto_version': r['crypto_version'],
                'crypto_scope': r['crypto_scope'],
                'crypto_key_version': r['crypto_key_version'],
                'crypto_nonce': r['crypto_nonce'],
                'crypto_mac': r['crypto_mac'],
                'thumbnail_crypto_nonce': r['thumbnail_crypto_nonce'],
                'thumbnail_crypto_mac': r['thumbnail_crypto_mac'],
              },
              localPath: r['local_path']?.toString(),
            ).toJson(),
          )
          .toList();
      out.add(GroupMessage.fromJson(data));
    }
    return out;
  }

  Future<void> saveRestoredFile(Attachment file) async {
    await _db.insert(
        'restored_files',
        {
          'id': file.id,
          'original_name': file.originalName,
          'content_type': file.contentType,
          'size': file.size,
          'sha256': file.sha256,
          'width': file.width,
          'height': file.height,
          'is_image': file.isImage ? 1 : 0,
          'download_url': file.downloadUrl,
          'thumbnail_url': file.thumbnailUrl,
          'crypto_version': file.cryptoVersion,
          'crypto_scope': file.cryptoScope,
          'crypto_key_version': file.cryptoKeyVersion,
          'crypto_nonce': file.cryptoNonce,
          'crypto_mac': file.cryptoMac,
          'thumbnail_crypto_nonce': file.thumbnailCryptoNonce,
          'thumbnail_crypto_mac': file.thumbnailCryptoMac,
          'restored_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Attachment>> restoredFiles() async {
    final rows = await _db.query('restored_files',
        orderBy: 'original_name COLLATE NOCASE, id ASC');
    return rows
        .map((r) => Attachment.fromJson({
              'id': r['id'],
              'original_name': r['original_name'],
              'content_type': r['content_type'],
              'size': r['size'],
              'sha256': r['sha256'],
              'width': r['width'],
              'height': r['height'],
              'is_image': r['is_image'] == 1,
              'download_url': r['download_url'],
              'thumbnail_url': r['thumbnail_url'],
              'crypto_version': r['crypto_version'],
              'crypto_scope': r['crypto_scope'],
              'crypto_key_version': r['crypto_key_version'],
              'crypto_nonce': r['crypto_nonce'],
              'crypto_mac': r['crypto_mac'],
              'thumbnail_crypto_nonce': r['thumbnail_crypto_nonce'],
              'thumbnail_crypto_mac': r['thumbnail_crypto_mac'],
            }))
        .toList();
  }

  Future<File> backupTo(String destinationPath) async {
    await _db.execute('PRAGMA wal_checkpoint(FULL)');
    return File(_db.path).copy(destinationPath);
  }

  @visibleForTesting
  Future<void> clearAll() async {
    await _db.transaction((txn) async {
      for (final table in [
        'messages',
        'outbox',
        'group_outbox',
        'settings',
        'message_attachments',
        'direct_files',
        'known_devices',
        'pending_attachments',
        'pending_group_attachments',
        'group_message_attachments',
        'group_messages',
        'group_members',
        'groups',
        'calls',
        'call_quality_samples',
        'restored_files',
        'notification_state'
      ]) {
        await txn.delete(table);
      }
    });
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _recoveryRequestSecretKey);
    _serverAddress = null;
    _deviceId = null;
    _deviceName = null;
    _deviceToken = null;
    _accountId = null;
    _username = null;
    _syncCursor = null;
    _adminUserWifiRadioPolicy = null;
    _adminDeviceWifiRadioPolicy = null;
    _adminUserPolicyVersion = 0;
    _adminDevicePolicyVersion = 0;
    _adminPolicyUpdatedAt = '';
  }

  Future<void> close() async {
    if (!_deletedMessageIds.isClosed) await _deletedMessageIds.close();
    if (_databaseOpened) {
      _databaseOpened = false;
      await _db.close();
    }
  }

  Future<void> applyAdminNetworkPolicy(Map<String, dynamic> policy,
      {bool authoritativeSnapshot = false}) async {
    final userWifi =
        AdminWifiRadioPolicyX.fromStorage(policy['user_wifi_radio_policy']);
    final deviceWifi =
        AdminWifiRadioPolicyX.fromStorage(policy['device_wifi_radio_policy']);
    final userVersion =
        int.tryParse(policy['user_policy_version']?.toString() ?? '') ?? 0;
    final deviceVersion =
        int.tryParse(policy['device_policy_version']?.toString() ?? '') ?? 0;
    final incomingUpdatedAt = policy['updated_at']?.toString() ?? '';
    final acceptUser =
        authoritativeSnapshot || userVersion >= _adminUserPolicyVersion;
    final acceptDevice =
        authoritativeSnapshot || deviceVersion >= _adminDevicePolicyVersion;
    if (!acceptUser && !acceptDevice) return;
    if (acceptUser) {
      _adminUserWifiRadioPolicy = userWifi;
      _adminUserPolicyVersion = userVersion;
    }
    if (acceptDevice) {
      _adminDeviceWifiRadioPolicy = deviceWifi;
      _adminDevicePolicyVersion = deviceVersion;
    }
    _adminPolicyUpdatedAt = incomingUpdatedAt;
    await _putSetting(
        'admin_user_wifi_radio_policy', userWifi?.storageValue ?? '');
    await _putSetting(
        'admin_device_wifi_radio_policy', deviceWifi?.storageValue ?? '');
    await _putSetting('admin_user_policy_version', '$userVersion');
    await _putSetting('admin_device_policy_version', '$deviceVersion');
    await _putSetting('admin_policy_updated_at', incomingUpdatedAt);
  }

  Future<void> clearAdminNetworkPolicies() async {
    _adminUserWifiRadioPolicy = null;
    _adminDeviceWifiRadioPolicy = null;
    _adminUserPolicyVersion = 0;
    _adminDevicePolicyVersion = 0;
    _adminPolicyUpdatedAt = '';
    for (final key in const [
      'admin_user_wifi_radio_policy',
      'admin_device_wifi_radio_policy',
      'admin_user_policy_version',
      'admin_device_policy_version',
      'admin_policy_updated_at',
    ]) {
      await _putSetting(key, '');
    }
  }

  Future<String?> readSetting(String key) async {
    final row = await _db.query('settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return row.isEmpty ? null : row.first['value']?.toString();
  }

  Future<void> writeSetting(String key, String value) async =>
      _putSetting(key, value);

  Future<void> _putSetting(String key, String value) async =>
      _db.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
}
