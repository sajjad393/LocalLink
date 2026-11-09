import 'dart:async';
import 'dart:convert';

import 'package:locallink/core/identity/dup_account_235.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart'
    show AdminBlockService, ed25519Verify;
import 'package:locallink/features/directory/domain/directory_models.dart';

/// Bundle 235: one phone = one account.
///
/// On a FRIEND's phone:
/// * a card (directory gossip or a nearby add) of a NEW account from a phone
///   that I know as another account's phone is refused at once (no server
///   needed) and the phone gets a short "owner" note (plain, one step);
/// * the owner's recovery key (public half, signed by the owner's card key)
///   is kept, so a later "return card" signed with the recovery code can be
///   checked offline;
/// * a valid return card (recovery key, or the server's trust key) gives the
///   old account the new keys of that phone. Friends never pass it on.
///
/// On the phone with the new account: an owner note sets [DupBlock235] (the
/// app shows "Confirm your account"); after the proof the return card goes
/// to every friend that comes near (30 days).
class DuplicateGuard235 {
  DuplicateGuard235({
    required this.store,
    required this.signingKey,
    required this.identityKey,
    required this.sign,
    required this.send,
    required this.broadcast,
    required Stream<Map<String, dynamic>> events,
    this.serverAllows,
    this.republish,
    DateTime Function()? clock,
  })  : _events = events,
        _clock = clock ?? DateTime.now;

  /// Set by the app; the directory and pairing hooks use it (null = off).
  static DuplicateGuard235? instance;

  static const ownerType = 'dup235_owner';
  static const recoveryKeyType = 'dup235_rkey';
  static const returnType = 'dup235_return';

  static const recoveryKeysSetting = 'recovery_keys_235';
  static const myRecoveryKeySetting = 'my_recovery_key_235';
  static const returnCardSetting = 'dup235_return_card';
  static const returnsSetting = 'returns_235';

  static const ownerNoteGap = Duration(minutes: 2);
  static const recoveryKeyGap = Duration(hours: 6);
  static const returnCardLife = Duration(days: 30);
  static const allowCacheFor = Duration(minutes: 10);

  final LocalStore store;
  final Future<String> Function() signingKey;
  final Future<String> Function() identityKey;
  final Future<String> Function(String body) sign;
  final Future<void> Function(String peer, Map<String, dynamic> payload) send;
  final Future<void> Function(Map<String, dynamic> payload) broadcast;

  /// Online friends only: true when the server already gave this phone to
  /// the new account (the admin's "New owner").
  final Future<bool> Function(String newUserId, String deviceId)? serverAllows;

  /// Sends my own card again (after a return card, so friends take it).
  final Future<void> Function()? republish;

  final Stream<Map<String, dynamic>> _events;
  final DateTime Function() _clock;
  StreamSubscription<Map<String, dynamic>>? _sub;

  final Map<String, DateTime> _ownerSent = <String, DateTime>{};
  final Map<String, DateTime> _keySent = <String, DateTime>{};
  final Map<String, ({bool ok, DateTime at})> _allowed =
      <String, ({bool ok, DateTime at})>{};
  DateTime? _republishedAt;

  void start() {
    _sub ??= _events.listen((event) {
      unawaited(_onEvent(event).catchError((Object e) {
        AppLogger.warning('DUP_GUARD_FAILED', detail: '$e');
      }));
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    if (identical(instance, this)) instance = null;
  }

  Future<String> _myUserId() async {
    final id = store.accountId ?? '';
    if (id.isNotEmpty) return id;
    try {
      return (await store.profile())?.userId ?? '';
    } catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------------ friend side

  /// The account that already owns [deviceId] when [newUserId] is a
  /// DIFFERENT account with different keys (null = not a duplicate).
  /// Re-login of the same account, the same install (same keys) and 218 id
  /// moves are never duplicates. Never throws.
  Future<Map<String, dynamic>?> oldAccountFor({
    required String deviceId,
    required String newUserId,
    String newIdentityKey = '',
    String newSigningKey = '',
  }) async {
    try {
      deviceId = deviceId.trim();
      newUserId = newUserId.trim();
      if (deviceId.isEmpty || newUserId.isEmpty) return null;
      final me = await _myUserId();
      if (newUserId == me) return null;
      for (final row in await store.directoryProfilesByDevice218(deviceId)) {
        final old = row['user_id']?.toString().trim() ?? '';
        if (old.isEmpty || old == newUserId || old == me) continue;
        final oldId = row['identity_public_key']?.toString().trim() ?? '';
        final oldSign = row['signing_public_key']?.toString().trim() ?? '';
        if (oldId.isEmpty && oldSign.isEmpty) continue;
        if (oldId.isNotEmpty && oldId == newIdentityKey.trim()) continue;
        if (oldSign.isNotEmpty && oldSign == newSigningKey.trim()) continue;
        if (await store.movedId218(old) == newUserId) continue; // 218 move
        if (await store.movedId218(newUserId) == old) continue;
        return row;
      }
      // After a return, only the owner's id is taken from that phone.
      final owner = (await _returns())['dev:$deviceId']?.toString() ?? '';
      if (owner.isNotEmpty && owner != newUserId && owner != me) {
        final row = await store.directoryProfile(owner);
        if (row != null) return row;
      }
    } catch (_) {}
    return null;
  }

  /// True = the card must NOT be saved (a new account on a known phone).
  Future<bool> refuseCard(DirectoryProfile card, {String via = 'card'}) async {
    final old = await oldAccountFor(
      deviceId: card.deviceId,
      newUserId: card.userId,
      newIdentityKey: card.identityPublicKey,
      newSigningKey: card.signingPublicKey,
    );
    if (old == null) return false;
    final oldId = old['user_id']?.toString() ?? '';
    if (await _serverGaveIt(card.userId, card.deviceId)) {
      AppLogger.info('DUP_ACCOUNT_NEW_OWNER',
          detail: 'device=…${tail6Of235(card.deviceId)} '
              'old=${tail6Of235(oldId)} new=${tail6Of235(card.userId)}');
      // The admin gave this phone away: the old account loses it here too.
      try {
        await store.saveDirectoryProfile(
            Map<String, dynamic>.from(old)..['device_id'] = '');
      } catch (_) {}
      return false;
    }
    AppLogger.info('DUP_ACCOUNT_BLOCKED',
        detail: 'device=…${tail6Of235(card.deviceId)} '
            'old=${tail6Of235(oldId)} new=${tail6Of235(card.userId)} via=$via');
    // A copy saved before this build goes away (the chat stays the old
    // account's).
    try {
      final had = await store.directoryProfile(card.userId);
      if (had != null && had['device_id']?.toString() == card.deviceId) {
        await store.dropDirectoryProfile235(card.userId);
      }
    } catch (_) {}
    unawaited(_sendOwnerNote(card, old).catchError((_) {}));
    return true;
  }

  Future<bool> _serverGaveIt(String newUserId, String deviceId) async {
    final ask = serverAllows;
    if (ask == null || newUserId.startsWith('offline_')) return false;
    final key = '$newUserId|$deviceId';
    final hit = _allowed[key];
    final now = _clock();
    if (hit != null && now.difference(hit.at) < allowCacheFor) return hit.ok;
    var ok = false;
    try {
      ok = await ask(newUserId, deviceId).timeout(const Duration(seconds: 5));
    } catch (_) {
      ok = false;
    }
    _allowed[key] = (ok: ok, at: now);
    return ok;
  }

  Future<void> _sendOwnerNote(
      DirectoryProfile card, Map<String, dynamic> old) async {
    final key = '${card.deviceId}|${card.userId}';
    final now = _clock();
    final last = _ownerSent[key];
    if (last != null && now.difference(last) < ownerNoteGap) return;
    _ownerSent[key] = now;
    final oldId = old['user_id']?.toString() ?? '';
    await send(card.deviceId, <String, dynamic>{
      'type': ownerType,
      'v': 1,
      'device_id': card.deviceId,
      'for_user': card.userId,
      'user_id': oldId,
      'username': old['username']?.toString() ?? '',
      'name': old['display_name']?.toString() ?? '',
      'recovery_key': await recoveryKeyOf(oldId),
      'at': now.millisecondsSinceEpoch,
    });
  }

  // ----------------------------------------------------------- the events

  Future<void> _onEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString() ?? '';
    if (type == 'peer_connected') {
      final peer = event['peer_id']?.toString() ?? '';
      if (peer.isNotEmpty) await _onPeer(peer);
      return;
    }
    if (type != 'message') return;
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains('dup235_')) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      msg = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final sender = event['sender_id']?.toString() ?? '';
    switch (msg['type']?.toString()) {
      case ownerType:
        await onOwnerNote(msg, sender);
      case recoveryKeyType:
        await onRecoveryKey(msg);
      case returnType:
        await onReturnCard(msg);
    }
  }

  Future<void> _onPeer(String peer) async {
    await sendReturnCardTo(peer);
    await spreadMyRecoveryKey(to: peer);
  }

  // ------------------------------------------------- the new account's phone

  /// A friend says this phone belongs to another account.
  Future<void> onOwnerNote(Map<String, dynamic> msg, String sender) async {
    final me = await _myUserId();
    final dev = store.deviceId ?? '';
    final oldId = msg['user_id']?.toString().trim() ?? '';
    final oldName = msg['username']?.toString().trim() ?? '';
    if (me.isEmpty || dev.isEmpty || oldId.isEmpty || oldName.isEmpty) return;
    if (msg['device_id']?.toString() != dev) return;
    if (msg['for_user']?.toString() != me || oldId == me) return;
    // The server already took this account on this phone: friends that
    // were away still block it, but this phone is not stopped.
    if (!store.isOfflinePending && (store.deviceToken ?? '').isNotEmpty) {
      AppLogger.info('DUP_ACCOUNT_NOTE_IGNORED', detail: 'reason=on_server');
      return;
    }
    await DupBlock235.set(
        store.writeSetting,
        DupBlockInfo235(
          userId: oldId,
          username: oldName,
          name: msg['name']?.toString() ?? '',
          deviceId: dev,
          recoveryKey: msg['recovery_key']?.toString() ?? '',
          source: 'friend',
          at: _clock().toUtc().toIso8601String(),
        ));
  }

  // ------------------------------------------------------- recovery keys

  /// My recovery key (public half), made once per code + account.
  Future<String> myRecoveryKey() async {
    final code = store.localRecoveryCode ?? '';
    final me = await _myUserId();
    if (!RecoveryKey235.looksLikeCode(code) || me.isEmpty) return '';
    final tag = '${RecoveryKey235.normalize(code).hashCode}|$me';
    try {
      final saved = await store.readSetting(myRecoveryKeySetting);
      if (saved != null && saved.isNotEmpty) {
        final m = jsonDecode(saved);
        if (m is Map && m['tag'] == tag && (m['key']?.toString() ?? '').isNotEmpty) {
          return m['key'].toString();
        }
      }
    } catch (_) {}
    final key = await RecoveryKey235.publicKey(code, me);
    try {
      await store.writeSetting(
          myRecoveryKeySetting, jsonEncode({'tag': tag, 'key': key}));
    } catch (_) {}
    return key;
  }

  /// Hands my recovery key to [to] (or to every phone on the link).
  Future<void> spreadMyRecoveryKey({String? to}) async {
    if (DupBlock235.state.value != null) return;
    final key = await myRecoveryKey();
    final me = await _myUserId();
    final dev = store.deviceId ?? '';
    if (key.isEmpty || me.isEmpty || dev.isEmpty) return;
    if (to != null) {
      // Once per 6 h per phone, and again at once when my key changed.
      final tag = '$to|$key';
      final last = _keySent[tag];
      final now = _clock();
      if (last != null && now.difference(last) < recoveryKeyGap) return;
      _keySent[tag] = now;
    }
    final body = jsonEncode({
      'kind': 'recovery_key_235',
      'v': 1,
      'user_id': me,
      'device_id': dev,
      'key': key,
      'at': _clock().millisecondsSinceEpoch,
    });
    final payload = <String, dynamic>{
      'type': recoveryKeyType,
      'body': body,
      'sig': await sign(body),
    };
    try {
      if (to != null) {
        await send(to, payload);
      } else {
        await broadcast(payload);
      }
    } catch (_) {}
  }

  /// The code changed: friends get the new recovery key.
  Future<void> recoveryCodeChanged() async {
    _keySent.clear();
    await spreadMyRecoveryKey();
  }

  Future<Map<String, dynamic>> _readMap(String key) async {
    try {
      final raw = await store.readSetting(key);
      if (raw == null || raw.isEmpty) return <String, dynamic>{};
      final m = jsonDecode(raw);
      return m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<String> recoveryKeyOf(String userId) async {
    if (userId.isEmpty) return '';
    final m = (await _readMap(recoveryKeysSetting))[userId];
    return m is Map ? (m['key']?.toString() ?? '') : '';
  }

  /// A friend's recovery key: checked with that friend's card key.
  Future<void> onRecoveryKey(Map<String, dynamic> msg) async {
    final body = msg['body']?.toString() ?? '';
    final sig = msg['sig']?.toString() ?? '';
    Map<String, dynamic> b;
    try {
      b = Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (_) {
      return;
    }
    if (b['kind'] != 'recovery_key_235') return;
    final user = b['user_id']?.toString() ?? '';
    final key = b['key']?.toString() ?? '';
    final at = (b['at'] as num?)?.toInt() ?? 0;
    if (user.isEmpty || key.isEmpty) return;
    final row = await store.directoryProfile(user);
    if (row == null) return;
    final signKey = row['signing_public_key']?.toString() ?? '';
    if (signKey.isEmpty || row['device_id']?.toString() != b['device_id']?.toString()) {
      return;
    }
    if (!await ed25519Verify(body, sig, signKey)) {
      AppLogger.info('DUP_RKEY_BAD', detail: 'user=${tail6Of235(user)}');
      return;
    }
    final all = await _readMap(recoveryKeysSetting);
    final old = all[user];
    if (old is Map) {
      final oldAt = (old['at'] as num?)?.toInt() ?? 0;
      if (old['key'] == key || oldAt >= at) return;
    }
    all[user] = {'key': key, 'at': at};
    await store.writeSetting(recoveryKeysSetting, jsonEncode(all));
    AppLogger.info('DUP_RKEY_SAVED', detail: 'user=${tail6Of235(user)}');
  }

  // --------------------------------------------------------- return cards

  /// The new install proved the old account with the recovery code: a return
  /// card signed with the recovery key. Kept 30 days and sent now.
  Future<void> makeCodeReturn({
    required String code,
    required String userId,
    required String username,
    String name = '',
  }) async {
    final body = jsonEncode({
      'kind': 'account_return_235',
      'v': 1,
      'user_id': userId,
      'username': username,
      'name': name,
      'device_id': store.deviceId ?? '',
      'signing_key': await signingKey(),
      'identity_key': await identityKey(),
      'at': _clock().millisecondsSinceEpoch,
      'via': 'code',
    });
    final sig = await RecoveryKey235.sign(code, userId, body);
    await keepReturnCard(body, sig);
  }

  /// Keeps a return card (made here, or signed by the server) and sends it.
  Future<void> keepReturnCard(String body, String sig) async {
    if (body.isEmpty || sig.isEmpty) return;
    final until = _clock().add(returnCardLife).millisecondsSinceEpoch;
    await store.writeSetting(returnCardSetting,
        jsonEncode({'body': body, 'sig': sig, 'until': until}));
    AppLogger.info('DUP_RETURN_KEPT');
    try {
      await broadcast(<String, dynamic>{'type': returnType, 'body': body, 'sig': sig});
    } catch (_) {}
    _republishSoon(force: true);
  }

  Future<void> sendReturnCardTo(String peer) async {
    final m = await _readMap(returnCardSetting);
    final body = m['body']?.toString() ?? '';
    final sig = m['sig']?.toString() ?? '';
    final until = (m['until'] as num?)?.toInt() ?? 0;
    if (body.isEmpty || sig.isEmpty) return;
    if (until < _clock().millisecondsSinceEpoch) {
      await store.writeSetting(returnCardSetting, '');
      return;
    }
    try {
      await send(peer, <String, dynamic>{'type': returnType, 'body': body, 'sig': sig});
    } catch (_) {}
    _republishSoon();
  }

  void _republishSoon({bool force = false}) {
    final hook = republish;
    if (hook == null) return;
    final now = _clock();
    final last = _republishedAt;
    if (!force && last != null && now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _republishedAt = now;
    Timer(const Duration(seconds: 2), () {
      unawaited(hook().catchError((_) {}));
    });
  }

  Future<Map<String, dynamic>> _returns() => _readMap(returnsSetting);

  /// A friend's phone came back to its old account. Checked offline with the
  /// recovery key (or the server's trust key). Never passed on.
  Future<bool> onReturnCard(Map<String, dynamic> msg) async {
    final body = msg['body']?.toString() ?? '';
    final sig = msg['sig']?.toString() ?? '';
    Map<String, dynamic> b;
    try {
      b = Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (_) {
      return false;
    }
    if (b['kind'] != 'account_return_235') return false;
    final user = b['user_id']?.toString() ?? '';
    final dev = b['device_id']?.toString() ?? '';
    final newSign = b['signing_key']?.toString() ?? '';
    final newId = b['identity_key']?.toString() ?? '';
    final at = (b['at'] as num?)?.toInt() ?? 0;
    if (user.isEmpty || dev.isEmpty || newSign.isEmpty || newId.isEmpty) return false;
    if (user == await _myUserId()) return false;
    final row = await store.directoryProfile(user);
    if (row == null) return false; // not someone I know
    if (row['device_id']?.toString() != dev) return false;
    final done = await _returns();
    final lastAt = (done['at:$user'] as num?)?.toInt() ?? 0;
    if (at <= lastAt) return false;
    var ok = false;
    final rk = await recoveryKeyOf(user);
    if (rk.isNotEmpty) ok = await RecoveryKey235.verify(body, sig, rk);
    if (!ok) {
      final trust = await store.readSetting(AdminBlockService.trustKeySetting) ?? '';
      if (trust.isNotEmpty) ok = await ed25519Verify(body, sig, trust);
    }
    if (!ok) {
      AppLogger.info('DUP_RETURN_BAD', detail: 'user=${tail6Of235(user)}');
      return false;
    }
    done['at:$user'] = at;
    done['dev:$dev'] = user;
    await store.writeSetting(returnsSetting, jsonEncode(done));
    final same = row['signing_public_key']?.toString() == newSign &&
        row['identity_public_key']?.toString() == newId;
    if (!same) {
      // The old card stays (name, photo, number); the keys are the phone's
      // new keys, and the next card from that phone is taken.
      await store.saveDirectoryProfile(Map<String, dynamic>.from(row)
        ..['signing_public_key'] = newSign
        ..['identity_public_key'] = newId
        ..['signature'] = ''
        ..['profile_version'] = 0
        ..['updated_at'] = '');
      KeyChange235.bump();
    }
    // The new account's copies on that phone go away.
    try {
      for (final r in await store.directoryProfilesByDevice218(dev)) {
        final other = r['user_id']?.toString() ?? '';
        if (other.isNotEmpty && other != user) {
          await store.dropDirectoryProfile235(other);
        }
      }
    } catch (_) {}
    AppLogger.info('DUP_ACCOUNT_RETURN_OK',
        detail: 'user=${tail6Of235(user)} via=${b['via']} keys=${same ? 'same' : 'new'}');
    return true;
  }
}
