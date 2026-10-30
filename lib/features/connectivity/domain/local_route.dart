enum LocalRouteKind { none, lan, wifiDirect, mesh }

enum LocalTransportState {
  unavailable,
  starting,
  searching,
  waitingForRoute,
  available,
  connected,
  stale,
}

final class LocalRouteResult {
  final LocalRouteKind kind;
  final String peerId;
  final int? lastSeenAt;
  final int? expiresAt;
  final String? nextHopId;
  final LocalTransportState transportState;

  /// Bundle 158: hops on a relayed (mesh) route; null when unknown. Direct
  /// links are 1 hop.
  final int? hopCount;

  const LocalRouteResult({
    required this.kind,
    required this.peerId,
    this.lastSeenAt,
    this.expiresAt,
    this.nextHopId,
    this.transportState = LocalTransportState.unavailable,
    this.hopCount,
  });

  bool get isAvailable => kind != LocalRouteKind.none;

  @override
  bool operator ==(Object other) =>
      other is LocalRouteResult &&
      other.kind == kind &&
      other.peerId == peerId &&
      other.lastSeenAt == lastSeenAt &&
      other.expiresAt == expiresAt &&
      other.nextHopId == nextHopId &&
      other.transportState == transportState &&
      other.hopCount == hopCount;

  @override
  int get hashCode => Object.hash(
        kind,
        peerId,
        lastSeenAt,
        expiresAt,
        nextHopId,
        transportState,
        hopCount,
      );
}
