import 'dart:async';
import 'dart:convert';

import 'package:locallink/core/models/device.dart';
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

  /// Bundle 126: "nodeId|kind" entries currently being processed. The LAN
  /// transport burst-delivers each packet (typically three copies in the
  /// same tick); the mute check used to run only AFTER awaiting _verify, so
  /// every copy raced through — the receiver stacked phantom "wants to
  /// connect" dialogs (Connect closed one and the next rose instantly,
  /// looking like the dialog refused to dismiss) and the sender adopted the
  /// same peer three times. Added/removed around the processing below.
  final Set<String> _inflightPairs = <String>{};

  Stream<PairRequest> get requests => _requests.stream;
  Stream<String> get paired => _paired.stream;

  /// Bundle 112: human-readable diagnostics (toasts). Pairing used to fail
  /// completely silently, which made field debugging impossible.
  Stream<String> get diagnostics => _diagnostics.stream;

  final _diagnostics = StreamController<String>.broadcast();

  void _diag(String message) {
    AppLogger.info('PAIR_DIAG', detail: message);
    if (!_diagnostics.isClosed) _diagnostics.add(message);
  }

  void start() {
    if (_started) return;
    _started = true;
    AppLogger.warning('PAIR_STAGE', detail: 'pairing service started');
    _events = _transport.events.listen(_handleTransportEvent);
    // Bundle 113: the receiver side must already have identity+sockets when a
    // packet lands; configure lazily here (idempotent, safe, never restarts
    // existing links).
    unawaited(_ensureTransportReady());
  }

  /// Bundle 113: pairing can be the FIRST transport user on phones that went
  /// through the local-only boot or lost the service to an OEM task killer —
  /// in either case sendPairPayload returned 'transport is not running' /
  /// 'not configured'. Make the transport ready on demand instead of relying
  /// on cold-start ordering.
  Future<void> _ensureTransportReady() async {
    final deviceId = _store.deviceId ?? '';
    AppLogger.warning('PAIR_STAGE', detail: 'ensureTransportReady deviceId=${deviceId.isEmpty ? '<empty>' : deviceId.substring(0, deviceId.length > 12 ? 12 : deviceId.length)}…');
    if (deviceId.isEmpty) return; // nothing to identify with yet
    final devices = await _store.localDevices();
    final ids = devices
        .where((device) => device.revokedAt.isEmpty)
        .map((device) => device.id)
        .toList();
    try {
      await _transport.ensureTransportReady(deviceId: deviceId, knownPeers: ids);
    } catch (error) {
      AppLogger.warning('PAIR_TRANSPORT_READY_FAILED', detail: '$error');
    }
  }

  Future<void> dispose() async {
    _started = false;
    await _events?.cancel();
    _events = null;
    await _requests.close();
    await _paired.close();
    await _diagnostics.close();
  }

  // ---------------------------------------------------------------- OUTGOING

  /// Ask the locally visible peer [nodeId] to pair. Throws when the peer
  /// is not currently visible on the local network (native error).
  Future<void> requestPair(String nodeId) async {
    AppLogger.warning('PAIR_STAGE', detail: 'requestPair entered node=$nodeId');
    final body = await _payload();
    AppLogger.warning('PAIR_STAGE', detail: 'payload built');
    await _ensureTransportReady();
    AppLogger.warning('PAIR_STAGE', detail: 'transport ensured, sending');
    try {
      await _transport.sendPairPayload(
          nodeId: nodeId, kind: 'request', body: body);
      AppLogger.warning('PAIR_STAGE', detail: 'native send returned OK');
      _diag('Pair request sent to native transport.');
    } catch (first) {
      AppLogger.warning('PAIR_SEND_THROW', detail: '$first');
      // Bundle 113: one silent self-heal retry — the ensure call may have had
      // to (re)start the native service; endpoint tables resolve next tap.
      await _ensureTransportReady();
      await _transport.sendPairPayload(
          nodeId: nodeId, kind: 'request', body: body);
    }
  }

  /// Accept an incoming verified request: import the peer, add the contact,
  /// push the fresh roster so native sessions open, then answer with our
  /// own signed identity so the OTHER phone pairs us back automatically.
  Future<void> accept(PairRequest request, {String customName = ''}) async {
    // Bundle 117: the accept packet goes out FIRST so the requester's UI
    // unblocks immediately; local adoption (import, contact write, roster
    // push — including its server mirror) runs after, best effort.
    AppLogger.warning('PAIR_ACCEPT',
        detail: 'stage=entered node=${request.nodeId} from=${request.displayName}');
    await _ensureTransportReady();
    AppLogger.warning('PAIR_ACCEPT', detail: 'stage=transport_ready');
    var answerSent = false;
    Object? sendError;
    try {
      final body = await _payload();
      AppLogger.warning('PAIR_ACCEPT', detail: 'stage=payload_built');
      await _transport.sendPairPayload(
          nodeId: request.nodeId, kind: 'accept', body: body);
      answerSent = true;
      AppLogger.warning('PAIR_ACCEPT', detail: 'stage=accept_packet_sent');
    } catch (error) {
      sendError = error;
      // Best effort: the requester can re-ask; the roster is already right
      // on this side and their next request auto-answers (trusted fast path).
      AppLogger.warning('PAIR_ACCEPT_SEND_FAILED', detail: '$error');
    }
    AppLogger.warning('PAIR_ACCEPT', detail: 'stage=adopting');
    try {
      await _adopt(request.raw, request.profile, request.nodeId,
          customName: customName, signalPaired: false);
    } catch (error) {
      // Bundle 122: adoption failures used to escape unlabeled (stage=done
      // never printed, and the UI showed a generic snackbar). Name the stage
      // and carry the real cause to the caller.
      AppLogger.warning('PAIR_ACCEPT',
          detail: 'stage=adopt_failed error=$error');
      rethrow;
    }
    AppLogger.warning('PAIR_ACCEPT', detail: 'stage=done');
    // Bundle 122: honest completion — only claim "connected" when our accept
    // packet actually left the device AND the peer was adopted. When the
    // answer failed (e.g. local profile not set up yet), adoption has still
    // run so the peer is trusted: their next retry will auto-answer silently.
    // Surface the real reason instead of faking success.
    if (answerSent) {
      if (!_paired.isClosed) _paired.add(request.profile.displayName);
    } else {
      throw sendError ??
          StateError(
              'Pair answer was not sent — check the connection and ask them to pair again.');
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
    _diag('Pair packet received from …${nodeId.length > 6 ? nodeId.substring(nodeId.length - 6) : nodeId} ($kind)');
    final body = event['body']?.toString() ?? '';
    if (nodeId.isEmpty || body.isEmpty) {
      _diag('Pair packet dropped: empty fields');
      return;
    }
    if (!{'request', 'accept'}.contains(kind)) {
      _diag('Pair packet dropped: unknown kind $kind');
      return;
    }

    // Bundle 126: drop burst duplicates synchronously, before the first
    // await. A copy that arrives while its sibling is still being verified
    // returns here; one arriving after processing completes is caught by
    // the mute window (request) or the trusted fast path (accept) below.
    final inflightKey = '$nodeId|$kind';
    if (!_inflightPairs.add(inflightKey)) {
      return;
    }

    final mutedAt = _mutedUntil[nodeId];
    final isMuted = mutedAt != null && DateTime.now().isBefore(mutedAt);

    try {
      final parsed = await _verify(body, nodeId);
      if (parsed == null) {
        _diag('Pair packet rejected: identity or signature did not check out.');
        return;
      }
      final (raw, profile) = parsed;

      if (await _isTrusted(profile.deviceId)) {
        // Already friends: answers are free — no dialog, no toasts, keep the
        // request-idempotent so pairing survives app restarts on one side.
        if (kind == 'request' && !isMuted) {
          _mutedUntil[nodeId] = DateTime.now().add(_muteWindow);
          try {
            final answer = await _payload();
            await _transport.sendPairPayload(
                nodeId: nodeId, kind: 'accept', body: answer);
          } catch (error) {
            // Bundle 122: _payload() used to sit ABOVE the try, so a missing
            // local profile here escaped as a mislabeled PAIR_PACKET_REJECTED.
            AppLogger.warning('PAIR_TRUSTED_ANSWER_FAILED', detail: '$error');
          }
        }
        return;
      }

      if (isMuted) {
        _diag('Pair request from …${nodeId.substring(nodeId.length - 6)} muted (already handled recently)');
        return;
      }

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
      _diag('Pair packet failed: $error');
      AppLogger.warning('PAIR_PACKET_REJECTED',
          detail: 'node=$nodeId error=$error');
    } finally {
      _inflightPairs.remove(inflightKey);
    }
  }

  /// Import + contact + roster push + completion signal. Shared by the
  /// accept-in-dialog path and the incoming-'accept' path.
  Future<void> _adopt(Map<String, dynamic> raw, DirectoryProfile profile,
      String nodeId,
      {String customName = '', bool signalPaired = true}) async {
    // Bundle 117: stage logs — if adoption ever stalls (server mirror with no
    // internet, encrypted store contention) the log names the exact step.
    await _directory.importQrProfile(raw);
    AppLogger.warning('PAIR_ACCEPT', detail: 'stage=adopt_import_done');
    await _directory.addContact(profile.userId, customName: customName);
    AppLogger.warning('PAIR_ACCEPT', detail: 'stage=adopt_contact_saved');
    // Bundle 125: register the peer's device in known_devices. _isTrusted
    // reads that table — without this row the trusted fast path was
    // structurally unreachable: the peer's later pair retries fell off the
    // mute window and re-opened the Accept dialog forever ("Connected"
    // toast but popup never stays dismissed), and the roster push below
    // silently omitted the peer. Presence flags are painted by the normal
    // discovery feeds afterwards; defaults are fine here.
    await _store.saveDevice(Device(
      id: profile.deviceId,
      name: profile.displayName,
      platform: 'android',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      lastSeenAt: DateTime.now().toUtc().toIso8601String(),
    ));
    AppLogger.warning('PAIR_ACCEPT', detail: 'stage=adopt_device_registered');
    await _pushRoster();
    AppLogger.warning('PAIR_ACCEPT', detail: 'stage=adopt_roster_pushed');
    // signalPaired=false is used by accept(): the dialog path only announces
    // completion after the accept packet has actually been sent (Bundle 122).
    if (signalPaired && !_paired.isClosed) _paired.add(profile.displayName);
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

  /// Bundle 125: node ids this phone already trusts (paired peers). Nearby
  /// uses it to stop offering "Pair" for phones that are already paired —
  /// the button used to re-appear because nothing marked the peer known.
  Future<Set<String>> trustedNodeIds() async {
    final devices = await _store.localDevices();
    return devices
        .where((device) => device.revokedAt.isEmpty)
        .map((device) => device.id)
        .toSet();
  }

  // ---------------------------------------------------------------- IDENTITY

  /// Byte-identical to MyQrScreen._payload(): a v1 signed identity bundle.
  Future<String> _payload() async {
    final deviceId = _store.deviceId ?? '';
    if (deviceId.isEmpty) {
      throw StateError('Device identity is not ready yet');
    }
    // Bundle 114: offline-created accounts can reach pairing before any
    // crypto init ran; init() is idempotent (reads-or-generates seed), so
    // make payload building fully self-healing instead of dying on an
    // uninitialized key store.
    await _crypto.init(deviceId);
    final profile = await _store.profile();
    if (profile == null) {
      throw StateError('Finish setting up your profile before pairing');
    }
    String signingPublicKey;
    String identityPublicKey;
    try {
      signingPublicKey = await _crypto.signingPublicKey();
      identityPublicKey = await _crypto.publicKey();
    } catch (error) {
      AppLogger.warning('PAIR_KEYS_FAILED', detail: '$error');
      throw Exception(
          'Identity keys are not ready on this phone — restart the app once and try again.');
    }
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
    String signature;
    try {
      signature = await _crypto.signDirectoryProfile(unsigned.canonical());
    } catch (error) {
      AppLogger.warning('PAIR_SIGN_FAILED', detail: '$error');
      throw Exception('Could not sign your identity for pairing.');
    }
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
