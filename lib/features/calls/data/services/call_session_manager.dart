import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/call_quality.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/models/call_notification_action.dart';
import 'package:locallink/features/calls/data/platform/call_handover_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_failure_reason.dart';
import 'package:locallink/features/calls/data/services/call_notification_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_ringtone_service.dart';
import 'package:locallink/features/calls/data/services/call_stale_guard.dart';
import 'package:locallink/features/calls/data/repositories/call_repository.dart';
import 'package:locallink/features/calls/domain/call_repository_contract.dart';
import 'package:locallink/features/calls/data/transport/call_transport.dart';
import 'package:locallink/features/calls/data/transport/call_transport_factory.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/calls/data/transport/call_transport_selection_policy.dart';
import 'package:locallink/features/calls/data/services/call_preflight_exception.dart';
import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/features/calls/domain/call_gateway.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/calls/data/services/call_answer_timer.dart';
import 'package:locallink/features/calls/data/services/call_nearby_wait.dart';
import 'package:locallink/features/calls/data/services/call_voice_key_266.dart';
import 'package:locallink/core/identity/person_name_258.dart';

final class CallSessionManager implements CallGateway {
  final LocalStore store;
  final PeerTransportContract directTransport;
  final CallRepositoryContract repository;
  final CallAudioPlatformService audioPlatform;
  final CallRingtoneService ringtone;
  final CallNotificationPlatformService notificationPlatform;
  final CallMediaPlatformService mediaPlatform;
  final IdentityTrustService identityTrust;
  final LocalRoutePolicyService routePolicy;

  final _sessionController = StreamController<CallSession?>.broadcast();
  final _historyController = StreamController<List<CallRecord>>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _nativeSub;
  StreamSubscription<CallNotificationAction>? _notificationActionSub;
  StreamSubscription<LocalRouteResult>? _routeSub;
  Timer? _ringTimer;

  // Bundle 295 (A): ghost ring. The caller repeats its invite every 5 s
  // while it calls (also after "Ringing…"); the called phone stops ringing
  // when no repeat came for 12 s (the cancel could not arrive) -> Missed.
  // Only for an invite that says it repeats (an older caller does not).
  static const String ringAliveField295 = 'ring_alive_295';
  static const String ringAliveRepeatField295 = 'ring_alive_repeat_295';
  static Duration ringAliveEvery295 = const Duration(seconds: 5);
  static Duration ringAliveLimit295 = const Duration(seconds: 12);
  Timer? _ringAliveWatch295;
  Timer? _ringAliveSend295;
  Map<String, dynamic>? _lastInvite295;

  // Bundle 295 (G1): the call answer is the proof. No answer 6 s after an
  // invite went out on a stored way -> that way is dropped (native), the
  // friend is grey at once and the call becomes an away call ("Waiting for
  // <name> to connect…", Nearby search, 60 s).
  static Duration proofWait295 = const Duration(seconds: 6);
  Timer? _proofTimer295;
  String? _proofArmedFor295;
  final Set<String> _unproven295 = <String>{};

  /// Bundle 295 (G1): drops the stored way to the friend and greys them.
  /// True = dropped (a direct link is kept and counts as proof).
  Future<bool> Function(String peerId)? routeUnproven295;

  @visibleForTesting
  bool unprovenForTest(String callId) => _unproven295.contains(callId);
  Timer? _statsTimer;
  Timer? _heartbeatTimer;
  Timer? _meshRouteRecoveryTimer;
  Timer? _routeWaitTimer;
  Timer? _connectWatchdogTimer;
  CallSession? _session;
  CallTransport? _transport;
  late final CallTransportFactory transportFactory;
  /// Live invite arrivals replayed by the mesh store/forward layer are
  /// suppressed here. Clock skew between phones used to kill every invite —
  /// see the clamp below.
  final Set<String> _seenInviteIds = <String>{};
  int _seenInviteCursor = 0;
  // Bundle 172: calls known to be over — a late invite for one never rings.
  final EndedCallMemory _endedCalls = EndedCallMemory();
  // Bundle 172: one "that call is over" reply per call every 10 s at most.
  final Map<String, DateTime> _callOverRepliedAt = <String, DateTime>{};
  bool _disposed = false;
  final WebSocketService? socket;
  StreamSubscription<dynamic>? _socketSub;
  // Dedupes lifecycle signals that can legitimately arrive twice at the same
  // instant: once over Wi-Fi Direct, once relayed through the server WS
  // fallback. Keyed by type|call_id|sender. call_invite is excluded on
  // purpose: the 5s route-wait resend loop legitimately repeats identical
  // invites, and _seenInviteIds guards duplicates for those.
  final Map<String, DateTime> _recentSignalFingerprints =
      <String, DateTime>{};
  bool _inviteInFlight = false;
  DateTime? _lastInviteAttemptAt;
  int _recoveryAttempts = 0;
  int _meshRouteRecoveryAttempts = 0;
  // Media-flow truth, fed by _collectStats()' packets_received deltas. Mesh
  // route churn events (degraded/invalidated) are hyper-eager — they fire
  // dozens of times during a perfectly audible call — so a live-media
  // window suppresses their user-facing 'reconnecting' flips. 7s covers
  // the 5s stats tick plus slack.
  int _lastMediaPacketsReceived = -1;
  CallQualitySample? _lastQualitySample;
  DateTime? _lastMediaRxAt;
  bool get _mediaIsLive {
    final at = _lastMediaRxAt;
    return at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 7);
  }

  // Bundle 52: hot route-churn events no longer print one line each —
  // ROUTE_CHURN_SUPPRESSED fired at media-tick cadence (~dozens/sec) and
  // was itself re-freezing weak handsets even after the 51 sampler.
  // Same 10s fold-in pattern as the reliable-messaging sampler.
  Timer? _routeChurnSummaryTimer;
  final Map<String, int> _routeChurnPending = <String, int>{};

  void _recordRouteChurn(String type) {
    _routeChurnPending[type] = (_routeChurnPending[type] ?? 0) + 1;
    _routeChurnSummaryTimer ??=
        Timer.periodic(const Duration(seconds: 10), (_) {
      if (_routeChurnPending.isEmpty || _disposed) return;
      final parts = _routeChurnPending.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(' ');
      _routeChurnPending.clear();
      AppLogger.info('ROUTE_CHURN_SUMMARY',
          detail: 'window=10s call=${_session?.id ?? '-'} $parts');
    });
  }

  // Bundle 52A - offline lifecycle hardening. Accept/end/reject/busy are
  // single-shot signals: if the direct link flakes exactly at send time
  // and the server is unreachable too, the other phone holds a ghost call.
  // Queue them for 20s of 5s retries; any inbound frame for the same call
  // corroborates state and retires the entry early. Every inbound handler
  // is idempotent (fingerprint dedupe + state guards), so re-delivery is
  // safe.
  static const Set<String> _lifecycleRetryTypes = <String>{
    'call_accept',
    'call_end',
    'call_reject',
    'call_busy',
  };
  final Map<String, Map<String, dynamic>> _pendingLifecycleSignals =
      <String, Map<String, dynamic>>{};
  final Map<String, DateTime> _lifecycleQueuedAt = <String, DateTime>{};
  final Map<String, DateTime> _lifecycleInboundRxAt = <String, DateTime>{};
  Timer? _lifecycleRetryTimer;

  void _enqueueLifecycleRetry(Map<String, dynamic> msg) {
    final type = msg['type']?.toString() ?? '';
    final callId = msg['call_id']?.toString() ?? '';
    if (!_lifecycleRetryTypes.contains(type) || callId.isEmpty) return;
    final key = '$type|$callId';
    if (_pendingLifecycleSignals.containsKey(key)) return;
    _pendingLifecycleSignals[key] = Map<String, dynamic>.from(msg);
    _lifecycleQueuedAt[key] = DateTime.now();
    _lifecycleRetryTimer ??= Timer.periodic(const Duration(seconds: 5),
        (_) => _retryLifecycleSignals());
    AppLogger.info('CALL_LIFECYCLE_QUEUED', detail: 'type=$type call=$callId');
  }

  void _noteLifecycleInbound(Map<String, dynamic> msg) {
    final callId = msg['call_id']?.toString();
    if (callId == null || callId.isEmpty) return;
    _lifecycleInboundRxAt[callId] = DateTime.now();
  }

  void _retryLifecycleSignals() {
    if (_disposed) return;
    if (_pendingLifecycleSignals.isEmpty) {
      _lifecycleRetryTimer?.cancel();
      _lifecycleRetryTimer = null;
      return;
    }
    for (final entry in _pendingLifecycleSignals.entries.toList()) {
      final key = entry.key;
      final queuedAt = _lifecycleQueuedAt[key] ?? DateTime.now();
      final callId = entry.value['call_id']?.toString() ?? '';
      final inbound = _lifecycleInboundRxAt[callId];
      // Bundle 146: an answered call whose audio is arriving proves the
      // accept landed; stop resending it (logs showed 20 s of resends).
      final mediaProves = key.startsWith('call_accept|') &&
          _session?.id == callId &&
          _mediaIsLive;
      final settled =
          (inbound != null && inbound.isAfter(queuedAt)) || mediaProves;
      final expired =
          DateTime.now().difference(queuedAt) > const Duration(seconds: 20);
      if (settled || expired) {
        _pendingLifecycleSignals.remove(key);
        _lifecycleQueuedAt.remove(key);
        if (expired && !settled) {
          AppLogger.info('CALL_LIFECYCLE_RETRY_EXPIRED', detail: 'key=$key');
        }
        continue;
      }
      unawaited(_sendSignal(Map<String, dynamic>.from(entry.value)));
    }
  }
  int _presentationRevision = 0;
  bool _appInForeground = true;

  Stream<CallSession?> get sessionStream => _sessionController.stream;
  Stream<List<CallRecord>> get historyStream => _historyController.stream;
  CallSession? get session => _session;
  String? get selfDeviceId => store.deviceId;
  CallTransport? get activeTransport => _transport;

  CallSessionManager(
    this.store,
    this.directTransport, {
    this.socket,
    required this.repository,
    required this.audioPlatform,
    required this.ringtone,
    required this.notificationPlatform,
    required this.mediaPlatform,
    IdentityTrustService? identityTrust,
    LocalRoutePolicyService? routePolicy,
    this.handover,
  })  : identityTrust = identityTrust ?? const IdentityTrustService(),
        routePolicy = routePolicy ?? LocalRoutePolicyService(directTransport) {
    transportFactory = CallTransportFactory(
      mesh: directTransport,
      media: mediaPlatform,
      audio: audioPlatform,
    );
    transportFactory.nativeMesh.voiceKeyFor = (callId) => _voiceKeys[callId];
  }

  /// Bundle 176 (3): ringing-call hand-over between app engines (null = off).
  final CallHandoverPlatformService? handover;

  // Bundle 159: per-call voice keys (callId -> base64 key). Memory only,
  // never saved or logged. A key is used only when BOTH phones agreed
  // (sealed invite carried it, the accept said voice_lock).
  final Map<String, String> _voiceKeys = <String, String>{};

  @visibleForTesting
  String? voiceKeyForTest(String callId) => _voiceKeys[callId];

  /// The caller's key for this call, only if the invite can travel locked.
  String? _voiceKeyForInvite(CallSession session) {
    final existing = _voiceKeys[session.id];
    if (existing != null) return existing;
    final transport = directTransport;
    if (transport is! SealingPeerTransport ||
        !transport.isSealCapable(session.peerId)) {
      return null;
    }
    final key = CallVoiceKey.generate();
    _voiceKeys[session.id] = key;
    return key;
  }

  // ------------------------------------------------ Bundle 266
  // A: calls ring through the server too. B: they talk through the server
  // when there is no nearby way (locked end to end). D: the friend who calls
  // through the server wakes Nearby for us.

  /// Calls the server knows (their invite went or came through it).
  final Set<String> _serverKnown = <String>{};

  /// Calls whose invite already went through the server (once per call).
  final Set<String> _serverInviteSent = <String>{};

  /// `type|call` already copied to the server (one copy, not per retry).
  final Set<String> _serverCopied = <String>{};

  /// B1: call keys worked out from the pair link key (memory only).
  final Map<String, String> _derivedKeys = <String, String>{};

  /// B: the call that talks through the server when needed (null = none).
  String? _serverVoiceCallId;
  final Set<String> _serverVoiceStopped = <String>{};
  StreamSubscription<Map<String, dynamic>>? _voiceOutSub;
  DateTime? _serverVoiceRxAt;
  int _serverVoiceTx = 0;
  int _serverVoiceRx = 0;
  final List<String> _voiceInBatch = <String>[];
  String _voiceInCall = '';
  String _voiceInSender = '';
  Timer? _voiceInTimer;

  /// D: the 60 s limit of the Nearby wake for a server call.
  Timer? _wakeTimer;
  static const Duration wakeLimit266 = Duration(seconds: 60);

  static const Set<String> _serverCopyTypes = <String>{
    'call_invite_ack',
    'call_accept',
    'call_reject',
    'call_busy',
    'call_end',
  };

  @visibleForTesting
  bool serverKnownForTest(String callId) => _serverKnown.contains(callId);

  @visibleForTesting
  String? get serverVoiceCallForTest => _serverVoiceCallId;

  @visibleForTesting
  String? derivedKeyForTest(String callId) => _derivedKeys[callId];

  static void _addBounded(Set<String> set, String value, [int max = 64]) {
    set.add(value);
    while (set.length > max) {
      set.remove(set.first);
    }
  }

  void _markServerKnown(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return;
    _addBounded(_serverKnown, id);
  }

  /// B1: the caller works the call key out from the link key before the
  /// first invite (a random key as before when there is no link key).
  Future<void> _prepareVoiceKey266(CallSession session) async {
    if (_voiceKeys.containsKey(session.id)) return;
    final transport = directTransport;
    if (transport is! SealingPeerTransport) return;
    final key = await transport.callVoiceKey266(session.peerId, session.id);
    if (key == null || _voiceKeys.containsKey(session.id)) return;
    _voiceKeys[session.id] = key;
    _derivedKeys[session.id] = key;
  }

  /// A1: the invite through the server too, once per call (the server
  /// knows the call id and never rings twice).
  void _sendInviteViaServer266(String callId, Map<String, dynamic> invite) {
    if (_serverInviteSent.contains(callId)) return;
    final ws = socket;
    if (ws == null || !ws.isConnected) return;
    final sent = ws.send({
      ...Map<String, dynamic>.from(invite)
        ..remove(SealingPeerTransport.voiceKeyField),
      'sender_id': store.deviceId,
      'transport_mode': CallTransportMode.offlineMesh.wireName,
    });
    if (!sent) return;
    _addBounded(_serverInviteSent, callId);
    _markServerKnown(callId);
    AppLogger.info('CALL_INVITE_SERVER', detail: 'sent call=$callId');
  }

  /// A2: answer / end / busy / reject of a call the server knows go
  /// through the server too (not only when the nearby send fails).
  void _copyToServer266(Map<String, dynamic> msg) {
    final type = msg['type']?.toString() ?? '';
    final callId = msg['call_id']?.toString() ?? '';
    if (!_serverCopyTypes.contains(type) || !_serverKnown.contains(callId)) {
      return;
    }
    final key = '$type|$callId';
    if (_serverCopied.contains(key)) return;
    final ws = socket;
    if (ws == null || !ws.isConnected) return;
    final sent = ws.send({
      ...Map<String, dynamic>.from(msg)
        ..remove(SealingPeerTransport.voiceKeyField),
      'sender_id': store.deviceId,
      'transport_mode': CallTransportMode.offlineMesh.wireName,
    });
    if (!sent) return;
    _addBounded(_serverCopied, key, 128);
    AppLogger.info('CALL_SIGNAL_SERVER_COPY', detail: 'type=$type call=$callId');
  }

  /// A: the server keeps a connected call only while it hears from it
  /// (60 s). A call the server knows sends its heartbeat there too.
  void _serverHeartbeat266(CallSession session) {
    if (!_serverKnown.contains(session.id) || session.answeredAt == null) {
      return;
    }
    final ws = socket;
    if (ws == null || !ws.isConnected) return;
    ws.send({'type': 'call_heartbeat', 'call_id': session.id});
  }

  /// The server said "answered" for our call. The nearby answer (with the
  /// codec and the lock) usually comes within milliseconds when a nearby way
  /// exists: wait a little for it. False = nothing more to do here.
  Future<bool> _serverAnswer266(CallSession session) async {
    var route = false;
    try {
      route = await _hasLocalRouteTo(session.peerId);
    } catch (_) {}
    if (route) {
      for (var i = 0; i < 15 && _transport == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final live = _session;
        if (live == null || live.id != session.id || _isClosing(live)) {
          return false;
        }
      }
    }
    final live = _session;
    if (live == null || live.id != session.id || _isClosing(live)) return false;
    if (_transport != null) return false; // the nearby answer started it
    // opus2 when we offered it: the friend picks it by the same rule, and
    // each voice piece says its codec (the sound falls back by itself).
    final used =
        live.supportedMediaCodecs.contains(_opusCodec) ? _opusCodec : _pcmCodec;
    // The friend can't say voice_lock through the server: keep the lock only
    // when both phones work the key out (B1).
    final derived = _derivedKeys[live.id];
    if (derived == null || _voiceKeys[live.id] != derived) {
      _voiceKeys.remove(live.id);
    }
    _setSession(live.copyWith(mediaCodec: used));
    AppLogger.info('CALL_ANSWER_VIA_SERVER',
        detail: 'call=${live.id} codec=$used '
            'locked=${_voiceKeys.containsKey(live.id)} route=$route');
    return true;
  }

  /// B4: server voice may run for [s] (the server knows the call, the
  /// socket is up and both phones use the worked-out key).
  bool _serverVoiceAllowed(CallSession s) {
    final derived = _derivedKeys[s.id];
    final ws = socket;
    return derived != null &&
        _voiceKeys[s.id] == derived &&
        _serverKnown.contains(s.id) &&
        !_serverVoiceStopped.contains(s.id) &&
        ws != null &&
        ws.isConnected;
  }

  /// B4: the friend's voice is coming through the server right now.
  bool _serverVoiceRunning(CallSession s) {
    final at = _serverVoiceRxAt;
    return _serverVoiceCallId == s.id &&
        _serverVoiceAllowed(s) &&
        at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 5);
  }

  /// B2/B3: turns server voice on for the live answered call, off otherwise.
  Future<void> _syncServerVoice266() async {
    final s = _session;
    final want = s != null &&
        !_isClosing(s) &&
        s.answeredAt != null &&
        _transport != null &&
        _serverVoiceAllowed(s);
    final current = _serverVoiceCallId;
    if (want && current == s.id) return;
    if (!want && current == null) return;
    if (current != null) {
      _serverVoiceCallId = null;
      _flushVoiceIn();
      await _voiceOutSub?.cancel();
      _voiceOutSub = null;
      AppLogger.info('CALL_VOICE_SERVER',
          detail: 'at=off call=$current tx=$_serverVoiceTx rx=$_serverVoiceRx');
      try {
        await mediaPlatform.setServerVoice(callId: current, on: false);
      } catch (_) {}
    }
    if (!want) return;
    final id = s.id;
    _serverVoiceCallId = id;
    _serverVoiceTx = 0;
    _serverVoiceRx = 0;
    _serverVoiceRxAt = null;
    try {
      _voiceOutSub ??= mediaPlatform
          .serverVoiceOut()
          .listen(_onServerVoiceOut, onError: (Object _) {});
    } catch (_) {}
    AppLogger.info('CALL_VOICE_SERVER', detail: 'at=on call=$id');
    try {
      await mediaPlatform.setServerVoice(callId: id, on: true);
    } catch (_) {}
  }

  /// B3: locked pieces from the native side -> one `call_voice` frame each.
  void _onServerVoiceOut(Map<String, dynamic> event) {
    final id = event['call_id']?.toString() ?? '';
    if (id.isEmpty || id != _serverVoiceCallId) return;
    final voices = event['voices'];
    if (voices is! List) return;
    final ws = socket;
    if (ws == null || !ws.isConnected) return;
    for (final v in voices) {
      if (v is! String || v.isEmpty || v.length > 1400) continue;
      if (ws.send({'type': 'call_voice', 'call_id': id, 'voice': v})) {
        _serverVoiceTx++;
      }
    }
  }

  /// B3: a locked piece through the server -> the native side (small
  /// batches every 40 ms, no log per piece).
  void _onServerVoiceIn(Map<String, dynamic> msg) {
    final s = _session;
    final id = msg['call_id']?.toString() ?? '';
    final sender = msg['sender_id']?.toString().trim() ?? '';
    final voice = msg['voice']?.toString() ?? '';
    if (s == null ||
        s.id != id ||
        _isClosing(s) ||
        _transport == null ||
        sender != s.peerId ||
        voice.isEmpty ||
        voice.length > 1400) {
      return;
    }
    _serverVoiceRxAt = DateTime.now();
    if (_serverVoiceRx++ == 0) {
      AppLogger.info('CALL_VOICE_SERVER', detail: 'at=first_rx call=$id');
    }
    if (_voiceInCall != id || _voiceInSender != sender) {
      _flushVoiceIn();
      _voiceInCall = id;
      _voiceInSender = sender;
    }
    _voiceInBatch.add(voice);
    if (_voiceInBatch.length >= 16) {
      _flushVoiceIn();
      return;
    }
    _voiceInTimer ??= Timer(const Duration(milliseconds: 40), _flushVoiceIn);
  }

  void _flushVoiceIn() {
    _voiceInTimer?.cancel();
    _voiceInTimer = null;
    if (_voiceInBatch.isEmpty) return;
    final voices = List<String>.of(_voiceInBatch);
    _voiceInBatch.clear();
    unawaited(mediaPlatform
        .serverVoiceIn(
            callId: _voiceInCall, senderId: _voiceInSender, voices: voices)
        .catchError((Object _) {}));
  }

  /// B3: the server stopped passing our voice (one line, off for this call).
  void _onServerVoiceStop(Map<String, dynamic> msg) {
    final id = msg['call_id']?.toString().trim() ?? '';
    if (id.isEmpty || _serverVoiceStopped.contains(id)) return;
    _addBounded(_serverVoiceStopped, id, 16);
    AppLogger.info('CALL_VOICE_SERVER',
        detail: 'at=stop call=$id reason=${msg['reason'] ?? '-'}');
    unawaited(_syncServerVoice266());
  }

  /// D1: a friend calls through the server and there is no nearby way to
  /// them -> Nearby looks for that friend while the call is on (60 s max).
  Future<void> _wakeForServerCall266(String callId, String peerId) async {
    var route = true;
    try {
      route = await _hasLocalRouteTo(peerId);
    } catch (_) {}
    final s = _session;
    if (route || s == null || s.id != callId || _isClosing(s)) return;
    CallNearbyWait.instance.startWake(callId, peerId);
    _wakeTimer?.cancel();
    _wakeTimer = Timer(wakeLimit266, () {
      _wakeTimer = null;
      if (CallNearbyWait.instance.wakingFor(callId)) {
        CallNearbyWait.instance.stopWake('limit');
      }
    });
  }

  void _syncWake266(CallSession? session) {
    final wait = CallNearbyWait.instance;
    final id = wait.wakeCallId;
    if (id == null) return;
    final why = CallNearbyWait.wakeEndWhy(session, id);
    if (why == null) return;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    wait.stopWake(why);
  }

  void start() {
    if (_disposed) return;
    _notificationActionSub ??= notificationPlatform.actions
        .listen((action) => unawaited(_handleNotificationAction(action)));
    _nativeSub ??=
        transportFactory.nativeMesh.events.listen(_handleNativeTransportEvent);
    _routeSub ??= routePolicy.routeChanges.listen(_handleRouteChange);
    // Server-relay intake: the backend hub forwards call lifecycle frames
    // between validated participants. When Wi-Fi Direct is down this is the
    // only path an invite/accept/end can arrive on.
    _socketSub ??= socket?.messages
        .listen((msg) => unawaited(_handleServerCallSignal(msg)));
    unawaited(_synchronizeIncomingPresentation());
    unawaited(syncHistory());
    unawaited(_restoreSavedAccept());
    unawaited(_takeHandover());
  }

  /// Bundle 179 (2.2): the call id that came from the closed-app hand-over
  /// (for the CALL_ACCEPT_APPLIED source).
  String? _handoverCallId;

  /// Bundle 179 (2.2): Accept was tapped on the notification but this app
  /// (or a rebuilt screen) missed the tap. Android kept it for 60 s: answer
  /// the matching call as soon as it rings. Never answers another call.
  Future<void> _restoreSavedAccept() async {
    final saved = await notificationPlatform.acceptedCall();
    if (saved == null || _disposed) return;
    AppLogger.info('CALL_ACCEPT_RESTORED',
        detail: 'call=${saved.callId} left_ms=${saved.remaining.inMilliseconds}');
    _notificationTapAge = saved.tapAge;
    final session = _session;
    if (session != null &&
        !session.isFinished &&
        (session.id != saved.callId || session.peerId != saved.callerId)) {
      // A different call is on: the old Accept is not for it.
      unawaited(notificationPlatform.clearAcceptedCall(saved.callId));
      return;
    }
    if ((session == null || session.isFinished) &&
        _pendingNotificationAccept != null) {
      return;
    }
    await _handleNotificationAction(saved.action, window: saved.remaining);
  }

  /// Bundle 176 (3): a call that rang in the other engine (no-screen engine
  /// before the app opened, or the app before it was swiped away) rings here
  /// now. Ended calls and repeats are refused by the normal invite checks.
  Future<void> _takeHandover() async {
    final invite = await handover?.take();
    if (invite == null || _disposed) return;
    AppLogger.info('CALL_HANDOVER_TAKEN',
        detail: 'call=${invite['call_id'] ?? ''}');
    _handoverCallId = invite['call_id']?.toString();
    await _handleLocalCallSignal(invite);
  }

  void onAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _appInForeground = state == AppLifecycleState.resumed;
    final session = _session;
    if (session != null &&
        session.direction == CallDirection.incoming &&
        session.state == CallState.ringing) {
      if (_appInForeground) {
        unawaited(notificationPlatform.cancelIncoming());
      } else {
        unawaited(notificationPlatform.showIncoming(
            callId: session.id,
            callerId: session.peerId,
            callerName: session.peerName));
      }
    }
    if (state == AppLifecycleState.resumed) {
      if (_session != null && !_session!.isFinished) {
        _sendHeartbeat();
        _startStatsTimer();
      }
    }
  }

  Future<void> syncHistory() async {
    final local = await repository.syncHistory();
    if (!_historyController.isClosed) _historyController.add(local);
  }

  Future<void> startCall(Device device) async {
    // Bundle 212: my own account is blocked by admin (read only).
    if (AdminBlockBook.instance.selfBlocked) {
      throw const CallPreflightException(
        CallPreflightCode.peerBlocked,
        'Blocked by admin',
      );
    }
    // Bundle 213: this app version is stopped by admin (read only).
    if (VersionGuard.instance.stopped) {
      throw const CallPreflightException(
        CallPreflightCode.peerBlocked,
        'Old version. Update to call.',
      );
    }
    if (await store.isBlockedPeer(device.id)) {
      throw const CallPreflightException(
        CallPreflightCode.peerBlocked,
        'This user is blocked',
      );
    }
    if (_session != null && !_session!.isFinished) {
      throw const CallPreflightException(
        CallPreflightCode.activeCall,
        'Another call is already active',
      );
    }

    try {
      await transportFactory.ensureReady();
    } catch (_) {
      throw const CallPreflightException(
        CallPreflightCode.transportUnavailable,
        'Local calling service is unavailable',
      );
    }

    if (!await identityTrust.canEstablishLocalCall(device.id)) {
      throw const CallPreflightException(
        CallPreflightCode.identityUnavailable,
        'This user identity is not trusted for local calling',
      );
    }
    // Bundle 158 (D1): voice calls go at most 3 hops; further away the
    // sound breaks up, so show the usual "couldn't reach" instead.
    LocalRouteResult? callRoute;
    try {
      callRoute = await routePolicy.resolve(device.id);
    } catch (_) {}
    if (callRoute != null && VoiceCallHopPolicy.tooFar(callRoute)) {
      AppLogger.info('CALL_TOO_FAR',
          detail: 'hops=${callRoute.hopCount} max=${VoiceCallHopPolicy.maxHops}');
      throw const CallPreflightException(
        CallPreflightCode.noLocalRoute,
        "Couldn't reach them — try again",
      );
    }
    final mode = CallTransportSelectionPolicy.select(localRouteAvailable: true);
    final id = _newCallId();
    final now = DateTime.now();
    final session = CallSession(
      id: id,
      peerId: device.id,
      // Same display rule as incoming calls: profile nickname, never the
      // auto-generated device label.
      peerName: await _peerDisplayName(device.id),
      direction: CallDirection.outgoing,
      state: CallState.connecting,
      startedAt: now,
      // Bundle 144: voice calls start on the SPEAKER again (user choice: the
      // 143 earpiece default sounded filtered). The speaker button moves to
      // the earpiece; proximity screen-off is active only then.
      speakerOn: true,
      directMode: true,
      transportMode: mode,
      signalingConnected: false,
      supportedMediaCodecs: await _supportedMediaCodecs(),
    );
    _setSession(session);
    _inviteInFlight = false;
    _lastInviteAttemptAt = null;
    await _persistSession();
    _startRouteWaitTimer();
    await _trySendPendingInvite();
    // Connecting watchdog: without it a peer that never acks leaves the
    // caller staring at "connecting…" forever. 45s covers one full link
    // recovery window, then fail closed with a clear reason.
    _connectWatchdogTimer?.cancel();
    _connectWatchdogTimer = Timer(connectWatchdog, _onConnectWatchdog);
  }

  /// Connecting watchdog for a call that had a link (45 s).
  @visibleForTesting
  static Duration connectWatchdog = const Duration(seconds: 45);

  /// Bundle 225 (P5): a call that was "away" (no link at all to the friend)
  /// keeps trying this long in total.
  @visibleForTesting
  static Duration awayCallWatchdog = CallNearbyWait.awayLimit;

  void _onConnectWatchdog() {
    final current = _session;
    if (_disposed || current == null || current.isFinished) return;
    if (current.direction != CallDirection.outgoing ||
        current.state != CallState.connecting) {
      return;
    }
    // Bundle 225 (P5): an away call waits 60 s, not 45 s.
    final extra = awayCallWatchdog - connectWatchdog;
    if (CallNearbyWait.instance.wasAway(current.id) &&
        !extra.isNegative &&
        extra > Duration.zero &&
        _awayExtendedCallId != current.id) {
      _awayExtendedCallId = current.id;
      AppLogger.info('CALL_CONNECT_WATCHDOG_EXTEND',
          detail: 'call=${current.id} away=1 extra_s=${extra.inSeconds}');
      _connectWatchdogTimer = Timer(extra, _onConnectWatchdog);
      return;
    }
    AppLogger.warning('CALL_CONNECT_WATCHDOG_TIMEOUT', detail: 'call=${current.id}');
    unawaited(_finishLocal(CallState.failed, 'unreachable',
        notifyServer: false));
  }

  String? _awayExtendedCallId;

  /// Bundle 225 (P1): start / stop the away-call wait after a route check.
  void _syncAwayCall(CallSession session, {required bool routeAvailable}) {
    final wait = CallNearbyWait.instance;
    if (CallNearbyWait.isAwayCall(session, routeAvailable: routeAvailable)) {
      wait.start(session);
    } else if (wait.waitingFor(session.id)) {
      wait.stop(routeAvailable ? 'route' : 'ended');
    }
  }

  /// Bundle 225 (P1): the wait ends when the call rings, connects or ends.
  void _syncAwayCallState(CallSession? session) {
    final wait = CallNearbyWait.instance;
    final id = wait.callId;
    if (id == null) return;
    final why = CallNearbyWait.endWhy(session, id);
    if (why != null) wait.stop(why);
  }

  // Bundle 146: two accepts for the same call (notification + screen, or a
  // duplicate notification dispatch) both passed the 'ringing' check while
  // the first waited on a slow store, so media started twice (the receiver's
  // audio restarted ~1 s after accept in the logs).
  String? _acceptingCallId;

  Future<void> acceptIncoming() async {
    final session = _session;
    if (session == null ||
        session.direction != CallDirection.incoming ||
        session.state != CallState.ringing) return;
    if (_acceptingCallId == session.id) {
      AppLogger.info('CALL_ACCEPT_DUPLICATE_IGNORED', detail: 'call=${session.id}');
      return;
    }
    _acceptingCallId = session.id;
    try {
      await _acceptIncomingOnce(session);
    } finally {
      if (_acceptingCallId == session.id) _acceptingCallId = null;
    }
  }

  Future<void> _acceptIncomingOnce(CallSession session) async {
    // Bundle 186 (A1): how long each answer step takes. sinceTap = Accept
    // was tapped on the notification that long ago (the app was opening).
    final tapAge = _notificationTapAge;
    _notificationTapAge = null;
    final timer = CallAnswerTimer(callId: session.id, sinceTap: tapAge);
    if (await store.isBlockedPeer(session.peerId)) {
      await rejectIncoming(reason: 'blocked');
      return;
    }
    timer.step('blocked_check');
    // The store wait above can be slow; the call may have ended meanwhile.
    final live = _session;
    if (live == null ||
        live.id != session.id ||
        live.state != CallState.ringing) {
      return;
    }
    try {
      _cancelCallTimers();
      final selectedCodec = await _negotiateCodec(session.supportedMediaCodecs);
      timer.step('codec');
      _setSession(live.copyWith(
        state: CallState.connecting,
        mediaCodec: selectedCodec,
        transportMode: CallTransportMode.offlineMesh,
        directMode: true,
        // Bundle 162 (4.8): answered now — the screen shows 00:00 at once.
        // Voice only (video is paused and left exactly as it was).
        answeredAt: live.videoEnabled ? null : DateTime.now(),
      ));
      // Fire-and-forget: a stalled store must not hold the callee on
      // 'Connecting…' while the microphone is already live below.
      unawaited(_persistSession());
      _transport =
          transportFactory.resolve(requested: CallTransportMode.offlineMesh);
      // Bundle 186 (B1): the quick checks first (link up, identity not
      // changed), then tell the caller AT ONCE - before our own mic and
      // speaker start - so both phones start their sound at the same time.
      // Before 186 the caller kept ringing until our audio was running
      // (~1.9 s after the tap on the Realme). If our audio then fails, the
      // catch below sends the normal call end (the caller sees it end).
      await _transport!.prepare(_session!);
      timer.step('prepare');
      await _sendSignal({
        'type': 'call_accept',
        'call_id': session.id,
        'recipient_id': session.peerId,
        'selected_media_codec': selectedCodec,
        'transport_mode': CallTransportMode.offlineMesh.wireName,
        'mesh_call': true,
        'direct': true,
        // Bundle 159: tells the caller to lock its sound too.
        if (_voiceKeys.containsKey(session.id)) 'voice_lock': true,
      });
      timer.step('accept_sent');
      final current = _session;
      if (current == null || current.id != session.id || _isClosing(current)) {
        // Hung up while the accept was going out: nothing to start.
        return;
      }
      await _transport!.start(current);
      timer.step('audio');
      await _markConnected();
      timer.done();
    } catch (e, stackTrace) {
      // Every failure used to collapse into 'microphone_unavailable', which
      // hid the real cause (most often a missing mic permission on a fresh
      // install). Classify so the UI can offer the right next step and the
      // logs show the true failure.
      final reason = callFailureReason(e);
      AppLogger.error('CALL_ACCEPT_FAILED',
          detail: 'reason=$reason', error: e, stackTrace: stackTrace);
      await _fail(reason);
      rethrow;
    }
  }

  /// Bundle 186 (A3): when the first invite of the current outgoing call
  /// went out (for CALL_CONNECT_MS).
  (String, Stopwatch)? _inviteSentAt;

  /// Bundle 186 (A1): how long ago Accept was tapped on the notification
  /// (from the saved Accept), used once by the next answer.
  Duration? _notificationTapAge;

  /// Single display-name rule for every call-surface peer label:
  /// directory profile display_name → username → last known → LinkUp user.
  /// Device ids and device names are never shown as a person's name.
  Future<String> _peerDisplayName(String peerId) async {
    try {
      final label = await repository.labelForPeer(peerId);
      if (label != null && label.trim().isNotEmpty) return label.trim();
    } catch (_) {}
    // Bundle 258 (B2): the last name seen for this person.
    return NameBook258.instance.lastKnown(peerId) ?? NameBook258.noName;
  }

  Future<void> rejectIncoming({String reason = 'rejected'}) async {
    final session = _session;
    if (session == null ||
        session.direction != CallDirection.incoming ||
        session.isFinished) return;
    _cancelCallTimers();
    await _sendSignal({
      'type': 'call_reject',
      'call_id': session.id,
      'recipient_id': session.peerId,
      'reason': reason
    });
    await _finishLocal(CallState.rejected, reason, notifyServer: false);
  }

  Future<void> endCall({String reason = 'hangup'}) async {
    final session = _session;
    if (session == null || session.isFinished) return;
    _cancelCallTimers();
    _meshRouteRecoveryTimer?.cancel();
    if (session.direction == CallDirection.outgoing &&
        session.state == CallState.connecting) {
      if (_lastInviteAttemptAt != null) {
        try {
          await _sendSignal({
            'type': 'call_end',
            'call_id': session.id,
            'recipient_id': session.peerId,
            'reason': reason,
          });
        } catch (_) {}
      }
      await _finishLocal(CallState.canceled, reason, notifyServer: false);
      return;
    }
    _setSession(session.copyWith(state: CallState.ending, reason: reason));
    await _sendSignal({
      'type': 'call_end',
      'call_id': session.id,
      'recipient_id': session.peerId,
      'reason': reason
    });
    await _finishLocal(CallState.ended, reason, notifyServer: false);
  }

  Future<void> toggleMute() async {
    final session = _session;
    final transport = _transport;
    if (session == null || transport == null) return;
    final muted = !session.muted;
    await transport.setMuted(session, muted);
    _setSession(session.copyWith(muted: muted));
  }

  Future<void> toggleVideo() async {
    final session = _session;
    final transport = _transport;
    if (session == null || transport == null || !transport.supportsVideo)
      return;
    final enabled = !session.videoEnabled;
    if (enabled && session.localVideoTextureId == null) {
      Map<String, dynamic> video;
      try {
        video = await transport.startVideo(session);
      } catch (error) {
        // The native error carries a "Call video: <reason>" message; log it so
        // a capture names the exact device failure behind the toast.
        AppLogger.error('CALL_VIDEO_START_FAIL',
            detail: 'call=${session.id} peer=${session.peerId} err=$error');
        rethrow;
      }
      _setSession(session.copyWith(
        videoEnabled: true,
        localVideoTextureId: (video['local_texture_id'] as num?)?.toInt(),
        remoteVideoTextureId: (video['remote_texture_id'] as num?)?.toInt(),
        localVideoRotation: (video['rotation'] as num?)?.toInt() ?? 0,
      ));
      await _speakerForVideo();
      return;
    }
    await transport.setVideoEnabled(session, enabled);
    _setSession(session.copyWith(
      videoEnabled: enabled,
      videoSwitchRequested: false,
      videoSwitchDeclined: false,
    ));
    if (enabled) await _speakerForVideo();
  }

  /// WhapApp-style: the local user accepted the peer's switch-to-video —
  /// turn OUR camera on for this call (same path as a manual toggle). Falls
  /// back to a receive-only viewer when the camera can't start (permission
  /// still denied etc.) so the peer's video at least renders.
  @override
  Future<void> acceptVideoSwitch() async {
    final session = _session;
    if (session == null || !session.videoSwitchRequested) return;
    _setSession(session.copyWith(
        videoSwitchRequested: false, videoSwitchDeclined: false));
    if (session.videoEnabled) return;
    try {
      await toggleVideo();
    } catch (_) {
      final fresh = _session;
      if (fresh != null &&
          fresh.answeredAt != null &&
          fresh.remoteVideoTextureId == null) {
        await _acceptRemoteVideo(fresh);
      }
      rethrow;
    }
  }

  @override
  Future<void> declineVideoSwitch() async {
    final session = _session;
    if (session == null) return;
    _setSession(session.copyWith(
        videoSwitchRequested: false, videoSwitchDeclined: true));
  }

  /// Receive-side half of the WhatsApp-style switch-to-video: the peer turned
  /// their camera on mid-call; allocate a local video session in receive-only
  /// mode (camera closed — no camera permission prompt on this device) so the
  /// peer's video renders on our screen.
  Future<void> _acceptRemoteVideo(CallSession session) async {
    final transport = _transport;
    if (_disposed ||
        transport == null ||
        !transport.supportsVideo ||
        _session?.id != session.id) return;
    try {
      final video = await transport.startVideo(session, enableCamera: false);
      final latest = _session;
      if (latest == null || latest.id != session.id || latest.isFinished)
        return;
      _setSession(latest.copyWith(
        localVideoTextureId: (video['local_texture_id'] as num?)?.toInt(),
        remoteVideoTextureId: (video['remote_texture_id'] as num?)?.toInt(),
        peerVideoActive: true,
      ));
      await _speakerForVideo();
    } catch (error) {
      AppLogger.error('CALL_VIDEO_ACCEPT_FAIL',
          detail: 'call=${session.id} peer=${session.peerId} err=$error');
    }
  }

  Future<void> switchCamera() async {
    final session = _session;
    final transport = _transport;
    if (session == null ||
        transport == null ||
        !transport.supportsVideo ||
        !session.videoEnabled) return;
    await transport.switchCamera(session);
  }

  Future<void> toggleSpeaker() async {
    final session = _session;
    if (session == null) return;
    final next = !session.speakerOn;
    try {
      await audioPlatform.setSpeakerphoneOn(next);
      _setSession(session.copyWith(speakerOn: next));
    } catch (_) {}
  }

  Future<List<CallRecord>> history() => repository.history();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelCallTimers();
    _clearPendingNotificationAccept();
    unawaited(notificationPlatform.setCallLockScreen(
        show: false, turnScreenOn: false));
    await _callScreenRequestController.close();
    await _callUnavailableController.close();
    _routeChurnSummaryTimer?.cancel();
    _routeChurnSummaryTimer = null;
    _routeChurnPending.clear();
    _lifecycleRetryTimer?.cancel();
    _lifecycleRetryTimer = null;
    _pendingLifecycleSignals.clear();
    _lifecycleQueuedAt.clear();
    _lifecycleInboundRxAt.clear();
    await _nativeSub?.cancel();
    await _notificationActionSub?.cancel();
    await _routeSub?.cancel();
    await _socketSub?.cancel();
    _socketSub = null;
    // Bundle 266
    _voiceInTimer?.cancel();
    _voiceInTimer = null;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    await _voiceOutSub?.cancel();
    _voiceOutSub = null;
    _nativeSub = null;
    _notificationActionSub = null;
    _presentationRevision++;
    await ringtone.stop();
    await notificationPlatform.cancelIncoming();
    if (_transport != null && _session != null) {
      try {
        await _transport!.stop(_session!);
      } catch (_) {}
    }
    _transport = null;
    _voiceKeys.clear();
    await transportFactory.dispose();
    await _historyController.close();
    await _sessionController.close();
  }

  Future<bool> _hasLocalRouteTo(String peerId) async =>
      (await routePolicy.resolve(peerId)).isAvailable;


  /// Server-WS relay intake. The backend hub only relays call lifecycle
  /// frames between validated call participants, so frames arriving here are
  /// source-trusted. Normalized into the mesh-style envelope and funneled
  /// through the shared dispatcher, whose fingerprint dedupe drops the
  /// duplicate copy when mesh managed to deliver first.
  Future<void> _handleServerCallSignal(Map<String, dynamic> msg) async {
    if (_disposed) return;
    final type = msg['type']?.toString() ?? '';
    // Bundle 266 (B3): voice pieces never go through the signal dispatcher.
    if (type == 'call_voice') {
      _onServerVoiceIn(msg);
      return;
    }
    if (type == 'call_voice_stop') {
      _onServerVoiceStop(msg);
      return;
    }
    if (!type.startsWith('call_')) return;
    // Bundle 266 (A2): the server knows this call.
    if (type == 'call_invite' || type == 'call_invite_ack') {
      _markServerKnown(msg['call_id']?.toString() ?? '');
    }
    final withDefaults = Map<String, dynamic>.from(msg);
    withDefaults['server'] = true;
    // The hub only handles offline_mesh calls; satisfying the local-invite
    // gate even for frames relayed before the backend preserved
    // transport_mode.
    withDefaults['transport_mode'] ??= CallTransportMode.offlineMesh.wireName;
    await _handleLocalCallSignal(withDefaults);
  }

  Future<void> _handleLocalCallSignal(Map<String, dynamic> msg) async {
    // Bundle 295 (A): a ring repeat says nothing about our accept / end.
    if (msg[ringAliveRepeatField295] != true) _noteLifecycleInbound(msg);
    if (_disposed) return;
    final type = msg['type']?.toString() ?? '';
    // Dual-channel delivery (mesh + server relay) means the same logical
    // signal can arrive twice milliseconds apart; process the first only.
    // Invites are intentionally NOT deduped here: the 5s resend loop emits
    // identical fingerprints legitimately, and _seenInviteIds covers them.
    const skipDedupe = {'call_invite', 'call_heartbeat_ack'};
    if (!skipDedupe.contains(type)) {
      // Bundle 266: the server sends every call_state with the caller as
      // sender, so "connected" then "ended" are two different signals.
      final key = '$type|${msg['call_id'] ?? ''}|${msg['sender_id'] ?? ''}'
          '${type == 'call_state' ? '|${msg['status'] ?? ''}' : ''}';
      final now = DateTime.now();
      _recentSignalFingerprints.removeWhere(
          (_, ts) => now.difference(ts) > const Duration(seconds: 10));
      if (_recentSignalFingerprints.containsKey(key)) return;
      _recentSignalFingerprints[key] = now;
    }
    switch (msg['type']?.toString()) {
      case 'call_invite':
        await _handleInvite(msg);
        return;
      case 'call_invite_ack':
        await _handleInviteAck(msg);
        return;
      case 'call_accept':
        await _handleAccept(msg);
        return;
      case 'call_reject':
      case 'call_busy':
        await _handleReject({
          ...msg,
          if (msg['type'] == 'call_busy')
            'reason': (msg['reason']?.toString().isNotEmpty == true)
                ? msg['reason']
                : 'busy'
        });
        return;
      case 'call_end':
        await _handleEnd(msg);
        return;
      case 'call_state':
        await _handleState(msg);
        return;
      case 'call_heartbeat_ack':
        _handleHeartbeatAck(msg);
        return;
    }
  }

  Future<void> _handleInvite(Map<String, dynamic> msg) async {
    final callId = msg['call_id']?.toString().trim() ?? '';
    final peerId = msg['sender_id']?.toString().trim() ?? '';
    final recipientId = msg['recipient_id']?.toString().trim() ?? '';
    final selfId = store.deviceId?.trim() ?? '';
    if (callId.isEmpty ||
        peerId.isEmpty ||
        selfId.isEmpty ||
        recipientId != selfId ||
        peerId == selfId) return;
    final localInvite = msg['direct'] == true ||
        msg['mesh_call'] == true ||
        msg['transport_mode']?.toString().trim().toLowerCase() ==
            CallTransportMode.offlineMesh.wireName;
    if (!localInvite) return;
    // Bundle 266 (A2): an invite through the server = the server knows it.
    if (msg['server'] == true) _markServerKnown(callId);
    // Bundle 172: this call already ended (its "call ended" came first, or
    // it rang here before). A late copy from the send queue never rings.
    if (_endedCalls.contains(callId)) {
      AppLogger.info('CALL_INVITE_ALREADY_ENDED', detail: 'call=$callId');
      return;
    }
    final createdAtRaw =
        DateTime.tryParse(msg['created_at']?.toString() ?? '')?.toLocal();
    // Phone clocks on a mesh can drift by hours; the hard "age > 2min => reject"
    // guard silently killed every cross-clock invite. The mesh only forwards
    // fresh events through the live transport stream anyway — stale replays
    // are filtered by the seen-check below, not by wall-clock comparisons.
    final createdAt = createdAtRaw ?? DateTime.now();
    if (!_seenInviteIds.contains(callId)) {
      _seenInviteIds.add(callId);
      _seenInviteCursor++;
      if (_seenInviteIds.length > 64 || _seenInviteCursor > 256) {
        _seenInviteCursor = 0;
        if (_seenInviteIds.length > 64) {
          final excess = _seenInviteIds.length - 64;
          final list = _seenInviteIds.toList();
          _seenInviteIds.removeAll(list.take(excess));
        }
      }
    } else {
      // Bundle 266 (B1): the locked copy of an invite that first came
      // through the server - its key wins (before the answer).
      final lateKey =
          CallVoiceKey.normalize(msg[SealingPeerTransport.voiceKeyField]);
      final ringing = _session;
      if (lateKey != null &&
          ringing != null &&
          ringing.id == callId &&
          ringing.state == CallState.ringing &&
          _voiceKeys[callId] != lateKey) {
        _voiceKeys[callId] = lateKey;
        AppLogger.info('CALL_VOICE_KEY_FROM_INVITE', detail: 'call=$callId');
      }
      // Bundle 295 (A): the caller still calls - keep ringing.
      if (ringing != null &&
          ringing.id == callId &&
          ringing.direction == CallDirection.incoming &&
          ringing.state == CallState.ringing &&
          _ringAliveWatch295 != null) {
        _ringAliveWatch295?.cancel();
        _ringAliveWatch295 = null;
        if (msg['server'] != true && !_serverKnown.contains(callId)) {
          _ringAliveWatch295 =
              Timer(ringAliveLimit295, () => _onRingAliveLost295(callId));
        }
      }
      AppLogger.info('CALL_INVITE_DUPLICATE_IGNORED', detail: 'call=$callId');
      return;
    }
    if (await store.isBlockedPeer(peerId)) {
      unawaited(_sendSignal({
        'type': 'call_reject',
        'call_id': callId,
        'recipient_id': peerId,
        'reason': 'blocked'
      }));
      return;
    }
    final existing = _session;
    if (existing != null && !existing.isFinished) {
      if (existing.id == callId &&
          existing.peerId == peerId &&
          existing.direction == CallDirection.incoming &&
          existing.state == CallState.ringing) return;
      // Glare: both devices started calling each other ~simultaneously, so
      // both hold a pre-answer OUTGOING session to the same peer. Resolve
      // deterministically without server help: the lexicographically lower
      // device id keeps its outgoing call and drops this invite; the higher
      // id cancels its own outgoing call (call_end reason 'glare') and
      // adopts THIS invite — its user sees the normal Answer/Decline bar and
      // one single call survives instead of two stuck dialing screens.
      if (existing.direction == CallDirection.outgoing &&
          existing.peerId == peerId &&
          existing.answeredAt == null &&
          (existing.state == CallState.connecting ||
              existing.state == CallState.reconnecting)) {
        final selfId = store.deviceId?.trim() ?? '';
        final keepCalling = selfId.isNotEmpty && selfId.compareTo(peerId) < 0;
        if (keepCalling) {
          AppLogger.info('CALL_GLARE_IGNORED_INVITE',
              detail: 'theirs=$callId ours=${existing.id}');
          return;
        }
        AppLogger.info('CALL_GLARE_ADOPTED_INVITE',
            detail: 'ours=${existing.id} theirs=$callId');
        await endCall(reason: 'glare');
        // Fall through: our outgoing session is finished; this invite is
        // adopted as our live session below.
      } else if (existing.direction == CallDirection.outgoing &&
          existing.peerId == peerId) {
        // Same peer, but our call is already answered (media active): real busy.
        unawaited(_sendSignal({
          'type': 'call_busy',
          'call_id': callId,
          'recipient_id': peerId,
          'reason': 'busy',
          'transport_mode': CallTransportMode.offlineMesh.wireName,
          'mesh_call': true,
          'direct': true
        }));
        return;
      } else if (existing.direction != CallDirection.outgoing || existing.peerId != peerId) {
      // Zombie guard: an abandoned ringing/connecting session (crash or link
      // flap mid-call) must not DoS every future caller with call_busy. A
      // genuinely active (recent) call still reports busy.
      final isLiveCall = existing.state == CallState.connected ||
          existing.state == CallState.reconnecting ||
          DateTime.now()
                  .difference(existing.startedAt) <
              const Duration(seconds: 60);
      if (isLiveCall) {
        unawaited(_sendSignal({
          'type': 'call_busy',
          'call_id': callId,
          'recipient_id': peerId,
          'reason': 'busy',
          'transport_mode': CallTransportMode.offlineMesh.wireName,
          'mesh_call': true,
          'direct': true
        }));
        return;
      }
      AppLogger.warning(
        'CALL_ZOMBIE_SESSION_CLEARED',
        detail: 'state=${existing.state.name} age=${DateTime.now().difference(existing.startedAt).inSeconds}s',
      );
      await _finishLocal(CallState.canceled, 'superseded',
          notifyServer: false);
      }
      // An incoming-ring session for the same (or another) peer that is no
      // longer live was cleared above; adoption continues below.
    }
    // Display name for the incoming caller must be the ACCOUNT's profile
    // nickname (or username) — never the raw device id and never the
    // auto-generated device label ("My Android Phone (xxxx)"). When no
    // profile is known yet, show a safe generic label.
    final name = await _peerDisplayName(peerId);
    final advertised = (msg['supported_media_codecs'] is List)
        ? (msg['supported_media_codecs'] as List)
            .map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty && e != CallVoiceKey266.marker)
            .toSet()
            .toList()
        : const <String>['pcm_s16le'];
    _setSession(CallSession(
      id: callId,
      peerId: peerId,
      peerName: name,
      direction: CallDirection.incoming,
      state: CallState.ringing,
      startedAt: createdAt,
      // Bundle 144: voice calls start on the SPEAKER again (user choice: the
      // 143 earpiece default sounded filtered). The speaker button moves to
      // the earpiece; proximity screen-off is active only then.
      speakerOn: true,
      directMode: true,
      transportMode: CallTransportMode.offlineMesh,
      supportedMediaCodecs: advertised,
    ));
    // Bundle 159: keep the caller's voice key (memory only) if valid.
    final voiceKey =
        CallVoiceKey.normalize(msg[SealingPeerTransport.voiceKeyField]);
    _voiceKeys.clear();
    _derivedKeys.clear();
    if (voiceKey != null) _voiceKeys[callId] = voiceKey;
    // Bundle 266 (B1): no key in the invite (it came through the server)
    // but the caller used the worked-out key -> work it out here too.
    if (voiceKey == null &&
        CallVoiceKey266.marked(msg['supported_media_codecs'])) {
      final transport = directTransport;
      if (transport is SealingPeerTransport) {
        final derived = await transport.callVoiceKey266(peerId, callId);
        if (derived != null &&
            _session?.id == callId &&
            !_voiceKeys.containsKey(callId)) {
          _voiceKeys[callId] = derived;
          _derivedKeys[callId] = derived;
        }
      }
    } else if (voiceKey != null &&
        CallVoiceKey266.marked(msg['supported_media_codecs'])) {
      // The locked invite carries the worked-out key: remember it as such
      // (server voice may run for this call).
      final transport = directTransport;
      if (transport is SealingPeerTransport) {
        final derived = await transport.callVoiceKey266(peerId, callId);
        if (derived != null && derived == voiceKey) {
          _derivedKeys[callId] = derived;
        }
      }
    }
    await _persistSession();
    _startRingTimer(outgoing: false);
    _armRingAlive295(msg, callId);
    // Bundle 176 (3): if this engine stops while ringing, the next one rings on.
    unawaited(handover?.park(callId, msg));
    // Bundle 266 (D1): rang through the server, no nearby way -> Nearby
    // looks for this friend now (only while their call is on).
    if (msg['server'] == true) unawaited(_wakeForServerCall266(callId, peerId));
    unawaited(_sendSignal({
      'type': 'call_invite_ack',
      'call_id': callId,
      'recipient_id': peerId,
      'status': 'ringing',
      // Bundle 172: useless after the ring time — leaves the queue then.
      queueLifetimeField: inviteQueueLifetime.inMilliseconds,
    }));
  }

  // Bundle 146: notification Accept opens the call screen.
  // The app reads [requestedCallScreenId] (or listens to [callScreenRequests])
  // and pushes CallScreen for a LIVE call, not only a ringing one.
  final _callScreenRequestController = StreamController<String>.broadcast();
  final _callUnavailableController = StreamController<String>.broadcast();
  String? _requestedCallScreenId;
  String? _pendingUnavailableNotice;
  CallNotificationAction? _pendingNotificationAccept;
  Timer? _pendingNotificationAcceptTimer;
  @visibleForTesting
  // Bundle 179 (2.3): was 10 s - too short for slow phones (ZTE).
  static Duration coldAcceptWindow = const Duration(seconds: 60);

  @override
  Stream<String> get callScreenRequests => _callScreenRequestController.stream;
  @override
  Stream<String> get callUnavailableNotices =>
      _callUnavailableController.stream;
  @override
  String? get requestedCallScreenId => _requestedCallScreenId;

  @override
  void clearCallScreenRequest(String callId) {
    if (_requestedCallScreenId == callId) _requestedCallScreenId = null;
  }

  @override
  String? takeCallUnavailableNotice() {
    final notice = _pendingUnavailableNotice;
    _pendingUnavailableNotice = null;
    return notice;
  }

  void _requestCallScreen(String callId) {
    _requestedCallScreenId = callId;
    if (!_callScreenRequestController.isClosed) {
      _callScreenRequestController.add(callId);
    }
  }

  void _noticeCallUnavailable(String callId, String reason) {
    AppLogger.info('CALL_NOTIFICATION_ACCEPT_UNAVAILABLE',
        detail: 'call=$callId reason=$reason');
    _pendingUnavailableNotice = callId;
    if (!_callUnavailableController.isClosed) {
      _callUnavailableController.add(callId);
    }
    // The Accept intent may have lifted the app over the lock screen; with no
    // call to show, hand the lock screen back.
    if (_session == null || _session!.isFinished) {
      _lastLockScreenShow = null;
      _syncCallLockScreen(_session);
    }
  }

  void _clearPendingNotificationAccept() {
    _pendingNotificationAcceptTimer?.cancel();
    _pendingNotificationAcceptTimer = null;
    _pendingNotificationAccept = null;
  }

  Future<void> _handleNotificationAction(CallNotificationAction action,
      {Duration? window}) async {
    AppLogger.info('CALL_NOTIFICATION_ACTION',
        detail: 'action=${action.type.name} call=${action.callId} '
            'app=${_appInForeground ? 'foreground' : 'background'} '
            'session=${_session?.id == action.callId ? _session!.state.name : (_session == null ? 'none' : 'other')}');
    final session = _session;
    final matches = session != null &&
        session.id == action.callId &&
        session.peerId == action.callerId;

    if (action.type == CallNotificationActionType.accept) {
      // Bundle 179 (2): an OLD finished call still on file counts as "no
      // call yet" - before, its Accept was refused and the new call then
      // rang again asking for a second Accept.
      if (session == null ||
          (session.isFinished && session.id != action.callId)) {
        // Cold start: the app was swiped away while ringing, the Accept
        // intent restarted it, and no session exists yet. Wait briefly for a
        // matching ringing session (re-delivered invite), then give up with
        // a visible notice instead of hanging.
        _clearPendingNotificationAccept();
        _pendingNotificationAccept = action;
        final wait = window == null || window > coldAcceptWindow
            ? coldAcceptWindow
            : window;
        _pendingNotificationAcceptTimer = Timer(wait, () {
          final pending = _pendingNotificationAccept;
          if (pending == null || _disposed) return;
          _clearPendingNotificationAccept();
          AppLogger.info('CALL_ACCEPT_EXPIRED',
              detail: 'call=${pending.callId} where=app');
          unawaited(notificationPlatform.clearAcceptedCall(pending.callId));
          _noticeCallUnavailable(pending.callId, 'no_session');
        });
        return;
      }
      if (!matches || session.isFinished) {
        if (matches) {
          unawaited(notificationPlatform.clearAcceptedCall(action.callId));
        }
        _noticeCallUnavailable(
            action.callId, matches ? 'finished' : 'other_call');
        return;
      }
      if (session.direction != CallDirection.incoming) return;
      unawaited(notificationPlatform.clearAcceptedCall(session.id));
      if (session.state != CallState.ringing) {
        // Already accepted (duplicate action or in-app accept): just make
        // sure the call screen is shown.
        _requestCallScreen(session.id);
        return;
      }
      if (await store.isBlockedPeer(session.peerId)) {
        await rejectIncoming(reason: 'blocked');
        return;
      }
      AppLogger.info('CALL_ACCEPT_APPLIED',
          detail: 'call=${session.id} '
              'source=${_handoverCallId == session.id ? 'handover' : 'ring'}');
      // Request first so the session change that acceptIncoming() emits
      // already carries the request to the app.
      _requestCallScreen(session.id);
      try {
        await acceptIncoming();
      } catch (_) {}
      final after = _session;
      if (after == null || after.id != session.id || after.isFinished) {
        clearCallScreenRequest(session.id);
      }
      return;
    }

    // Reject
    unawaited(notificationPlatform.clearAcceptedCall(action.callId));
    if (!matches ||
        session.isFinished ||
        session.direction != CallDirection.incoming ||
        session.state != CallState.ringing) {
      return;
    }
    try {
      await rejectIncoming();
    } catch (_) {}
  }

  // Bundle 146: the app may show over the lock screen while a call is live
  // (incoming ringing, or any answered call). Before, cancelling the incoming
  // notification on accept dropped the call screen behind the lock screen.
  bool? _lastLockScreenShow;
  bool? _lastLockScreenTurnOn;

  void _syncCallLockScreen(CallSession? s) {
    final live = s != null && !s.isFinished;
    final ringingIn = live &&
        s.direction == CallDirection.incoming &&
        s.state == CallState.ringing;
    final show = live &&
        (s.direction == CallDirection.incoming || s.answeredAt != null);
    final turnOn = ringingIn;
    if (show == _lastLockScreenShow && turnOn == _lastLockScreenTurnOn) return;
    _lastLockScreenShow = show;
    _lastLockScreenTurnOn = turnOn;
    unawaited(notificationPlatform.setCallLockScreen(
        show: show, turnScreenOn: turnOn));
  }

  bool _signalTargetsThisSession(Map<String, dynamic> msg, CallSession session,
      {bool requireRemoteSender = false}) {
    final selfId = store.deviceId;
    if (selfId == null || selfId.isEmpty) return false;
    if (msg['call_id']?.toString() != session.id) return false;
    final sender = msg['sender_id']?.toString().trim() ?? '';
    final recipient = msg['recipient_id']?.toString().trim() ?? '';
    if (sender.isEmpty || recipient.isEmpty) return false;
    if (requireRemoteSender)
      return sender == session.peerId && recipient == selfId;
    return (sender == selfId && recipient == session.peerId) ||
        (sender == session.peerId && recipient == selfId);
  }

  Future<void> _handleAccept(Map<String, dynamic> msg) async {
    final session = _session;
    final callId = msg['call_id']?.toString() ?? '';
    // Bundle 172: an answer for a call that is over (cancelled before they
    // picked up) must never start the sound. Tell them it is over instead.
    if (session == null || session.id != callId || _isClosing(session)) {
      if (shouldReplyCallOver(live: session, callId: callId)) {
        _replyCallOver(msg, 'accept');
      }
      return;
    }
    if (session.direction != CallDirection.outgoing ||
        !_signalTargetsThisSession(msg, session, requireRemoteSender: true))
      return;
    try {
      _ringTimer?.cancel();
      // Bundle 162 (4.8): they answered — the screen shows 00:00 at once
      // instead of "Ringing…" while the sound starts.
      // Voice only (video is paused and left exactly as it was).
      if (session.answeredAt == null && !session.videoEnabled) {
        _setSession(session.copyWith(answeredAt: DateTime.now()));
      }
      final selectedCodec =
          msg['selected_media_codec']?.toString().trim().toLowerCase();
      if (_transport == null) {
        // Bundle 149: opus2 only if the receiver picked it AND we offered it.
        // The legacy 142-145 'opus' (or anything unknown) means PCM; the old
        // receiver's own native side falls back to PCM as well.
        final useOpus = selectedCodec == _opusCodec &&
            session.supportedMediaCodecs.contains(_opusCodec);
        final used = useOpus ? _opusCodec : _pcmCodec;
        if (selectedCodec != null && selectedCodec != used) {
          AppLogger.info('CALL_CODEC_FORCED',
              detail: 'selected=$selectedCodec used=$used');
        }
        final current = (_session ?? session).copyWith(mediaCodec: used);
        _setSession(current);
        // Bundle 159: lock only if the other phone agreed (older apps
        // don't send voice_lock and keep plain voice).
        if (msg['voice_lock'] != true) _voiceKeys.remove(session.id);
        AppLogger.info('CALL_VOICE_LOCK',
            detail: 'call=${session.id} locked=${_voiceKeys.containsKey(session.id)}');
        _transport = transportFactory.resolve(requested: current.transportMode);
        // Bundle 186 (A3): invite -> answer, answer -> our sound running.
        final audioWatch = Stopwatch()..start();
        await _transport!.start(current);
        final sentAt = _inviteSentAt;
        AppLogger.info('CALL_CONNECT_MS',
            detail: CallConnectTiming.line(
                callId: session.id,
                inviteToAcceptMs: sentAt == null || sentAt.$1 != session.id
                    ? null
                    : sentAt.$2.elapsedMilliseconds -
                        audioWatch.elapsedMilliseconds,
                acceptToAudioMs: audioWatch.elapsedMilliseconds));
      }
      await _markConnected();
    } catch (error, stackTrace) {
      final reason = callFailureReason(error);
      AppLogger.error('CALL_MEDIA_SETUP_FAILED',
          detail: 'reason=$reason', error: error, stackTrace: stackTrace);
      await _fail(reason);
    }
  }

  Future<void> _handleReject(Map<String, dynamic> msg) async {
    final session = _session;
    if (session == null ||
        !_signalTargetsThisSession(msg, session, requireRemoteSender: true))
      return;
    await _finishLocal(
        CallState.rejected,
        msg['reason']?.toString().isNotEmpty == true
            ? msg['reason'].toString()
            : 'rejected',
        notifyServer: false);
  }

  Future<void> _handleEnd(Map<String, dynamic> msg) async {
    final session = _session;
    if (session == null ||
        !_signalTargetsThisSession(msg, session, requireRemoteSender: true)) {
      // Bundle 172: "call ended" arrived before its invite (the newer
      // message left the queue first). Remember it so the late invite
      // never rings.
      final callId = msg['call_id']?.toString().trim() ?? '';
      final sender = msg['sender_id']?.toString().trim() ?? '';
      final selfId = store.deviceId?.trim() ?? '';
      if (callId.isNotEmpty &&
          sender.isNotEmpty &&
          selfId.isNotEmpty &&
          sender != selfId &&
          msg['recipient_id']?.toString().trim() == selfId) {
        _endedCalls.remember(callId);
        AppLogger.info('CALL_END_BEFORE_INVITE_REMEMBERED',
            detail: 'call=$callId');
      }
      return;
    }
    if (session.isFinished) {
      // Bundle 172: already over here — just confirm, never finish twice.
      _endedCalls.remember(session.id);
      unawaited(_sendSignal({
        'type': 'call_end_ack',
        'call_id': session.id,
        'recipient_id': session.peerId,
      }));
      return;
    }
    final reason = msg['reason']?.toString();
    // Bundle 146: tell the peer its call_end arrived so it stops resending.
    // Best-effort, never retried; older builds ignore the unknown type.
    unawaited(_sendSignal({
      'type': 'call_end_ack',
      'call_id': session.id,
      'recipient_id': session.peerId,
    }));
    // Bundle 174: an incoming call that stopped ringing before I answered
    // is a MISSED call (red in the Calls list), not a normal ended call.
    final missed = session.direction == CallDirection.incoming &&
        session.answeredAt == null;
    await _finishLocal(
        missed ? CallState.missed : CallState.ended,
        reason?.isNotEmpty == true ? reason! : (missed ? 'missed' : 'ended'),
        notifyServer: false);
  }

  Future<void> _handleNativeTransportEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString() ?? '';
    final session = _session;
    if (session != null &&
        !session.isFinished &&
        session.transportMode == CallTransportMode.offlineMesh) {
      final destination = event['destination_id']?.toString() ??
          event['mesh_destination_id']?.toString() ??
          event['peer_id']?.toString() ??
          '';
      final callId = event['call_id']?.toString();
      final eventTargets = destination == session.peerId &&
          (callId == null || callId.isEmpty || callId == session.id);
      // Only a call that was actually answered owns media-level reconnect
      // semantics. Pre-answer sessions (outgoing 'connecting', incoming
      // 'ringing') must NOT be flipped to 'reconnecting'/'connected' by
      // background mesh churn — that is how an unaccepted call ended up
      // showing "Reconnecting…" with phantom recovery attempts.
      if (eventTargets &&
          session.answeredAt != null &&
          (type == 'route_invalidated' ||
              type == 'route_removed' ||
              type == 'call_media_route_degraded')) {
        if (_mediaIsLive) {
          // Media packets arrived within the last few seconds, so this churn
          // is a native-side blip, not an outage. Keep the live call (and its
          // timer) on screen; refresh only the hop diagnostics.
          _recordRouteChurn(type);
          // Bundle 53: a degraded media event fires per ~20ms while Wi-Fi
          // Direct churns, and each one used to rebuild + rebroadcast the
          // whole session (heap churn on weak handsets). Only refresh when
          // the hop diagnostics actually changed.
          final churnNextHop = event['next_hop_id']?.toString();
          final churnHopCount = (event['hop_count'] as num?)?.toInt();
          if (churnNextHop != session.mediaNextHopId ||
              churnHopCount != session.mediaHopCount) {
            _setSession(session.copyWith(
              mediaNextHopId: churnNextHop,
              mediaHopCount: churnHopCount,
            ));
          }
        } else {
          _meshRouteRecoveryAttempts++;
          _meshRouteRecoveryTimer?.cancel();
          _setSession(session.copyWith(
            state: CallState.reconnecting,
            quality: CallQuality.reconnecting,
            recoveryAttempts: _meshRouteRecoveryAttempts,
            mediaNextHopId: event['next_hop_id']?.toString(),
            mediaHopCount: (event['hop_count'] as num?)?.toInt(),
          ));
          _meshRouteRecoveryTimer = Timer(const Duration(seconds: 10), () {
            final current = _session;
            if (current == null ||
                current.isFinished ||
                current.id != session.id ||
                current.transportMode != CallTransportMode.offlineMesh) return;
            _setSession(current.copyWith(quality: CallQuality.reconnecting));
          });
        }
      } else if (eventTargets && type == 'route_recovered') {
        if (session.answeredAt != null &&
            session.state == CallState.reconnecting) {
          _meshRouteRecoveryTimer?.cancel();
          _meshRouteRecoveryAttempts = 0;
          _setSession(session.copyWith(
              state: CallState.connected,
              quality: CallQuality.good,
              recoveryAttempts: 0,
              mediaNextHopId: event['next_hop_id']?.toString(),
              mediaHopCount: (event['hop_count'] as num?)?.toInt()));
          _queuePersistSession();
        } else if (session.direction == CallDirection.outgoing &&
            session.state == CallState.connecting) {
          // Route is back before the invite was acked: fire a resend now
          // instead of waiting out the 5s route-wait timer. The invite was
          // likely swallowed when the route dropped under it.
          unawaited(_trySendPendingInvite());
        }
      } else if (eventTargets && type == 'call_media_route_changed') {
        _setSession(session.copyWith(
          mediaNextHopId: event['next_hop_id']?.toString(),
          mediaHopCount: (event['hop_count'] as num?)?.toInt(),
          quality: session.state == CallState.reconnecting
              ? CallQuality.good
              : session.quality,
          state: session.state == CallState.reconnecting
              ? CallState.connected
              : session.state,
        ));
      }
      // WhatsApp-style switch-to-video sync. 'call_remote_video_started' is
      // raised natively when a peer's video frames arrive for an answered call
      // that has no local video session yet; we auto-spawn a receive-only
      // session (camera stays closed, no camera permission needed on this
      // device) so both screens flip to video on a single tap.
      if (eventTargets && type == 'call_remote_video_started') {
        AppLogger.info('CALL_REMOTE_VIDEO_STARTED',
            detail: 'call=${session.id}');
        if (!session.peerVideoActive) {
          _setSession(session.copyWith(peerVideoActive: true));
        }
        if (session.answeredAt != null &&
            session.remoteVideoTextureId == null &&
            !session.videoSwitchRequested) {
          // Suppressed while the switch-consent dialog is up: the Accept
          // action itself starts our side of video.
          unawaited(_acceptRemoteVideo(session));
        }
      }
      // Bundle 59: native drop ledger for inbound video packets (named reasons,
      // 2s summaries) plus decoder config failures -- the next capture names
      // exactly why peer video never paints.
      if (eventTargets && type == 'call_video_drop') {
        final reasons = event['reasons']?.toString() ?? '';
        AppLogger.warning('CALL_VIDEO_DROP',
            detail: 'call=${session.id} ${event['reasons']}');
        if (reasons != session.videoDropSummary) {
          _setSession(session.copyWith(videoDropSummary: reasons));
        }
      }
      if (eventTargets && type == 'call_video_decoder_error') {
        AppLogger.error('CALL_VIDEO_DECODER_ERROR',
            detail: 'call=${session.id} err=${event['error']}');
      }
      // Peer video rotation arrives alongside each codec config frame; keep the
      // display angle synced so a portrait-held phone stops stretching video.
      if (eventTargets && type == 'call_video_config_received') {
        final rot = (event['rotation'] as num?)?.toInt() ?? 0;
        final w = (event['width'] as num?)?.toInt() ?? 0;
        final h = (event['height'] as num?)?.toInt() ?? 0;
        if (!session.videoRemoteConfigured ||
            rot != session.remoteVideoRotation ||
            (w > 0 && w != session.remoteVideoWidth) ||
            (h > 0 && h != session.remoteVideoHeight)) {
          _setSession(session.copyWith(
            videoRemoteConfigured: true,
            remoteVideoRotation: rot,
            remoteVideoWidth: w > 0 ? w : session.remoteVideoWidth,
            remoteVideoHeight: h > 0 ? h : session.remoteVideoHeight,
          ));
        }
      }
      // Live RX counter for the on-screen diagnostics: proves frames actually
      // cross the wire even before the first decoded paint.
      if (eventTargets && type == 'call_video_received') {
        final next = session.videoRxFrames + 1;
        // Throttled: 30fps sessions would otherwise rebuild the overlay per
        // frame; the counter refreshes in bursts of five plus the first frame.
        if (next % 5 == 0 || session.videoRxFrames == 0) {
          _setSession(session.copyWith(
            videoRxFrames: next,
            videoRemoteConfigured: true, // frames are downstream of config
          ));
        }
      }
      if (eventTargets && type == 'call_video_started') {
        final w = (event['width'] as num?)?.toInt() ?? 0;
        final h = (event['height'] as num?)?.toInt() ?? 0;
        if (w > 0 && h > 0 &&
            (w != session.localVideoWidth || h != session.localVideoHeight)) {
          _setSession(session.copyWith(localVideoWidth: w, localVideoHeight: h));
        }
      }
      if (eventTargets && type == 'call_peer_video_state') {
        final on = event['enabled'] == true;
        if (session.peerVideoActive != on ||
            (on && !session.videoEnabled) ||
            (!on && (session.videoSwitchRequested || session.videoSwitchDeclined))) {
          AppLogger.info('CALL_PEER_VIDEO_STATE',
              detail: 'call=${session.id} enabled=$on');
          final askConsent = on &&
              session.answeredAt != null &&
              !session.videoEnabled &&
              !session.videoSwitchDeclined;
          _setSession(session.copyWith(
            peerVideoActive: on,
            // Ask once per peer-video-on episode; decline resets on peer-off.
            videoSwitchRequested:
                askConsent ? true : (!on ? false : session.videoSwitchRequested),
            videoSwitchDeclined: !on ? false : session.videoSwitchDeclined,
          ));
        }
      }
    }
    if (type != 'message') return;
    final raw = event['payload']?.toString();
    if (raw == null || raw.isEmpty) return;
    try {
      final msg = jsonDecode(raw);
      if (msg is Map<String, dynamic> &&
          (msg['type']?.toString().startsWith('call_') ?? false)) {
        final withDefaults = Map<String, dynamic>.from(msg);
        withDefaults['direct'] = true;
        withDefaults['mesh_call'] = true;
        withDefaults['sender_id'] ??= event['sender_id'];
        unawaited(_handleLocalCallSignal(withDefaults));
      }
    } catch (_) {}
  }

  Future<void> _handleInviteAck(Map<String, dynamic> msg) async {
    final session = _session;
    final selfId = store.deviceId;
    // Bundle 172: their phone rings for a call that is over here (a late
    // invite from the send queue) — tell it to stop at once.
    final ackCallId = msg['call_id']?.toString() ?? '';
    if (msg['status']?.toString() == 'ringing' &&
        (session == null || session.id != ackCallId || session.isFinished) &&
        shouldReplyCallOver(live: session, callId: ackCallId)) {
      _replyCallOver(msg, 'ringing');
      return;
    }
    if (session == null ||
        selfId == null ||
        session.id != msg['call_id']?.toString() ||
        session.direction != CallDirection.outgoing ||
        msg['sender_id']?.toString() != session.peerId ||
        msg['recipient_id']?.toString() != selfId) return;
    if (msg['status']?.toString() != 'ringing') return;
    // Signals travel on TWO unordered paths (direct mesh + server relay), so a
    // duplicate invite_ack can land AFTER the accept. Without this guard the
    // caller's screen visibly regressed to 'Ringing…' for seconds mid-call.
    if (session.answeredAt != null ||
        session.state == CallState.connected ||
        session.state == CallState.reconnecting) {
      AppLogger.info('CALL_INVITE_ACK_LATE_IGNORED',
          detail: 'call=${session.id}');
      return;
    }
    AppLogger.info('CALL_INVITE_ACK_RECEIVED', detail: 'call=${session.id}');
    // Bundle 266 (A3): first invite -> their phone rings, and which way.
    final ringSentAt = _inviteSentAt;
    if (ringSentAt != null && ringSentAt.$1 == session.id) {
      AppLogger.info('CALL_RING_MS',
          detail: 'call=${session.id} ms=${ringSentAt.$2.elapsedMilliseconds} '
              'via=${msg['server'] == true ? 'server' : 'mesh'}');
    }
    _stopRouteWaitTimer();
    _setSession(session.copyWith(state: CallState.ringing, signalingConnected: true));
    _startRingTimer(outgoing: true);
    _startRingAliveSend295(session.id);
    // WhatsApp-style ringback: the peer's phone is now actually ringing, so
    // let the caller hear it too. Stops on answer/end in _markConnected /
    // _finishLocal.
    unawaited(ringtone.startRingback(session.id));
    await _persistSession();
  }

  void _handleRouteChange(LocalRouteResult route) {
    // Bundle 266 (D1): a nearby way to the friend who calls through the
    // server is there - the wake has done its job.
    final wake = CallNearbyWait.instance;
    if (route.isAvailable &&
        wake.wakeCallId != null &&
        wake.peerId == route.peerId &&
        !_disposed) {
      _wakeTimer?.cancel();
      _wakeTimer = null;
      wake.stopWake('route');
    }
    final session = _session;
    if (_disposed ||
        !route.isAvailable ||
        session == null ||
        session.isFinished ||
        session.direction != CallDirection.outgoing ||
        session.state != CallState.connecting ||
        route.peerId != session.peerId) {
      return;
    }
    // Bundle 225 (P1): a link (LAN, Wi-Fi Direct or mesh) is back.
    // Bundle 295 (G1): not for a call that proved the way dead (only an
    // answer from the friend ends that wait).
    if (CallNearbyWait.instance.waitingFor(session.id) &&
        !_unproven295.contains(session.id)) {
      CallNearbyWait.instance.stop('route');
    }
    unawaited(_trySendPendingInvite());
  }

  Future<void> _trySendPendingInvite() async {
    final session = _session;
    if (_disposed ||
        _inviteInFlight ||
        session == null ||
        session.isFinished ||
        session.direction != CallDirection.outgoing ||
        session.state != CallState.connecting) {
      return;
    }
    final now = DateTime.now();
    final lastAttempt = _lastInviteAttemptAt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 5)) {
      return;
    }
    LocalRouteResult? route;
    try {
      route = await routePolicy.resolve(session.peerId);
    } catch (error, stackTrace) {
      AppLogger.error(
        'CALL_ROUTE_RESOLUTION_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    // No usable route right now? Still attempt the send. The native mesh
    // router queues signaling when the peer is down and flushes the moment a
    // link appears (LAN beacon, Wi-Fi Direct reconnect, multi-hop), which —
    // combined with the 5s route-wait resend — makes invites resilient to
    // link flapping instead of silently never leaving this device.
    final routeAvailable = route.isAvailable;
    // Bundle 295 (G1): a way the call already proved dead is not a way.
    final unproven = _unproven295.contains(session.id);
    final latest = _session;
    if (latest != null && latest.id == session.id) {
      _syncAwayCall(latest, routeAvailable: routeAvailable && !unproven);
    }
    if (!routeAvailable) {
      AppLogger.info(
        'CALL_WAITING_FOR_ROUTE',
        detail: 'state=${route.transportState.name} — queueing invite anyway',
      );
    }
    _inviteInFlight = true;
    _lastInviteAttemptAt = now;
    try {
      // Bundle 266 (B1): the call key from the link key (both phones can
      // work it out, so a call that rings through the server talks locked).
      await _prepareVoiceKey266(session);
      final invite = <String, dynamic>{
        'type': 'call_invite',
        'call_id': session.id,
        'recipient_id': session.peerId,
        'created_at': now.toUtc().toIso8601String(),
        'transport_mode': session.transportMode.wireName,
        'mesh_call': true,
        'direct': true,
        'supported_media_codecs': <String>[
          ...session.supportedMediaCodecs,
          if (_derivedKeys.containsKey(session.id)) CallVoiceKey266.marker,
        ],
        // Bundle 172: an invite waits in the send queue 60 s at most, so a
        // cancelled call never rings hours later.
        queueLifetimeField: inviteQueueLifetime.inMilliseconds,
        // Bundle 295 (A): this caller repeats while it calls.
        ringAliveField295: true,
        // Bundle 159: locks the call sound (travels only inside a sealed
        // invite; SealingPeerTransport drops it otherwise).
        if (_voiceKeyForInvite(session) case final key?)
          SealingPeerTransport.voiceKeyField: key,
      };
      await _sendSignal(invite);
      // Bundle 266 (A1): and through the server (once per call), so a
      // friend the server reaches rings now whatever the nearby state.
      _sendInviteViaServer266(session.id, invite);
      _lastInvite295 = invite;
      // Bundle 295 (B): say whether a way was there and whether it is
      // proven: a direct link is (its own heartbeat), a stored mesh way is
      // not until the friend answers.
      final mesh = route.kind == LocalRouteKind.mesh;
      final way = !routeAvailable
          ? 'none'
          : (unproven || mesh ? 'unproven' : 'ok');
      AppLogger.info('CALL_INVITE_SENT', detail: 'transport=${route.kind.name} queued=${!routeAvailable} route=$way');
      // Bundle 295 (G1): first invite on a stored mesh way -> 6 s for the
      // answer.
      if (routeAvailable && mesh && !unproven && _proofArmedFor295 != session.id) {
        _proofArmedFor295 = session.id;
        _proofTimer295?.cancel();
        final id = session.id;
        _proofTimer295 = Timer(proofWait295, () => unawaited(_onProofTimeout295(id)));
      }
      // Bundle 186 (A3): first invite of this call (repeats keep the time).
      if (_inviteSentAt?.$1 != session.id) {
        _inviteSentAt = (session.id, Stopwatch()..start());
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'CALL_INVITE_SEND_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _inviteInFlight = false;
    }
  }

  void _startRouteWaitTimer() {
    _routeWaitTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_trySendPendingInvite()),
    );
  }

  void _stopRouteWaitTimer() {
    _routeWaitTimer?.cancel();
    _routeWaitTimer = null;
  }

  Future<void> _handleState(Map<String, dynamic> msg) async {
    final session = _session;
    if (session == null ||
        session.id != msg['call_id']?.toString() ||
        !_signalTargetsThisSession(msg, session)) return;
    final status = msg['status']?.toString() ?? '';
    final reason = msg['reason']?.toString() ?? '';
    // Bundle 266: a call that is over here stays over (late server copies).
    if (session.isFinished) return;
    // Bundle 266: the server's own timeouts never end a call that still
    // talks nearby (or whose sound is arriving).
    if (msg['server'] == true &&
        (reason == 'heartbeat_timeout' || reason == 'server_timeout')) {
      var nearby = _mediaIsLive;
      if (!nearby) {
        try {
          nearby = await _hasLocalRouteTo(session.peerId);
        } catch (_) {}
      }
      if (nearby) {
        AppLogger.info('CALL_SERVER_STATE_IGNORED',
            detail: 'call=${session.id} status=$status reason=$reason');
        return;
      }
    }
    if (status == 'connected') {
      // Bundle 172: never start the sound for a call that is over.
      if (_isClosing(session)) return;
      if (session.direction == CallDirection.outgoing &&
          session.state != CallState.connected) {
        // Bundle 266: answered through the server - codec + lock first.
        if (_transport == null &&
            msg['server'] == true &&
            !await _serverAnswer266(session)) {
          return;
        }
        final current = _session;
        if (current == null || current.id != session.id || _isClosing(current)) {
          return;
        }
        await transportFactory.ensureReady();
        if (_transport == null) {
          _transport =
              transportFactory.resolve(requested: current.transportMode);
          await _transport!.start(current);
        }
        await _markConnected();
      } else if (session.direction == CallDirection.incoming &&
          session.state != CallState.connected) {
        // Bundle 266: our answer is still starting; it connects by itself.
        if (_acceptingCallId == session.id) return;
        await _markConnected();
      }
      return;
    }
    if (status == 'reconnecting') {
      if (session.answeredAt != null && _mediaIsLive) {
        _recordRouteChurn('peer_status_reconnecting');
        _setSession(session.copyWith(quality: CallQuality.reconnecting));
      } else {
        _setSession(session.copyWith(
            state: CallState.reconnecting, quality: CallQuality.reconnecting));
      }
      return;
    }
    if (status == 'rejected') {
      await _finishLocal(
          CallState.rejected, reason.isEmpty ? 'rejected' : reason,
          notifyServer: false);
      return;
    }
    if (status == 'missed') {
      await _finishLocal(CallState.missed, reason.isEmpty ? 'missed' : reason,
          notifyServer: false);
      return;
    }
    if (status == 'canceled') {
      await _finishLocal(
          CallState.canceled, reason.isEmpty ? 'canceled' : reason,
          notifyServer: false);
      return;
    }
    if (status == 'failed') {
      await _finishLocal(CallState.failed, reason.isEmpty ? 'failed' : reason,
          notifyServer: false);
      return;
    }
    if (status == 'ended')
      await _finishLocal(CallState.ended, reason.isEmpty ? 'ended' : reason,
          notifyServer: false);
  }

  Future<void> _sendSignal(Map<String, dynamic> msg) async {
    final recipient = msg['recipient_id']?.toString().trim();
    if (recipient == null || recipient.isEmpty) return;
    // No-op for non-lifecycle types (see _lifecycleRetryTypes).
    _enqueueLifecycleRetry(msg);
    try {
      await transportFactory.ensureReady();
      AppLogger.info('CALL_SIGNAL_SEND', detail: 'type=${msg['type']} call=${msg['call_id'] ?? ''}');
      await transportFactory.nativeMesh
          .sendControl(recipientId: recipient, payload: {
        ...msg,
        'sender_id': store.deviceId,
        'direct': true,
        'mesh_call': true,
        'transport_mode': CallTransportMode.offlineMesh.wireName,
      });
      // Bundle 266 (A2): a call the server knows hears it there too.
      _copyToServer266(msg);
    } catch (error) {
      // Wi-Fi Direct peers flap constantly (see peer_connected/disconnected
      // churn in DIRECT_EVENT logs). A heartbeat landing while the peer is
      // momentarily down is transient — swallow with a log; the next tick or
      // the recovery loop heals it. Lifecycle signals are different: losing
      // them while the direct link is down leaves the peer holding a ghost
      // call (observed in production logs), so relay them via the server WS.
      final type = msg['type']?.toString() ?? '';
      const relayable = {
        'call_invite',
        'call_invite_ack',
        'call_accept',
        'call_reject',
        'call_busy',
        'call_end',
      };
      final ws = socket;
      if (relayable.contains(type) && ws != null && ws.isConnected) {
        // Bundle 159: the voice key never goes to the server.
        final relayed = ws.send({
          ...Map<String, dynamic>.from(msg)
            ..remove(SealingPeerTransport.voiceKeyField),
          'sender_id': store.deviceId,
          'transport_mode': CallTransportMode.offlineMesh.wireName,
        });
        if (relayed) {
          // Bundle 266 (A1): the server knows this call now.
          final relayedId = msg['call_id']?.toString() ?? '';
          if (type == 'call_invite') {
            _addBounded(_serverInviteSent, relayedId);
            _markServerKnown(relayedId);
          } else if (_serverKnown.contains(relayedId)) {
            _addBounded(_serverCopied, '$type|$relayedId', 128);
          }
          AppLogger.warning(
            'CALL_SIGNAL_RELAYED',
            detail: 'type=$type call=${msg['call_id'] ?? ''} '
                'via=server reason=mesh_down error=$error',
          );
          return;
        }
      }
      AppLogger.warning(
        'CALL_SIGNAL_SEND_FAILED',
        detail:
        'type=${msg['type']} call=${msg['call_id'] ?? ''} error=$error',
      );
    }
  }

  Future<void> _recoverLostMeshTransport(
      CallSession active, String? reason) async {
    final live = _session;
    if (live?.id != active.id || active.isFinished) return;
    // Transport 'failed' can arrive while endCall() is already tearing the
    // session down; recovering here resurrects a call the user just ended.
    if (live != null && _isClosing(live)) return;
    final localStillAvailable = await _hasLocalRouteTo(active.peerId);
    if (!localStillAvailable) {
      // Bundle 266 (B4): the call can talk through the server - keep it.
      final now = _session;
      if (now != null && now.id == active.id && _serverVoiceAllowed(now)) {
        AppLogger.info('CALL_SERVER_VOICE_KEEP',
            detail: 'call=${active.id} reason=${reason ?? '-'}');
        return;
      }
      await _fail(reason ?? 'mesh_route_failed');
      return;
    }
    final current = _session;
    final oldTransport = _transport;
    if (current == null || _isClosing(current)) return;
    _setSession(current.copyWith(
        state: CallState.reconnecting, quality: CallQuality.reconnecting));
    try {
      if (oldTransport != null) await oldTransport.stop(current);
      final next =
          transportFactory.resolve(requested: CallTransportMode.offlineMesh);
      _transport = next;
      await next.start(current.copyWith(state: CallState.connecting));
      await _markConnected();
    } catch (_) {
      await _fail('mesh_transport_recovery_failed');
    }
  }

  void _onTransportState(CallSession session, String state, String? reason) {
    if (_session?.id != session.id || _disposed) return;
    switch (state) {
      case 'connected':
        unawaited(_markConnected());
        break;
      case 'reconnecting':
        final current = _session!;
        if (_isClosing(current)) return;
        if (current.answeredAt != null && _mediaIsLive) {
          _recordRouteChurn('transport_reconnecting');
          _setSession(current.copyWith(quality: CallQuality.reconnecting));
        } else {
          _setSession(current.copyWith(
              state: CallState.reconnecting,
              quality: CallQuality.reconnecting,
              reason: reason ?? current.reason));
          _queuePersistSession();
        }
        break;
      case 'failed':
        final active = _session;
        if (active != null && _isClosing(active)) return;
        if (active != null &&
            active.transportMode == CallTransportMode.offlineMesh) {
          unawaited(_recoverLostMeshTransport(active, reason));
        } else {
          unawaited(_fail(reason ?? 'transport_failed'));
        }
        break;
    }
  }

  Future<void> _markConnected() async {
    final session = _session;
    if (session == null || _isClosing(session)) return;
    _ringTimer?.cancel();
    unawaited(ringtone.stopRingback());
    _recoveryAttempts = 0;
    _setSession(session.copyWith(
        state: CallState.connected,
        answeredAt: session.answeredAt ?? DateTime.now(),
        quality: CallQuality.excellent,
        recoveryAttempts: 0));
    await _persistSession();
    _startHeartbeatTimer();
    _startStatsTimer();
    unawaited(_syncServerVoice266()); // Bundle 266 (B)
  }

  Future<void> _fail(String reason) async {
    final session = _session;
    if (session == null || session.isFinished) return;
    unawaited(_sendSignal({
      'type': 'call_end',
      'call_id': session.id,
      'recipient_id': session.peerId,
      'reason': 'failed'
    }));
    await _finishLocal(CallState.failed, reason, notifyServer: false);
  }

  Future<void> _finishLocal(CallState state, String reason,
      {required bool notifyServer}) async {
    final session = _session;
    if (session == null) return;
    _cancelCallTimers();
    unawaited(ringtone.stopRingback());
    final endedAt = DateTime.now();
    _persistTimer?.cancel();
    _persistPending = false;
    final lastSample = _lastQualitySample;
    _lastQualitySample = null;
    if (lastSample != null) {
      unawaited(store.saveCallQualitySample(lastSample));
    }
    final next =
        session.copyWith(state: state, endedAt: endedAt, reason: reason);
    // Bundle 172: a late copy of this call's invite never rings again.
    _endedCalls.remember(session.id);
    _setSession(next);
    await _persistSession();
    try {
      if (_transport != null) await _transport!.stop(session);
    } catch (_) {}
    _transport = null;
    _voiceKeys.remove(session.id);
    _derivedKeys.remove(session.id); // Bundle 266
    unawaited(_syncServerVoice266());
    if (notifyServer)
      unawaited(_sendSignal({
        'type': 'call_end',
        'call_id': session.id,
        'recipient_id': session.peerId,
        'reason': reason
      }));
    unawaited(syncHistory());
  }

  Future<void> _collectStats() async {
    final session = _session;
    final transport = _transport;
    if (session == null || session.isFinished || transport == null) return;
    try {
      final stats = await transport.stats(session);
      final loss = (stats['packet_loss_percent'] as num?)?.toDouble();
      final quality = _qualityFor(
        stats['connection_state']?.toString() ??
            (session.transportMode == CallTransportMode.offlineMesh
                ? 'mesh'
                : 'unknown'),
        stats['transport_state']?.toString() ??
            (session.transportMode == CallTransportMode.offlineMesh
                ? 'mesh'
                : 'unknown'),
        loss,
        (stats['rtt_ms'] as num?)?.toDouble(),
        (stats['jitter_ms'] as num?)?.toDouble(),
      );
      final sample = CallQualitySample(
        callId: session.id,
        sampledAt: DateTime.now(),
        connectionState: stats['connection_state']?.toString() ??
            stats['transport']?.toString() ??
            'unknown',
        transportState: stats['transport_state']?.toString() ??
            stats['transport']?.toString() ??
            'unknown',
        rttMs: (stats['rtt_ms'] as num?)?.toDouble(),
        jitterMs: (stats['jitter_ms'] as num?)?.toDouble(),
        packetsLost: _asInt(stats['packets_lost'] ?? stats['lost_packets']),
        packetsReceived:
            _asInt(stats['packets_received'] ?? stats['received_packets']),
        packetLossPercent: loss,
        quality: quality.name,
      );
      // Bundle 61: samples fire every second during a call. Writing each one
      // through the serialized SQLCipher queue was the engine behind the
      // 50-90s STORE_OP_SLOW pileups on weak handsets; keep them in memory
      // and persist exactly one at call end instead.
      _lastQualitySample = sample;
      final hadRxCounter = stats.containsKey('packets_received') ||
          stats.containsKey('received_packets');
      final rxNow =
          _asInt(stats['packets_received'] ?? stats['received_packets']);
      final latest = _session;
      if (latest != null && latest.id == session.id && !latest.isFinished) {
        var recovering = false;
        if (hadRxCounter) {
          if (_lastMediaPacketsReceived >= 0 &&
              rxNow > _lastMediaPacketsReceived) {
            _lastMediaRxAt = DateTime.now();
            recovering = latest.state == CallState.reconnecting;
          }
          _lastMediaPacketsReceived = rxNow;
        }
        if (recovering) {
          // Media is provably flowing again — drop the phantom reconnecting
          // state instead of waiting for a route_recovered event that may
          // never arrive on this transport.
          AppLogger.info('MEDIA_LIVE_RECOVERED',
              detail: 'call=${latest.id} rx_packets=$rxNow');
          _meshRouteRecoveryAttempts = 0;
          _meshRouteRecoveryTimer?.cancel();
          _setSession(latest.copyWith(
              state: CallState.connected,
              quality: quality,
              qualitySample: sample,
              recoveryAttempts: 0));
          _queuePersistSession();
        } else {
          _setSession(latest.copyWith(quality: quality, qualitySample: sample));
        }
      }
    } catch (_) {}
  }

  CallQuality _qualityFor(String connection, String transportState,
      double? loss, double? rtt, double? jitter) {
    if (connection.toLowerCase().contains('disconnected') ||
        connection.toLowerCase().contains('failed') ||
        transportState.toLowerCase().contains('disconnected') ||
        transportState.toLowerCase().contains('failed'))
      return CallQuality.reconnecting;
    final l = loss ?? 0;
    final rr = rtt ?? 0;
    final j = jitter ?? 0;
    if (l >= 5 || rr >= 300 || j >= 30) return CallQuality.poor;
    if (l >= 2 || rr >= 200 || j >= 15) return CallQuality.fair;
    if (l >= 1 || rr >= 120 || j >= 8) return CallQuality.good;
    if (loss == null && rtt == null && jitter == null)
      return CallQuality.unknown;
    return CallQuality.excellent;
  }

  int _asInt(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    final active = _session;
    if (active == null || _isClosing(active)) return;
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _sendHeartbeat());
  }

  void _sendHeartbeat() {
    final session = _session;
    if (session == null || _isClosing(session)) return;
    // Bundle 266: the server hears from a call it knows (else it ends it
    // after 60 s), and server voice turns on once the socket is back.
    _serverHeartbeat266(session);
    unawaited(_syncServerVoice266());
    unawaited(() async {
      // Bundle 129: heartbeat ticks used to throw PlatformException
      // (PEER_UNAVAILABLE) every 15 s whenever the mesh route was momentarily
      // down — caught downstream, but it halted debuggers and spammed
      // CALL_SIGNAL_SEND_FAILED. Skip silently instead; the recovery loop
      // owns healing a missing link.
      if (!await _hasLocalRouteTo(session.peerId)) {
        AppLogger.info(
          'CALL_HEARTBEAT_SKIPPED',
          detail: 'call=${session.id} reason=no_local_route',
        );
        return;
      }
      await _sendSignal({
        'type': 'call_heartbeat',
        'call_id': session.id,
        'recipient_id': session.peerId
      });
    }());
  }

  void _handleHeartbeatAck(Map<String, dynamic> msg) {
    final session = _session;
    if (session == null || session.id != msg['call_id']?.toString()) return;
    if (!session.signalingConnected)
      _setSession(session.copyWith(signalingConnected: true));
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    final session = _session;
    if (session == null || session.isFinished) return;
    _statsTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => unawaited(_collectStats()));
    unawaited(_collectStats());
  }

  /// A call that is ending or is already in a terminal state must not be
  /// re-armed by late transport events. `ending` is deliberately included:
  /// the local user already hung up, so the recovery loop, reconnect handler
  /// and heartbeat timer must stand down instead of resurrecting the call.
  bool _isClosing(CallSession session) =>
      session.isFinished || session.state == CallState.ending;

  /// Bundle 172: "that call is over" — answer to a late ring/answer for a
  /// call that is not happening here, so the other phone stops at once.
  /// At most once per call every 10 s; never to ourselves.
  void _replyCallOver(Map<String, dynamic> msg, String why) {
    final callId = msg['call_id']?.toString().trim() ?? '';
    final sender = msg['sender_id']?.toString().trim() ?? '';
    final selfId = store.deviceId?.trim() ?? '';
    if (callId.isEmpty || sender.isEmpty || selfId.isEmpty) return;
    if (sender == selfId) return;
    if (msg['recipient_id']?.toString().trim() != selfId) return;
    final now = DateTime.now();
    _callOverRepliedAt.removeWhere(
        (_, at) => now.difference(at) > const Duration(seconds: 30));
    final last = _callOverRepliedAt[callId];
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _callOverRepliedAt[callId] = now;
    _endedCalls.remember(callId);
    AppLogger.info('CALL_OVER_REPLIED', detail: 'call=$callId why=$why');
    unawaited(_sendSignal({
      'type': 'call_end',
      'call_id': callId,
      'recipient_id': sender,
      'reason': 'canceled',
    }));
  }

  // ------------------------------------------------ Bundle 205 (P7)
  /// Calls go over nearby ways only: "Reconnecting…" for at most this long
  /// without any nearby way, then "Call ended: no nearby connection".
  static const Duration noNearbyAfter = Duration(seconds: 20);
  Timer? _noNearbyTimer;
  String? _noNearbyCallId;

  bool _waitingForNearby(CallSession s) =>
      !_isClosing(s) &&
      s.answeredAt != null &&
      (s.state == CallState.reconnecting ||
          s.quality == CallQuality.reconnecting);

  void _syncNoNearbyTimer(CallSession? s) {
    if (s == null || _disposed || !_waitingForNearby(s)) {
      _noNearbyTimer?.cancel();
      _noNearbyTimer = null;
      _noNearbyCallId = null;
      return;
    }
    if (_noNearbyTimer != null && _noNearbyCallId == s.id) return;
    _noNearbyTimer?.cancel();
    _noNearbyCallId = s.id;
    final callId = s.id;
    _noNearbyTimer =
        Timer(noNearbyAfter, () => unawaited(_onNoNearbyTimer(callId)));
  }

  Future<void> _onNoNearbyTimer(String callId) async {
    _noNearbyTimer = null;
    final s = _session;
    if (s == null || s.id != callId || _disposed || !_waitingForNearby(s)) {
      _noNearbyCallId = null;
      return;
    }
    var route = false;
    try {
      route = await _hasLocalRouteTo(s.peerId);
    } catch (_) {}
    final now = _session;
    if (now == null || now.id != callId || !_waitingForNearby(now)) {
      _noNearbyCallId = null;
      return;
    }
    // Bundle 266 (B4): the voice comes through the server - not ended.
    final viaServer = !route && _serverVoiceRunning(now);
    if (route || viaServer) {
      // A nearby way is there; the recovery may still make it. Wait again.
      AppLogger.info('CALL_NO_NEARBY_WAIT',
          detail: 'call=$callId reason=${viaServer ? 'server_voice' : 'route_present'}');
      _noNearbyCallId = null;
      _syncNoNearbyTimer(now);
      return;
    }
    AppLogger.info('CALL_NO_NEARBY_END',
        detail: 'call=$callId waited_s=${noNearbyAfter.inSeconds}');
    await endCall(reason: 'no_nearby_connection');
  }

  void _cancelCallTimers() {
    // Bundle 295 (A/G1)
    _ringAliveWatch295?.cancel();
    _ringAliveWatch295 = null;
    _ringAliveSend295?.cancel();
    _ringAliveSend295 = null;
    _proofTimer295?.cancel();
    _proofTimer295 = null;
    _noNearbyTimer?.cancel();
    _noNearbyTimer = null;
    _noNearbyCallId = null;
    _ringTimer?.cancel();
    _statsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _meshRouteRecoveryTimer?.cancel();
    _connectWatchdogTimer?.cancel();
    _stopRouteWaitTimer();
    _ringTimer = null;
    _statsTimer = null;
    _heartbeatTimer = null;
    _meshRouteRecoveryTimer = null;
    _connectWatchdogTimer = null;
  }

  Future<void> _persistSession() async {
    final session = _session;
    final self = store.deviceId;
    if (session == null || self == null) return;
    await LocalStore.timedOp(
        'call_save', () => store.saveCall(session.toRecord(self)));
  }

  // Bundle 61: route/recovery paths fire this on every mesh event; coalesce
  // to one trailing write per 3s so the DB queue never piles up mid-call.
  Timer? _persistTimer;
  bool _persistPending = false;

  void _queuePersistSession() {
    _persistPending = true;
    if (_persistTimer?.isActive == true) return;
    _persistTimer = Timer(const Duration(seconds: 3), () {
      _persistTimer = null;
      if (!_persistPending || _disposed) return;
      _persistPending = false;
      unawaited(_persistSession());
    });
  }

  void _setSession(CallSession? session) {
    final previous = _session;
    _session = session;
    if (!_sessionController.isClosed) _sessionController.add(session);
    final wasRinging = previous != null &&
        previous.direction == CallDirection.incoming &&
        previous.state == CallState.ringing;
    final isRinging = session != null &&
        session.direction == CallDirection.incoming &&
        session.state == CallState.ringing;
    // Bundle 176 (3): answered, declined, missed or ended - nothing to hand over.
    if (wasRinging && (!isRinging || previous.id != session.id)) {
      unawaited(handover?.clear(previous.id));
    }
    if (isRinging && (!wasRinging || previous?.id != session.id)) {
      final revision = ++_presentationRevision;
      unawaited(_presentIncomingCall(session, revision));
    } else if (!isRinging && (wasRinging || session == null)) {
      final revision = ++_presentationRevision;
      unawaited(_clearIncomingPresentation(revision));
    }
    _syncCallUi(session);
    _syncCallLockScreen(session);
    _syncNoNearbyTimer(session);
    _syncAwayCallState(session);
    _syncWake266(session); // Bundle 266 (D1)
    final pending = _pendingNotificationAccept;
    if (pending != null &&
        isRinging &&
        session.id == pending.callId &&
        session.peerId == pending.callerId) {
      _clearPendingNotificationAccept();
      scheduleMicrotask(() => unawaited(_handleNotificationAction(pending)));
    }
  }

  // Bundle 143: proximity screen-off + call-volume keys follow the session.
  bool? _callUiInCall;
  bool? _callUiProximity;

  void _syncCallUi(CallSession? s) {
    final live = s != null &&
        !s.isFinished &&
        s.state != CallState.ending &&
        // An incoming call still ringing is not "on the call" yet: volume
        // keys stay on the ringer and the screen stays on to answer.
        !(s.direction == CallDirection.incoming &&
            s.state == CallState.ringing);
    // Ear-to-phone only: never blank the screen on speaker or any video.
    final proximity = live &&
        !s.videoEnabled &&
        !s.peerVideoActive &&
        !s.speakerOn;
    if (live == _callUiInCall && proximity == _callUiProximity) return;
    _callUiInCall = live;
    _callUiProximity = proximity;
    unawaited(audioPlatform
        .setCallUi(inCall: live, proximity: proximity)
        .catchError((Object _) {}));
  }

  /// Bundle 143: video is watched, not held to the ear — move to the
  /// loudspeaker once when video starts (either side). The user can still
  /// switch back with the speaker button.
  Future<void> _speakerForVideo() async {
    final session = _session;
    if (session == null || session.isFinished || session.speakerOn) return;
    try {
      await audioPlatform.setSpeakerphoneOn(true);
      final latest = _session;
      if (latest != null && latest.id == session.id) {
        _setSession(latest.copyWith(speakerOn: true));
      }
    } catch (_) {}
  }

  Future<void> _presentIncomingCall(CallSession session, int revision) async {
    if (_disposed || revision != _presentationRevision) return;
    try {
      await ringtone.start(session.id);
    } catch (_) {}
    if (_disposed || revision != _presentationRevision) return;
    try {
      if (_appInForeground)
        await notificationPlatform.cancelIncoming();
      else
        await notificationPlatform.showIncoming(
            callId: session.id,
            callerId: session.peerId,
            callerName: session.peerName);
    } catch (_) {}
  }

  Future<void> _clearIncomingPresentation(int revision) async {
    if (revision != _presentationRevision) return;
    await ringtone.stop();
    if (revision != _presentationRevision) return;
    await notificationPlatform.cancelIncoming();
  }

  Future<void> _synchronizeIncomingPresentation() async {
    final session = _session;
    final revision = ++_presentationRevision;
    if (session != null &&
        session.direction == CallDirection.incoming &&
        session.state == CallState.ringing)
      await _presentIncomingCall(session, revision);
    else
      await _clearIncomingPresentation(revision);
  }

  /// Bundle 295 (A): the called phone watches the caller's repeats.
  void _armRingAlive295(Map<String, dynamic> msg, String callId) {
    _ringAliveWatch295?.cancel();
    _ringAliveWatch295 = null;
    // An older caller does not repeat after "Ringing…": its call rings 30 s.
    if (msg[ringAliveField295] != true) return;
    // The server knows the call: its end arrives through the server.
    if (msg['server'] == true || _serverKnown.contains(callId)) return;
    _ringAliveWatch295 =
        Timer(ringAliveLimit295, () => _onRingAliveLost295(callId));
  }

  void _onRingAliveLost295(String callId) {
    _ringAliveWatch295 = null;
    final session = _session;
    if (_disposed ||
        session == null ||
        session.id != callId ||
        session.isFinished ||
        session.direction != CallDirection.incoming ||
        session.state != CallState.ringing ||
        _serverKnown.contains(callId)) return;
    AppLogger.info('CALL_RING_ALIVE_LOST',
        detail: 'call=$callId after_s=${ringAliveLimit295.inSeconds}');
    unawaited(_sendSignal({
      'type': 'call_end',
      'call_id': session.id,
      'recipient_id': session.peerId,
      'reason': 'missed'
    }));
    unawaited(_finishLocal(CallState.missed, 'missed', notifyServer: false));
  }

  /// Bundle 295 (A): the caller repeats the invite every 5 s while their
  /// phone rings (the called phone ignores the copies).
  void _startRingAliveSend295(String callId) {
    _ringAliveSend295?.cancel();
    _ringAliveSend295 = null;
    final invite = _lastInvite295;
    if (invite == null || invite['call_id']?.toString() != callId) return;
    _ringAliveSend295 = Timer.periodic(ringAliveEvery295, (timer) {
      final s = _session;
      if (_disposed ||
          s == null ||
          s.id != callId ||
          s.isFinished ||
          s.direction != CallDirection.outgoing ||
          s.state != CallState.ringing ||
          s.answeredAt != null) {
        timer.cancel();
        if (identical(_ringAliveSend295, timer)) _ringAliveSend295 = null;
        return;
      }
      unawaited(_sendSignal(<String, dynamic>{
        ...invite,
        ringAliveRepeatField295: true,
      }));
    });
  }

  /// Bundle 295 (G1): 6 s after the first invite on a stored way.
  Future<void> _onProofTimeout295(String callId) async {
    _proofTimer295 = null;
    bool stillCalling(CallSession? s) =>
        !_disposed &&
        s != null &&
        s.id == callId &&
        !s.isFinished &&
        s.direction == CallDirection.outgoing &&
        s.state == CallState.connecting &&
        !s.signalingConnected &&
        s.answeredAt == null;
    final session = _session;
    if (!stillCalling(session)) return;
    var dropped = false;
    try {
      dropped = await (routeUnproven295?.call(session!.peerId) ??
          Future<bool>.value(false));
    } catch (_) {}
    AppLogger.info('CALL_ROUTE_UNPROVEN',
        detail: 'call=$callId after_ms=${proofWait295.inMilliseconds} '
            'dropped=${dropped ? 1 : 0}');
    final latest = _session;
    if (!dropped || !stillCalling(latest)) return;
    _addBounded(_unproven295, callId, 16);
    _syncAwayCall(latest!, routeAvailable: false);
  }

  void _startRingTimer({required bool outgoing}) {
    _ringTimer?.cancel();
    _statsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _ringTimer = Timer(Duration(seconds: outgoing ? 35 : 30), () {
      final session = _session;
      if (session == null ||
          session.isFinished ||
          session.state != CallState.ringing) return;
      if (outgoing) {
        unawaited(endCall(reason: 'timeout'));
      } else {
        unawaited(_sendSignal({
          'type': 'call_end',
          'call_id': session.id,
          'recipient_id': session.peerId,
          'reason': 'missed'
        }));
        unawaited(
            _finishLocal(CallState.missed, 'missed', notifyServer: false));
      }
    });
  }

  // Bundle 149: voice codecs.
  // * pcm_s16le: plain 16 kHz audio, always offered, works with every build.
  // * opus2: the fixed Opus (about 10x less data, better on weak links and
  //   through relays). Offered only when the native side passed its Opus
  //   self-test. The broken 142-145 'opus' name is never offered or used, so
  //   older builds (which only know 'opus'/'pcm_s16le') always land on PCM.
  static const String _pcmCodec = 'pcm_s16le';
  static const String _opusCodec = 'opus2';

  Future<List<String>> _supportedMediaCodecs() async {
    List<String> native;
    try {
      native = await mediaPlatform
          .supportedCodecs()
          .timeout(const Duration(seconds: 2), onTimeout: () => const [_pcmCodec]);
    } catch (_) {
      native = const [_pcmCodec];
    }
    return [if (native.contains(_opusCodec)) _opusCodec, _pcmCodec];
  }

  Future<String> _negotiateCodec(List<String> remoteCodecs) async {
    final local = await _supportedMediaCodecs();
    final used = local.contains(_opusCodec) && remoteCodecs.contains(_opusCodec)
        ? _opusCodec
        : _pcmCodec;
    AppLogger.info('CALL_CODEC_PICKED',
        detail: 'local=${local.join(',')} remote=${remoteCodecs.join(',')} used=$used');
    return used;
  }

  String _newCallId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'call-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}

/// Bundle 159: per-call voice key helpers (32 random bytes, base64).
abstract final class CallVoiceKey {
  static const int bytes = 32;

  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    return base64Encode(List<int>.generate(bytes, (_) => r.nextInt(256)));
  }

  /// The key if [raw] is a valid 32-byte base64 key, else null.
  static String? normalize(Object? raw) {
    if (raw is! String || raw.isEmpty || raw.length > 64) return null;
    try {
      final decoded = base64Decode(raw);
      return decoded.length == bytes ? base64Encode(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}

/// Bundle 158 (plan 158.2, D1): messages go up to 8 hops; voice calls were
/// limited to 3. Bundle 159 (D): the call sound is locked, so any LocalLink
/// phone may pass it on and voice goes up to 8 hops too. Only a relayed
/// route longer than that blocks a call; no route at all keeps the old
/// behaviour (the invite waits for a route).
abstract final class VoiceCallHopPolicy {
  static const int maxHops = 8;

  static bool tooFar(LocalRouteResult route) =>
      route.kind == LocalRouteKind.mesh &&
      route.hopCount != null &&
      route.hopCount! > maxHops;
}
