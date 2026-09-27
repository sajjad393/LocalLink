import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/call_quality.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/models/call_notification_action.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_notification_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_ringtone_service.dart';
import 'package:locallink/features/calls/data/repositories/call_repository.dart';
import 'package:locallink/features/calls/domain/call_repository_contract.dart';
import 'package:locallink/features/calls/data/transport/call_transport.dart';
import 'package:locallink/features/calls/data/transport/call_transport_factory.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/calls/data/transport/call_transport_selection_policy.dart';
import 'package:locallink/features/calls/domain/call_gateway.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

final class CallSessionManager implements CallGateway {
  final LocalStore store;
  final PeerTransportContract directTransport;
  final CallRepositoryContract repository;
  final CallAudioPlatformService audioPlatform;
  final CallRingtoneService ringtone;
  final CallNotificationPlatformService notificationPlatform;
  final CallMediaPlatformService mediaPlatform;
  final IdentityCryptoService crypto;

  final _sessionController = StreamController<CallSession?>.broadcast();
  final _historyController = StreamController<List<CallRecord>>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _nativeSub;
  StreamSubscription<CallNotificationAction>? _notificationActionSub;
  Timer? _ringTimer;
  Timer? _statsTimer;
  Timer? _heartbeatTimer;
  Timer? _meshRouteRecoveryTimer;
  CallSession? _session;
  CallTransport? _transport;
  late final CallTransportFactory transportFactory;
  bool _disposed = false;
  int _recoveryAttempts = 0;
  int _meshRouteRecoveryAttempts = 0;
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
    required this.repository,
    required this.audioPlatform,
    required this.ringtone,
    required this.notificationPlatform,
    required this.mediaPlatform,
    required this.crypto,
  }) {
    transportFactory = CallTransportFactory(
      mesh: directTransport,
      media: mediaPlatform,
      audio: audioPlatform,
      crypto: crypto,
    );
  }

  void start() {
    if (_disposed) return;
    _notificationActionSub ??= notificationPlatform.actions
        .listen((action) => unawaited(_handleNotificationAction(action)));
    _nativeSub ??=
        transportFactory.nativeMesh.events.listen(_handleNativeTransportEvent);
    unawaited(_synchronizeIncomingPresentation());
    unawaited(syncHistory());
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
    if (await store.isBlockedPeer(device.id))
      throw Exception('This user is blocked');
    if (_session != null && !_session!.isFinished)
      throw Exception('Another call is already active');
    if (!directTransport.isStarted)
      throw Exception('Local mesh transport is unavailable');

    final localRouteAvailable = await _hasLocalRouteTo(device.id);
    final mode = CallTransportSelectionPolicy.select(
        localRouteAvailable: localRouteAvailable);
    final id = _newCallId();
    final now = DateTime.now();
    final session = CallSession(
      id: id,
      peerId: device.id,
      peerName: device.name,
      direction: CallDirection.outgoing,
      state: CallState.ringing,
      startedAt: now,
      speakerOn: true,
      directMode: true,
      transportMode: mode,
      supportedMediaCodecs: await _supportedMediaCodecs(),
    );
    _setSession(session);
    await _persistSession();
    _startRingTimer(outgoing: true);
    _startHeartbeatTimer();
    await _sendSignal({
      'type': 'call_invite',
      'call_id': id,
      'recipient_id': device.id,
      'created_at': now.toUtc().toIso8601String(),
      'transport_mode': mode.wireName,
      'mesh_call': true,
      'direct': true,
      'supported_media_codecs': session.supportedMediaCodecs,
    });
  }

  Future<void> acceptIncoming() async {
    final session = _session;
    if (session == null ||
        session.direction != CallDirection.incoming ||
        session.state != CallState.ringing) return;
    if (await store.isBlockedPeer(session.peerId)) {
      await rejectIncoming(reason: 'blocked');
      return;
    }
    try {
      _cancelCallTimers();
      final selectedCodec = await _negotiateCodec(session.supportedMediaCodecs);
      _setSession(session.copyWith(
        state: CallState.connecting,
        mediaCodec: selectedCodec,
        transportMode: CallTransportMode.offlineMesh,
        directMode: true,
      ));
      await _persistSession();
      _transport =
          transportFactory.resolve(requested: CallTransportMode.offlineMesh);
      await _transport!.start(_session!);
      await _sendSignal({
        'type': 'call_accept',
        'call_id': session.id,
        'recipient_id': session.peerId,
        'selected_media_codec': selectedCodec,
        'transport_mode': CallTransportMode.offlineMesh.wireName,
        'mesh_call': true,
        'direct': true,
      });
      await _markConnected();
    } catch (e) {
      await _fail('microphone_unavailable');
      rethrow;
    }
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
      final video = await transport.startVideo(session);
      _setSession(session.copyWith(
        videoEnabled: true,
        localVideoTextureId: (video['local_texture_id'] as num?)?.toInt(),
        remoteVideoTextureId: (video['remote_texture_id'] as num?)?.toInt(),
      ));
      return;
    }
    await transport.setVideoEnabled(session, enabled);
    _setSession(session.copyWith(videoEnabled: enabled));
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
    await _nativeSub?.cancel();
    await _notificationActionSub?.cancel();
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
    await transportFactory.dispose();
    await _historyController.close();
    await _sessionController.close();
  }

  Future<bool> _hasLocalRouteTo(String peerId) async {
    if (!directTransport.isStarted) return false;
    try {
      final topology = await directTransport.topology();
      final now = DateTime.now().millisecondsSinceEpoch;

      final peersRaw = topology['peers'] ?? topology['mesh_peers'];
      if (peersRaw is List) {
        for (final raw in peersRaw.whereType<Map>()) {
          final peer = Map<String, dynamic>.from(raw);
          final id = (peer['node_id'] ?? peer['peer_id'])?.toString().trim();
          final state = peer['state']?.toString().trim().toUpperCase();
          if (id == peerId &&
              (state == null ||
                  state.isEmpty ||
                  state == 'CONNECTED' ||
                  state == 'DISCOVERED')) {
            return true;
          }
        }
      }

      final routesRaw = topology['routes'];
      if (routesRaw is List) {
        for (final raw in routesRaw.whereType<Map>()) {
          final route = Map<String, dynamic>.from(raw);
          final destination = (route['destination'] ??
                  route['destination_node_id'] ??
                  route['destination_id'])
              ?.toString()
              .trim();
          final state = route['state']?.toString().trim().toUpperCase();
          final expiresAt = (route['expires_at'] as num?)?.toInt();
          final active = state == null || state.isEmpty || state == 'ACTIVE';
          final notExpired = expiresAt == null || expiresAt > now;
          if (destination == peerId && active && notExpired) return true;
        }
      }
    } catch (_) {
      // A topology read failure is treated as no local route.
    }
    return false;
  }

  Future<void> _handleLocalCallSignal(Map<String, dynamic> msg) async {
    if (_disposed) return;
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
    final createdAt =
        DateTime.tryParse(msg['created_at']?.toString() ?? '')?.toLocal();
    if (createdAt == null) return;
    final age = DateTime.now().difference(createdAt);
    if (age > const Duration(minutes: 2) ||
        age < const Duration(seconds: -30)) {
      unawaited(_sendSignal({
        'type': 'call_reject',
        'call_id': callId,
        'recipient_id': peerId,
        'reason': 'stale_invite'
      }));
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
    final name = await repository
        .loadDeviceNames()
        .then((names) => names[peerId] ?? peerId);
    final advertised = (msg['supported_media_codecs'] is List)
        ? (msg['supported_media_codecs'] as List)
            .map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty)
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
      speakerOn: true,
      directMode: true,
      transportMode: CallTransportMode.offlineMesh,
      supportedMediaCodecs: advertised,
    ));
    await _persistSession();
    _startRingTimer(outgoing: false);
  }

  Future<void> _handleNotificationAction(CallNotificationAction action) async {
    final session = _session;
    if (session == null ||
        session.isFinished ||
        session.direction != CallDirection.incoming ||
        session.state != CallState.ringing ||
        session.id != action.callId ||
        session.peerId != action.callerId) return;
    if (await store.isBlockedPeer(session.peerId)) {
      await rejectIncoming(reason: 'blocked');
      return;
    }
    try {
      switch (action.type) {
        case CallNotificationActionType.accept:
          await acceptIncoming();
        case CallNotificationActionType.reject:
          await rejectIncoming();
      }
    } catch (_) {}
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
    if (session == null ||
        session.direction != CallDirection.outgoing ||
        !_signalTargetsThisSession(msg, session, requireRemoteSender: true))
      return;
    try {
      _ringTimer?.cancel();
      final selectedCodec =
          msg['selected_media_codec']?.toString().trim().toLowerCase();
      if (_transport == null) {
        final current =
            (selectedCodec == 'opus' || selectedCodec == 'pcm_s16le')
                ? session.copyWith(mediaCodec: selectedCodec)
                : session;
        _setSession(current);
        _transport = transportFactory.resolve(requested: current.transportMode);
        await _transport!.start(current);
      }
      await _markConnected();
    } catch (_) {
      await _fail('media_setup_failed');
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
        !_signalTargetsThisSession(msg, session, requireRemoteSender: true))
      return;
    final reason = msg['reason']?.toString();
    await _finishLocal(
        CallState.ended, reason?.isNotEmpty == true ? reason! : 'ended',
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
          '';
      final callId = event['call_id']?.toString();
      final eventTargets = destination == session.peerId &&
          (callId == null || callId.isEmpty || callId == session.id);
      if (eventTargets &&
          (type == 'route_invalidated' ||
              type == 'route_removed' ||
              type == 'call_media_route_degraded')) {
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
      } else if (eventTargets && type == 'route_recovered') {
        _meshRouteRecoveryTimer?.cancel();
        _meshRouteRecoveryAttempts = 0;
        _setSession(session.copyWith(
            state: CallState.connected,
            quality: CallQuality.good,
            recoveryAttempts: 0,
            mediaNextHopId: event['next_hop_id']?.toString(),
            mediaHopCount: (event['hop_count'] as num?)?.toInt()));
        unawaited(_persistSession());
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
    if (session == null ||
        session.id != msg['call_id']?.toString() ||
        session.direction != CallDirection.outgoing ||
        msg['sender_id']?.toString() != store.deviceId ||
        msg['recipient_id']?.toString() != session.peerId) return;
    if (msg['status']?.toString() != 'ringing') return;
    _setSession(session.copyWith(state: CallState.ringing));
  }

  Future<void> _handleState(Map<String, dynamic> msg) async {
    final session = _session;
    if (session == null ||
        session.id != msg['call_id']?.toString() ||
        !_signalTargetsThisSession(msg, session)) return;
    final status = msg['status']?.toString() ?? '';
    final reason = msg['reason']?.toString() ?? '';
    if (status == 'connected') {
      if (session.direction == CallDirection.outgoing &&
          session.state != CallState.connected) {
        if (_transport == null) {
          _transport =
              transportFactory.resolve(requested: session.transportMode);
          await _transport!.start(session);
        }
        await _markConnected();
      } else if (session.direction == CallDirection.incoming &&
          session.state != CallState.connected) {
        await _markConnected();
      }
      return;
    }
    if (status == 'reconnecting') {
      _setSession(session.copyWith(
          state: CallState.reconnecting, quality: CallQuality.reconnecting));
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
    if (!directTransport.isStarted)
      throw StateError('local mesh transport is unavailable');
    await transportFactory.nativeMesh
        .sendControl(recipientId: recipient, payload: {
      ...msg,
      'sender_id': store.deviceId,
      'direct': true,
      'mesh_call': true,
      'transport_mode': CallTransportMode.offlineMesh.wireName,
    });
  }

  Future<void> _recoverLostMeshTransport(
      CallSession active, String? reason) async {
    if (_session?.id != active.id || active.isFinished) return;
    final localStillAvailable = await _hasLocalRouteTo(active.peerId);
    if (!localStillAvailable) {
      await _fail(reason ?? 'mesh_route_failed');
      return;
    }
    final current = _session;
    final oldTransport = _transport;
    if (current == null || current.isFinished) return;
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
        _setSession(_session!.copyWith(
            state: CallState.reconnecting,
            quality: CallQuality.reconnecting,
            reason: reason ?? _session!.reason));
        unawaited(_persistSession());
        break;
      case 'failed':
        final active = _session;
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
    if (session == null || session.isFinished) return;
    _ringTimer?.cancel();
    _recoveryAttempts = 0;
    _setSession(session.copyWith(
        state: CallState.connected,
        answeredAt: session.answeredAt ?? DateTime.now(),
        quality: CallQuality.excellent,
        recoveryAttempts: 0));
    await _persistSession();
    _startHeartbeatTimer();
    _startStatsTimer();
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
    final endedAt = DateTime.now();
    final next =
        session.copyWith(state: state, endedAt: endedAt, reason: reason);
    _setSession(next);
    await _persistSession();
    try {
      if (_transport != null) await _transport!.stop(session);
    } catch (_) {}
    _transport = null;
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
      await store.saveCallQualitySample(sample);
      final latest = _session;
      if (latest != null && latest.id == session.id && !latest.isFinished)
        _setSession(latest.copyWith(quality: quality, qualitySample: sample));
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
    if (_session == null || _session!.isFinished) return;
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _sendHeartbeat());
  }

  void _sendHeartbeat() {
    final session = _session;
    if (session == null || session.isFinished) return;
    unawaited(_sendSignal({
      'type': 'call_heartbeat',
      'call_id': session.id,
      'recipient_id': session.peerId
    }));
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

  void _cancelCallTimers() {
    _ringTimer?.cancel();
    _statsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _meshRouteRecoveryTimer?.cancel();
    _ringTimer = null;
    _statsTimer = null;
    _heartbeatTimer = null;
    _meshRouteRecoveryTimer = null;
  }

  Future<void> _persistSession() async {
    final session = _session;
    final self = store.deviceId;
    if (session == null || self == null) return;
    await store.saveCall(session.toRecord(self));
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
    if (isRinging && (!wasRinging || previous?.id != session.id)) {
      final revision = ++_presentationRevision;
      unawaited(_presentIncomingCall(session, revision));
    } else if (!isRinging && (wasRinging || session == null)) {
      final revision = ++_presentationRevision;
      unawaited(_clearIncomingPresentation(revision));
    }
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

  Future<List<String>> _supportedMediaCodecs() async {
    final codecs = await mediaPlatform.supportedCodecs();
    final normalized = codecs
        .map((e) => e.trim().toLowerCase())
        .where((e) => e == 'opus' || e == 'pcm_s16le')
        .toSet()
        .toList();
    return normalized.isEmpty ? const ['pcm_s16le'] : normalized;
  }

  Future<String> _negotiateCodec(List<String> remoteCodecs) async {
    final local = await _supportedMediaCodecs();
    if (remoteCodecs.contains('opus') && local.contains('opus')) return 'opus';
    return 'pcm_s16le';
  }

  String _newCallId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'call-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
