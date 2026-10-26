import 'dart:async';
import 'dart:convert';

import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';

/// Bundle 108 — verified pairing request pulled from the local network.
///
/// The payload travelling over the LAN is exactly the signed QR identity
/// bundle (the same bytes My QR shows the camera), so both transports land
/// in the identical crypto check and disk import path. Pairing works fully
/// offline: no server, no QR camera, no device ids typed by users.
class PairRequest {
  final DirectoryProfile profile;

  /// Raw {v, profile, signature} map, kept verbatim for importQrProfile().
  final Map<String, dynamic> raw;

  /// Transport node id (= device id) that sent the packet.
  final String nodeId;

  const PairRequest({
    required this.profile,
    required this.raw,
    required this.nodeId,
  });

  String get displayName =>
      profile.displayName.isNotEmpty ? profile.displayName : 'LocalLink user';
  String get username => profile.username;
}

final class PairingService {
  PairingService({
    required LocalStore store,
    required IdentityCryptoService crypto,
    required DirectoryRepositoryContract directory,
    required PeerTransportContract transport,
  })  : _store = store,
        _crypto = crypto,
        _directory = directory,
        _transport = transport;

  /// One request / decline silences that phone for this long.
  static const _muteWindow = Duration(minutes: 10);

  final LocalStore _store;
  final IdentityCryptoService _crypto;
  final DirectoryRepositoryContract _directory;
  final PeerTransportContract _transport;

  final _requests = StreamController<PairRequest>.broadcast();

  /// Fired with the peer's display name after a mutual pair completes.
  final _paired = StreamController<String>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _events;
  final Map<String, DateTime> _mutedUntil = <String, DateTime>{};
  bool _started = false;

  Stream<PairRequest> get requests => _requests.stream;
  Stream<String> get paired => _paired.stream;

  void start() {
    if (_started) return;
    _started = true;
    _events = _transport.events.listen(_handleTransportEvent);
  }

  Future<void> dispose() async {
    _started = false;
    await _events?.cancel();
    _events = null;
    await _requests.close();
    await _paired.close();
  }

  // ---------------------------------------------------------------- OUTGOING

  /// Ask the locally visible peer [nodeId] to pair. Throws when the peer
  /// is not currently visible on the local network (native error).
  Future<void> requestPair(String nodeId) async {
    final body = await _payload();
    await _transport.sendPairPayload(
        nodeId: nodeId, kind: 'request', body: body);
  }

  /// Accept an incoming verified request: import the peer, add the contact,
  /// push the fresh roster so native sessions open, then answer with our
  /// own signed identity so the OTHER phone pairs us back automatically.
  Future<void> accept(PairRequest request, {String customName = ''}) async {
    await _adopt(request.raw, request.profile, request.nodeId,
        customName: customName);
    final body = await _payload();
    try {
      await _transport.sendPairPayload(
          nodeId: request.nodeId, kind: 'accept', body: body);
    } catch (_) {
      // Best effort: the requester can re-ask; the roster is already right
      // on this side and their next request auto-answers (trusted fast path).
    }
  }

  /// Decline: the requester stays muted for [_muteWindow] (set when the
  /// request was first surfaced).
  void decline(PairRequest request) {
    _mutedUntil[request.nodeId] = DateTime.now().add(_muteWindow);
  }

  // ---------------------------------------------------------------- INCOMING

  Future<void> _handleTransportEvent(Map<String, dynamic> event) async {
    if (event['type']?.toString() != 'pair_packet') return;
    final kind = event['pair']?.toString() ?? '';
    final nodeId = event['node_id']?.toString().trim() ?? '';
    final body = event['body']?.toString() ?? '';
    if (nodeId.isEmpty || body.isEmpty) return;
    if (!{'request', 'accept'}.contains(kind)) return;

    final mutedAt = _mutedUntil[nodeId];
    final isMuted = mutedAt != null && DateTime.now().isBefore(mutedAt);

    try {
      final parsed = await _verify(body, nodeId);
      if (parsed == null) return; // signature/device-id mismatch: drop silent
      final (raw, profile) = parsed;

      if (await _isTrusted(profile.deviceId)) {
        // Already friends: answers are free — no dialog, no toasts, keep the
        // request-idempotent so pairing survives app restarts on one side.
        if (kind == 'request' && !isMuted) {
          _mutedUntil[nodeId] = DateTime.now().add(_muteWindow);
          final answer = await _payload();
          try {
            await _transport.sendPairPayload(
                nodeId: nodeId, kind: 'accept', body: answer);
          } catch (_) {}
        }
        return;
      }

      if (isMuted) return;

      if (kind == 'request') {
        _mutedUntil[nodeId] = DateTime.now().add(_muteWindow);
        if (!_requests.isClosed) {
          _requests.add(PairRequest(profile: profile, raw: raw, nodeId: nodeId));
        }
      } else {
        // Mutual accept for a request we sent: pair without another dialog.
        _mutedUntil[nodeId] = DateTime.now().add(_muteWindow);
        await _adopt(raw, profile, nodeId);
      }
    } catch (error) {
      AppLogger.warning('PAIR_PACKET_REJECTED',
          detail: 'node=$nodeId error=$error');
    }
  }

  /// Import + contact + roster push + completion signal. Shared by the
  /// accept-in-dialog path and the incoming-'accept' path.
  Future<void> _adopt(Map<String, dynamic> raw, DirectoryProfile profile,
      String nodeId,
      {String customName = ''}) async {
    await _directory.importQrProfile(raw);
    await _directory.addContact(profile.userId, customName: customName);
    await _pushRoster();
    if (!_paired.isClosed) _paired.add(profile.displayName);
  }

  Future<void> _pushRoster() async {
    final devices = await _store.localDevices();
    final ids = devices
        .where((device) => device.revokedAt.isEmpty)
        .map((device) => device.id)
        .toList();
    await _transport.updateKnownPeers(ids);
  }

  Future<bool> _isTrusted(String deviceId) async {
    if (deviceId.isEmpty) return false;
    final devices = await _store.localDevices();
    return devices.any(
        (device) => device.id == deviceId && device.revokedAt.isEmpty);
  }

  // ---------------------------------------------------------------- IDENTITY

  /// Byte-identical to MyQrScreen._payload(): a v1 signed identity bundle.
  Future<String> _payload() async {
    final profile = await _store.profile();
    if (profile == null) {
      throw StateError('Finish setting up your profile before pairing');
    }
    final deviceId = _store.deviceId ?? '';
    if (deviceId.isEmpty) {
      throw StateError('Device identity is not ready yet');
    }
    final signingPublicKey = await _crypto.signingPublicKey();
    final identityPublicKey = await _crypto.publicKey();
    final unsigned = _directoryProfile(profile, deviceId).copyWith(
      deviceId: deviceId,
      phoneNumber: '',
      avatarUrl: '',
      signingPublicKey: signingPublicKey,
      identityPublicKey: identityPublicKey,
      signature: '',
      source: 'qr',
      syncedAt: '',
    );
    final signature =
        await _crypto.signDirectoryProfile(unsigned.canonical());
    return jsonEncode(<String, dynamic>{
      'v': 1,
      'profile': unsigned.toMap(),
      'signature': signature,
    });
  }

  DirectoryProfile _directoryProfile(LocalProfile value, String deviceId) =>
      DirectoryProfile(
        userId: value.userId,
        deviceId: deviceId,
        username: value.username,
        displayName: value.displayName,
        profileVersion: value.profileVersion,
        updatedAt: value.updatedAt,
        phoneVisibility: value.phoneVisibility,
        discoverableByPhone: value.discoverableByPhone,
        discoverableByName: value.discoverableByName,
        directorySyncEnabled: value.directorySyncEnabled,
        source: 'pairing',
      );

  /// Same verification contract as the QR scanner: v1 envelope, parseable
  /// signed profile, valid signature — PLUS the sender's transport node id
  /// must equal the profile's device id (no mix-and-match replays).
  Future<(Map<String, dynamic>, DirectoryProfile)?> _verify(
      String body, String nodeId) async {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['v']?.toString() != '1') return null;
    final payload = Map<String, dynamic>.from(decoded);
    final profileMap = payload['profile'];
    final signature = payload['signature']?.toString() ?? '';
    if (profileMap is! Map || signature.isEmpty) return null;
    final profile = DirectoryProfile.fromMap(
      Map<String, dynamic>.from(profileMap),
    ).copyWith(
      signature: signature,
      source: 'qr',
      syncedAt: DateTime.now().toUtc().toIso8601String(),
    );
    if (profile.deviceId != nodeId) return null;
    if (!profile.isSigned) return null;
    final ok = await _crypto.verifyDirectoryProfile(
      canonicalPayload: profile.canonical(),
      signature: profile.signature,
      signingPublicKey: profile.signingPublicKey,
    );
    if (!ok) return null;
    return (payload, profile);
  }
}
