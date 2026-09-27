import 'dart:async';
import 'dart:convert';

import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'wifi_radio_control_service.dart';

final class NetworkPolicySyncService {
  final LocalStore store;
  final LocalLinkApi api;
  final WebSocketService socket;
  final ApiHttpClient httpClient;
  final WifiRadioControlService wifiRadio;
  StreamSubscription<Map<String, dynamic>>? _socketSub;
  StreamSubscription<bool>? _stateSub;
  Timer? _refreshTimer;
  bool _running = false;

  NetworkPolicySyncService(this.store, this.api, this.socket, {ApiHttpClient? httpClient, WifiRadioControlService? wifiRadio})
      : httpClient = httpClient ?? ApiHttpClient(),
        wifiRadio = wifiRadio ?? WifiRadioControlService();

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _socketSub = socket.messages.listen(_handleMessage);
    _stateSub = socket.connectionState.listen((connected) {
      if (connected) unawaited(refresh());
    });
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) { unawaited(refresh()); });
    await refresh();
  }

  Future<void> _apply(Map<String, dynamic> policy, {bool authoritativeSnapshot = false}) async {
    await store.applyAdminNetworkPolicy(policy, authoritativeSnapshot: authoritativeSnapshot);
    final wifi = policy['wifi_radio_policy']?.toString() ?? '';
    if (wifi == 'forced_on' || wifi == 'forced_off') {
      try { await wifiRadio.enforce(wifi); } catch (_) {}
    }
  }

  Future<void> refresh() async {
    if (!_running || store.deviceId == null || store.deviceToken == null || store.serverAddress == null) return;
    try {
      final response = await httpClient.get(
        Uri.parse('${api.baseUrl}/api/v1/device/network-policy'),
        headers: api.wsHeaders,
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final value = jsonDecode(response.body);
      if (value is Map) {
        await _apply(Map<String, dynamic>.from(value), authoritativeSnapshot: true);
      }
    } catch (_) {}
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (message['type']?.toString() != 'network_policy_update') return;
    final deviceId = message['device_id']?.toString() ?? '';
    if (deviceId.isNotEmpty && deviceId != store.deviceId) return;
    dynamic payload = message;
    final rawBody = message['body'];
    if (rawBody is String && rawBody.trim().isNotEmpty) {
      try { payload = jsonDecode(rawBody); } catch (_) { return; }
    }
    if (payload is Map) unawaited(_apply(Map<String, dynamic>.from(payload))); 
  }

  Future<void> stop() async {
    _running = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _socketSub?.cancel();
    await _stateSub?.cancel();
    _socketSub = null;
    _stateSub = null;
  }

  Future<void> dispose() => stop();
}
