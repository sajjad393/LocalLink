import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

enum LocalRouteKind { none, lan, wifiDirect, mesh }

enum LocalTransportState { unavailable, starting, available, connected, stale }

final class LocalRouteResult {
  final LocalRouteKind kind;
  final String peerId;
  final int? lastSeenAt;
  final int? expiresAt;
  final String? nextHopId;
  final LocalTransportState transportState;

  const LocalRouteResult({
    required this.kind,
    required this.peerId,
    this.lastSeenAt,
    this.expiresAt,
    this.nextHopId,
    this.transportState = LocalTransportState.unavailable,
  });

  bool get isAvailable => kind != LocalRouteKind.none;
}

final class LocalRouteResolver {
  static const _freshnessWindow = Duration(seconds: 90);
  final PeerTransportContract transport;

  const LocalRouteResolver(this.transport);

  Future<LocalRouteResult> resolve(String peerId) async {
    final normalized = peerId.trim();
    if (normalized.isEmpty || !transport.isStarted) {
      return LocalRouteResult(
          kind: LocalRouteKind.none,
          peerId: normalized,
          transportState: LocalTransportState.unavailable);
    }
    final topology = await transport.topology().timeout(
          const Duration(seconds: 5),
        );
    final now = DateTime.now().millisecondsSinceEpoch;

    final peers = _maps(topology['peers'] ?? topology['mesh_peers']);
    for (final peer in peers) {
      final id = (peer['node_id'] ?? peer['peer_id'])?.toString().trim() ?? '';
      if (id != normalized) continue;
      final state = peer['state']?.toString().trim().toUpperCase() ?? '';
      if (!_validPeerState(state)) continue;
      final lastSeen = _intValue(peer['last_seen_at'] ?? peer['connected_at']);
      if (lastSeen != null && now - lastSeen > _freshnessWindow.inMilliseconds)
        continue;
      final transportName = (peer['active_transport'] ?? peer['transport'])
              ?.toString()
              .trim()
              .toLowerCase() ??
          '';
      final wifi =
          transportName.contains('wifi') || transportName.contains('direct');
      return LocalRouteResult(
        kind: wifi ? LocalRouteKind.wifiDirect : LocalRouteKind.lan,
        peerId: normalized,
        lastSeenAt: lastSeen,
        transportState: LocalTransportState.connected,
      );
    }

    final routes = _maps(topology['routes']);
    for (final route in routes) {
      final destination = (route['destination'] ??
                  route['destination_node_id'] ??
                  route['destination_id'])
              ?.toString()
              .trim() ??
          '';
      if (destination != normalized) continue;
      final state = route['state']?.toString().trim().toUpperCase() ?? 'ACTIVE';
      if (state.isNotEmpty && state != 'ACTIVE') continue;
      final expiresAt = _intValue(route['expires_at']);
      if (expiresAt != null && expiresAt <= now) continue;
      final nextHop = (route['next_hop_id'] ?? route['next_hop_node_id'])
          ?.toString()
          .trim();
      return LocalRouteResult(
        kind: LocalRouteKind.mesh,
        peerId: normalized,
        expiresAt: expiresAt,
        nextHopId: nextHop,
        transportState: LocalTransportState.available,
      );
    }
    return LocalRouteResult(
        kind: LocalRouteKind.none,
        peerId: normalized,
        transportState: LocalTransportState.unavailable);
  }

  static bool _validPeerState(String state) =>
      state == 'CONNECTED' || state == 'AVAILABLE' || state == 'DISCOVERED';

  static int? _intValue(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static List<Map<String, dynamic>> _maps(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false)
      : const <Map<String, dynamic>>[];
}
