import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:locallink/core/services/message_seal_service.dart';

/// Bundle 160: one link key shared with one contact.
///
/// [ownKid] / [peerKid] are the short key ids from the message seal; the
/// native link hello offers "<ownKid>.<peerKid>" so both phones pick the same
/// key. [keyHex] is the 32-byte secret (hex). It never leaves the phone.
class LinkKeyEntry {
  final String ownKid;
  final String peerKid;
  final String keyHex;

  const LinkKeyEntry({
    required this.ownKid,
    required this.peerKid,
    required this.keyHex,
  });

  Map<String, String> toJson() => <String, String>{
    'o': ownKid,
    'p': peerKid,
    'k': keyHex,
  };
}

/// Bundle 160: signed device id — the secret two contacts share for the
/// link hello.
///
/// X25519 between one of my identity keys and the contact's identity key,
/// then HKDF-SHA256. Both phones get the same 32 bytes (ids and key ids are
/// sorted into the HKDF info). Up to 3 of my keys (current + older, after a
/// key rotation) so a contact that still knows an older key also matches.
class LinkKeyService {
  LinkKeyService();

  static const int maxOwnKeys = 3;
  static const String _salt = 'locallink-link-v1';

  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final Map<String, LinkKeyEntry> _cache = <String, LinkKeyEntry>{};

  /// Link keys between [selfId] (keys [mine]) and [peerId] (public key
  /// [theirPublic]). Empty when the contact key is not 32 bytes.
  Future<List<LinkKeyEntry>> keysFor({
    required String selfId,
    required String peerId,
    required List<SealKeyPair> mine,
    required List<int> theirPublic,
  }) async {
    if (theirPublic.length != 32 || selfId.isEmpty || peerId.isEmpty) {
      return const <LinkKeyEntry>[];
    }
    final peerKid = MessageSealService.keyId(theirPublic);
    final out = <LinkKeyEntry>[];
    for (final pair in mine.take(maxOwnKeys)) {
      final ownKid = MessageSealService.keyId(pair.publicKey);
      final cacheKey = '$selfId|$peerId|$ownKid|$peerKid';
      final cached = _cache[cacheKey];
      if (cached != null) {
        out.add(cached);
        continue;
      }
      final shared = await _x25519.sharedSecretKey(
        keyPair: pair.pair,
        remotePublicKey: SimplePublicKey(theirPublic, type: KeyPairType.x25519),
      );
      final ids = <String>[selfId, peerId]..sort();
      final kids = <String>[ownKid, peerKid]..sort();
      final key = await _hkdf.deriveKey(
        secretKey: shared,
        nonce: utf8.encode(_salt),
        info: utf8.encode('link|${ids.join('|')}|${kids.join('|')}'),
      );
      final bytes = await key.extractBytes();
      final entry = LinkKeyEntry(
        ownKid: ownKid,
        peerKid: peerKid,
        keyHex: bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      );
      if (_cache.length >= 1024) _cache.remove(_cache.keys.first);
      _cache[cacheKey] = entry;
      out.add(entry);
    }
    return out;
  }

  /// {peerId: [{o, p, k}]} for every contact with a known key.
  Future<Map<String, List<Map<String, String>>>> buildAll({
    required String selfId,
    required Iterable<String> peerIds,
    required List<SealKeyPair> mine,
    required Future<List<int>?> Function(String peerId) publicKeyOf,
  }) async {
    final out = <String, List<Map<String, String>>>{};
    for (final peerId in peerIds) {
      final id = peerId.trim();
      if (id.isEmpty || id == selfId || out.containsKey(id)) continue;
      final theirs = await publicKeyOf(id);
      if (theirs == null) continue;
      final keys = await keysFor(
        selfId: selfId,
        peerId: id,
        mine: mine,
        theirPublic: theirs,
      );
      if (keys.isNotEmpty) out[id] = [for (final k in keys) k.toJson()];
    }
    return out;
  }
}
