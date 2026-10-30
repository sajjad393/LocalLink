import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/core/services/message_seal_service.dart';

/// Bundle 166 (5.2): fresh keys for sealed messages.
///
/// Before, every sealed message used the two phones' long-term identity keys.
/// Whoever stole a phone later could open every old message they had
/// captured on the air. Now:
/// - each phone makes a new short-lived "session" key every day and tells
///   its contacts inside its own sealed messages;
/// - the sender locks each message with a brand-new one-time key plus the
///   receiver's session key (and both identity keys, so it still proves who
///   sent it). The one-time key is thrown away at once;
/// - old session keys are deleted after 3 days.
/// So a stolen phone can open at most the last ~3 days of captured packets,
/// never older ones.
class SessionKeyPolicy {
  SessionKeyPolicy._();

  /// A new session key every day.
  static const Duration rotateAfter = Duration(hours: 24);

  /// A sender uses a contact's session key only while it is younger than
  /// this (a mesh packet lives at most 24 h, plus 12 h for clocks).
  static const Duration useFor = Duration(hours: 36);

  /// Old session keys are deleted once older than this.
  static const Duration deleteAfter = Duration(hours: 72);

  /// A key "from the future" more than this is refused (wrong clock).
  static const Duration maxFutureSkew = Duration(hours: 12);

  /// At most this many session keys are kept (current + older).
  static const int maxKept = 6;

  static bool needsRotation(int createdAtMs, DateTime now) =>
      now.millisecondsSinceEpoch - createdAtMs >= rotateAfter.inMilliseconds;

  static bool shouldDelete(int createdAtMs, DateTime now, {required bool current}) =>
      !current &&
      now.millisecondsSinceEpoch - createdAtMs >= deleteAfter.inMilliseconds;

  /// May a sender lock a message with a contact's session key made at
  /// [createdAtMs]?
  static bool usable(int createdAtMs, DateTime now) {
    final age = now.millisecondsSinceEpoch - createdAtMs;
    return age < useFor.inMilliseconds && age > -maxFutureSkew.inMilliseconds;
  }
}

/// One of this phone's session keys.
class SessionKey {
  SessionKey(this.id, this.pair, this.publicKey, this.createdAtMs);
  final String id;
  final SimpleKeyPair pair;
  final List<int> publicKey;
  final int createdAtMs;
}

/// A contact's session key as learned from one of its sealed messages.
class PeerSessionKey {
  const PeerSessionKey(this.id, this.publicKey, this.createdAtMs);
  final String id;
  final List<int> publicKey;
  final int createdAtMs;

  /// The `_sp` field carried inside a sealed message.
  Map<String, dynamic> toWire() => {
        'k': id,
        'p': _b64(publicKey),
        't': createdAtMs,
      };

  /// Null when the field is missing or broken.
  static PeerSessionKey? fromWire(Object? raw) {
    if (raw is! Map) return null;
    try {
      final p = _unb64(raw['p']?.toString() ?? '');
      final k = raw['k']?.toString() ?? '';
      final t = raw['t'];
      if (p.length != 32 || t is! int || t <= 0) return null;
      // The id must match the key, so a wrong pair can't be slipped in.
      if (k != MessageSealService.keyId(p)) return null;
      return PeerSessionKey(k, p, t);
    } catch (_) {
      return null;
    }
  }
}

/// Where the session keys are kept (secure storage in the app).
abstract interface class SessionKeyVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureSessionKeyVault implements SessionKeyVault {
  SecureSessionKeyVault([SecureStorageService? secure])
      : _secure = secure ?? const SecureStorageService();

  /// Starts with the prefix [IdentityCryptoService.clearIdentity] wipes.
  static const String storageKey = 'locallink_session_x25519_v1';
  final SecureStorageService _secure;

  @override
  Future<String?> read() => _secure.read(key: storageKey);
  @override
  Future<void> write(String value) =>
      _secure.write(key: storageKey, value: value);
  @override
  Future<void> delete() => _secure.delete(key: storageKey);
}

/// This phone's session keys: makes, rotates and deletes them.
class SessionKeyService {
  SessionKeyService({SessionKeyVault? vault, DateTime Function()? clock})
      : _vault = vault ?? SecureSessionKeyVault(),
        _clock = clock ?? DateTime.now;

  final SessionKeyVault _vault;
  final DateTime Function() _clock;
  final X25519 _x25519 = X25519();
  List<SessionKey>? _keys;
  Future<SessionKey>? _busy;

  /// The key to tell contacts about now (made or rotated when needed).
  Future<SessionKey> current() {
    final busy = _busy;
    if (busy != null) return busy;
    final f = _current();
    _busy = f;
    return f.whenComplete(() => _busy = null);
  }

  Future<SessionKey> _current() async {
    final now = _clock();
    final keys = await _load();
    var changed = false;
    if (keys.isEmpty || SessionKeyPolicy.needsRotation(keys.first.createdAtMs, now)) {
      keys.insert(0, await _make(now));
      changed = true;
    }
    final before = keys.length;
    final head = keys.first;
    keys.removeWhere(
      (k) => !identical(k, head) &&
          SessionKeyPolicy.shouldDelete(k.createdAtMs, now, current: false),
    );
    while (keys.length > SessionKeyPolicy.maxKept) {
      keys.removeLast();
    }
    if (changed || keys.length != before) await _save(keys);
    return keys.first;
  }

  /// One of my session keys by id, or null (unknown or already deleted).
  Future<SessionKey?> byId(String id) async {
    await current(); // also deletes expired ones first
    for (final k in await _load()) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// Number of session keys kept now (for tests / logs).
  Future<int> keptCount() async => (await _load()).length;

  Future<void> wipe() async {
    _keys = <SessionKey>[];
    await _vault.delete();
  }

  Future<SessionKey> _make(DateTime now) async {
    final pair = await _x25519.newKeyPair();
    final pub = (await pair.extractPublicKey()).bytes;
    return SessionKey(
      MessageSealService.keyId(pub),
      pair,
      pub,
      now.millisecondsSinceEpoch,
    );
  }

  Future<List<SessionKey>> _load() async {
    final cached = _keys;
    if (cached != null) return cached;
    final out = <SessionKey>[];
    try {
      final raw = await _vault.read();
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final e in list) {
            if (e is! Map) continue;
            final seed = _unb64(e['s']?.toString() ?? '');
            final t = e['t'];
            if (seed.length != 32 || t is! int) continue;
            final pair = await _x25519.newKeyPairFromSeed(seed);
            final pub = (await pair.extractPublicKey()).bytes;
            out.add(SessionKey(MessageSealService.keyId(pub), pair, pub, t));
          }
        }
      }
    } catch (_) {
      // Broken store: start fresh (contacts fall back to the old lock once).
    }
    out.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    _keys = out;
    return out;
  }

  Future<void> _save(List<SessionKey> keys) async {
    final list = <Map<String, dynamic>>[];
    for (final k in keys) {
      list.add({
        's': _b64(await k.pair.extractPrivateKeyBytes()),
        't': k.createdAtMs,
      });
    }
    await _vault.write(jsonEncode(list));
  }
}

String _b64(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

List<int> _unb64(String value) {
  var v = value;
  while (v.length % 4 != 0) {
    v += '=';
  }
  return base64Url.decode(v);
}
