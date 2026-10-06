import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/models/sensitive_identity_bundle.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';

class ServiceRestoreProgress {
  final String phase;
  final int completed;
  final int total;
  final String detail;

  const ServiceRestoreProgress({required this.phase, required this.completed, required this.total, this.detail = ''});
}

class AccountRestorationService {
  static const String _backupPrefix = 'locallink-crypto-backup:v1:';
  static const int _pbkdf2Iterations = 180000;
  static const int _backupSaltBytes = 16;

  final LocalStore store;
  final LocalLinkApi api;
  final IdentityCryptoService crypto;
  final AesGcm _aes = AesGcm.with256bits();
  final Hmac _hmac = Hmac.sha256();

  AccountRestorationService(this.store, this.api, this.crypto);

  String _encodeUrl(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

  List<int> _decodeUrl(String value) {
    var v = value;
    while (v.length % 4 != 0) v += '=';
    return base64Url.decode(v);
  }

  List<int> _randomBytes(int length) => List<int>.generate(length, (_) => Random.secure().nextInt(256));

  Future<List<int>> _pbkdf2(String passphrase, List<int> salt) async {
    final password = utf8.encode(passphrase);
    final blocks = <int>[];
    // One 32-byte block is sufficient because AES-256 needs exactly 32 bytes.
    var u = await _hmac.calculateMac(
      [...salt, 0, 0, 0, 1],
      secretKey: SecretKey(password),
    );
    var t = Uint8List.fromList(u.bytes);
    for (var i = 1; i < _pbkdf2Iterations; i++) {
      u = await _hmac.calculateMac(u.bytes, secretKey: SecretKey(password));
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u.bytes[j];
      }
    }
    blocks.addAll(t);
    return blocks;
  }

  Future<String> createEncryptedCryptoBackup({required String passphrase}) async {
    if (passphrase.length < 10) throw Exception('Backup passphrase must be at least 10 characters');
    final bundle = await crypto.exportPortableIdentityKeyBundle();
    final plaintext = utf8.encode(jsonEncode(bundle.toJson()));
    final salt = _randomBytes(_backupSaltBytes);
    final keyBytes = await _pbkdf2(passphrase, salt);
    final aad = utf8.encode('${_backupPrefix}${store.accountId ?? ''}');
    final box = await _aes.encrypt(plaintext, secretKey: SecretKey(keyBytes), aad: aad);
    final envelope = {
      'v': 1,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _pbkdf2Iterations,
      'salt': _encodeUrl(salt),
      'nonce': _encodeUrl(box.nonce),
      'ciphertext': _encodeUrl(box.cipherText),
      'mac': _encodeUrl(box.mac.bytes),
      'account_id': store.accountId ?? '',
    };
    final encoded = _encodeUrl(utf8.encode(jsonEncode(envelope)));
    final result = '$_backupPrefix$encoded';
    await api.putCryptoBackup(result);
    return result;
  }

  Future<void> restoreEncryptedCryptoBackup({required String passphrase}) async {
    if (passphrase.length < 10) throw Exception('Backup passphrase must be at least 10 characters');
    final remote = await api.getCryptoBackup();
    if (!remote.available || remote.envelope.isEmpty) throw Exception('No encrypted identity backup is available');
    final envelope = _decodeEnvelope(remote.envelope);
    final accountId = envelope['account_id']?.toString() ?? '';
    if (accountId.isNotEmpty && store.accountId != null && accountId != store.accountId) {
      throw Exception('Encrypted backup belongs to a different account');
    }
    final salt = _decodeUrl(envelope['salt']?.toString() ?? '');
    final nonce = _decodeUrl(envelope['nonce']?.toString() ?? '');
    final ciphertext = _decodeUrl(envelope['ciphertext']?.toString() ?? '');
    final mac = _decodeUrl(envelope['mac']?.toString() ?? '');
    final iterations = int.tryParse(envelope['iterations']?.toString() ?? '') ?? 0;
    if (iterations != _pbkdf2Iterations || salt.length != _backupSaltBytes || nonce.length < 8 || mac.isEmpty || ciphertext.isEmpty) {
      throw const FormatException('Invalid encrypted identity backup');
    }
    final key = await _pbkdf2(passphrase, salt);
    final aad = utf8.encode('${_backupPrefix}${store.accountId ?? accountId}');
    final plaintext = await _aes.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key),
      aad: aad,
    );
    final bundle = jsonDecode(utf8.decode(plaintext));
    if (bundle is! Map) throw const FormatException('Invalid identity backup bundle');
    await crypto.importPortableIdentityKeyBundle(SensitiveIdentityBundle.fromJson(Map<String, dynamic>.from(bundle)));
  }

  Map<String, dynamic> _decodeEnvelope(String envelope) {
    if (!envelope.startsWith(_backupPrefix)) throw const FormatException('Unsupported crypto backup format');
    final raw = jsonDecode(utf8.decode(_decodeUrl(envelope.substring(_backupPrefix.length))));
    if (raw is! Map) throw const FormatException('Invalid crypto backup envelope');
    if ((raw['v'] as num?)?.toInt() != 1) throw const FormatException('Unsupported crypto backup version');
    if (raw['kdf']?.toString() != 'PBKDF2-HMAC-SHA256') throw const FormatException('Unsupported crypto backup KDF');
    return Map<String, dynamic>.from(raw);
  }

  Future<AccountRestoreManifest> loadManifest() => api.accountRestoreManifest();

  Future<ServiceRestoreProgress> restoreAccountData({
    required void Function(ServiceRestoreProgress progress) onProgress,
    bool restoreMessages = true,
    bool restoreGroupMessages = true,
    bool restoreCalls = true,
    bool restoreFiles = true,
    String? cryptoBackupPassphrase,
  }) async {
    if (store.accountId == null || store.accountId!.isEmpty) throw Exception('This device is not linked to a LocalLink account');

    final manifest = await loadManifest();
    var totalSteps = 1 +
        (restoreMessages ? 1 : 0) +
        (restoreGroupMessages ? 1 : 0) +
        (restoreCalls ? 1 : 0) +
        (restoreFiles ? 1 : 0) +
        ((cryptoBackupPassphrase?.isNotEmpty ?? false) ? 1 : 0);
    var step = 0;
    onProgress(ServiceRestoreProgress(phase: 'metadata', completed: step, total: totalSteps, detail: 'Restoring account, profile, devices and groups'));

    final metadata = await api.accountRestoreData(scope: 'metadata', limit: 500);
    await _restoreMetadata(manifest, metadata);
    step++;
    onProgress(ServiceRestoreProgress(phase: 'metadata', completed: step, total: totalSteps, detail: 'Metadata restored'));

    if (cryptoBackupPassphrase != null && cryptoBackupPassphrase.isNotEmpty) {
      await restoreEncryptedCryptoBackup(passphrase: cryptoBackupPassphrase);
      step++;
      onProgress(ServiceRestoreProgress(phase: 'crypto', completed: step, total: totalSteps, detail: 'Encrypted historical identity keys restored locally'));
    }

    if (restoreMessages) {
      await _restoreMessages(onProgress, step, totalSteps);
      step++;
    }
    if (restoreGroupMessages) {
      await _restoreGroupMessages(onProgress, step, totalSteps);
      step++;
    }
    if (restoreCalls) {
      await _restoreCalls(onProgress, step, totalSteps);
      step++;
    }
    if (restoreFiles) {
      await _restoreFiles(onProgress, step, totalSteps);
      step++;
    }

    // Re-cache the current profile/avatar from the server. Settings and local UI
    // preferences deliberately remain device-local rather than being copied.
    try {
      await api.getProfile(downloadAvatar: true);
    } catch (_) {}
    return ServiceRestoreProgress(phase: 'complete', completed: totalSteps, total: totalSteps, detail: 'Account restoration complete');
  }

  Future<void> _restoreMetadata(AccountRestoreManifest manifest, AccountRestorePage metadata) async {
    final account = metadata.account ?? manifest.account;
    final profile = metadata.profile ?? manifest.profile;
    if (account.id.isNotEmpty && account.id == store.accountId) {
      await store.saveConfiguration(
        server: store.serverAddress!,
        id: store.deviceId!,
        name: store.deviceName ?? 'Local Device',
        token: store.deviceToken,
        accountId: account.id,
        username: account.username,
      );
    }
    await store.saveProfile(profile);
    for (final device in [...manifest.devices, ...metadata.devices]) {
      await store.saveDevice(device);
    }
    for (final group in metadata.groups) {
      await store.saveGroup({'id': group.id, 'name': group.name, 'owner_id': group.ownerId, 'created_at': group.createdAt});
    }
    for (final member in metadata.groupMembers) {
      await store.saveGroupMember({'group_id': member.groupId, 'device_id': member.deviceId, 'role': member.role, 'joined_at': member.joinedAt, 'name': member.name});
    }
  }

  Future<void> _restoreMessages(void Function(ServiceRestoreProgress) onProgress, int step, int total) async {
    String? cursor;
    var pageIndex = 0;
    do {
      final page = await api.accountRestoreData(scope: 'messages', cursor: cursor, limit: 200);
      for (final message in page.messages) {
        await store.saveMessage(message);
      }
      pageIndex++;
      onProgress(ServiceRestoreProgress(phase: 'messages', completed: step, total: total, detail: 'Restored $pageIndex message page(s)'));
      cursor = page.hasMore ? page.nextCursor : null;
      if (page.hasMore && (cursor == null || cursor.isEmpty)) throw StateError('Server returned a paginated restore page without a cursor');
    } while (cursor != null && cursor.isNotEmpty);
  }

  Future<void> _restoreGroupMessages(void Function(ServiceRestoreProgress) onProgress, int step, int total) async {
    String? cursor;
    var pageIndex = 0;
    do {
      final page = await api.accountRestoreData(scope: 'group_messages', cursor: cursor, limit: 200);
      for (final message in page.groupMessages) {
        await store.saveGroupMessage({
          'id': message.id,
          'group_id': message.groupId,
          'sender_id': message.senderId,
          'body': message.body,
          'created_at': message.createdAt,
          'server_seq': message.serverSeq,
          'attachments': message.attachments.map((a) => a.toJson()).toList(),
        });
      }
      pageIndex++;
      onProgress(ServiceRestoreProgress(phase: 'group_messages', completed: step, total: total, detail: 'Restored $pageIndex group-message page(s)'));
      cursor = page.hasMore ? page.nextCursor : null;
      if (page.hasMore && (cursor == null || cursor.isEmpty)) throw StateError('Server returned a paginated restore page without a cursor');
    } while (cursor != null && cursor.isNotEmpty);
  }

  Future<void> _restoreCalls(void Function(ServiceRestoreProgress) onProgress, int step, int total) async {
    String? cursor;
    var pageIndex = 0;
    do {
      final page = await api.accountRestoreData(scope: 'calls', cursor: cursor, limit: 200);
      for (final call in page.calls) {
        await store.saveCall(call);
      }
      pageIndex++;
      onProgress(ServiceRestoreProgress(phase: 'calls', completed: step, total: total, detail: 'Restored $pageIndex call-history page(s)'));
      cursor = page.hasMore ? page.nextCursor : null;
      if (page.hasMore && (cursor == null || cursor.isEmpty)) throw StateError('Server returned a paginated restore page without a cursor');
    } while (cursor != null && cursor.isNotEmpty);
  }

  Future<void> _restoreFiles(void Function(ServiceRestoreProgress) onProgress, int step, int total) async {
    String? cursor;
    var pageIndex = 0;
    do {
      final page = await api.accountRestoreData(scope: 'files', cursor: cursor, limit: 200);
      // File restoration is metadata-first. Actual content remains remote and is
      // downloaded only when the user opens/needs the attachment.
      for (final file in page.files) {
        await store.saveRestoredFile(file);
      }
      pageIndex++;
      onProgress(ServiceRestoreProgress(phase: 'files', completed: step, total: total, detail: 'Restored $pageIndex file-metadata page(s)'));
      cursor = page.hasMore ? page.nextCursor : null;
      if (page.hasMore && (cursor == null || cursor.isEmpty)) throw StateError('Server returned a paginated restore page without a cursor');
    } while (cursor != null && cursor.isNotEmpty);
  }

}
