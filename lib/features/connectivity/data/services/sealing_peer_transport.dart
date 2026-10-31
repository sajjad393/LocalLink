import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/message_seal_service.dart';
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
  static const Duration _probeEvery = Duration(minutes: 10);

  final PeerTransportContract inner;
  final MessageSealService _sealer;
  SealKeySource? _keys;

  final Set<String> _capable = <String>{};
  final Map<String, DateTime> _probedAt = <String, DateTime>{};
  final Map<String, DateTime> _answeredAt = <String, DateTime>{};
  StreamController<Map<String, dynamic>>? _controller;
  StreamSubscription<Map<String, dynamic>?>? _subscription;

  /// Connects the key source (after the store and keys exist).
  void bind(SealKeySource keys) {
    _keys = keys;
    unawaited(_loadCapabilities());
  }

  @visibleForTesting
  Set<String> get capablePeers => Set.unmodifiable(_capable);

  bool isSealCapable(String peerId) => _capable.contains(peerId);

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
      );
    } on SealOpenException catch (e) {
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
        );
      } on SealOpenException catch (e2) {
        AppLogger.warning('SEAL_OPEN_FAILED', detail: 'reason=${e2.reason}');
        return null;
      }
    }
    _setCapable(sender, true);
    if (inner['type'] == probeType) {
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
    if (keys == null || peerId.isEmpty || _capable.contains(peerId)) return;
    final last = _probedAt[peerId];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _probeEvery) return;
    _probedAt[peerId] = now;
    await _sendSealed(peerId, {'type': probeType, 'v': 1, 'ask': true});
  }

  Future<void> _answerProbe(String peerId) async {
    final now = DateTime.now();
    final last = _answeredAt[peerId];
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _answeredAt[peerId] = now;
    await _sendSealed(peerId, {'type': probeType, 'v': 1, 'ask': false});
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
    await inner.dispose();
  }
}
