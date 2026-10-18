import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/services/app_logger.dart';
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

  // Server-unreachable tracking: while the server is down, probe quietly on
  // a growing backoff (30s -> 60s -> 120s cap) instead of hammering it, and
  // log once per reachability transition rather than once per failed probe.
  int _consecutiveUnreachable = 0;
  DateTime? _nextProbeAt;
  bool _unreachableLogged = false;

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
    // Startup fetch is strictly fire-and-forget: it must never delay app
    // startup, and with a powered-off server it completes in ~6s (client
    // socket timeout) rather than the kernel's ~130s TCP-SYN budget.
    unawaited(refresh());
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
    final now = DateTime.now();
    final nextProbe = _nextProbeAt;
    if (nextProbe != null && now.isBefore(nextProbe)) return; // quiet backoff window
    try {
      final response = await httpClient.get(
        Uri.parse('${api.baseUrl}/api/v1/device/network-policy'),
        headers: api.wsHeaders,
      ).timeout(const Duration(seconds: 8));
      // Any HTTP answer — even an error status — means the server is up.
      _markReachable();
      if (response.statusCode != 200) return;
      final value = jsonDecode(response.body);
      if (value is Map) {
        await _apply(Map<String, dynamic>.from(value), authoritativeSnapshot: true);
      }
    } catch (error) {
      if (!errorIsServerUnreachable(error)) return; // keep the quiet contract
      _consecutiveUnreachable++;
      final shift = (_consecutiveUnreachable - 1).clamp(0, 2).toInt();
      final backoffSeconds = (30 << shift).clamp(30, 120).toInt();
      _nextProbeAt = now.add(Duration(seconds: backoffSeconds));
      if (!_unreachableLogged) {
        _unreachableLogged = true;
        AppLogger.warning(
          'NETWORK_POLICY_SERVER_UNREACHABLE',
          detail: 'offline mode; probing every ${backoffSeconds}s — ${error.runtimeType}',
        );
      }
    }
  }

  /// Whether [error] means "server is down/unreachable" as opposed to a code
  /// bug or a response-shape problem: refused connection (111), unreachable
  /// host, or the connect-phase timeout (SocketException carries errno 110 on
  /// Android when the kernel SYN budget beats our 6s client timeout).
  static bool errorIsServerUnreachable(Object error) =>
      error is SocketException || error is TimeoutException || error is HttpException || error is OSError;

  void _markReachable() {
    if (_unreachableLogged) {
      AppLogger.info('NETWORK_POLICY_SERVER_REACHABLE', detail: 'resuming normal 2-minute sync');
    }
    _consecutiveUnreachable = 0;
    _nextProbeAt = null;
    _unreachableLogged = false;
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (message['type']?.toString() != 'network_policy_update') return;
    final deviceId = message['device_id']?.toString() ?? '';
    if (deviceId.isNotEmpty && deviceId != store.deviceId) return;
    // A live policy push over the socket proves the server is back: reset
    // the offline backoff so the very next scheduled probe runs immediately.
    _markReachable();
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
