import 'dart:async';

import 'package:locallink/core/diagnostics/app_diagnostics.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

/// Selects the best authenticated local route for each peer.
///
/// The native transport owns physical links, while this service makes the
/// application-visible policy explicit: LAN, then Wi-Fi Direct, then mesh.
final class LocalRoutePolicyService {
  LocalRoutePolicyService(this.transport, {this.onRouteUnavailable});

  static const freshnessWindow = Duration(seconds: 90);

  final PeerTransportContract transport;
  final Future<void> Function(String peerId)? onRouteUnavailable;
  final StreamController<LocalRouteResult> _routeChanges =
      StreamController<LocalRouteResult>.broadcast();
  final Map<String, LocalRouteResult> _routes = {};

  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _started = false;
  bool _disposed = false;

  Stream<LocalRouteResult> get routeChanges => _routeChanges.stream;
  Map<String, LocalRouteResult> get routes => Map.unmodifiable(_routes);

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _subscription = transport.events.listen(
      _handleTransportEvent,
      onError: (Object error, StackTrace stackTrace) {
        AppDiagnostics.instance.recordException(
          'route_policy',
          'transport_event_failed',
          error,
          reasonCode: 'transport_event',
        );
      },
    );
    await refresh();
  }

  Future<LocalRouteResult> resolve(String peerId) async {
    final normalized = peerId.trim();
    if (normalized.isEmpty) {
      return _unavailable(normalized);
    }
    if (!transport.isStarted) {
      _requestFallback(normalized);
      return _unavailable(normalized);
    }
    final topology = await _readTopology();
    _publishRoutes(topology);
    final route = select(
        topology: topology, peerId: normalized, transportStarted: true);
    if (!route.isAvailable) _requestFallback(normalized);
    return route;
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (!transport.isStarted) {
      _publishRoutes(const <String, dynamic>{});
      return;
    }
    _publishRoutes(await _readTopology());
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    await _routeChanges.close();
  }

  static LocalRouteResult select({
    required Map<String, dynamic> topology,
    required String peerId,
    required bool transportStarted,
    DateTime? now,
  }) {
    final normalized = peerId.trim();
    if (normalized.isEmpty || !transportStarted) {
      return _unavailable(normalized);
    }
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final directCandidates = _maps(topology['peers'])
        .where((peer) => _peerId(peer) == normalized)
        .where(
            (peer) => peer['direct'] == true && peer['authenticated'] == true)
        .where((peer) => _connectedPeerState(peer['state']))
        .where((peer) => _isFresh(peer, timestamp));

    LocalRouteResult? wifiDirect;
    for (final peer in directCandidates) {
      final transports = _transports(peer);
      final route = LocalRouteResult(
        kind: transports.contains('lan')
            ? LocalRouteKind.lan
            : LocalRouteKind.wifiDirect,
        peerId: normalized,
        lastSeenAt: _intValue(peer['last_seen_at'] ?? peer['connected_at']),
        transportState: LocalTransportState.connected,
      );
      if (route.kind == LocalRouteKind.lan) return route;
      wifiDirect ??= route;
    }
    if (wifiDirect != null) return wifiDirect;

    for (final route in _maps(topology['routes'])) {
      if (_routeDestination(route) != normalized) continue;
      if (route['state']?.toString().trim().toUpperCase() != 'ACTIVE') continue;
      final expiresAt = _intValue(route['expires_at']);
      if (expiresAt == null || expiresAt <= timestamp) continue;
      return LocalRouteResult(
        kind: LocalRouteKind.mesh,
        peerId: normalized,
        expiresAt: expiresAt,
        nextHopId: (route['next_hop_id'] ??
                route['next_hop_node_id'] ??
                route['next_hop'])
            ?.toString()
            .trim(),
        transportState: LocalTransportState.available,
      );
    }
    return LocalRouteResult(
      kind: LocalRouteKind.none,
      peerId: normalized,
      transportState: LocalTransportState.waitingForRoute,
    );
  }

  Future<Map<String, dynamic>> _readTopology() =>
      transport.topology().timeout(const Duration(seconds: 5));

  void _requestFallback(String peerId) {
    final fallback = onRouteUnavailable;
    if (fallback == null || _disposed) return;
    unawaited(fallback(peerId).catchError((Object error, StackTrace stackTrace) {
      AppDiagnostics.instance.recordException(
        'route_policy',
        'fallback_request_failed',
        error,
        reasonCode: 'wifi_direct_fallback',
      );
    }));
  }

  void _handleTransportEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    if (event['type']?.toString() == 'topology') {
      _publishRoutes(event);
      return;
    }
    unawaited(refresh().catchError((Object error, StackTrace stackTrace) {
      AppDiagnostics.instance.recordException(
          'route_policy', 'topology_refresh_failed', error,
          reasonCode: 'topology_refresh');
    }));
  }

  void _publishRoutes(Map<String, dynamic> topology) {
    final peerIds = <String>{
      ..._maps(topology['peers']).map(_peerId),
      ..._maps(topology['routes']).map(_routeDestination),
      ..._routes.keys,
    }..removeWhere((id) => id.isEmpty);
    for (final peerId in peerIds) {
      final next = select(
          topology: topology,
          peerId: peerId,
          transportStarted: transport.isStarted);
      if (_routes[peerId] == next) continue;
      _routes[peerId] = next;
      _routeChanges.add(next);
      AppDiagnostics.instance
          .record('route_policy', 'route_selected', data: <String, Object?>{
        'transport': next.kind.name,
        'state': next.transportState.name,
      });
    }
  }

  static LocalRouteResult _unavailable(String peerId) => LocalRouteResult(
        kind: LocalRouteKind.none,
        peerId: peerId,
        transportState: LocalTransportState.unavailable,
      );

  static bool _connectedPeerState(Object? value) {
    final state = value?.toString().trim().toUpperCase();
    return state == 'CONNECTED' || state == 'AVAILABLE';
  }

  static bool _isFresh(Map<String, dynamic> peer, int now) {
    final lastSeen = _intValue(peer['last_seen_at'] ?? peer['connected_at']);
    return lastSeen != null && now - lastSeen <= freshnessWindow.inMilliseconds;
  }

  static Set<String> _transports(Map<String, dynamic> peer) {
    final values = <String>{
      peer['active_transport']?.toString().trim().toLowerCase() ?? '',
      peer['transport']?.toString().trim().toLowerCase() ?? '',
      ..._stringList(peer['available_transports']),
    };
    return values.where((value) => value.isNotEmpty).toSet();
  }

  static String _peerId(Map<String, dynamic> peer) =>
      (peer['node_id'] ?? peer['peer_id'])?.toString().trim() ?? '';
  static String _routeDestination(Map<String, dynamic> route) =>
      (route['destination'] ??
              route['destination_node_id'] ??
              route['destination_id'])
          ?.toString()
          .trim() ??
      '';
  static int? _intValue(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
  static List<Map<String, dynamic>> _maps(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList(growable: false)
      : const <Map<String, dynamic>>[];
  static Iterable<String> _stringList(Object? raw) => raw is List
      ? raw.map((value) => value.toString().trim().toLowerCase())
      : const <String>[];
}
