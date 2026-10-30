import 'dart:async';
import 'dart:convert';

import 'package:locallink/core/network/api_http_client.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_service.dart';
import 'wifi_radio_control_service.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

class PresenceService {
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

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _socketSub = socket.connectionState.listen((connected) =>
        unawaited(publish(force: connected)));
    // The server throttles presence_update (PRESENCE_RATE_LIMITED +
    // retry_after). Field [_rateLimitedUntil] was checked on every publish
    // but never set, so the app kept bursting into rejections. Honour the
    // server's window now, exactly like the other rate-limit feedback loops.
    _serverErrorSub = socket.messages.listen((message) {
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
      if (event['type'] == 'peer_connected') unawaited(publish(force: true));
    }, onError: (Object _) {});
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshWifiDirect());
      unawaited(publish());
    });
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
    try {
      final topology = await directTransport.topology();
      lanAvailable = topology['lan_active'] == true;
      meshAvailable = topology['transport_active'] == true;
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
    });
    final last = _lastPublishAt;
    if (!force && _lastPublishedSignature == signature &&
        last != null && now.difference(last) < const Duration(seconds: 30)) {
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
