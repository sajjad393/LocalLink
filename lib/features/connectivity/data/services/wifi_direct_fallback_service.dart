import 'dart:async';

import 'package:locallink/core/diagnostics/app_diagnostics.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

/// Bundle 155: what the automatic reconnect should do right now.
class FallbackConnectPlan {
  /// Wi-Fi Direct address to connect to, or null = do nothing now.
  final String? address;

  /// The LocalLink person this attempt is for (null for the legacy path).
  final String? peerId;

  /// true = this phone asks to become the host (intent 15), false = join (0).
  final bool wantHost;

  /// Why (for logs and tests).
  final String reason;

  const FallbackConnectPlan._(
      this.address, this.peerId, this.wantHost, this.reason);
  const FallbackConnectPlan.none(String reason)
      : this._(null, null, false, reason);
  const FallbackConnectPlan.connect(
      String address, String? peerId, bool wantHost, String reason)
      : this._(address, peerId, wantHost, reason);

  bool get acts => address != null;
}

/// Bundle 155: pure decision for the automatic Wi-Fi Direct reconnect.
///
/// Rules ("never break a working route"):
/// * a phone that is a MEMBER of a group never leaves it automatically;
/// * a phone that is a member of ANOTHER group is never pulled away;
/// * two hosts don't merge yet (bundle 157) — wait;
/// * a full host (tag full=1) is skipped — nobody gets kicked (D9);
/// * pick the phone whose tag matches the waiting person (no guessing);
/// * legacy: when NO visible phone has a tag (older app version), keep the
///   old "exactly one available phone" rule, but only while not in a group.
FallbackConnectPlan planFallbackConnect({
  required List<String> waitingPeerIds,
  required List<WifiDirectPeer> peers,
  required Map<String, NearbyTag> tagsByAddress,
  required bool connected,
  required bool groupOwner,
  Set<String> coolingDown = const <String>{},
}) {
  if (waitingPeerIds.isEmpty) return const FallbackConnectPlan.none('idle');
  if (connected && !groupOwner) {
    return const FallbackConnectPlan.none('member_keeps_group');
  }
  final available = peers
      .where((p) =>
          p.isAvailable &&
          p.address.trim().isNotEmpty &&
          !coolingDown.contains(p.address.trim().toLowerCase()))
      .toList(growable: false);

  String? lastReason;
  for (final peerId in waitingPeerIds) {
    final hash = NearbyTag.idFor(peerId);
    for (final peer in available) {
      final tag = tagsByAddress[peer.address.trim().toLowerCase()];
      if (tag == null || tag.idHash != hash) continue;
      if (tag.member) {
        lastReason = 'target_in_other_group';
        continue;
      }
      if (tag.host) {
        if (connected) {
          lastReason = 'both_hosts';
          continue;
        }
        if (tag.full) {
          lastReason = 'target_full';
          continue;
        }
        return FallbackConnectPlan.connect(
            peer.address, peerId, false, 'join_host');
      }
      return FallbackConnectPlan.connect(peer.address, peerId, true,
          connected ? 'invite_to_my_group' : 'start_group');
    }
  }
  if (lastReason != null) return FallbackConnectPlan.none(lastReason);

  final anyTagged = peers.any(
      (p) => tagsByAddress.containsKey(p.address.trim().toLowerCase()));
  if (anyTagged) return const FallbackConnectPlan.none('no_match');
  if (connected) return const FallbackConnectPlan.none('legacy_needs_idle');
  if (peers.length > 1) return const FallbackConnectPlan.none('ambiguous_peers');
  if (available.length == 1 && peers.length == 1) {
    return FallbackConnectPlan.connect(
        available.single.address, null, true, 'legacy_single_peer');
  }
  return const FallbackConnectPlan.none('no_peer');
}

/// Starts a bounded Wi-Fi Direct fallback when a requested peer has no route.
///
/// Bundle 155: phones now carry a "who is who" tag (Wi-Fi Direct service
/// discovery), so the fallback connects the RIGHT person even with many
/// phones around, never pulls itself or others out of a working group, and
/// does nothing while a Local Wi-Fi / mesh route exists ([hasLocalRoute]).
///
/// Re-discovery is periodic while any peer is waiting: discovery results are
/// event-driven, but Android silently stops discovery after a while, and a
/// failed connect attempt produces no event at all. Without a re-arm loop the
/// fallback could stall forever until the user sent another message.
final class WifiDirectFallbackService {
  WifiDirectFallbackService(
    this.connectivity, {
    Duration rediscoveryInterval = const Duration(seconds: 45),
    this.hasLocalRoute,
  }) : _rediscoveryInterval = rediscoveryInterval;

  static const _retryCooldown = Duration(seconds: 20);

  /// How often discovery is re-armed while any peer waits for a route.
  /// Long enough to sit below the OS rate limits, short enough that a phone
  /// arriving within a minute is picked up without user action.
  final Duration _rediscoveryInterval;

  /// Bundle 109: waiters expire — proactive probing (boot + server-loss) can
  /// park many watch entries; without a TTL the rediscovery loop would spin
  /// for contacts that are simply far away today.
  static const _waiterTtl = Duration(minutes: 10);

  /// Bundle 155 (Local Wi-Fi first): true when the person is already
  /// reachable over Local Wi-Fi or the mesh — then Wi-Fi Direct does nothing.
  bool Function(String peerId)? hasLocalRoute;

  final ConnectivityRepositoryContract connectivity;
  final Map<String, DateTime> _waitingSince = <String, DateTime>{};
  final Map<String, DateTime> _attemptedAddresses = <String, DateTime>{};
  final Map<String, NearbyTag> _tags = <String, NearbyTag>{};
  List<WifiDirectPeer> _lastPeers = const <WifiDirectPeer>[];
  StreamSubscription? _wifiSubscription;
  Timer? _rediscoveryTimer;
  bool _started = false;
  bool _disposed = false;
  bool _discoveryInFlight = false;
  bool _connectionInFlight = false;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _wifiSubscription = connectivity.wifiDirectEvents.listen(_handleWifiEvent);
  }

  Future<void> requestRoute(String peerId) async {
    final normalized = peerId.trim();
    if (_disposed || normalized.isEmpty) return;
    if (_reachableLocally(normalized)) {
      _record('lan_first_skip');
      return;
    }
    _waitingSince[normalized] = DateTime.now();
    _armRediscoveryTimer();
    await _discoverAndConnect();
  }

  /// Called when any route to [peerId] becomes available again (LAN or mesh
  /// recovered). The fallback only makes sense while no route exists, so the
  /// waiter is drained; the re-discovery loop stops once nobody is waiting.
  void cancelWaiting(String peerId) {
    final normalized = peerId.trim();
    if (normalized.isEmpty) return;
    _waitingSince.remove(normalized);
    if (_waitingSince.isEmpty) {
      _rediscoveryTimer?.cancel();
      _rediscoveryTimer = null;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _waitingSince.clear();
    _rediscoveryTimer?.cancel();
    _rediscoveryTimer = null;
    await _wifiSubscription?.cancel();
    _wifiSubscription = null;
  }

  bool _reachableLocally(String peerId) {
    try {
      return hasLocalRoute?.call(peerId) ?? false;
    } catch (_) {
      return false;
    }
  }

  void _handleWifiEvent(dynamic event) {
    if (_disposed || event is! Map) return;
    final type = event['type']?.toString();
    if (type == 'services') {
      final tags = NearbyTag.listFromEvent(event['peers']);
      _tags
        ..clear()
        ..addAll({for (final t in tags) t.address: t});
      NearbyTagRegistry.instance.ingest(tags);
      unawaited(_tryConnect(_lastPeers));
      return;
    }
    if (type != 'peers') return;
    final raw = event['peers'];
    final peers = raw is List
        ? raw
            .whereType<Map>()
            .map((peer) =>
                WifiDirectPeer.fromMap(Map<dynamic, dynamic>.from(peer)))
            .toList(growable: false)
        : const <WifiDirectPeer>[];
    _lastPeers = peers;
    unawaited(_tryConnect(peers));
  }

  /// Re-arms discovery while waiters exist. Skips ticks that would overlap
  /// an in-flight discovery or connect — never stacks attempts, never pops
  /// dialogs (the enable request runs at most once per waiting episode by
  /// _discoverAndConnect's own gating inside the repository).
  void _armRediscoveryTimer() {
    if (_rediscoveryTimer != null || _disposed) return;
    _rediscoveryTimer = Timer.periodic(_rediscoveryInterval, (_) {
      // Expire parked waiters (Bundle 109 TTL) before deciding to stop.
      _waitingSince.removeWhere((_, since) =>
          DateTime.now().difference(since) > _waiterTtl);
      if (_disposed || _waitingSince.isEmpty) {
        _rediscoveryTimer?.cancel();
        _rediscoveryTimer = null;
        return;
      }
      if (_discoveryInFlight || _connectionInFlight) return;
      unawaited(_discoverAndConnect());
    });
  }

  Future<void> _discoverAndConnect() async {
    if (_disposed || _waitingSince.isEmpty || _discoveryInFlight) return;
    _discoveryInFlight = true;
    try {
      if (!await connectivity.isWifiDirectSupported()) {
        _record('unsupported');
        return;
      }
      if (!await connectivity.isWifiDirectPermissionGranted()) {
        await connectivity.requestWifiDirectEnable();
        _record('permission_requested');
        return;
      }
      // Bundle 155: no more early "already_connected" stop — a host can
      // still invite people into its group; a member simply waits
      // (decided in planFallbackConnect).
      await connectivity.startWifiDirectDiscovery();
      _record('discovery_started');
      final peers = await connectivity.wifiDirectPeers();
      _lastPeers = peers;
      await _tryConnect(peers);
    } catch (error) {
      AppDiagnostics.instance.recordException(
        'wifi_direct_fallback',
        'discovery_failed',
        error,
        reasonCode: 'discovery_failed',
      );
    } finally {
      _discoveryInFlight = false;
    }
  }

  Future<void> _tryConnect(List<WifiDirectPeer> peers) async {
    if (_disposed || _waitingSince.isEmpty || _connectionInFlight) return;
    // Local Wi-Fi / mesh first: drop waiters that are already reachable.
    for (final id in _waitingSince.keys.toList()) {
      if (_reachableLocally(id)) cancelWaiting(id);
    }
    if (_waitingSince.isEmpty) return;

    _connectionInFlight = true;
    try {
      var connection =
          const WifiDirectConnection(connected: false, groupOwner: false);
      try {
        connection = await connectivity.wifiDirectConnectionInfo();
      } catch (_) {}
      final now = DateTime.now();
      final cooling = <String>{
        for (final e in _attemptedAddresses.entries)
          if (now.difference(e.value) < _retryCooldown) e.key,
      };
      final waiting = _waitingSince.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final plan = planFallbackConnect(
        waitingPeerIds: [for (final e in waiting) e.key],
        peers: peers,
        tagsByAddress: _tags,
        connected: connection.connected,
        groupOwner: connection.groupOwner,
        coolingDown: cooling,
      );
      if (!plan.acts) {
        if (plan.reason != 'no_peer' && plan.reason != 'idle') {
          _record(plan.reason, count: peers.length);
        }
        return;
      }
      final address = plan.address!;
      _attemptedAddresses[address.trim().toLowerCase()] = now;
      AppLogger.info('NEARBY',
          detail: 'auto_connect reason=${plan.reason} '
              'intent=${plan.wantHost ? 15 : 0} role='
              '${!connection.connected ? 'none' : connection.groupOwner ? 'host' : 'member'}');
      await connectivity.connectWifiDirect(address,
          wantHost: plan.wantHost, allowLeaveGroup: false);
      _record('connection_requested');
    } catch (error) {
      AppDiagnostics.instance.recordException(
        'wifi_direct_fallback',
        'connection_failed',
        error,
        reasonCode: 'connection_failed',
      );
    } finally {
      _connectionInFlight = false;
    }
  }

  void _record(String state, {int? count}) {
    AppDiagnostics.instance.record(
      'wifi_direct_fallback',
      'state',
      data: <String, Object?>{
        'state': state,
        if (count != null) 'count': count,
      },
    );
  }
}
