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




}
