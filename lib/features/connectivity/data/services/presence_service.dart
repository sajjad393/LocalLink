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
  StreamSubscription? _wifiSub;
  Timer? _timer;
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
    if (!_running || _sending || store.deviceId == null || store.deviceToken == null) return;
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
    if (last != null && now.difference(last) < const Duration(seconds: 5)) return;
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
      if (serverConnected) {
        socket.send({
          'type': 'presence_update',
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
    await _socketSub?.cancel();
    await _wifiSub?.cancel();
    _socketSub = null;
    _wifiSub = null;
    _sending = false;
  }

  Future<void> dispose() => stop();
}
