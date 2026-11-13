import 'dart:async';
import 'dart:convert';

import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/presence/reach_check_296.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_service.dart';
import 'wifi_radio_control_service.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

class PresenceService {
  /// Bundle 222: set by AppDependencies (offline accounts seen nearby,
  /// sent as `offline_seen` with presence_update).
  static Future<List<Map<String, Object>>> Function()? offlineSeen222;

  final LocalStore store;
  final WebSocketService socket;
  final WifiDirectService wifiDirect;
  final PeerTransportContract directTransport;
  StreamSubscription<bool>? _socketSub;
  StreamSubscription? _serverErrorSub;
  StreamSubscription? _wifiSub;
  StreamSubscription? _transportSub;
  Timer? _timer;
  Timer? _forceRetry;
  DateTime? _lastPublishAt;
  DateTime? _rateLimitedUntil;
  String? _lastPublishedSignature;
  bool _wifiDirectConnected = false;
  bool _running = false;
  bool _sending = false;
  final ApiHttpClient httpClient;
  final IdentityCryptoService? crypto;
  final WifiRadioControlService wifiRadio;
  WifiRadioStatus? _wifiRadioStatus;

  PresenceService(this.store, this.socket, this.wifiDirect, this.directTransport, {ApiHttpClient? httpClient, this.crypto, WifiRadioControlService? wifiRadio})
      : httpClient = httpClient ?? ApiHttpClient(),
        wifiRadio = wifiRadio ?? WifiRadioControlService();

  // ------------------------------------------------ Bundle 296 (H2 + H4)
  /// H4: proven links go to the server in their own frame every 15 s and
  /// at once on a change (2 s wait to group changes). Checked every 5 s
  /// while LinkUp is open on screen, every 15 s in the background.
  static const Duration linkReportEvery = Duration(seconds: 15);
  static const Duration linkCheckEvery = Duration(seconds: 5);
  static const Duration linkBatch = Duration(seconds: 2);
  static const String linkReportType = 'link_report_296';
  Timer? _linkTimer;
  Timer? _linkBatchTimer;
  String? _linkSig;
  DateTime? _linkSentAt;
  bool _linkBusy = false;
  bool _linkOff = false; // an old server said it does not know the frame
  int _linkTick = 0;
  bool _foreground = false;
  ReachCheck296? _reach;

  /// H2: "are you there" for friends through other phones (open on screen).
  ReachCheck296 get reach => _reach ??= ReachCheck296(
        transport: directTransport,
        selfId: () => store.deviceId,
        friendIds: () async => [
          for (final d in await store.localDevices())
            if (d.revokedAt.isEmpty && d.id != store.deviceId) d.id,
        ],
        sealCapable: directTransport is SealingPeerTransport
            ? (directTransport as SealingPeerTransport).isSealCapable
            : null,
        loadCapable: () => store.readSetting(ReachCheck296.settingKey),
        saveCapable: (json) =>
            store.writeSetting(ReachCheck296.settingKey, json),
      );

  /// LinkUp open on screen (true) or not (false).
  void setForeground(bool on) {
    _foreground = on;
    if (_running) reach.setForeground(on);
    if (on) _scheduleLinkReport();
  }

  void _scheduleLinkReport() {
    if (!_running || _linkOff) return;
    _linkBatchTimer ??= Timer(linkBatch, () {
      _linkBatchTimer = null;
      unawaited(sendLinkReport());
    });
  }

  /// H4: sends the proven links when they changed or 15 s passed. Returns
  /// true when a frame went out.
  Future<bool> sendLinkReport() async {
    if (!_running || _linkOff || _linkBusy) return false;
    final id = store.deviceId;
    if (id == null || store.deviceToken == null || !socket.isConnected) {
      return false;
    }
    _linkBusy = true;
    try {
      var list = const <Map<String, String>>[];
      if (directTransport.isStarted) {
        try {
          list = presenceNeighbors216(await directTransport.topology(),
              selfId: id,
              isBlocked: AdminBlockBook.instance.isBlocked,
              nowMs: DateTime.now().millisecondsSinceEpoch);
        } catch (_) {
          return false; // no fresh answer: send nothing rather than guess
        }
      }
      final sig = [for (final n in list) '${n['device_id']}:${n['link']}'].join(',');
      final now = DateTime.now();
      final step = linkReportStep296(
          sig: sig, lastSig: _linkSig, lastAt: _linkSentAt, now: now);
      if (step == 'skip') return false;
      if (step == 'wait') {
        _scheduleLinkReport();
        return false;
      }
      socket.send(<String, dynamic>{
        'type': linkReportType,
        'device_id': id,
        'neighbors': list,
      });
      if (sig != _linkSig) {
        AppLogger.info('LINK_REPORT', detail: 'links=${list.length}');
      }
      _linkSig = sig;
      _linkSentAt = now;
      return true;
    } finally {
      _linkBusy = false;
    }
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _socketSub = socket.connectionState.listen((connected) {
      unawaited(publish(force: connected));
      // Bundle 296 (H4): a new server session gets the links at once.
      if (connected) {
        _linkSig = null;
        _scheduleLinkReport();
      }
    });
    // The server throttles presence_update (PRESENCE_RATE_LIMITED +
    // retry_after). Field [_rateLimitedUntil] was checked on every publish
    // but never set, so the app kept bursting into rejections. Honour the
    // server's window now, exactly like the other rate-limit feedback loops.
    _serverErrorSub = socket.messages.listen((message) {
      if (message['type'] == 'error' &&
          (message['error']?.toString() ?? '').contains(linkReportType)) {
        _linkOff = true; // Bundle 296: an old server (frame unknown)
        return;
      }
      if (message['type'] != 'error' ||
          message['error_code'] != 'PRESENCE_RATE_LIMITED') return;
      final seconds =
          int.tryParse(message['retry_after']?.toString() ?? '') ?? 30;
      _rateLimitedUntil = DateTime.now()
          .toUtc()
          .add(Duration(seconds: seconds.clamp(5, 120)));
    });
    _wifiSub = wifiDirect.events.listen((event) {
      if (event is! Map || event['type'] != 'connection') return;
      final raw = event['connection'];
      if (raw is Map) {
        try {
          _wifiDirectConnected = WifiDirectConnection.fromMap(Map<dynamic, dynamic>.from(raw)).connected;
          unawaited(publish());
        } catch (_) {}
      }
    });
    // Bundle 144: a new direct link gets our presence at once (no-server mode
    // otherwise showed the peer "offline" for up to 30s, or forever).
    _transportSub = directTransport.events.listen((event) {
      // Bundle 274 (A-1): a lost link is told at once too (admin map live).
      if (event['type'] == 'peer_connected' || event['type'] == 'peer_disconnected') {
        unawaited(publish(force: true));
        _scheduleLinkReport(); // Bundle 296 (H4)
      }
    }, onError: (Object _) {});
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshWifiDirect());
      unawaited(publish());
    });
    // Bundle 296 (H4): proven links, every 5 s on screen / 15 s behind.
    _linkTimer = Timer.periodic(linkCheckEvery, (_) {
      _linkTick++;
      if (_foreground || _linkTick % 3 == 0) unawaited(sendLinkReport());
    });
    // Bundle 296 (H2).
    unawaited(reach.start().then((_) {
      if (_running) reach.setForeground(_foreground);
    }));
    await _refreshWifiDirect();
    await publish();
  }

  Future<void> _refreshWifiDirect() async {
    try {
      if (!await wifiDirect.hasPermission()) {
        _wifiDirectConnected = false;
        return;
      }
      final info = await wifiDirect.connectionInfo();
      _wifiDirectConnected = info.connected;
    } catch (_) {}
  }


  Future<void> publish({bool force = false}) async {
    // Bundle 144: no deviceToken gate. The token is only for the server; a phone
    // that never registered (offline-only) must still announce itself directly.
    if (!_running || _sending || store.deviceId == null) return;
    final now = DateTime.now().toUtc();
    final cooldown = _rateLimitedUntil;
    if (cooldown != null && now.isBefore(cooldown)) return;
    try {
      _wifiRadioStatus = await wifiRadio.status();
    } catch (_) {}
    final serverConnected = socket.isConnected;
    var lanAvailable = directTransport.isStarted;
    var meshAvailable = directTransport.isStarted;
    var neighbors = const <Map<String, String>>[];
    try {
      final topology = await directTransport.topology();
      lanAvailable = topology['lan_active'] == true;
      meshAvailable = topology['transport_active'] == true;
      // Bundle 216g: who this phone reaches right now (web map lines).
      neighbors = presenceNeighbors216(topology,
          selfId: store.deviceId ?? '',
          isBlocked: AdminBlockBook.instance.isBlocked,
          nowMs: now.millisecondsSinceEpoch);
    } catch (_) {}
    final signingKey = crypto == null ? '' : await crypto!.signingPublicKey();
    final signature = jsonEncode(<String, Object>{
      'server_connected': serverConnected,
      'wifi_direct_connected': _wifiDirectConnected,
      'lan_available': lanAvailable,
      'mesh_available': meshAvailable,
      'wifi_control_capable': _wifiRadioStatus?.canControl ?? false,
      'managed_device': _wifiRadioStatus?.managedDevice ?? false,
      'wifi_enabled': _wifiRadioStatus?.enabled ?? false,
      'signing_public_key': signingKey,
      'neighbors': [for (final n in neighbors) '${n['device_id']}:${n['link']}'],
    });
    final last = _lastPublishAt;
    // Bundle 148: 25 s (not 30 s) so the 30 s timer never skips a beat by a
    // few milliseconds — a skipped beat meant a 60 s gap and a status flicker.
    if (!force && _lastPublishedSignature == signature &&
        last != null && now.difference(last) < const Duration(seconds: 25)) {
      return;
    }
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      // Bundle 144: a forced publish (new link) inside the 5s floor is retried
      // right after it instead of being dropped.
      if (force && _forceRetry == null) {
        _forceRetry = Timer(const Duration(seconds: 5) - now.difference(last), () {
          _forceRetry = null;
          unawaited(publish(force: true));
        });
      }
      return;
    }
    _sending = true;
    try {
      final statusUpdatedAt = now.toIso8601String();
      final payload = {
        'type': 'direct_presence',
        'sender_id': store.deviceId,
        'server_connected': serverConnected,
        'wifi_direct_connected': _wifiDirectConnected,
        'lan_available': lanAvailable,
        'mesh_available': meshAvailable,
        'wifi_control_capable': _wifiRadioStatus?.canControl ?? false,
        'managed_device': _wifiRadioStatus?.managedDevice ?? false,
        'wifi_enabled': _wifiRadioStatus?.enabled ?? false,
        'signing_public_key': signingKey,
        'status_updated_at': statusUpdatedAt,
      };
      if (serverConnected && store.deviceToken != null) {
        // Bundle 222: offline accounts seen nearby (old servers ignore it).
        var seen222 = const <Map<String, Object>>[];
        try {
          seen222 = await (offlineSeen222?.call() ?? Future.value(const <Map<String, Object>>[]));
        } catch (_) {}
        socket.send({
          'type': 'presence_update',
          'device_id': store.deviceId,
          'sender_id': store.deviceId,
          'server_connected': true,
            'wifi_direct_connected': _wifiDirectConnected,
          'lan_available': lanAvailable,
          'mesh_available': meshAvailable,
                'wifi_control_capable': _wifiRadioStatus?.canControl ?? false,
          'managed_device': _wifiRadioStatus?.managedDevice ?? false,
          'wifi_enabled': _wifiRadioStatus?.enabled ?? false,
          'signing_public_key': signingKey,
          'status_updated_at': statusUpdatedAt,
          // Bundle 216g: old servers ignore this field.
          'neighbors': neighbors,
          if (seen222.isNotEmpty) 'offline_seen': seen222,
        });
      }
      if (directTransport.isStarted) {
        try { await directTransport.broadcast(payload); } catch (_) {}
      }
      _lastPublishedSignature = signature;
      _lastPublishAt = now;
    } finally {
      _sending = false;
    }
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _forceRetry?.cancel();
    _forceRetry = null;
    _linkTimer?.cancel();
    _linkTimer = null;
    _linkBatchTimer?.cancel();
    _linkBatchTimer = null;
    _linkSig = null;
    _linkSentAt = null;
    await _reach?.stop();
    await _transportSub?.cancel();
    _transportSub = null;
    await _serverErrorSub?.cancel();
    _serverErrorSub = null;
    await _socketSub?.cancel();
    await _wifiSub?.cancel();
    _socketSub = null;
    _wifiSub = null;
    _sending = false;
  }

  Future<void> dispose() => stop();
}

/// Bundle 296 (H4): what to do with a link report now.
/// 'send' = changed (and 2 s since the last frame) or 15 s passed;
/// 'wait' = changed inside 2 s (sent right after); 'skip' = nothing new.
String linkReportStep296({
  required String sig,
  required String? lastSig,
  required DateTime? lastAt,
  required DateTime now,
}) {
  if (lastAt == null) return 'send';
  final gap = now.difference(lastAt);
  final due = gap >=
      PresenceService.linkReportEvery - const Duration(milliseconds: 500);
  if (sig == lastSig && !due) return 'skip';
  if (gap < PresenceService.linkBatch) return 'wait';
  return 'send';
}

/// Bundle 216g: phones this phone reaches directly, for the server's link
/// map. Max 32, never blocked phones, never itself.
/// link = wifi_direct | lan | mesh.
/// Bundle 296 (H4): only proven links (own pong in the last 10 s). A
/// snapshot without the `proven` flag keeps the old "seen in 4 min" rule.
List<Map<String, String>> presenceNeighbors216(
  Map<String, dynamic> topology, {
  required String selfId,
  required bool Function(String id) isBlocked,
  required int nowMs,
}) {
  final raw = topology['peers'];
  if (raw is! List) return const [];
  final out = <String, String>{};
  const fourMin = 4 * 60 * 1000;
  for (final p in raw) {
    if (p is! Map) continue;
    final id = '${p['node_id'] ?? p['peer_id'] ?? ''}'.trim();
    if (id.isEmpty || id == selfId || out.containsKey(id) || isBlocked(id)) continue;
    if (p['direct'] == false) continue;
    final proven = p['proven'];
    if (proven is bool) {
      if (!proven) continue; // Bundle 296 (H4)
    } else {
      final seen = p['last_seen_at'];
      if (seen is num && seen > 0 && nowMs - seen > fourMin) continue;
    }
    final kind = '${p['path_kind'] ?? p['transport'] ?? ''}'.toLowerCase();
    out[id] = switch (kind) {
      'wifi_direct' || 'local_net' => 'wifi_direct',
      'lan' => 'lan',
      _ => 'mesh',
    };
    if (out.length >= 32) break;
  }
  final ids = out.keys.toList()..sort();
  return [for (final id in ids) {'device_id': id, 'link': out[id]!}];
}

