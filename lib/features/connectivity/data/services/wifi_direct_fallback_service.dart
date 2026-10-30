import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/diagnostics/app_diagnostics.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/nearby_local_net_planner.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';

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
    this.isBusy,
    int Function()? clock,
    Random? random,
    Duration groupTick = const Duration(seconds: 5),
  })  : _rediscoveryInterval = rediscoveryInterval,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _random = random ?? Random(),
        _groupTickInterval = groupTick;

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

  // ---------------------------------------------------- Bundle 157 state
  /// A call is going on (a group is never dissolved under it).
  bool Function()? isBusy;
  final int Function() _clock;
  final Random _random;
  final Duration _groupTickInterval;
  String? _selfHash;
  NearbyGroupRole _role = NearbyGroupRole.none;
  String? _myGroup;
  int _myMembers = 0;
  int _hostSince = 0;
  bool _onWifiNetwork = false;
  bool _selfCharging = false;

  /// Bundle 160 (plan 160.4): blocked Wi-Fi check.
  int _wifiSince = 0;
  int _lastLanAt = 0;
  bool _wifiBlocked = false;

  @visibleForTesting
  bool get wifiBlocked => _wifiBlocked;

  /// On Wi-Fi and the Wi-Fi really connects phones (not blocked).
  bool get _usableWifi => _onWifiNetwork && !_wifiBlocked;

  /// Bundle 159 (battery): the app screen is open. Searching is faster then;
  /// in the background it follows D7 (60 s while someone waits, else 3 min,
  /// or off when nobody waits and this phone is on Wi-Fi alone).
  bool _foreground = true;

  /// Bundle 159.3: read-only state for the admin view (no keys, no names).
  Map<String, Object?> nearbyStatus() => <String, Object?>{
        'role': _role.name,
        'group': _myGroup,
        'members': _myMembers,
        'bridge': _bridging,
        'charging': _selfCharging,
        'foreground': _foreground,
        'nearby_tags': _tags.length,
        'waiting': _waitingSince.length,
        'plan': _lastPlanReason,
        // Bundle 160: this Wi-Fi blocks phones from seeing each other.
        'wifi_blocked': _wifiBlocked,
        // Bundle 161 (tests): linked group / LocalLink hotspot.
        'local_net': _lnState,
        'local_net_kind': _lnKind,
        'hotspot': _hotspotOn,
      };

  /// Called on every app lifecycle change.
  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    AppLogger.info('NEARBY',
        detail: 'search mode=${foreground ? 'foreground' : 'background'}');
  }
  final Map<String, int> _firstSeen = <String, int>{};
  final Map<String, String> _tagState = <String, String>{};
  String? _pairTarget;
  int _pairUntil = 0;
  int _pairAt = 0;
  bool _pairInvited = false;
  bool _pendingUserTap = false;
  int _lostAt = 0;
  int _lostJitterMs = 2000;
  Set<String> _lostMates = const <String>{};
  final Set<String> _mates = <String>{};
  final NearbyGroupBackoff _backoff = NearbyGroupBackoff();
  NearbyGroupActionKind? _pendingKind;
  String? _pendingHost;
  int _pendingSince = 0;
  final Map<String, int> _coolingUntil = <String, int>{};
  final Map<String, int> _joinFailures = <String, int>{};
  List<String> _lastWanted = const <String>[];
  String _lastPlanReason = '';
  int _lastGroupDiscoveryAt = 0;
  bool _groupBusy = false;
  Timer? _groupTimer;

  // ---------------------------------------------------- Bundle 158 bridge
  /// Device ids of LocalLink phones seen on this Wi-Fi (LAN beacons).
  Iterable<String> Function()? lanPeerIds;
  String? _pendingReason;
  bool _bridging = false;
  int _bridgeSince = 0;
  int _bridgeOffUntil = 0;
  final Map<String, int> _bridgeSeen = <String, int>{};

  /// Wi-Fi lost this soon after bridging = this phone can't keep Wi-Fi and a
  /// group at the same time.
  static const int bridgeWifiCheckMs = 20 * 1000;

  /// Then no bridging for this long (plan 158.1).
  static const int bridgeOffMs = 10 * 60 * 1000;

  // ------------------------------------------- Bundle 161 linked networks
  /// The two Settings tests (off by default).
  NearbyExperiments experiments = NearbyExperiments.instance;

  /// `group` / `hotspot` while joining or linked.
  String? _lnKind;
  String? _lnTo;
  String? _lnFromGroup;

  /// `off` / `joining` / `linked`.
  String _lnState = 'off';
  int _lnOffUntil = 0;
  bool _lnUnsupported = false;
  bool _hotspotOn = false;
  int _hotspotOffUntil = 0;
  bool _lnBusy = false;
  bool _listening = false;

  NearbyLocalNetControl? get _localNet {
    final c = connectivity;
    return c is NearbyLocalNetControl ? c as NearbyLocalNetControl : null;
  }

  @visibleForTesting
  String get localNetState => _lnState;
  @visibleForTesting
  String? get localNetKind => _lnKind;
  @visibleForTesting
  bool get hotspotOn => _hotspotOn;
  @visibleForTesting
  int get localNetOffUntil => _lnOffUntil;

  @visibleForTesting
  bool get bridging => _bridging;
  @visibleForTesting
  int get bridgeOffUntil => _bridgeOffUntil;

  NearbyGroupControl? get _group {
    final c = connectivity;
    return c is NearbyGroupControl ? c as NearbyGroupControl : null;
  }

  /// Bundle 157: shared groups are on when the native side supports them and
  /// this phone's tag id is known.
  bool get groupMode => _group != null && _selfHash != null;

  /// Bundle 157: this phone's tag id (16 hex), set once identity is known.
  set selfIdHash(String? value) {
    final clean = value?.trim().toLowerCase();
    _selfHash = (clean == null || clean.isEmpty) ? null : clean;
    if (groupMode) _armGroupTimer();
  }

  @visibleForTesting
  NearbyGroupRole get groupRole => _role;
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
    if (groupMode) _armGroupTimer();
    if (_localNet != null && !_listening) {
      _listening = true;
      experiments.addListener(_onExperimentsChanged);
    }
  }

  /// Bundle 161: a test switch changed — act now, not at the next tick.
  void _onExperimentsChanged() {
    if (_disposed) return;
    if (groupMode) {
      unawaited(_evaluateGroup());
    } else {
      unawaited(_checkLocalNet(_clock()));
    }
  }

  /// Bundle 157: the user tapped Pair on a nearby Wi-Fi Direct phone.
  /// Tagged phones with group support go through the shared-group rules
  /// (join their group, or bring them into ours, no pop-ups); everything
  /// else keeps the 155 connect.
  Future<void> pairTap(WifiDirectPeer peer) async {
    final address = peer.address.trim().toLowerCase();
    final tag = _tags[address] ?? NearbyTagRegistry.instance.tagFor(address);
    if (!groupMode || tag == null) {
      await connectivity.connectWifiDirect(peer.address,
          wantHost: !(tag?.host ?? false), allowLeaveGroup: true);
      return;
    }
    _pairTarget = tag.idHash;
    _pairAt = _clock();
    _pairUntil = _pairAt + 60 * 1000;
    _pairInvited = false;
    AppLogger.info('NEARBY', detail: 'pair_tap target=${tag.idHash} '
        'host=${tag.host} member=${tag.member} gv=${tag.groupAware}');
    _armGroupTimer();
    await _evaluateGroup(userTap: true);
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
    if (_listening) {
      _listening = false;
      experiments.removeListener(_onExperimentsChanged);
    }
    _groupTimer?.cancel();
    _groupTimer = null;
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
      _trackTags(tags);
      if (groupMode) {
        unawaited(_evaluateGroup());
      } else {
        unawaited(_tryConnect(_lastPeers));
      }
      return;
    }
    if (type == 'my_group') {
      _applyMyGroup(event);
      return;
    }
    if (type == 'local_net') {
      _applyLocalNetEvent(event);
      return;
    }
    if (type == 'hotspot') {
      _applyHotspotEvent(event);
      return;
    }
    if (type == 'connection') {
      final raw = event['connection'];
      if (raw is Map) {
        _applyConnection(WifiDirectConnection.fromMap(raw));
      }
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
    if (groupMode) {
      unawaited(_evaluateGroup());
    } else {
      unawaited(_tryConnect(peers));
    }
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
    if (groupMode) {
      await _evaluateGroup();
      return;
    }
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

  // ------------------------------------------------ Bundle 157: the group

  void _armGroupTimer() {
    if (_groupTimer != null || _disposed || !_started) return;
    _groupTimer = Timer.periodic(_groupTickInterval, (_) {
      if (_disposed) return;
      unawaited(_groupTick());
    });
  }

  /// Remembers when each tag was first seen in its current state (merge
  /// waits until another host has been seen for a while), and who shares
  /// my group (D4: they pick the new host if ours leaves).
  void _trackTags(List<NearbyTag> tags) {
    final now = _clock();
    final present = <String>{};
    for (final t in tags) {
      present.add(t.address);
      final state = '${t.host}|${t.member}|${t.group}';
      if (_tagState[t.address] != state) {
        _tagState[t.address] = state;
        _firstSeen[t.address] = now;
      }
      if (_myGroup != null && t.group == _myGroup && !t.host) {
        _mates.add(t.idHash);
      }
      // Bundle 158: when each group last showed a bridge.
      if (t.bridge && t.group != null) _bridgeSeen[t.group!] = now;
    }
    _bridgeSeen.removeWhere((_, at) => now - at > bridgeOffMs);
    _tagState.removeWhere((a, _) => !present.contains(a));
    _firstSeen.removeWhere((a, _) => !present.contains(a));
  }

  void _applyMyGroup(Map<dynamic, dynamic> event) {
    final role = switch (event['role']?.toString()) {
      'host' => NearbyGroupRole.host,
      'member' => NearbyGroupRole.member,
      _ => NearbyGroupRole.none,
    };
    final name = event['name']?.toString();
    if (name != null && name.isNotEmpty && name != _myGroup) _mates.clear();
    _myGroup = (name == null || name.isEmpty) ? null : name;
    _myMembers = (event['members'] as num?)?.toInt() ?? 0;
    // Bundle 159: on a charger = preferred host/bridge on a tie.
    if (event.containsKey('charging')) _selfCharging = event['charging'] == true;
    _setRole(role);
    if (groupMode) unawaited(_evaluateGroup());
  }

  void _applyConnection(WifiDirectConnection c) {
    if (c.wifiNetwork && !_onWifiNetwork) _wifiSince = _clock();
    if (!c.wifiNetwork) _wifiSince = 0;
    _onWifiNetwork = c.wifiNetwork;
    _setRole(!c.connected
        ? NearbyGroupRole.none
        : c.groupOwner
            ? NearbyGroupRole.host
            : NearbyGroupRole.member);
  }

  void _setRole(NearbyGroupRole role) {
    final before = _role;
    if (before == role) return;
    final now = _clock();
    _role = role;
    if (role == NearbyGroupRole.host) _hostSince = now;
    if (role != NearbyGroupRole.host) _hostSince = 0;
    if (role == NearbyGroupRole.none) {
      _myGroup = null;
      _myMembers = 0;
    }
    final leaving = _pendingKind == NearbyGroupActionKind.leave ||
        _pendingKind == NearbyGroupActionKind.leaveAndJoin;
    if (before == NearbyGroupRole.member &&
        role == NearbyGroupRole.none &&
        !leaving) {
      // D4: our host left. Wait 1–4 s, then join the new host — or, as the
      // smallest id of the old group, become it.
      _lostAt = now;
      _lostJitterMs = 1000 + _random.nextInt(3001);
      _lostMates = {..._mates}..remove(_selfHash);
      AppLogger.info('NEARBY',
          detail: 'group host_left mates=${_lostMates.length} '
              'wait_ms=$_lostJitterMs');
      _lastGroupDiscoveryAt = 0;
    }
    if (role != NearbyGroupRole.none) {
      _lostAt = 0;
      _mates.clear();
    }
    _checkPending(now);
    AppLogger.info('NEARBY',
        detail: 'group role ${before.name}->${role.name} '
            'members=$_myMembers grp=${_myGroup ?? '-'}');
  }

  /// A create/join counts as done when the role changed the right way;
  /// after 25 s without that it failed (back-off, and that host cools down).
  void _checkPending(int now) {
    final kind = _pendingKind;
    if (kind == null) return;
    final done = switch (kind) {
      NearbyGroupActionKind.create => _role == NearbyGroupRole.host,
      NearbyGroupActionKind.join ||
      NearbyGroupActionKind.leaveAndJoin =>
        _role == NearbyGroupRole.member,
      NearbyGroupActionKind.leave => _role == NearbyGroupRole.none,
      NearbyGroupActionKind.legacyConnect => _role != NearbyGroupRole.none,
      NearbyGroupActionKind.none => true,
    };
    if (done) {
      _backoff.succeeded();
      if (_pendingHost != null) _joinFailures.remove(_pendingHost);
      final reason = _pendingReason;
      _pendingKind = null;
      _pendingHost = null;
      _pendingReason = null;
      if (reason != null &&
          reason.startsWith('bridge_') &&
          kind != NearbyGroupActionKind.leave) {
        _startBridge(now, reason);
      }
      return;
    }
    if (now - _pendingSince > 25 * 1000) {
      AppLogger.info('NEARBY', detail: 'group ${kind.name} timed_out');
      _failPending(now);
    }
  }

  void _failPending(int now) {
    _backoff.failed(now);
    final reason = _pendingReason;
    _pendingReason = null;
    if (reason != null && reason.startsWith('bridge_')) {
      // Bundle 158: a bridge join/create that fails (busy radio, no
      // Wi-Fi + group at once): no bridging for 10 min.
      _bridgeOffUntil = now + bridgeOffMs;
      AppLogger.info('NEARBY',
          detail: 'group bridge_incapable reason=action_failed off_min=10');
    }
    final host = _pendingHost;
    if (host != null) {
      final n = (_joinFailures[host] ?? 0) + 1;
      _joinFailures[host] = n;
      // Two failed joins: treat that host as full for 10 minutes (D9).
      _coolingUntil[host] = now + (n >= 2 ? 10 * 60 * 1000 : 20 * 1000);
    }
    _pendingKind = null;
    _pendingHost = null;
  }

  Future<void> _groupTick() async {
    if (!groupMode || _disposed) return;
    final now = _clock();
    _checkPending(now);
    if (_pairTarget != null && now > _pairUntil) _pairTarget = null;
    // The Pair target is in our group now: nothing more to do for it.
    if (_pairTarget != null && _myGroup != null) {
      for (final t in _tags.values) {
        if (t.idHash == _pairTarget && t.group == _myGroup) {
          _pairTarget = null;
          break;
        }
      }
    }
    // How often to look for nearby tags (Bundle 159 battery rules, see
    // NearbySearchCadence).
    final urgent = _pairTarget != null ||
        _pendingKind != null ||
        (_lostAt > 0 && now - _lostAt <= NearbyGroupRules.lostWindowMs);
    final everyMs = NearbySearchCadence.everyMs(
      urgent: urgent,
      foreground: _foreground,
      inGroup: _role != NearbyGroupRole.none,
      onWifi: _usableWifi,
      waiting: _waitingSince.isNotEmpty,
    );
    if (everyMs > 0 &&
        !_discoveryInFlight &&
        now - _lastGroupDiscoveryAt >= everyMs) {
      _lastGroupDiscoveryAt = now;
      unawaited(_groupDiscovery());
    }
    await _evaluateGroup();
  }

  Future<void> _groupDiscovery() async {
    if (_discoveryInFlight) return;
    _discoveryInFlight = true;
    try {
      if (!await connectivity.isWifiDirectSupported()) return;
      if (!await connectivity.isWifiDirectPermissionGranted()) return;
      await connectivity.startWifiDirectDiscovery();
    } catch (_) {
      // Busy radio: the next tick tries again.
    } finally {
      _discoveryInFlight = false;
    }
  }

  List<String> _waitingHashes() {
    for (final id in _waitingSince.keys.toList()) {
      if (_reachableLocally(id)) cancelWaiting(id);
    }
    final waiting = _waitingSince.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [for (final e in waiting) NearbyTag.idFor(e.key)];
  }

  Future<void> _publishWanted(List<String> waiting) async {
    final group = _group;
    if (group == null) return;
    final wanted = <String>{
      if (_pairTarget != null) NearbyTag.wantedIdFor(_pairTarget!),
      for (final h in waiting) NearbyTag.wantedIdFor(h),
    }.take(3).toList(growable: false);
    if (listEquals(wanted, _lastWanted)) return;
    _lastWanted = wanted;
    try {
      await group.setNearbyWanted(wanted);
    } catch (_) {}
  }

  Future<void> _evaluateGroup({bool userTap = false}) async {
    final group = _group;
    final self = _selfHash;
    if (group == null || self == null || _disposed) return;
    if (_groupBusy) {
      // Never drop a user's tap: run again right after this round.
      if (userTap) _pendingUserTap = true;
      return;
    }
    _groupBusy = true;
    if (_pendingUserTap) {
      userTap = true;
      _pendingUserTap = false;
    }
    try {
      final now = _clock();
      try {
        _applyConnection(await connectivity.wifiDirectConnectionInfo());
      } catch (_) {}
      _checkPending(now);
      _checkWifiBlocked(now);
      await _checkBridge(now);
      await _checkLocalNet(now);
      final waiting = _waitingHashes();
      await _publishWanted(waiting);
      if (_pendingKind != null && !userTap) return;
      _coolingUntil.removeWhere((_, until) => until <= now);
      final plan = planNearbyGroup(NearbyGroupInput(
        selfHash: self,
        now: now,
        role: _role,
        myGroup: _myGroup,
        myMembers: _myMembers,
        hostSince: _hostSince,
        onWifiNetwork: _usableWifi,
        tags: _tags.values.toList(growable: false),
        firstSeen: {..._firstSeen},
        waiting: waiting,
        pairTarget: _pairTarget,
        pairAgeMs: now - _pairAt,
        pairInviteAllowed: !_pairInvited,
        cooling: _coolingUntil.keys.toSet(),
        lostAt: _lostAt,
        lostJitterMs: _lostJitterMs,
        lostMates: _lostMates,
        busy: _isBusy(),
        lanPeers: _lanHashes(),
        bridgeAllowed: !_bridging && now >= _bridgeOffUntil,
        bridgeSeen: {..._bridgeSeen},
        selfCharging: _selfCharging,
      ));
      if (plan.reason != _lastPlanReason) {
        _lastPlanReason = plan.reason;
        AppLogger.info('NEARBY',
            detail: 'group plan=${plan.kind.name} reason=${plan.reason} '
                'role=${_role.name} members=$_myMembers '
                'tags=${_tags.length}');
      }
      if (!plan.acts) return;
      if (!_backoff.mayAct(now, userTap: userTap)) return;
      if (plan.kind == NearbyGroupActionKind.legacyConnect &&
          _pairTarget != null) {
        _pairInvited = true;
      }
      await _runGroupAction(group, plan, now);
    } finally {
      _groupBusy = false;
      if (_pendingUserTap && !_disposed) unawaited(_evaluateGroup());
    }
  }

  bool _isBusy() {
    try {
      return isBusy?.call() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _runGroupAction(
      NearbyGroupControl group, NearbyGroupAction plan, int now) async {
    _backoff.acted(now);
    _pendingKind = plan.kind;
    _pendingReason = plan.reason;
    _pendingSince = now;
    if (plan.kind == NearbyGroupActionKind.leave && _bridging) {
      // Our bridge group closed empty: nobody needed it, rest 10 min.
      _bridgeOffUntil = now + bridgeOffMs;
      await _stopBridge('group_closed');
    }
    _pendingHost = plan.host?.address ?? plan.address;
    AppLogger.info('NEARBY',
        detail: 'group do=${plan.kind.name} reason=${plan.reason}'
            '${plan.host != null ? ' host=${plan.host!.idHash} '
                'members=${plan.host!.members} key=${plan.host!.key != null ? 1 : 0}' : ''}');
    _record('group_${plan.kind.name}');
    try {
      switch (plan.kind) {
        case NearbyGroupActionKind.join:
        case NearbyGroupActionKind.leaveAndJoin:
          final host = plan.host!;
          // After 1 failed password join, use the classic connect.
          final useKey = (_joinFailures[host.address] ?? 0) == 0;
          await group.joinNearbyGroup(
            name: useKey ? host.group : null,
            key: useKey ? host.key : null,
            address: host.address,
            leave: plan.kind == NearbyGroupActionKind.leaveAndJoin,
          );
        case NearbyGroupActionKind.create:
          await group.createNearbyGroup();
        case NearbyGroupActionKind.leave:
          await connectivity.disconnectWifiDirect();
        case NearbyGroupActionKind.legacyConnect:
          await connectivity.connectWifiDirect(plan.address!,
              wantHost: plan.wantHost, allowLeaveGroup: false);
        case NearbyGroupActionKind.none:
          break;
      }
    } catch (error) {
      AppLogger.info('NEARBY',
          detail: 'group ${plan.kind.name} failed error=$error');
      _failPending(now);
    }
  }

  // ------------------------------------------- Bundle 160: blocked Wi-Fi

  /// Wi-Fi that never lets us hear the LocalLink phones we see nearby:
  /// act as if not on Wi-Fi (join the nearby group). Logged once each way.
  void _checkWifiBlocked(int now) {
    if (_lanHashes().isNotEmpty) _lastLanAt = now;
    final blocked = NearbyWifiCheck.looksBlocked(
      onWifi: _onWifiNetwork,
      wifiSince: _wifiSince,
      lastLanAt: _lastLanAt,
      now: now,
      tags: _tags.values,
    );
    if (blocked == _wifiBlocked) return;
    _wifiBlocked = blocked;
    AppLogger.info('NEARBY',
        detail: blocked
            ? 'wifi_blocked on - no phones heard on this Wi-Fi for 60 s, using nearby groups'
            : 'wifi_blocked off');
  }

  // ------------------------------------------------ Bundle 158: the bridge

  Set<String> _lanHashes() {
    try {
      return {
        for (final id in lanPeerIds?.call() ?? const <String>[])
          if (id.trim().isNotEmpty) NearbyTag.idFor(id),
      };
    } catch (_) {
      return const <String>{};
    }
  }

  void _startBridge(int now, String reason) {
    if (_bridging) return;
    _bridging = true;
    _bridgeSince = now;
    AppLogger.info('NEARBY',
        detail: 'group bridge on reason=$reason role=${_role.name} '
            'grp=${_myGroup ?? '-'}');
    unawaited(_setBridgeFlag(true));
  }

  Future<void> _stopBridge(String reason) async {
    if (!_bridging) return;
    _bridging = false;
    AppLogger.info('NEARBY', detail: 'group bridge off reason=$reason');
    await _setBridgeFlag(false);
  }

  Future<void> _setBridgeFlag(bool on) async {
    final c = connectivity;
    if (c is! NearbyBridgeControl) return;
    try {
      await (c as NearbyBridgeControl).setNearbyBridge(on);
    } catch (_) {}
  }

  /// Keeps the bridge honest: off when we left the group or lost Wi-Fi. Wi-Fi
  /// lost within 20 s of bridging means this phone can't do both: leave the
  /// group (Wi-Fi comes back), no bridging for 10 min.
  Future<void> _checkBridge(int now) async {
    if (!_bridging) return;
    if (_role == NearbyGroupRole.none) {
      await _stopBridge('left_group');
      return;
    }
    if (_onWifiNetwork) return;
    if (now - _bridgeSince <= bridgeWifiCheckMs) {
      _bridgeOffUntil = now + bridgeOffMs;
      AppLogger.info('NEARBY',
          detail: 'group bridge_incapable reason=wifi_lost off_min=10');
      await _stopBridge('incapable');
      _pendingKind = NearbyGroupActionKind.leave;
      _pendingReason = 'bridge_leave';
      _pendingSince = now;
      _pendingHost = null;
      try {
        await connectivity.disconnectWifiDirect();
      } catch (_) {}
      return;
    }
    // Wi-Fi went away later (walked off): stay in the group as a normal
    // member — never break routes.
    await _stopBridge('wifi_off');
  }

  // ------------------------------------------------ Bundle 161 (tests)

  /// Follows the two Settings tests: our own hotspot, and joining another
  /// group / a LocalLink hotspot when groups cannot merge.
  Future<void> _checkLocalNet(int now) async {
    final ln = _localNet;
    final self = _selfHash;
    if (ln == null || self == null || _disposed || _lnBusy) return;
    final plan = planLocalNet(LocalNetInput(
      selfHash: self,
      now: now,
      role: _role.name,
      myGroup: _myGroup,
      myMembers: _myMembers,
      onUsableWifi: _usableWifi,
      tags: _tags.values.toList(growable: false),
      firstSeen: {..._firstSeen},
      linkGroupsOn: experiments.linkGroups,
      shareHotspotOn: experiments.shareHotspot,
      hotspotOn: _hotspotOn,
      hotspotAllowed: now >= _hotspotOffUntil,
      linkedKind: _lnKind,
      linkedTo: _lnTo,
      linkedFromGroup: _lnFromGroup,
      offUntil: _lnOffUntil,
      unsupported: _lnUnsupported,
      busy: _pendingKind != null || (isBusy?.call() ?? false),
    ));
    _publishLocalNetStatus(now);
    if (!plan.acts) return;
    _lnBusy = true;
    try {
      switch (plan.kind) {
        case LocalNetActionKind.startHotspot:
          _hotspotOn = true;
          experiments.updateStatus(hotspotState: 'starting');
          AppLogger.info('NEARBY', detail: 'hotspot start reason=${plan.reason}');
          final why = await ln.startLocalHotspot();
          if (why != null) _hotspotFailed(why, now);
        case LocalNetActionKind.stopHotspot:
          _hotspotOn = false;
          experiments.updateStatus(hotspotState: 'off');
          AppLogger.info('NEARBY', detail: 'hotspot stop reason=${plan.reason}');
          await ln.stopLocalHotspot(plan.reason);
        case LocalNetActionKind.leave:
          AppLogger.info('NEARBY',
              detail: 'local_net leave kind=$_lnKind reason=${plan.reason}');
          _clearLocalNet();
          await ln.leaveLocalNet(plan.reason);
          await ln.setNearbyLinkTarget(null);
        case LocalNetActionKind.linkGroup:
        case LocalNetActionKind.joinHotspot:
          final t = plan.target!;
          final group = plan.kind == LocalNetActionKind.linkGroup;
          final ssid = group ? t.group! : t.hotspotSsid!;
          final key = group ? t.key! : t.hotspotKey!;
          _lnKind = group ? 'group' : 'hotspot';
          _lnTo = ssid;
          _lnFromGroup = _myGroup;
          _lnState = 'joining';
          AppLogger.info('NEARBY',
              detail: 'local_net join kind=$_lnKind target=${t.idHash} '
                  'reason=${plan.reason} v6=${t.v6 != null}');
          // Claim the pair at once so group-mates don't link it too.
          if (group) await ln.setNearbyLinkTarget(NearbyTag.linkIdFor(ssid));
          final why = await ln.joinLocalNet(
              kind: _lnKind!, ssid: ssid, key: key, v6: group ? t.v6 : null);
          if (why != null) await _localNetFailed(why, now);
        case LocalNetActionKind.none:
          break;
      }
    } catch (error) {
      AppLogger.info('NEARBY', detail: 'local_net error=$error');
      if (plan.kind == LocalNetActionKind.startHotspot) {
        _hotspotFailed('error', now);
      } else if (plan.kind == LocalNetActionKind.linkGroup ||
          plan.kind == LocalNetActionKind.joinHotspot) {
        await _localNetFailed('error', now);
      }
    } finally {
      _lnBusy = false;
      _publishLocalNetStatus(now);
    }
  }

  void _clearLocalNet() {
    _lnKind = null;
    _lnTo = null;
    _lnFromGroup = null;
    _lnState = 'off';
  }

  Future<void> _localNetFailed(String reason, int now) async {
    final wasGroup = _lnKind == 'group';
    _clearLocalNet();
    if (reason == 'unsupported_os') {
      _lnUnsupported = true;
    } else {
      _lnOffUntil = now + LocalNetRules.failRestMs;
    }
    experiments.updateStatus(reason: reason);
    AppLogger.info('NEARBY', detail: 'local_net failed reason=$reason');
    // Give the network back to Android (a held request keeps Wi-Fi busy).
    try {
      await _localNet?.leaveLocalNet('failed');
    } catch (_) {}
    if (wasGroup) {
      try {
        await _localNet?.setNearbyLinkTarget(null);
      } catch (_) {}
    }
  }

  void _hotspotFailed(String reason, int now) {
    _hotspotOn = false;
    _hotspotOffUntil = now + LocalNetRules.failRestMs;
    experiments.updateStatus(hotspotState: 'failed', reason: reason);
    AppLogger.info('NEARBY', detail: 'hotspot failed reason=$reason');
  }

  void _applyLocalNetEvent(Map<dynamic, dynamic> event) {
    final state = event['state']?.toString();
    final reason = event['reason']?.toString();
    final now = _clock();
    switch (state) {
      case 'linked':
        if (_lnKind != null) _lnState = 'linked';
      case 'link_lost':
        if (_lnKind != null) _lnState = 'joining';
      case 'failed':
        if (_lnKind != null) unawaited(_localNetFailed(reason ?? 'failed', now));
      case 'left':
        if (_lnKind != null) {
          // The other network went away by itself: rest a little.
          final wasGroup = _lnKind == 'group';
          _clearLocalNet();
          _lnOffUntil = now + LocalNetRules.lostRestMs;
          if (wasGroup) {
            unawaited(_localNet?.setNearbyLinkTarget(null).catchError((_) {}));
          }
        }
    }
    AppLogger.info('NEARBY',
        detail: 'local_net event state=$state reason=$reason');
    _publishLocalNetStatus(now);
  }

  void _applyHotspotEvent(Map<dynamic, dynamic> event) {
    final state = event['state']?.toString();
    final reason = event['reason']?.toString();
    final now = _clock();
    switch (state) {
      case 'on':
        _hotspotOn = true;
        experiments.updateStatus(hotspotState: 'on');
      case 'failed':
        _hotspotFailed(reason ?? 'failed', now);
      case 'off':
        if (_hotspotOn && experiments.shareHotspot) {
          // Android stopped it while the switch is on: don't loop.
          _hotspotFailed(reason ?? 'stopped', now);
        } else {
          _hotspotOn = false;
          experiments.updateStatus(hotspotState: 'off');
        }
    }
  }

  void _publishLocalNetStatus(int now) {
    final String link;
    if (!experiments.linkGroups) {
      link = 'off';
    } else if (_lnUnsupported) {
      link = 'unsupported';
    } else if (_lnKind != null) {
      link = _lnState;
    } else if (now < _lnOffUntil) {
      link = 'resting';
    } else {
      link = 'waiting';
    }
    experiments.updateStatus(
        linkState: link, linkKind: _lnKind, clearKind: _lnKind == null);
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
