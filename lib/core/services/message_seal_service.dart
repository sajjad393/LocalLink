import 'dart:convert';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';

/// Bundle 156: one of this phone's X25519 identity key pairs.
class SealKeyPair {
  final SimpleKeyPair pair;
  final List<int> publicKey;
  const SealKeyPair(this.pair, this.publicKey);

  static Future<SealKeyPair> from(SimpleKeyPair pair) async =>
      SealKeyPair(pair, (await pair.extractPublicKey()).bytes);
}

/// Why a sealed packet could not be opened (logged as SEAL_OPEN_FAILED).
class SealOpenException implements Exception {
  final String reason;
  const SealOpenException(this.reason);
  @override
  String toString() => 'SealOpenException($reason)';
}

/// Bundle 156: end-to-end "lock" for offline messages.
///
/// X25519 between the sender's and the receiver's identity keys (exchanged at
/// pairing) → HKDF-SHA256 → AES-256-GCM. Only the two phones can open it, so
/// any LocalLink phone — even a stranger's — may pass it on.
///
/// What stays outside (relays need it for routing): sender id, receiver id
/// (in the mesh envelope) and short key ids. Everything else — the message
/// type, ids, text, timestamps — is inside.
///
/// The sender id, receiver id, key ids and the outer type are bound as
/// associated data: a relay can't re-address, re-type or replay a packet as
/// coming from someone else without the open failing.
class MessageSealService {
  MessageSealService();

  static const int version = 1;

  /// Bundle 166 (5.2): fresh keys - a one-time key per message plus the
  /// receiver's daily session key (see SessionKeyService).
  static const int freshVersion = 2;

  /// Store-and-forward class (chat, receipts, call signals).
  static const String sealedType = 'sealed';

  /// Best-effort class (presence, heartbeats, probes).
  static const String sealedLiveType = 'sealed_x';

  /// Bundle 172: how long (ms) the native send queue may keep this message.
  /// Copied outside the lock so the queue can read it (no private data).
  static const String queueLifetimeField = 'qt';

  /// Inner types the native queue keeps when no route exists (same list as
  /// `isStoreForwardable` in LocalLinkTransportService.kt).
  static const Set<String> queueableInnerTypes = {
    'direct_message',
    'direct_delivery_ack',
    'call_invite',
    'call_invite_ack',
    'call_accept',
    'call_reject',
    'call_busy',
    'call_end',
  };

  /// Types the native layer handles itself at the destination (live call
  /// media, video, file chunks). They must never be sealed.
  static const List<String> _nativePrefixes = [
    'call_media',
    'call_video_',
    'direct_file_',
  ];

  static bool isSealedType(String? type) =>
      type == sealedType || type == sealedLiveType;

  /// Whether a payload of [type] is sealed before it leaves this phone.
  static bool shouldSeal(String? type) {
    final t = type?.trim() ?? '';
    if (t.isEmpty || isSealedType(t)) return false;
    for (final prefix in _nativePrefixes) {
      if (t.startsWith(prefix)) return false;
    }
    return true;
  }

  /// Short public id of a key (first 8 bytes of SHA-256, base64url).
  static String keyId(List<int> publicKey) =>
      _b64(digest.sha256.convert(publicKey).bytes.sublist(0, 8));

  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final Map<String, SecretKey> _keys = <String, SecretKey>{};

  Future<SecretKey> _key({
    required SealKeyPair mine,
    required List<int> theirPublic,
    required String senderId,
    required String recipientId,
    required String sk,
    required String rk,
  }) async {
    final cacheKey = '$sk|$rk|$senderId|$recipientId';
    final cached = _keys[cacheKey];
    if (cached != null) return cached;
    final shared = await _x25519.sharedSecretKey(
      keyPair: mine.pair,
      remotePublicKey: SimplePublicKey(theirPublic, type: KeyPairType.x25519),
    );
    final key = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('locallink-seal-v$version'),
      info: utf8.encode('v$version|$senderId|$recipientId|$sk|$rk'),
    );
    if (_keys.length >= 256) _keys.remove(_keys.keys.first);
    _keys[cacheKey] = key;
    return key;
  }

  static List<int> _aad(
    String outer,
    String senderId,
    String recipientId,
    String sk,
    String rk,
  ) => utf8.encode('v$version|$outer|$senderId|$recipientId|$sk|$rk');

  /// Seals [payload] from [senderId] to [recipientId].
  Future<Map<String, dynamic>> seal({
    required Map<String, dynamic> payload,
    required String senderId,
    required String recipientId,
    required SealKeyPair mine,
    required List<int> theirPublic,
    String? outerType,
  }) async {
    if (theirPublic.length != 32) {
      throw ArgumentError('recipient key must be 32 bytes');
    }
    final innerType = payload['type']?.toString();
    final outer =
        outerType ??
        (queueableInnerTypes.contains(innerType) ? sealedType : sealedLiveType);
    final sk = keyId(mine.publicKey);
    final rk = keyId(theirPublic);
    final key = await _key(
      mine: mine,
      theirPublic: theirPublic,
      senderId: senderId,
      recipientId: recipientId,
      sk: sk,
      rk: rk,
    );
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: _aes.newNonce(),
      aad: _aad(outer, senderId, recipientId, sk, rk),
    );
    return <String, dynamic>{
      'type': outer,
      'v': version,
      'sk': sk,
      'rk': rk,
      'n': _b64(box.nonce),
      'c': _b64([...box.cipherText, ...box.mac.bytes]),
    };
  }

  static List<int> _aad2(
    String outer,
    String senderId,
    String recipientId,
    String sk,
    String rk,
    String pk,
    String ek,
  ) =>
      utf8.encode('v$freshVersion|$outer|$senderId|$recipientId|$sk|$rk|$pk|$ek');

  Future<SecretKey> _freshKey({
    required List<int> dhSession,
    required List<int> dhIdentity,
    required String senderId,
    required String recipientId,
    required String sk,
    required String rk,
    required String pk,
    required String ek,
  }) =>
      _hkdf.deriveKey(
        secretKey: SecretKey([...dhSession, ...dhIdentity]),
        nonce: utf8.encode('locallink-seal-v$freshVersion'),
        info: utf8.encode('v$freshVersion|$senderId|$recipientId|$sk|$rk|$pk|$ek'),
      );

  /// Bundle 166 (5.2): seals [payload] with fresh keys.
  ///
  /// key = HKDF( X25519(one-time key, receiver's session key)
  ///           | X25519(my identity key, receiver's identity key) )
  /// The one-time key is made here and forgotten when this returns, so
  /// later nobody - not even this phone - can work the key out again
  /// without the receiver's session key, which is deleted after 3 days.
  /// The identity part still proves who sent it.
  Future<Map<String, dynamic>> sealFresh({
    required Map<String, dynamic> payload,
    required String senderId,
    required String recipientId,
    required SealKeyPair mine,
    required List<int> theirPublic,
    required String theirSessionId,
    required List<int> theirSessionPublic,
    String? outerType,
  }) async {
    if (theirPublic.length != 32 || theirSessionPublic.length != 32) {
      throw ArgumentError('recipient keys must be 32 bytes');
    }
    final innerType = payload['type']?.toString();
    final outer =
        outerType ??
        (queueableInnerTypes.contains(innerType) ? sealedType : sealedLiveType);
    final sk = keyId(mine.publicKey);
    final rk = keyId(theirPublic);
    final pk = theirSessionId;
    final once = await _x25519.newKeyPair();
    final ekBytes = (await once.extractPublicKey()).bytes;
    final ek = _b64(ekBytes);
    final dhSession = await (await _x25519.sharedSecretKey(
      keyPair: once,
      remotePublicKey: SimplePublicKey(theirSessionPublic, type: KeyPairType.x25519),
    )).extractBytes();
    final dhIdentity = await (await _x25519.sharedSecretKey(
      keyPair: mine.pair,
      remotePublicKey: SimplePublicKey(theirPublic, type: KeyPairType.x25519),
    )).extractBytes();
    final key = await _freshKey(
      dhSession: dhSession,
      dhIdentity: dhIdentity,
      senderId: senderId,
      recipientId: recipientId,
      sk: sk,
      rk: rk,
      pk: pk,
      ek: ek,
    );
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: _aes.newNonce(),
      aad: _aad2(outer, senderId, recipientId, sk, rk, pk, ek),
    );
    return <String, dynamic>{
      'type': outer,
      'v': freshVersion,
      'sk': sk,
      'rk': rk,
      'pk': pk,
      'e': ek,
      'n': _b64(box.nonce),
      'c': _b64([...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// Opens a sealed packet that arrived from [senderId] for [recipientId].
  /// [mine] = this phone's key pairs (current and older versions).
  /// Throws [SealOpenException] when it can't be opened.
  Future<Map<String, dynamic>> open({
    required Map<String, dynamic> sealed,
    required String senderId,
    required String recipientId,
    required List<SealKeyPair> mine,
    required List<int> theirPublic,
    Future<SimpleKeyPair?> Function(String sessionId)? sessionKey,
  }) async {
    final outer = sealed['type']?.toString();
    if (!isSealedType(outer)) throw const SealOpenException('not_sealed');
    final v = sealed['v'];
    if (v != version && v != freshVersion) {
      throw const SealOpenException('version');
    }
    final sk = sealed['sk']?.toString() ?? '';
    final rk = sealed['rk']?.toString() ?? '';
    SealKeyPair? own;
    for (final pair in mine) {
      if (keyId(pair.publicKey) == rk) {
        own = pair;
        break;
      }
    }
    if (own == null) throw const SealOpenException('unknown_recipient_key');
    if (theirPublic.length != 32 || keyId(theirPublic) != sk) {
      throw const SealOpenException('sender_key_mismatch');
    }
    final List<int> nonce;
    final List<int> data;
    try {
      nonce = _unb64(sealed['n']?.toString() ?? '');
      data = _unb64(sealed['c']?.toString() ?? '');
    } catch (_) {
      throw const SealOpenException('bad_encoding');
    }
    if (nonce.length != 12 || data.length < 17) {
      throw const SealOpenException('bad_size');
    }
    // Keys are derived in the SENDER→RECEIVER direction on both phones: the
    // receiver uses its own private key with the sender's public key.
    final SecretKey key;
    final List<int> aad;
    if (v == freshVersion) {
      // Bundle 166: fresh keys - my session key (by id) with the sender's
      // one-time key, plus both identity keys.
      final pk = sealed['pk']?.toString() ?? '';
      final ek = sealed['e']?.toString() ?? '';
      final List<int> ekBytes;
      try {
        ekBytes = _unb64(ek);
      } catch (_) {
        throw const SealOpenException('bad_encoding');
      }
      if (ekBytes.length != 32) throw const SealOpenException('bad_size');
      final session = sessionKey == null ? null : await sessionKey(pk);
      if (session == null) throw const SealOpenException('unknown_session_key');
      final dhSession = await (await _x25519.sharedSecretKey(
        keyPair: session,
        remotePublicKey: SimplePublicKey(ekBytes, type: KeyPairType.x25519),
      )).extractBytes();
      final dhIdentity = await (await _x25519.sharedSecretKey(
        keyPair: own.pair,
        remotePublicKey: SimplePublicKey(theirPublic, type: KeyPairType.x25519),
      )).extractBytes();
      key = await _freshKey(
        dhSession: dhSession,
        dhIdentity: dhIdentity,
        senderId: senderId,
        recipientId: recipientId,
        sk: sk,
        rk: rk,
        pk: pk,
        ek: ek,
      );
      aad = _aad2(outer!, senderId, recipientId, sk, rk, pk, ek);
    } else {
      key = await _key(
        mine: own,
        theirPublic: theirPublic,
        senderId: senderId,
        recipientId: recipientId,
        sk: sk,
        rk: rk,
      );
      aad = _aad(outer!, senderId, recipientId, sk, rk);
    }
    final List<int> clear;
    try {
      clear = await _aes.decrypt(
        SecretBox(
          data.sublist(0, data.length - 16),
          nonce: nonce,
          mac: Mac(data.sublist(data.length - 16)),
        ),
        secretKey: key,
        aad: aad,
      );
    } on SecretBoxAuthenticationError {
      throw const SealOpenException('auth_failed');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(clear));
    } catch (_) {
      throw const SealOpenException('bad_plaintext');
    }
    if (decoded is! Map) throw const SealOpenException('bad_plaintext');
    final inner = Map<String, dynamic>.from(decoded);
    if (!shouldSeal(inner['type']?.toString())) {
      throw const SealOpenException('bad_inner_type');
    }
    return inner;
  }

  static String _b64(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static List<int> _unb64(String value) {
    var v = value;
    while (v.length % 4 != 0) {
      v += '=';
    }
    return base64Url.decode(v);
  }
}
