import 'dart:async';

import 'package:locallink/core/diagnostics/app_diagnostics.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

/// Starts a bounded Wi-Fi Direct fallback when a requested peer has no route.
/// Android discovery exposes no LocalLink device ID, so automatic connection is
/// attempted only when exactly one eligible nearby peer is present.
///
/// Re-discovery is periodic while any peer is waiting: discovery results are
/// event-driven, but Android silently stops discovery after a while, and a
/// failed connect attempt produces no event at all. Without a re-arm loop the
/// fallback could stall forever until the user sent another message.
final class WifiDirectFallbackService {
  WifiDirectFallbackService(
    this.connectivity, {
    Duration rediscoveryInterval = const Duration(seconds: 45),
  }) : _rediscoveryInterval = rediscoveryInterval;

  static const _retryCooldown = Duration(seconds: 20);

  /// How often discovery is re-armed while any peer waits for a route.
  /// Long enough to sit below the OS rate limits, short enough that a phone
  /// arriving within a minute is picked up without user action.
  final Duration _rediscoveryInterval;

  final ConnectivityRepositoryContract connectivity;
  final Set<String> _waitingPeerIds = <String>{};
  final Map<String, DateTime> _attemptedAddresses = <String, DateTime>{};
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
    _waitingPeerIds.add(normalized);
    _armRediscoveryTimer();
    await _discoverAndConnect();
  }

  /// Called when any route to [peerId] becomes available again (LAN or mesh
  /// recovered). The fallback only makes sense while no route exists, so the
  /// waiter is drained; the re-discovery loop stops once nobody is waiting.
  void cancelWaiting(String peerId) {
    final normalized = peerId.trim();
    if (normalized.isEmpty) return;
    _waitingPeerIds.remove(normalized);
    if (_waitingPeerIds.isEmpty) {
      _rediscoveryTimer?.cancel();
      _rediscoveryTimer = null;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _waitingPeerIds.clear();
    _rediscoveryTimer?.cancel();
    _rediscoveryTimer = null;
    await _wifiSubscription?.cancel();
    _wifiSubscription = null;
  }

  void _handleWifiEvent(dynamic event) {
    if (_disposed || event is! Map || event['type']?.toString() != 'peers') {
      return;
    }
    final raw = event['peers'];
    final peers = raw is List
        ? raw
            .whereType<Map>()
            .map((peer) =>
                WifiDirectPeer.fromMap(Map<dynamic, dynamic>.from(peer)))
            .toList(growable: false)
        : const <WifiDirectPeer>[];
    unawaited(_connectSingleEligiblePeer(peers));
  }

  /// Re-arms discovery while waiters exist. Skips ticks that would overlap
  /// an in-flight discovery or connect — never stacks attempts, never pops
  /// dialogs (the enable request runs at most once per waiting episode by
  /// _discoverAndConnect's own gating inside the repository).
  void _armRediscoveryTimer() {
    if (_rediscoveryTimer != null || _disposed) return;
    _rediscoveryTimer = Timer.periodic(_rediscoveryInterval, (_) {
      if (_disposed || _waitingPeerIds.isEmpty) {
        _rediscoveryTimer?.cancel();
        _rediscoveryTimer = null;
        return;
      }
      if (_discoveryInFlight || _connectionInFlight) return;
      unawaited(_discoverAndConnect());
    });
  }

  Future<void> _discoverAndConnect() async {
    if (_disposed || _waitingPeerIds.isEmpty || _discoveryInFlight) return;
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
      final connection = await connectivity.wifiDirectConnectionInfo();
      if (connection.connected) {
        _record('already_connected');
        return;
      }
      await connectivity.startWifiDirectDiscovery();
      _record('discovery_started');
      await _connectSingleEligiblePeer(await connectivity.wifiDirectPeers());
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

  Future<void> _connectSingleEligiblePeer(List<WifiDirectPeer> peers) async {
    if (_disposed ||
        _waitingPeerIds.isEmpty ||
        _connectionInFlight ||
        peers.length != 1) {
      if (peers.length > 1) _record('ambiguous_peers', count: peers.length);
      return;
    }
    final peer = peers.single;
    if (peer.address.trim().isEmpty || !peer.isAvailable) return;
    final now = DateTime.now();
    final previous = _attemptedAddresses[peer.address];
    if (previous != null && now.difference(previous) < _retryCooldown) return;

    _connectionInFlight = true;
    _attemptedAddresses[peer.address] = now;
    try {
      await connectivity.connectWifiDirect(peer.address);
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
