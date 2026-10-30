import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/link_key_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/core/services/session_key_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_transport_service.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

/// Bundle 156: where the seal gets its keys and the contact list.
abstract interface class SealKeySource {
  String? get selfId;

  /// This phone's key pairs, current first (older versions still open old
  /// packets after a key rotation).
  Future<List<SealKeyPair>> ownKeys();

  /// Identity public key of a CONTACT (trusted, not revoked, not blocked),
  /// or null.
  Future<List<int>?> contactPublicKey(String peerId);

  Future<Set<String>> blockedPeerIds();
  Future<String?> readSetting(String key);
  Future<void> writeSetting(String key, String value);
}

/// Production key source: local store + identity keys.
class StoreSealKeySource implements SealKeySource {
  StoreSealKeySource({required this.store, required this.crypto});

  final LocalStore store;
  final IdentityCryptoService crypto;

  List<SealKeyPair>? _own;
  DateTime _ownAt = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, bool> _trusted = const {};
  DateTime _trustedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Set<String> _blocked = const {};
  final Map<String, List<int>> _publicKeys = <String, List<int>>{};

  @override
  String? get selfId => store.deviceId;

  @override
  Future<List<SealKeyPair>> ownKeys() async {
    final now = DateTime.now();
    final cached = _own;
    if (cached != null &&
        cached.isNotEmpty &&
        now.difference(_ownAt) < const Duration(minutes: 5)) {
      return cached;
    }
    final pairs = await crypto.sealKeyPairs();
    final keys = <SealKeyPair>[
      for (final p in pairs) await SealKeyPair.from(p),
    ];
    _own = keys;
    _ownAt = now;
    return keys;
  }

  /// Drops the cached key pairs so the next [ownKeys] reloads them.
  void forgetOwnKeys() {
    _own = null;
  }

  Future<void> _refreshTrusted() async {
    final now = DateTime.now();
    if (now.difference(_trustedAt) < const Duration(seconds: 15)) return;
    final devices = await store.localDevices();
    _blocked = await store.blockedPeerIds();
    _trusted = {
      for (final d in devices)
        if (d.revokedAt.isEmpty && !_blocked.contains(d.id)) d.id: true,
    };
    _trustedAt = now;
    _publicKeys.clear();
  }

  @override
  Future<List<int>?> contactPublicKey(String peerId) async {
    await _refreshTrusted();
    if (_trusted[peerId] != true) return null;
    final cached = _publicKeys[peerId];
    if (cached != null) return cached;
    final profile = await store.directoryProfileByDeviceId(peerId);
    final raw = profile?['identity_public_key']?.toString() ?? '';
    if (raw.isEmpty) return null;
    try {
      var v = raw.trim();
      while (v.length % 4 != 0) {
        v += '=';
      }
      final bytes = base64Url.decode(v);
      if (bytes.length != 32) return null;
      _publicKeys[peerId] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Set<String>> blockedPeerIds() => store.blockedPeerIds();

  @override
  Future<String?> readSetting(String key) => store.readSetting(key);

  @override
  Future<void> writeSetting(String key, String value) =>
      store.writeSetting(key, value);
}

/// Bundle 156: wraps the peer transport and locks messages end to end.
///
/// * Outgoing: payloads to a contact whose app can open sealed messages are
///   sealed (see [MessageSealService.shouldSeal]); everything else goes out
///   exactly as before.
/// * Incoming: sealed packets are opened and handed on as the original
///   payload, so the rest of the app doesn't change. A packet that can't be
///   opened is dropped and logged (SEAL_OPEN_FAILED).
/// * Who can open sealed messages is learned from the link hello, from any
///   sealed packet that opens, and from a one-off sealed probe.
class SealingPeerTransport implements PeerTransportContract {
  SealingPeerTransport(this.inner, {MessageSealService? sealer})
      : _sealer = sealer ?? MessageSealService();

  static const String probeType = 'seal_caps';

  /// Bundle 159: the per-call voice key field inside a call invite.
  static const String voiceKeyField = 'voice_key';
  static const String _capsSetting = 'seal_capable_peers_v1';

  /// Bundle 166 (5.2): fresh keys.
  static const String _freshSetting = 'fresh_seal_peers_v1';
  static const String _peerSessionSetting = 'peer_session_keys_v1';

  /// Inside a sealed message: the sender's current session key.
  static const String sessionField = '_sp';
  static const Duration _probeEvery = Duration(minutes: 10);

  final PeerTransportContract inner;
  final MessageSealService _sealer;
  SealKeySource? _keys;

  /// Bundle 160: link keys for the signed device id (last pushed set).
  final LinkKeyService _linkKeys = LinkKeyService();
  String _linkKeysPushed = '';

  final Set<String> _capable = <String>{};

  // Bundle 166 (5.2): fresh keys.
  SessionKeyService? _sessions;
  final Set<String> _fresh = <String>{};
  final Map<String, PeerSessionKey> _peerSessions = <String, PeerSessionKey>{};
  final Map<String, DateTime> _resetAt = <String, DateTime>{};
  final Map<String, List<_SentFresh>> _recentFresh = <String, List<_SentFresh>>{};
  final Map<String, DateTime> _probedAt = <String, DateTime>{};
  final Map<String, DateTime> _answeredAt = <String, DateTime>{};
  StreamController<Map<String, dynamic>>? _controller;
  StreamSubscription<Map<String, dynamic>?>? _subscription;

  /// Connects the key source (after the store and keys exist).
  /// [sessions] turns on fresh keys (5.2); without it the lock works as in 156.
  void bind(SealKeySource keys, {SessionKeyService? sessions}) {
    _keys = keys;
    _sessions = sessions;
    unawaited(_loadCapabilities());
    // Bundle 164 (5.7): a block / unblock reaches the link layer at once.
    _blockedSub ??= LocalStore.blockedChanges.listen((_) {
      unawaited(_pushBlocked());
    });
  }

  StreamSubscription<void>? _blockedSub;

  @visibleForTesting
  Set<String> get capablePeers => Set.unmodifiable(_capable);

  bool isSealCapable(String peerId) => _capable.contains(peerId);

  /// Bundle 166: this contact's app takes fresh keys.
  bool isFreshCapable(String peerId) => _fresh.contains(peerId);

  @visibleForTesting
  PeerSessionKey? peerSession(String peerId) => _peerSessions[peerId];

  // ---------------------------------------------------------------- events
  @override
  Stream<Map<String, dynamic>> get events {
    final controller = _controller ??=
        StreamController<Map<String, dynamic>>.broadcast(onListen: _listen);
    return controller.stream;
  }

  void _listen() {
    if (_subscription != null) return;
    _subscription = inner.events.asyncMap(_process).listen((event) {
      if (event != null) _controller?.add(event);
    }, onError: (Object e, StackTrace s) => _controller?.addError(e, s));
  }

  Future<Map<String, dynamic>?> _process(Map<String, dynamic> event) async {
    final type = event['type']?.toString();
    try {
      switch (type) {
        case 'peer_connected':
          final peer = event['peer_id']?.toString() ?? '';
          if (event.containsKey('seal')) {
            _setCapable(peer, event['seal'] == true);
          }
          return event;
        case 'route_recovered':
        case 'route_changed':
          final dest = event['destination_id']?.toString() ?? '';
          if (dest.isNotEmpty) unawaited(probe(dest));
          return event;
        case 'message':
          return await _openMessage(event);
      }
    } catch (error) {
      AppLogger.warning('SEAL_EVENT_FAILED', detail: '$error');
    }
    return event;
  }

  Future<Map<String, dynamic>?> _openMessage(Map<String, dynamic> event) async {
    final raw = event['payload']?.toString();
    if (raw == null || !raw.contains('"sealed')) return event;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return event;
    }
    if (decoded is! Map) return event;
    final outer = Map<String, dynamic>.from(decoded);
    if (!MessageSealService.isSealedType(outer['type']?.toString())) {
      return event;
    }
    final keys = _keys;
    final self = keys?.selfId ?? '';
    final sender = event['sender_id']?.toString() ?? '';
    if (keys == null || self.isEmpty || sender.isEmpty) {
      AppLogger.warning('SEAL_OPEN_FAILED', detail: 'reason=not_ready');
      return null;
    }
    final theirs = await keys.contactPublicKey(sender);
    if (theirs == null) {
      // Not a contact (or blocked): nothing from strangers reaches the app.
      AppLogger.warning('SEAL_OPEN_FAILED', detail: 'reason=not_a_contact');
      return null;
    }
    Map<String, dynamic> inner;
    try {
      inner = await _sealer.open(
        sealed: outer,
        senderId: sender,
        recipientId: self,
        mine: await keys.ownKeys(),
        theirPublic: theirs,
        sessionKey: _sessionLookup,
      );
    } on SealOpenException catch (e) {
      // Bundle 166: the sender used a session key this phone no longer has
      // (deleted, or the app data was cleared). Tell it the current one.
      if (e.reason == 'unknown_session_key') {
        AppLogger.warning('SEAL_OPEN_FAILED', detail: 'reason=unknown_session_key');
        unawaited(_sendReset(sender, outer['pk']?.toString() ?? ''));
        return null;
      }
      // Our key may have just been rotated: reload it once and retry.
      if (e.reason != 'unknown_recipient_key' || keys is! StoreSealKeySource) {
        AppLogger.warning('SEAL_OPEN_FAILED', detail: 'reason=${e.reason}');
        return null;
      }
      keys.forgetOwnKeys();
      try {
        inner = await _sealer.open(
          sealed: outer,
          senderId: sender,
          recipientId: self,
          mine: await keys.ownKeys(),
          theirPublic: theirs,
          sessionKey: _sessionLookup,
        );
      } on SealOpenException catch (e2) {
        AppLogger.warning('SEAL_OPEN_FAILED', detail: 'reason=${e2.reason}');
        return null;
      }
    }
    _setCapable(sender, true);
    // Bundle 166: the sender's current session key rides inside.
    final sp = PeerSessionKey.fromWire(inner.remove(sessionField));
    if (sp != null) _notePeerSession(sender, sp);
    if (inner['type'] == probeType) {
      if (inner['fs'] == 1) _setFresh(sender);
      if (inner['reset'] == true) {
        unawaited(_resendAfterReset(sender, inner['pk']?.toString() ?? ''));
      }
      if (inner['ask'] == true) unawaited(_answerProbe(sender));
      return null;
    }
    // The authenticated sender/recipient replace anything inside.
    inner['sender_id'] = sender;
    inner['recipient_id'] = self;
    for (final key in const ['mesh_packet_id', 'mesh_path']) {
      if (outer.containsKey(key)) inner[key] = outer[key];
    }
    return <String, dynamic>{
      ...event,
      'payload': jsonEncode(inner),
      'sealed': true,
    };
  }

  // ------------------------------------------------------------ capability
  void _setCapable(String peerId, bool capable) {
    if (peerId.isEmpty) return;
    final changed = capable ? _capable.add(peerId) : _capable.remove(peerId);
    if (!changed) return;
    AppLogger.info(
      'SEAL_PEER',
      detail: 'capable=$capable peers=${_capable.length}',
    );
    unawaited(_saveCapabilities());
  }

  Future<void> _loadCapabilities() async {
    try {
      final raw = await _keys?.readSetting(_capsSetting);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is List) _capable.addAll(list.map((e) => e.toString()));
    } catch (_) {}
    await _loadFresh();
  }

  // ------------------------------------------------- fresh keys (166)
  Future<SimpleKeyPair?> _sessionLookup(String id) async =>
      (await _sessions?.byId(id))?.pair;

  void _setFresh(String peerId) {
    if (_sessions == null || peerId.isEmpty || !_fresh.add(peerId)) return;
    AppLogger.info('SEAL_FRESH', detail: 'fresh keys on peers=${_fresh.length}');
    unawaited(_saveFresh());
  }

  void _notePeerSession(String peerId, PeerSessionKey key) {
    if (_sessions == null) return;
    _setFresh(peerId);
    final old = _peerSessions[peerId];
    if (old != null && (old.id == key.id || old.createdAtMs >= key.createdAtMs)) {
      return;
    }
    _peerSessions[peerId] = key;
    unawaited(_saveFresh());
  }

  Future<void> _loadFresh() async {
    if (_sessions == null) return;
    try {
      final raw = await _keys?.readSetting(_freshSetting);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) _fresh.addAll(list.map((e) => e.toString()));
      }
      final rawKeys = await _keys?.readSetting(_peerSessionSetting);
      if (rawKeys != null && rawKeys.isNotEmpty) {
        final map = jsonDecode(rawKeys);
        if (map is Map) {
          for (final entry in map.entries) {
            final key = PeerSessionKey.fromWire(entry.value);
            if (key != null) _peerSessions[entry.key.toString()] = key;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveFresh() async {
    try {
      await _keys?.writeSetting(_freshSetting, jsonEncode(_fresh.toList()));
      await _keys?.writeSetting(_peerSessionSetting, jsonEncode({
        for (final e in _peerSessions.entries) e.key: e.value.toWire(),
      }));
    } catch (_) {}
  }

  /// Tells [peerId] my current session key after its packet used one I no
  /// longer have (at most once a minute per contact).
  Future<void> _sendReset(String peerId, String badSessionId) async {
    if (_sessions == null) return;
    final now = DateTime.now();
    final last = _resetAt[peerId];
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _resetAt[peerId] = now;
    AppLogger.info('SEAL_FRESH', detail: 'reset sent');
    await _sendSealed(peerId, {
      'type': probeType,
      'v': 1,
      'ask': false,
      'fs': 1,
      'reset': true,
      'pk': badSessionId,
    });
  }

  /// The other phone couldn't open what I sent with its old session key:
  /// send the recent ones again with the new key (the app ignores
  /// duplicates by message id).
  Future<void> _resendAfterReset(String peerId, String badSessionId) async {
    final recent = _recentFresh[peerId];
    if (recent == null || badSessionId.isEmpty) return;
    final again = recent.where((r) => r.sessionId == badSessionId).toList();
    recent.removeWhere((r) => r.sessionId == badSessionId);
    if (again.isEmpty) return;
    AppLogger.info('SEAL_FRESH', detail: 'resend after reset count=${again.length}');
    for (final r in again) {
      await send(recipientId: peerId, payload: r.payload);
    }
  }

  void _rememberFresh(String peerId, String sessionId, Map<String, dynamic> payload) {
    if (!MessageSealService.queueableInnerTypes.contains(payload['type']?.toString())) {
      return;
    }
    final now = DateTime.now();
    final list = _recentFresh.putIfAbsent(peerId, () => <_SentFresh>[]);
    list.removeWhere((r) => now.difference(r.at) > const Duration(minutes: 30));
    list.add(_SentFresh(sessionId, Map<String, dynamic>.from(payload), now));
    while (list.length > 30) {
      list.removeAt(0);
    }
  }

  Future<void> _saveCapabilities() async {
    try {
      await _keys?.writeSetting(_capsSetting, jsonEncode(_capable.toList()));
    } catch (_) {}
  }

  /// Asks a contact (once per 10 minutes) whether its app opens sealed
  /// messages. Older apps simply ignore the probe.
  Future<void> probe(String peerId) async {
    final keys = _keys;
    if (keys == null || peerId.isEmpty) return;
    // Bundle 166: also ask a sealing contact once whether it takes fresh keys.
    if (_capable.contains(peerId) && (_sessions == null || _fresh.contains(peerId))) {
      return;
    }
    final last = _probedAt[peerId];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _probeEvery) return;
    _probedAt[peerId] = now;
    await _sendSealed(peerId, {
      'type': probeType,
      'v': 1,
      'ask': true,
      if (_sessions != null) 'fs': 1,
    });
  }

  Future<void> _answerProbe(String peerId) async {
    final now = DateTime.now();
    final last = _answeredAt[peerId];
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _answeredAt[peerId] = now;
    await _sendSealed(peerId, {
      'type': probeType,
      'v': 1,
      'ask': false,
      if (_sessions != null) 'fs': 1,
    });
  }

  Future<bool> _sendSealed(String peerId, Map<String, dynamic> payload) async {
    final sealed = await _trySeal(peerId, payload);
    if (sealed == null) return false;
    try {
      await inner.send(recipientId: peerId, payload: sealed);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _trySeal(
    String peerId,
    Map<String, dynamic> payload,
  ) async {
    final keys = _keys;
    final self = keys?.selfId ?? '';
    if (keys == null || self.isEmpty) return null;
    try {
      final theirs = await keys.contactPublicKey(peerId);
      if (theirs == null) return null;
      final mine = await keys.ownKeys();
      if (mine.isEmpty) return null;
      // Bundle 166 (5.2): fresh keys for a contact whose app takes them.
      final sessions = _sessions;
      final isProbe = payload['type'] == probeType;
      if (sessions != null && (_fresh.contains(peerId) || isProbe)) {
        final me = await sessions.current();
        final body = <String, dynamic>{
          ...payload,
          sessionField: PeerSessionKey(me.id, me.publicKey, me.createdAtMs).toWire(),
        };
        final theirSession = _peerSessions[peerId];
        if (!isProbe &&
            _fresh.contains(peerId) &&
            theirSession != null &&
            SessionKeyPolicy.usable(theirSession.createdAtMs, DateTime.now())) {
          _rememberFresh(peerId, theirSession.id, payload);
          return await _sealer.sealFresh(
            payload: body,
            senderId: self,
            recipientId: peerId,
            mine: mine.first,
            theirPublic: theirs,
            theirSessionId: theirSession.id,
            theirSessionPublic: theirSession.publicKey,
          );
        }
        // No usable session key yet (or too old): the 156 lock this once;
        // the answer brings the contact's current session key.
        return await _sealer.seal(
          payload: body,
          senderId: self,
          recipientId: peerId,
          mine: mine.first,
          theirPublic: theirs,
        );
      }
      return await _sealer.seal(
        payload: payload,
        senderId: self,
        recipientId: peerId,
        mine: mine.first,
        theirPublic: theirs,
      );
    } catch (error) {
      AppLogger.warning('SEAL_FAILED', detail: '$error');
      return null;
    }
  }

  // ------------------------------------------------------------------ send
  @override
  Future<void> send({
    required String recipientId,
    required Map<String, dynamic> payload,
  }) async {
    if (_capable.contains(recipientId) &&
        MessageSealService.shouldSeal(payload['type']?.toString())) {
      final sealed = await _trySeal(recipientId, payload);
      if (sealed != null) {
        return inner.send(recipientId: recipientId, payload: sealed);
      }
    }
    // Bundle 159: a call voice key only ever travels locked. If this
    // message can't be sealed, the key is dropped (the call stays plain).
    if (payload.containsKey(voiceKeyField)) {
      AppLogger.info('CALL_VOICE_KEY_DROPPED', detail: 'reason=not_sealed');
      return inner.send(
        recipientId: recipientId,
        payload: Map<String, dynamic>.from(payload)..remove(voiceKeyField),
      );
    }
    return inner.send(recipientId: recipientId, payload: payload);
  }

  // ------------------------------------------------------- pass-through
  @override
  bool get isStarted => inner.isStarted;

  @override
  Future<void> configure({
    required String deviceId,
    required bool connected,
    required bool groupOwner,
    String? groupOwnerAddress,
    required List<String> knownPeers,
  }) async {
    await inner.configure(
      deviceId: deviceId,
      connected: connected,
      groupOwner: groupOwner,
      groupOwnerAddress: groupOwnerAddress,
      knownPeers: knownPeers,
    );
    unawaited(_pushBlocked());
    unawaited(pushLinkKeys(knownPeers));
  }

  @override
  Future<void> ensureTransportReady({
    required String deviceId,
    List<String> knownPeers = const <String>[],
  }) =>
      inner.ensureTransportReady(deviceId: deviceId, knownPeers: knownPeers);

  @override
  Future<void> updateKnownPeers(List<String> peerIds) async {
    await inner.updateKnownPeers(peerIds);
    unawaited(_pushBlocked());
    unawaited(pushLinkKeys(peerIds));
  }

  /// Bundle 160: signed device id — hands the native side one link key per
  /// contact (and per own key, up to 3). Only when something changed.
  Future<void> pushLinkKeys(List<String> peerIds) async {
    final base = inner;
    final keys = _keys;
    if (base is! WifiDirectTransportService || keys == null) return;
    try {
      final self = keys.selfId;
      if (self == null || self.isEmpty) return;
      final map = await _linkKeys.buildAll(
        selfId: self,
        peerIds: peerIds,
        mine: await keys.ownKeys(),
        publicKeyOf: keys.contactPublicKey,
      );
      final signature = jsonEncode(map);
      if (signature == _linkKeysPushed) return;
      if (!await base.updateLinkKeys(map)) return; // service not up yet
      _linkKeysPushed = signature;
      AppLogger.info('LINK_AUTH', detail: 'keys pushed contacts=${map.length}');
    } catch (error) {
      AppLogger.warning('LINK_AUTH', detail: 'keys push failed error=$error');
    }
  }

  /// Blocked people are never used as relays (native side).
  Future<void> _pushBlocked() async {
    final base = inner;
    final keys = _keys;
    if (base is! WifiDirectTransportService || keys == null) return;
    try {
      await base.updateBlockedPeers((await keys.blockedPeerIds()).toList());
    } catch (_) {}
  }

  @override
  Future<void> sendPairPayload({
    required String nodeId,
    required String kind,
    required String body,
  }) =>
      inner.sendPairPayload(nodeId: nodeId, kind: kind, body: body);

  @override
  Future<Map<String, dynamic>> topology() => inner.topology();

  @override
  Future<void> flushQueue() => inner.flushQueue();

  @override
  Future<void> resume() => inner.resume();

  @override
  Future<void> clearStorage() => inner.clearStorage();

  @override
  Future<void> broadcast(Map<String, dynamic> payload) =>
      inner.broadcast(payload);

  @override
  Future<void> sendFile({
    required String recipientId,
    required String filePath,
    required String fileId,
    required String messageId,
    required String fileName,
    required String contentType,
  }) =>
      inner.sendFile(
        recipientId: recipientId,
        filePath: filePath,
        fileId: fileId,
        messageId: messageId,
        fileName: fileName,
        contentType: contentType,
      );

  @override
  Future<void> cancelFile(String fileId) => inner.cancelFile(fileId);

  @override
  Future<void> stop() => inner.stop();

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _blockedSub?.cancel();
    _blockedSub = null;
    await inner.dispose();
  }
}

/// Bundle 166: a message recently sent with a contact's session key, kept
/// for 30 minutes in memory in case that key turns out to be gone.
class _SentFresh {
  _SentFresh(this.sessionId, this.payload, this.at);
  final String sessionId;
  final Map<String, dynamic> payload;
  final DateTime at;
}
