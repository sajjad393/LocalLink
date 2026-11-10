import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/link_key_refresh_257.dart';

/// Bundle 235: one phone = one account.
///
/// The old account that owns this phone (as a friend's phone or the server
/// told us). While set, the app shows only "Confirm your account".
class DupBlockInfo235 {
  final String userId;
  final String username;
  final String name;
  final String deviceId;

  /// The old account's recovery public key (from a friend; '' = unknown).
  final String recoveryKey;

  /// 'friend' | 'server'.
  final String source;
  final String at;

  const DupBlockInfo235({
    required this.userId,
    required this.username,
    this.name = '',
    this.deviceId = '',
    this.recoveryKey = '',
    this.source = 'friend',
    this.at = '',
  });

  String get shownName => name.trim().isNotEmpty ? name.trim() : username;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'name': name,
        'device_id': deviceId,
        'recovery_key': recoveryKey,
        'source': source,
        'at': at,
      };

  static DupBlockInfo235? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final user = raw['user_id']?.toString().trim() ?? '';
    final name = raw['username']?.toString().trim() ?? '';
    if (user.isEmpty || name.isEmpty) return null;
    return DupBlockInfo235(
      userId: user,
      username: name,
      name: raw['name']?.toString() ?? '',
      deviceId: raw['device_id']?.toString() ?? '',
      recoveryKey: raw['recovery_key']?.toString() ?? '',
      source: raw['source']?.toString() ?? 'friend',
      at: raw['at']?.toString() ?? '',
    );
  }
}

/// Bundle 235: the block on THIS phone (kept in the settings table, so it
/// survives a restart).
abstract final class DupBlock235 {
  static const settingKey = 'dup235_block';
  static final ValueNotifier<DupBlockInfo235?> state =
      ValueNotifier<DupBlockInfo235?>(null);

  static Future<void> load(Future<String?> Function(String key) read) async {
    try {
      final raw = await read(settingKey);
      if (raw == null || raw.isEmpty) {
        state.value = null;
        return;
      }
      state.value = DupBlockInfo235.fromJson(jsonDecode(raw));
    } catch (_) {
      state.value = null;
    }
  }

  /// Sets (or refreshes) the block. A known recovery key is kept when a
  /// later note for the same account has none.
  static Future<void> set(
      Future<void> Function(String key, String value) write,
      DupBlockInfo235 info) async {
    final old = state.value;
    var next = info;
    if (old != null &&
        old.userId == info.userId &&
        info.recoveryKey.isEmpty &&
        old.recoveryKey.isNotEmpty) {
      next = DupBlockInfo235(
        userId: info.userId,
        username: info.username,
        name: info.name.isEmpty ? old.name : info.name,
        deviceId: info.deviceId.isEmpty ? old.deviceId : info.deviceId,
        recoveryKey: old.recoveryKey,
        source: info.source,
        at: info.at,
      );
    }
    try {
      await write(settingKey, jsonEncode(next.toJson()));
    } catch (_) {}
    final changed = old == null ||
        old.userId != next.userId ||
        old.recoveryKey != next.recoveryKey ||
        old.username != next.username;
    state.value = next;
    if (changed) {
      AppLogger.info('DUP_ACCOUNT_THIS_PHONE',
          detail: 'old=@${next.username} source=${next.source} '
              'rkey=${next.recoveryKey.isEmpty ? 0 : 1}');
    }
  }

  static Future<void> clear(
      Future<void> Function(String key, String value) write) async {
    try {
      await write(settingKey, '');
    } catch (_) {}
    if (state.value != null) AppLogger.info('DUP_ACCOUNT_CLEARED');
    state.value = null;
  }
}

/// Bundle 235: friends' phones took new keys for a contact (a return card).
/// The seal key cache drops its copies when this changes.
abstract final class KeyChange235 {
  static int generation = 0;
  static void bump() {
    generation++;
    LinkKeyRefresh257.request('key_change'); // Bundle 257 (A3)
  }
}

/// Bundle 235: the recovery key. Made from the account's recovery code (and
/// the user id), so the same code always gives the same key - on the old
/// phone (to hand the public half to friends) and on the new install (to
/// sign the return card with no server).
abstract final class RecoveryKey235 {
  static final Ed25519 _ed = Ed25519();
  static final Map<String, SimpleKeyPair> _cache = <String, SimpleKeyPair>{};

  static String normalize(String code) =>
      code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  static bool looksLikeCode(String code) => normalize(code).length == 20;

  static Future<SimpleKeyPair> _pair(String code, String userId) async {
    final c = normalize(code);
    final id = userId.trim();
    final cacheKey = '$c|$id';
    final hit = _cache[cacheKey];
    if (hit != null) return hit;
    final seed = await PasswordKdf.deriveAsync(
        c, Uint8List.fromList(utf8.encode('linkup-recovery-235|$id')));
    final pair = await _ed.newKeyPairFromSeed(seed);
    if (_cache.length > 4) _cache.clear();
    _cache[cacheKey] = pair;
    return pair;
  }

  static Future<String> publicKey(String code, String userId) async {
    final pair = await _pair(code, userId);
    final pub = await pair.extractPublicKey();
    return b64(pub.bytes);
  }

  static Future<String> sign(String code, String userId, String body) async {
    final pair = await _pair(code, userId);
    final sig = await _ed.sign(utf8.encode(body), keyPair: pair);
    return b64(sig.bytes);
  }

  static Future<bool> verify(String body, String sig, String key) async {
    try {
      final pub = unb64(key);
      final s = unb64(sig);
      if (pub.length != 32 || s.length != 64) return false;
      return await _ed.verify(utf8.encode(body),
          signature: Signature(s,
              publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)));
    } catch (_) {
      return false;
    }
  }

  static String b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> unb64(String value) {
    var v = value.trim();
    while (v.length % 4 != 0) {
      v += '=';
    }
    return base64Url.decode(v);
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();
}

/// Short id for logs (never a full id).
String tail6Of235(String id) =>
    id.length <= 6 ? id : id.substring(id.length - 6);
