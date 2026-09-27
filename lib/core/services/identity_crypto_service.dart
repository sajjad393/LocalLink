import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/core/models/sensitive_identity_bundle.dart';


class KeyRotationResult {
  final int keyVersion;
  final String publicKey;
  const KeyRotationResult({required this.keyVersion, required this.publicKey});
}

class IdentityCryptoService {
  String _encodeUrl(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');
  String encodeOpaqueStorageKey(String value, {String prefix = ''}) =>
      '$prefix${_encodeUrl(utf8.encode(value))}';

  List<int> decodeOpaqueStorageKey(String value) =>
      _decodeUrl(value.replaceFirst(RegExp(r'^[^A-Za-z0-9_-]+'), ''));


  List<int> _decodeUrl(String value) {
    var v = value;
    while (v.length % 4 != 0) {
      v += '=';
    }
    return base64Url.decode(v);
  }

  static const _legacyPrivateKeyStorage = 'locallink_identity_x25519_seed_v1';
  static const _legacyPublicKeyStorage = 'locallink_identity_x25519_public_v1';
  static const _currentVersionStorage = 'locallink_identity_key_version_v2';
  static const _seedPrefix = 'locallink_identity_x25519_seed_v2_';
  static const _publicPrefix = 'locallink_identity_x25519_public_v2_';
  static const _peerPrefix = 'locallink_peer_pub_v1_';
  static const _peerVersionPrefix = 'locallink_peer_key_version_v1_';
  static const _peerHistoryPrefix = 'locallink_peer_history_v1_';
  static const _pendingSeedPrefix = 'locallink_identity_pending_seed_v1_';
  static const _pendingPublicPrefix = 'locallink_identity_pending_public_v1_';
  static const _importedSeedPrefix = 'locallink_imported_identity_seed_v1_';
  static const _importedPublicPrefix = 'locallink_imported_identity_public_v1_';
  static const _directorySigningSeedKey = 'locallink_directory_ed25519_seed_v1';
  static const _directorySigningPublicKey = 'locallink_directory_ed25519_public_v1';

  final SecureStorageService _secure;

  IdentityCryptoService({SecureStorageService? secureStorage})
      : _secure = secureStorage ?? const SecureStorageService();
  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final Hmac _hmac = Hmac.sha256();
  final Ed25519 _ed25519 = Ed25519();
  SimpleKeyPair? _keyPair;
  String? _deviceId;
  int _keyVersion = 1;

  int get keyVersion => _keyVersion;

  String _seedKey(int version) => '$_seedPrefix$version';
  String _publicKeyKey(int version) => '$_publicPrefix$version';

  Future<void> init(String deviceId) async {
    _deviceId = deviceId;
    _keyVersion = await _readCurrentVersion();

    var saved = await _secure.read(key: _seedKey(_keyVersion));
    if ((saved == null || saved.isEmpty) && _keyVersion == 1) {
      // Migrate the Phase 23/24 seed into a versioned record. The legacy value
      // remains protected locally until clearIdentity() is explicitly called.
      saved = await _secure.read(key: _legacyPrivateKeyStorage);
    }

    List<int> seed;
    if (saved != null && saved.isNotEmpty) {
      seed = _decodeUrl(saved);
      if (seed.length != 32) {
        seed = _randomSeed();
        await _secure.write(key: _seedKey(_keyVersion), value: _encodeUrl(seed));
      } else if (await _secure.read(key: _seedKey(_keyVersion)) == null) {
        await _secure.write(key: _seedKey(_keyVersion), value: _encodeUrl(seed));
      }
    } else {
      seed = _randomSeed();
      await _secure.write(key: _seedKey(_keyVersion), value: _encodeUrl(seed));
    }

    _keyPair = await _x25519.newKeyPairFromSeed(seed);
    final publicBytes = await _keyPair!.extractPublicKey();
    await _secure.write(key: _publicKeyKey(_keyVersion), value: _encodeUrl(publicBytes.bytes));
    // Keep the legacy public key in sync for older local components; the new
    // protocol reads the versioned key first.
    await _secure.write(key: _legacyPublicKeyStorage, value: _encodeUrl(publicBytes.bytes));
    await _secure.write(key: _legacyPrivateKeyStorage, value: _encodeUrl(seed));
    await _writeCurrentVersion(_keyVersion);
  }

  Future<int> _readCurrentVersion() async {
    final raw = await _secure.read(key: _currentVersionStorage);
    final parsed = int.tryParse(raw ?? '');
    return parsed != null && parsed >= 1 && parsed <= 1000000 ? parsed : 1;
  }

  Future<void> _writeCurrentVersion(int version) async {
    await _secure.write(key: _currentVersionStorage, value: version.toString());
  }

  List<int> _randomSeed() => List<int>.generate(32, (_) => Random.secure().nextInt(256));

  Future<SimpleKeyPair> _loadKeyPair(int version) async {
    final seedValue = await _secure.read(key: _seedKey(version));
    if (seedValue == null || seedValue.isEmpty) {
      throw StateError('identity key version $version is not available on this device');
    }
    final seed = _decodeUrl(seedValue);
    if (seed.length != 32) {
      throw StateError('stored identity key version $version is invalid');
    }
    return _x25519.newKeyPairFromSeed(seed);
  }

  Future<String> publicKeyForVersion(int version) async {
    final value = await _secure.read(key: _publicKeyKey(version));
    if (value == null || value.isEmpty) throw StateError('identity key version $version is not initialized');
    return value;
  }

  Future<KeyRotationResult> prepareIdentityRotation() async {
    if (_deviceId == null || _keyPair == null) {
      throw StateError('identity key is not initialized');
    }
    final next = _keyVersion + 1;
    if (next <= _keyVersion) throw StateError('identity key version overflow');
    final pendingKey = '$_pendingPublicPrefix$next';
    final pendingSeedKey = '$_pendingSeedPrefix$next';
    final existing = await _secure.read(key: pendingKey);
    if (existing != null && existing.isNotEmpty) {
      throw StateError('an identity-key rotation is already pending');
    }
    final seed = _randomSeed();
    final pair = await _x25519.newKeyPairFromSeed(seed);
    final publicBytes = await pair.extractPublicKey();
    final publicKey = _encodeUrl(publicBytes.bytes);
    await _secure.write(key: pendingSeedKey, value: _encodeUrl(seed));
    await _secure.write(key: pendingKey, value: publicKey);
    return KeyRotationResult(keyVersion: next, publicKey: publicKey);
  }

  Future<void> commitIdentityRotation(int version) async {
    if (version <= _keyVersion) throw StateError('identity key version must be newer than current');
    final seedKey = '$_pendingSeedPrefix$version';
    final publicKeyName = '$_pendingPublicPrefix$version';
    final seed = await _secure.read(key: seedKey);
    final publicKey = await _secure.read(key: publicKeyName);
    if (seed == null || publicKey == null || seed.isEmpty || publicKey.isEmpty) {
      throw StateError('pending identity-key rotation is missing');
    }
    await _secure.write(key: _seedKey(version), value: seed);
    await _secure.write(key: _publicKeyKey(version), value: publicKey);
    await _writeCurrentVersion(version);
    _keyVersion = version;
    _keyPair = await _loadKeyPair(version);
    await _secure.delete(key: seedKey);
    await _secure.delete(key: publicKeyName);
    await _secure.write(key: _legacyPrivateKeyStorage, value: seed);
    await _secure.write(key: _legacyPublicKeyStorage, value: publicKey);
  }

  Future<void> discardPendingIdentityRotation(int version) async {
    await _secure.delete(key: '$_pendingSeedPrefix$version');
    await _secure.delete(key: '$_pendingPublicPrefix$version');
  }

  Future<KeyRotationResult> rotateIdentity() async {
    final next = await prepareIdentityRotation();
    await commitIdentityRotation(next.keyVersion);
    return next;
  }

  Future<List<int>> availableKeyVersions() async {
    final all = await _secure.readAll();
    final versions = <int>[];
    for (final key in all.keys) {
      if (!key.startsWith(_seedPrefix)) continue;
      final version = int.tryParse(key.substring(_seedPrefix.length));
      if (version != null && version > 0) versions.add(version);
    }
    versions.sort((a, b) => b.compareTo(a));
    return versions;
  }

  Future<void> clearIdentity() async {
    _keyPair = null;
    _deviceId = null;
    _keyVersion = 1;
    final keys = await _secure.readAll();
    for (final key in keys.keys) {
      if (key == _legacyPrivateKeyStorage ||
          key == _legacyPublicKeyStorage ||
          key == _currentVersionStorage ||
          key.startsWith(_seedPrefix) ||
          key.startsWith(_publicPrefix) ||
          key.startsWith(_peerPrefix) ||
          key.startsWith(_peerVersionPrefix) ||
          key.startsWith(_peerHistoryPrefix) ||
          key.startsWith(_pendingSeedPrefix) ||
          key.startsWith(_pendingPublicPrefix) ||
          key.startsWith(_importedSeedPrefix) ||
          key.startsWith(_importedPublicPrefix) ||
          key == _directorySigningSeedKey ||
          key == _directorySigningPublicKey) {
        await _secure.delete(key: key);
      }
    }
  }

  Future<void> _ensureDirectorySigningKey() async {
    final existingSeed = await _secure.read(key: _directorySigningSeedKey);
    final existingPublic = await _secure.read(key: _directorySigningPublicKey);
    if (existingSeed != null && existingSeed.isNotEmpty && existingPublic != null && existingPublic.isNotEmpty) return;
    final pair = await _ed25519.newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    final publicKey = await pair.extractPublicKey();
    await _secure.write(key: _directorySigningSeedKey, value: _encodeUrl(seed));
    await _secure.write(key: _directorySigningPublicKey, value: _encodeUrl(publicKey.bytes));
  }

  Future<SimpleKeyPair> _directorySigningPair() async {
    await _ensureDirectorySigningKey();
    final seedRaw = await _secure.read(key: _directorySigningSeedKey);
    if (seedRaw == null || seedRaw.isEmpty) throw StateError('directory signing key is unavailable');
    final seed = _decodeUrl(seedRaw);
    return _ed25519.newKeyPairFromSeed(seed);
  }

  Future<String> signingPublicKey() async {
    await _ensureDirectorySigningKey();
    return (await _secure.read(key: _directorySigningPublicKey))!;
  }

  Future<String> signDirectoryProfile(String canonicalPayload) async {
    final pair = await _directorySigningPair();
    final signature = await _ed25519.sign(utf8.encode(canonicalPayload), keyPair: pair);
    return _encodeUrl(signature.bytes);
  }

  Future<String> signPayload(String canonicalPayload) async {
    final pair = await _directorySigningPair();
    final signature = await _ed25519.sign(utf8.encode(canonicalPayload), keyPair: pair);
    return _encodeUrl(signature.bytes);
  }

  Future<bool> verifyPayloadSignature({required String canonicalPayload, required String signature, required String signingPublicKey}) async {
    try {
      final publicBytes = _decodeUrl(signingPublicKey);
      final signatureBytes = _decodeUrl(signature);
      if (publicBytes.length != 32 || signatureBytes.length != 64) return false;
      return await _ed25519.verify(
        utf8.encode(canonicalPayload),
        signature: Signature(signatureBytes, publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519)),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyDirectoryProfile({required String canonicalPayload, required String signature, required String signingPublicKey}) async {
    try {
      final publicBytes = _decodeUrl(signingPublicKey);
      final signatureBytes = _decodeUrl(signature);
      if (publicBytes.length != 32 || signatureBytes.length != 64) return false;
      return await _ed25519.verify(utf8.encode(canonicalPayload), signature: Signature(signatureBytes, publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519)));
    } catch (_) {
      return false;
    }
  }

  Future<String> publicKey() async {
    return publicKeyForVersion(_keyVersion);
  }

  Future<String> deriveSharedKey(
    String peerId,
    String peerPublicKey, {
    int? selfKeyVersion,
  }) async {
    final self = _deviceId;
    if (self == null) throw StateError('identity key is not initialized');
    final version = selfKeyVersion ?? _keyVersion;
    final pair = version == _keyVersion ? _keyPair : await _loadKeyPair(version);
    if (pair == null) throw StateError('identity key is not initialized');
    final remoteBytes = _decodeUrl(peerPublicKey);
    if (remoteBytes.length != 32) throw const FormatException('invalid peer identity key');
    final remote = SimplePublicKey(remoteBytes, type: KeyPairType.x25519);
    final shared = await _x25519.sharedSecretKey(keyPair: pair, remotePublicKey: remote);
    final a = self.compareTo(peerId) < 0 ? self : peerId;
    final b = self.compareTo(peerId) < 0 ? peerId : self;
    final info = utf8.encode('locallink-peer-e2e-v1|$a|$b');
    final derived = await Hkdf(hmac: _hmac, outputLength: 32).deriveKey(secretKey: shared, info: info);
    return _encodeUrl(await derived.extractBytes());
  }

  Future<List<String>> cachePeerPublicKeys(Map<String, String> keys, {Map<String, int> versions = const {}}) async {
    final existing = await cachedPeerPublicKeys();
    final existingVersions = await cachedPeerKeyVersions();
    final changed = <String>[];
    for (final entry in keys.entries) {
      if (entry.key.isEmpty || entry.value.isEmpty) continue;
      final nextVersion = versions[entry.key] ?? existingVersions[entry.key] ?? 1;
      final old = existing[entry.key];
      final oldVersion = existingVersions[entry.key] ?? 1;
      if (old != null && old != entry.value) {
        if (nextVersion <= oldVersion) {
          changed.add(entry.key);
          continue;
        }
      }
      await _secure.write(key: '$_peerPrefix${_encodeUrl(utf8.encode(entry.key))}', value: entry.value);
      await _secure.write(key: '$_peerVersionPrefix${_encodeUrl(utf8.encode(entry.key))}', value: nextVersion.toString());
    }
    return changed;
  }

  Future<Map<String, int>> cachedPeerKeyVersions() async {
    final all = await _secure.readAll();
    final out = <String, int>{};
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_peerVersionPrefix) || entry.value.isEmpty) continue;
      try {
        final peer = utf8.decode(_decodeUrl(entry.key.substring(_peerVersionPrefix.length)));
        final version = int.tryParse(entry.value) ?? 1;
        out[peer] = version;
      } catch (_) {}
    }
    return out;
  }

  Future<Map<String, String>> cachedPeerPublicKeys() async {
    final all = await _secure.readAll();
    final out = <String, String>{};
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_peerPrefix) || entry.value.isEmpty) continue;
      try {
        final peer = utf8.decode(_decodeUrl(entry.key.substring(_peerPrefix.length)));
        out[peer] = entry.value;
      } catch (_) {}
    }
    return out;
  }

  Future<void> cachePeerIdentityHistory(List<Map<String, dynamic>> records) async {
    for (final record in records) {
      final peerId = record['peer_id']?.toString() ?? record['device_id']?.toString() ?? '';
      final publicKey = record['public_key']?.toString() ?? '';
      final version = int.tryParse(record['key_version']?.toString() ?? '') ?? 0;
      if (peerId.isEmpty || publicKey.isEmpty || version < 1) continue;
      final key = '$_peerHistoryPrefix${_encodeUrl(utf8.encode('$peerId|$version'))}';
      await _secure.write(key: key, value: publicKey);
    }
  }

  Future<Map<String, Map<int, String>>> cachedPeerIdentityHistory() async {
    final all = await _secure.readAll();
    final out = <String, Map<int, String>>{};
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_peerHistoryPrefix) || entry.value.isEmpty) continue;
      try {
        final parts = utf8.decode(_decodeUrl(entry.key.substring(_peerHistoryPrefix.length))).split('|');
        if (parts.length != 2) continue;
        final version = int.tryParse(parts[1]);
        if (version == null || version < 1) continue;
        out.putIfAbsent(parts[0], () => {})[version] = entry.value;
      } catch (_) {}
    }
    return out;
  }

  Future<Map<String, String>> derivePeerKeys(Map<String, String> peerPublicKeys) async {
    final out = <String, String>{};
    for (final entry in peerPublicKeys.entries) {
      try {
        out[entry.key] = await deriveSharedKey(entry.key, entry.value);
      } catch (_) {}
    }
    return out;
  }

  Future<String> deriveCallMediaKey({
    required String peerId,
    required String peerPublicKey,
    required String callId,
  }) async {
    final shared = await deriveSharedKey(peerId, peerPublicKey);
    final sharedBytes = _decodeUrl(shared);
    if (sharedBytes.length != 32) throw const FormatException('invalid peer shared key');
    final a = _deviceId!.compareTo(peerId) < 0 ? _deviceId! : peerId;
    final b = _deviceId!.compareTo(peerId) < 0 ? peerId : _deviceId!;
    final info = utf8.encode('locallink-call-media-v1|$a|$b|$callId');
    final derived = await Hkdf(hmac: _hmac, outputLength: 32).deriveKey(
      secretKey: SecretKey(sharedBytes),
      info: info,
    );
    return _encodeUrl(await derived.extractBytes());
  }

  static const _messageEnvelopeVersion = 'e2e:v2:';
  static const _messageDomain = 'locallink-message-e2e-v2';

  String _canonicalMessageTimestamp(String value) {
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) throw const FormatException('invalid message timestamp');
    return parsed.toUtc().toIso8601String();
  }

  String _messageAad({
    required String senderId,
    required String recipientId,
    required String messageId,
    required String createdAt,
  }) {
    final canonical = <String, String>{
      'domain': _messageDomain,
      'type': 'direct_message',
      'sender_id': senderId,
      'recipient_id': recipientId,
      'message_id': messageId,
      'created_at': createdAt,
    };
    return jsonEncode(canonical);
  }

  Future<String> encryptMessage({
    required String senderId,
    required String recipientId,
    required String messageId,
    required String createdAt,
    required String plaintext,
    required String sharedKey,
  }) async {
    final keyBytes = _decodeUrl(sharedKey);
    if (keyBytes.length != 32) throw const FormatException('invalid shared key');
    if (senderId.trim().isEmpty || recipientId.trim().isEmpty || messageId.trim().isEmpty || createdAt.trim().isEmpty) {
      throw const FormatException('message identity metadata is required');
    }
    if (senderId == recipientId) throw const FormatException('sender and recipient must differ');
    final canonicalCreatedAt = _canonicalMessageTimestamp(createdAt);
    final key = SecretKey(keyBytes);
    final aadText = _messageAad(
      senderId: senderId,
      recipientId: recipientId,
      messageId: messageId,
      createdAt: canonicalCreatedAt,
    );
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: key, aad: utf8.encode(aadText));
    return '$_messageEnvelopeVersion${jsonEncode({
      'version': 2,
      'type': 'direct_message',
      'sender_id': senderId,
      'recipient_id': recipientId,
      'message_id': messageId,
      'created_at': canonicalCreatedAt,
      'nonce': _encodeUrl(box.nonce),
      'ciphertext': _encodeUrl(box.cipherText),
      'mac': _encodeUrl(box.mac.bytes),
    })}';
  }

  Future<String?> decryptMessage({
    required String senderId,
    required String recipientId,
    required String messageId,
    required String createdAt,
    required String value,
    required String sharedKey,
  }) async {
    if (!value.startsWith(_messageEnvelopeVersion)) return null;
    try {
      final raw = jsonDecode(value.substring(_messageEnvelopeVersion.length)) as Map<String, dynamic>;
      final canonicalCreatedAt = _canonicalMessageTimestamp(createdAt);
      if (raw['version']?.toString() != '2' ||
          raw['type']?.toString() != 'direct_message' ||
          raw['sender_id']?.toString() != senderId ||
          raw['recipient_id']?.toString() != recipientId ||
          raw['message_id']?.toString() != messageId ||
          raw['created_at']?.toString() != canonicalCreatedAt) return null;
      final keyBytes = _decodeUrl(sharedKey);
      if (keyBytes.length != 32) return null;
      final key = SecretKey(keyBytes);
      final box = SecretBox(
        _decodeUrl(raw['ciphertext'].toString()),
        nonce: _decodeUrl(raw['nonce'].toString()),
        mac: Mac(_decodeUrl(raw['mac'].toString())),
      );
      final plaintext = await _aes.decrypt(
        box,
        secretKey: key,
        aad: utf8.encode(_messageAad(
          senderId: senderId,
          recipientId: recipientId,
          messageId: messageId,
          createdAt: canonicalCreatedAt,
        )),
      );
      return utf8.decode(plaintext);
    } catch (_) {
      return null;
    }
  }

  Future<String?> decryptMessageWithHistory({
    required String senderId,
    required String recipientId,
    required String messageId,
    required String createdAt,
    required String value,
    required Map<int, String> peerKeysByVersion,
  }) async {
    if (!value.startsWith(_messageEnvelopeVersion)) return null;
    final versions = await availableKeyVersions();
    for (final localVersion in versions) {
      for (final entry in peerKeysByVersion.entries) {
        try {
          final shared = await deriveSharedKey(senderId, entry.value, selfKeyVersion: localVersion);
          final body = await decryptMessage(senderId: senderId, recipientId: recipientId, messageId: messageId, createdAt: createdAt, value: value, sharedKey: shared);
          if (body != null) return body;
        } catch (_) {}
      }
    }
    return null;
  }


  String _identityContextKey(String deviceId, int version) =>
      _encodeUrl(utf8.encode('$deviceId|$version'));

  Future<SensitiveIdentityBundle> exportPortableIdentityKeyBundle() async {
    if (_deviceId == null) throw StateError('identity key is not initialized');
    final versions = await availableKeyVersions();
    if (versions.isEmpty) throw StateError('no identity keys available');
    final keys = <SensitiveIdentityKeyRecord>[];
    for (final version in versions) {
      final seed = await _secure.read(key: _seedKey(version));
      if (seed == null || seed.isEmpty) continue;
      final publicKey = await _secure.read(key: _publicKeyKey(version));
      keys.add(SensitiveIdentityKeyRecord(version: version, seed: seed, publicKey: publicKey ?? ''));
    }
    return SensitiveIdentityBundle(deviceId: _deviceId!, keyVersions: List.unmodifiable(keys));
  }


  Future<void> importPortableIdentityKeyBundle(SensitiveIdentityBundle bundle) async {
    final deviceId = bundle.deviceId;
    for (final record in bundle.keyVersions) {
      final version = record.version;
      final seed = record.seed;
      if (version < 1 || seed.isEmpty) continue;
      final seedBytes = _decodeUrl(seed);
      if (seedBytes.length != 32) throw const FormatException('invalid historical identity seed');
      final pair = await _x25519.newKeyPairFromSeed(seedBytes);
      final computedPublic = _encodeUrl((await pair.extractPublicKey()).bytes);
      final suppliedPublic = record.publicKey;
      if (suppliedPublic.isNotEmpty && suppliedPublic != computedPublic) {
        throw const FormatException('historical identity public key mismatch');
      }
      final keyId = _identityContextKey(deviceId, version);
      await _secure.write(key: '$_importedSeedPrefix$keyId', value: seed);
      await _secure.write(key: '$_importedPublicPrefix$keyId', value: computedPublic);
    }
  }

  Future<Map<String, Map<int, String>>> importedIdentityKeyContexts() async {
    final all = await _secure.readAll();
    final out = <String, Map<int, String>>{};
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_importedSeedPrefix) || entry.value.isEmpty) continue;
      try {
        final decoded = utf8.decode(_decodeUrl(entry.key.substring(_importedSeedPrefix.length)));
        final parts = decoded.split('|');
        if (parts.length != 2) continue;
        final version = int.tryParse(parts[1]);
        if (version == null || version < 1) continue;
        out.putIfAbsent(parts[0], () => {})[version] = entry.value;
      } catch (_) {}
    }
    return out;
  }

  Future<void> clearImportedIdentityKeyContexts() async {
    final all = await _secure.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_importedSeedPrefix) || key.startsWith(_importedPublicPrefix)) {
        await _secure.delete(key: key);
      }
    }
  }

  Future<String> deriveSharedKeyForIdentityContext({
    required String selfDeviceId,
    required List<int> selfSeed,
    required String peerId,
    required String peerPublicKey,
  }) async {
    if (selfDeviceId.isEmpty) throw StateError('identity device ID is empty');
    if (selfSeed.length != 32) throw const FormatException('invalid identity seed');
    final pair = await _x25519.newKeyPairFromSeed(selfSeed);
    final remoteBytes = _decodeUrl(peerPublicKey);
    if (remoteBytes.length != 32) throw const FormatException('invalid peer identity key');
    final remote = SimplePublicKey(remoteBytes, type: KeyPairType.x25519);
    final shared = await _x25519.sharedSecretKey(keyPair: pair, remotePublicKey: remote);
    final a = selfDeviceId.compareTo(peerId) < 0 ? selfDeviceId : peerId;
    final b = selfDeviceId.compareTo(peerId) < 0 ? peerId : selfDeviceId;
    final info = utf8.encode('locallink-peer-e2e-v1|$a|$b');
    final derived = await Hkdf(hmac: _hmac, outputLength: 32).deriveKey(secretKey: shared, info: info);
    return _encodeUrl(await derived.extractBytes());
  }

  Future<String?> decryptMessageWithImportedHistory({
    required String senderId,
    required String recipientId,
    required String messageId,
    required String createdAt,
    required String value,
    required Map<int, String> peerKeysByVersion,
  }) async {
    return decryptMessageWithIdentityContexts(
      senderId: senderId,
      recipientId: recipientId,
      messageId: messageId,
      createdAt: createdAt,
      value: value,
      peerKeysByVersion: peerKeysByVersion,
    );
  }

  Future<String?> decryptMessageWithIdentityContexts({
    required String senderId,
    required String recipientId,
    required String messageId,
    required String createdAt,
    required String value,
    required Map<int, String> peerKeysByVersion,
  }) async {
    if (!value.startsWith(_messageEnvelopeVersion)) return null;
    final contexts = await importedIdentityKeyContexts();
    final participantIds = <String>{senderId, recipientId};
    for (final selfEntry in contexts.entries) {
      final selfDeviceId = selfEntry.key;
      if (!participantIds.contains(selfDeviceId)) continue;
      final peerId = selfDeviceId == senderId ? recipientId : senderId;
      for (final seedEntry in selfEntry.value.entries) {
        for (final peerEntry in peerKeysByVersion.entries) {
          try {
            final shared = await deriveSharedKeyForIdentityContext(
              selfDeviceId: selfDeviceId,
              selfSeed: _decodeUrl(seedEntry.value),
              peerId: peerId,
              peerPublicKey: peerEntry.value,
            );
            final body = await decryptMessage(
              senderId: senderId,
              recipientId: recipientId,
              messageId: messageId,
              createdAt: createdAt,
              value: value,
              sharedKey: shared,
            );
            if (body != null) return body;
          } catch (_) {}
        }
      }
    }
    return null;
  }

  static const _groupKeyEnvelopeVersion = 'gke:v1:';
  static const _groupMessageEnvelopeVersion = 'gme:v1:';
  static const _groupCryptoDomain = 'locallink-group-e2e-v1';

  String _groupKeyAad({
    required String groupId,
    required int keyVersion,
    required String senderId,
    required String recipientId,
  }) => jsonEncode(<String, Object>{
        'domain': _groupCryptoDomain,
        'type': 'group_key',
        'group_id': groupId,
        'key_version': keyVersion,
        'sender_id': senderId,
        'recipient_id': recipientId,
      });

  String _groupMessageAad({
    required String groupId,
    required int keyVersion,
    required String senderId,
    required String messageId,
    required String createdAt,
  }) => jsonEncode(<String, Object>{
        'domain': _groupCryptoDomain,
        'type': 'group_message',
        'group_id': groupId,
        'key_version': keyVersion,
        'sender_id': senderId,
        'message_id': messageId,
        'created_at': createdAt,
      });

  String newGroupKey() => _encodeUrl(_randomSeed());

  Future<String> encryptGroupKeyEnvelope({
    required String groupId,
    required int keyVersion,
    required String senderId,
    required String recipientId,
    required String groupKey,
    required String sharedKey,
  }) async {
    if (groupId.trim().isEmpty || senderId.trim().isEmpty || recipientId.trim().isEmpty ||
        keyVersion < 1 || senderId == recipientId) {
      throw const FormatException('invalid group-key identity metadata');
    }
    final groupKeyBytes = _decodeUrl(groupKey);
    final sharedKeyBytes = _decodeUrl(sharedKey);
    if (groupKeyBytes.length != 32 || sharedKeyBytes.length != 32) {
      throw const FormatException('invalid group key or shared key');
    }
    final box = await _aes.encrypt(
      groupKeyBytes,
      secretKey: SecretKey(sharedKeyBytes),
      aad: utf8.encode(_groupKeyAad(
        groupId: groupId,
        keyVersion: keyVersion,
        senderId: senderId,
        recipientId: recipientId,
      )),
    );
    return '$_groupKeyEnvelopeVersion${jsonEncode(<String, Object>{
      'version': 1,
      'type': 'group_key',
      'group_id': groupId,
      'key_version': keyVersion,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'nonce': _encodeUrl(box.nonce),
      'ciphertext': _encodeUrl(box.cipherText),
      'mac': _encodeUrl(box.mac.bytes),
    })}';
  }

  Future<String?> decryptGroupKeyEnvelope({
    required String groupId,
    required int keyVersion,
    required String senderId,
    required String recipientId,
    required String envelope,
    required String sharedKey,
  }) async {
    if (!envelope.startsWith(_groupKeyEnvelopeVersion)) return null;
    try {
      final raw = jsonDecode(envelope.substring(_groupKeyEnvelopeVersion.length)) as Map<String, dynamic>;
      if (raw['version']?.toString() != '1' ||
          raw['type']?.toString() != 'group_key' ||
          raw['group_id']?.toString() != groupId ||
          int.tryParse(raw['key_version']?.toString() ?? '') != keyVersion ||
          raw['sender_id']?.toString() != senderId ||
          raw['recipient_id']?.toString() != recipientId) return null;
      final keyBytes = _decodeUrl(sharedKey);
      if (keyBytes.length != 32) return null;
      final plaintext = await _aes.decrypt(
        SecretBox(
          _decodeUrl(raw['ciphertext']?.toString() ?? ''),
          nonce: _decodeUrl(raw['nonce']?.toString() ?? ''),
          mac: Mac(_decodeUrl(raw['mac']?.toString() ?? '')),
        ),
        secretKey: SecretKey(keyBytes),
        aad: utf8.encode(_groupKeyAad(
          groupId: groupId,
          keyVersion: keyVersion,
          senderId: senderId,
          recipientId: recipientId,
        )),
      );
      if (plaintext.length != 32) return null;
      return _encodeUrl(plaintext);
    } catch (_) {
      return null;
    }
  }

  Future<String> encryptGroupMessage({
    required String groupId,
    required int keyVersion,
    required String senderId,
    required String messageId,
    required String createdAt,
    required String plaintext,
    required String groupKey,
    required Map<String, String> senderAuthSharedKeysByRecipient,
  }) async {
    if (groupId.trim().isEmpty || senderId.trim().isEmpty || messageId.trim().isEmpty ||
        keyVersion < 1 || createdAt.trim().isEmpty) {
      throw const FormatException('group-message identity metadata is required');
    }
    if (utf8.encode(plaintext).length > 16 * 1024) {
      throw const FormatException('group message body is too large');
    }
    final canonicalCreatedAt = _canonicalMessageTimestamp(createdAt);
    final keyBytes = _decodeUrl(groupKey);
    if (keyBytes.length != 32) throw const FormatException('invalid group key');
    final aad = _groupMessageAad(
      groupId: groupId,
      keyVersion: keyVersion,
      senderId: senderId,
      messageId: messageId,
      createdAt: canonicalCreatedAt,
    );
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(keyBytes),
      aad: utf8.encode(aad),
    );
    final authTags = <String, String>{};
    for (final entry in senderAuthSharedKeysByRecipient.entries) {
      if (entry.key.isEmpty) throw const FormatException('invalid group sender-auth recipient');
      final pairwiseBytes = _decodeUrl(entry.value);
      if (pairwiseBytes.length != 32) throw const FormatException('invalid group sender-auth key');
      final canonical = utf8.encode(
        '$aad|${_encodeUrl(box.nonce)}|${_encodeUrl(box.cipherText)}|${_encodeUrl(box.mac.bytes)}|${entry.key}',
      );
      final tag = await _hmac.calculateMac(canonical, secretKey: SecretKey(pairwiseBytes));
      authTags[entry.key] = _encodeUrl(tag.bytes);
    }
    return '$_groupMessageEnvelopeVersion${jsonEncode(<String, Object>{
      'version': 1,
      'type': 'group_message',
      'group_id': groupId,
      'key_version': keyVersion,
      'sender_id': senderId,
      'message_id': messageId,
      'created_at': canonicalCreatedAt,
      'nonce': _encodeUrl(box.nonce),
      'ciphertext': _encodeUrl(box.cipherText),
      'mac': _encodeUrl(box.mac.bytes),
      'sender_auth': authTags,
    })}';
  }

  Future<bool> verifyGroupMessageSenderAuthTag({
    required String groupId,
    required int keyVersion,
    required String senderId,
    required String recipientId,
    required String messageId,
    required String createdAt,
    required String value,
    required String sharedKey,
  }) async {
    if (!value.startsWith(_groupMessageEnvelopeVersion)) return false;
    try {
      final raw = jsonDecode(value.substring(_groupMessageEnvelopeVersion.length)) as Map<String, dynamic>;
      if (raw['version']?.toString() != '1' || raw['type']?.toString() != 'group_message' ||
          raw['group_id']?.toString() != groupId ||
          int.tryParse(raw['key_version']?.toString() ?? '') != keyVersion ||
          raw['sender_id']?.toString() != senderId ||
          raw['message_id']?.toString() != messageId) return false;
      final canonicalCreatedAt = _canonicalMessageTimestamp(createdAt);
      if (raw['created_at']?.toString() != canonicalCreatedAt) return false;
      final tags = raw['sender_auth'];
      if (tags is! Map || !tags.containsKey(recipientId)) return false;
      final keyBytes = _decodeUrl(sharedKey);
      if (keyBytes.length != 32) return false;
      final nonce = _decodeUrl(raw['nonce']?.toString() ?? '');
      final ciphertext = _decodeUrl(raw['ciphertext']?.toString() ?? '');
      final mac = _decodeUrl(raw['mac']?.toString() ?? '');
      final aad = _groupMessageAad(
        groupId: groupId,
        keyVersion: keyVersion,
        senderId: senderId,
        messageId: messageId,
        createdAt: canonicalCreatedAt,
      );
      final expected = await _hmac.calculateMac(
        utf8.encode('$aad|${_encodeUrl(nonce)}|${_encodeUrl(ciphertext)}|${_encodeUrl(mac)}|$recipientId'),
        secretKey: SecretKey(keyBytes),
      );
      final supplied = _decodeUrl(tags[recipientId]?.toString() ?? '');
      if (supplied.length != expected.bytes.length) return false;
      var diff = 0;
      for (var i = 0; i < supplied.length; i++) {
        diff |= supplied[i] ^ expected.bytes[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  Future<String?> decryptGroupMessage({
    required String groupId,
    required int keyVersion,
    required String senderId,
    required String messageId,
    required String createdAt,
    required String value,
    required String groupKey,
  }) async {
    if (!value.startsWith(_groupMessageEnvelopeVersion)) return null;
    try {
      final raw = jsonDecode(value.substring(_groupMessageEnvelopeVersion.length)) as Map<String, dynamic>;
      final canonicalCreatedAt = _canonicalMessageTimestamp(createdAt);
      if (raw['version']?.toString() != '1' ||
          raw['type']?.toString() != 'group_message' ||
          raw['group_id']?.toString() != groupId ||
          int.tryParse(raw['key_version']?.toString() ?? '') != keyVersion ||
          raw['sender_id']?.toString() != senderId ||
          raw['message_id']?.toString() != messageId ||
          raw['created_at']?.toString() != canonicalCreatedAt) return null;
      final keyBytes = _decodeUrl(groupKey);
      if (keyBytes.length != 32) return null;
      final plaintext = await _aes.decrypt(
        SecretBox(
          _decodeUrl(raw['ciphertext']?.toString() ?? ''),
          nonce: _decodeUrl(raw['nonce']?.toString() ?? ''),
          mac: Mac(_decodeUrl(raw['mac']?.toString() ?? '')),
        ),
        secretKey: SecretKey(keyBytes),
        aad: utf8.encode(_groupMessageAad(
          groupId: groupId,
          keyVersion: keyVersion,
          senderId: senderId,
          messageId: messageId,
          createdAt: canonicalCreatedAt,
        )),
      );
      return utf8.decode(plaintext);
    } catch (_) {
      return null;
    }
  }

  int? groupMessageKeyVersion(String value) {
    if (!value.startsWith(_groupMessageEnvelopeVersion)) return null;
    try {
      final raw = jsonDecode(value.substring(_groupMessageEnvelopeVersion.length)) as Map<String, dynamic>;
      if (raw['version']?.toString() != '1' || raw['type']?.toString() != 'group_message') return null;
      final version = int.tryParse(raw['key_version']?.toString() ?? '');
      return version != null && version >= 1 ? version : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> fileChunkHmac({required String originId, required String recipientId, required String transferId, required String messageId, required int index, required String sha256, required List<int> plaintext, required String sharedKey}) async {
    final key = SecretKey(_decodeUrl(sharedKey));
    final canonical = utf8.encode('$originId|$recipientId|$transferId|$messageId|$index|$sha256|${_encodeUrl(plaintext)}');
    final mac = await _hmac.calculateMac(canonical, secretKey: key);
    return base64UrlEncode(mac.bytes);
  }
}
