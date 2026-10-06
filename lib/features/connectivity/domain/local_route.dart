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

  const LocalRouteResult({
    required this.kind,
    required this.peerId,
    this.lastSeenAt,
    this.expiresAt,
    this.nextHopId,
    this.transportState = LocalTransportState.unavailable,
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
      other.transportState == transportState;

  @override
  int get hashCode => Object.hash(
        kind,
        peerId,
        lastSeenAt,
        expiresAt,
        nextHopId,
        transportState,
      );
}
