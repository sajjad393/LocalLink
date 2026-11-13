import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/diagnostics/app_diagnostics.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/friend_link_memo.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';
import 'package:locallink/features/connectivity/data/services/nearby_friend_link.dart';
import 'package:locallink/features/connectivity/data/services/nearby_ble.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/nearby_local_net_planner.dart';
import 'package:locallink/features/connectivity/data/services/p2p_pause_262.dart';
import 'package:locallink/features/connectivity/data/services/host_rehost_295.dart';
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

  /// Bundle 177 (4.3): battery for the closed-app search rules (Q2).
  int _batteryLevel = -1;

  /// Bundle G3: last known battery % (-1 = not known yet).
  int get batteryLevel => _batteryLevel;
  bool _batteryCharging = false;
  bool _batteryStopLogged = false;

  /// Bundle 177 (4.4): true = the admin switched Wi-Fi off for this phone, so
  /// Nearby does nothing (no search, no join, no new group).
  bool Function()? nearbyOff;

  bool _off() {
    try {
      return nearbyOff?.call() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Bundle 177 (6.1): Add friend on a phone whose tag is not known yet -
  /// wait for its tag (60 s) instead of the old pop-up connect.
  String? _pairWaitAddress;
  int _pairWaitUntil = 0;

  /// Bundle 159.3: read-only state for the admin view (no keys, no names).
  Map<String, Object?> nearbyStatus() => <String, Object?>{
        'role': _role.name,
        'group': _myGroup,
        'members': _myMembers,
        'bridge': _bridging,
        'charging': _selfCharging,
        'foreground': _foreground,
        'battery': _batteryLevel,
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
  String? _lastSilentSkip;
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

  // ------------------------------------------ Bundle 261 (G)
  /// G1: the group name tried in the pending join, and per host address the
  /// group name whose join failed. A host seen later with ANOTHER group
  /// name (it made a new group) is not "full" any more.
  String? _pendingGroup261;
  final Map<String, String> _failedGroup261 = <String, String>{};

  /// G3: the "empty and deaf" leave: when it was last done, and no own new
  /// group (create) for 60 s after it.
  static const int deafLeaveEveryMs261 = 5 * 60 * 1000;
  static const int deafNoCreateMs261 = 60 * 1000;
  int _deafLeftAt261 = 0;
  int _noCreateUntil261 = 0;
  String _createHeldLogged261 = '';

  @visibleForTesting
  Set<String> get joinCooling261 => _coolingUntil.keys.toSet();

  /// Bundle 262 (B2): Wi-Fi Direct switched off by the phone.
  final P2pPause262 _p2p262 = P2pPause262();
  // Bundle 295 (C): the host makes its group again at once after a short off.
  final HostRehost295 _rehost295 = HostRehost295();
  @visibleForTesting
  bool get p2pOff262 => _p2p262.isOff(_clock());

  List<String> _lastWanted = const <String>[];
  String _lastPlanReason = '';
  int _lastGroupDiscoveryAt = 0;

  /// Bundle 205 (P2): search at the next tick (group lost / Wi-Fi off).
  bool _searchSoon = false;

  /// Bundle 225 (P1): an outgoing call waits for this friend (device id),
  /// who has no link at all. Cleared by the call side or at [_callUntil].
  String? _callTarget;
  int _callUntil = 0;
  bool _callAddedWaiter = false;

  /// Bundle 225: safety limit (the call itself gives up after 60 s).
  static const int callWaitLimitMs = 65 * 1000;

  @visibleForTesting
  String? get callTarget => _callTarget;

  // ------------------------------------------ Bundle 226: Bluetooth LE (B4)
  final BleSightings _ble = BleSightings();
  int _bleEchoAt = 0;
  BleWants? _bleSent;
  int _bleSentAt = 0;
  bool _bleAsked = false;

  /// Fresh Bluetooth sightings (tests / status).
  Map<String, BleSighting> bleSeen() => _ble.fresh(_clock());

  /// Bundle 225 (P1): [peerId] = the friend an outgoing call waits for (no
  /// router, Wi-Fi Direct or mesh link); null = the wait is over. While set:
  /// urgent searching and the pair's friend group opens / joins at once.
  void callWaiting(String? peerId) {
    final id = peerId?.trim() ?? '';
    if (id.isEmpty) {
      _clearCallTarget('call_side');
      return;
    }
    if (_disposed) return;
    if (_callTarget == id) return;
    if (_callTarget != null) _clearCallTarget('replaced');
    _callTarget = id;
    _callUntil = _clock() + callWaitLimitMs;
    _callAddedWaiter = !_waitingSince.containsKey(id);
    _searchSoon = true;
    AppLogger.info('NEARBY',
        detail: 'call_wait start friend=${NearbyTag.idFor(id).substring(0, 8)}');
    unawaited(requestRoute(id));
  }

  void _clearCallTarget(String why) {
    final id = _callTarget;
    if (id == null) return;
    _callTarget = null;
    _callUntil = 0;
    AppLogger.info('NEARBY', detail: 'call_wait end why=$why');
    // The call added this waiter: drop it again (no extra searching for
    // 10 min after the call). A waiter that was there before stays.
    if (_callAddedWaiter) cancelWaiting(id);
    _callAddedWaiter = false;
  }

  /// The call target, or null when none / its time is over.
  String? _activeCallTarget(int now) {
    if (_callTarget != null && now > _callUntil) _clearCallTarget('timeout');
    return _callTarget;
  }

  /// Bundle 205 (P2): when a friend that was reachable nearby went missing
  /// (0 = nobody missing).
  int _friendLostAt = 0;
  bool _groupBusy = false;
  Timer? _groupTimer;

  // ------------------------------------------ Bundle 200: friend link (B)
  /// Link keys per friend: device id -> link keys (hex, newest first). From
  /// the sealing transport (Bundle 160). Null = no friend backup link.
  Map<String, List<String>> Function()? friendLinkKeys;

  /// Friends with messages waiting (outbox). Read at most every 15 s.
  Future<Set<String>> Function()? pendingPeers;
  final Map<String, int> _friendWantedSince = <String, int>{};
  final Set<String> _friendSignLogged = <String>{};
  final Map<String, int> _friendSkipUntil = <String, int>{};
  final Map<String, int> _friendFailures = <String, int>{};
  final Map<String, FriendLinkCredentials> _friendCreds =
      <String, FriendLinkCredentials>{};
  Set<String> _friendGroupNames = const <String>{};
  Set<String> _friendPending = const <String>{};
  int _friendPendingAt = -1;
  int _friendOpenRestUntil = 0;
  int _friendIdleCloses = 0;
  String? _friendPendingSkipKey;
  bool _inFriendGroup = false;
  String _lastFriendReason = '';

  // ------------------------------------------ Bundle 201: friend memo (A)
  /// Read / write one small setting (the store). Null = memory only.
  Future<String?> Function(String key)? readMemo;
  Future<void> Function(String key, String value)? writeMemo;
  final FriendLinkMemo _memo = FriendLinkMemo();
  bool _memoLoaded = false;
  String _memoWritten = '';
  bool _memoWriting = false;
  int _phoneSeenAt = 0;
  String? _friendPendingId;
  String? _friendPendingAddress;
  String _friendPendingReason = '';

  @visibleForTesting
  FriendLinkMemo get friendMemo => _memo;

  /// Wait for the friend's tag: 20 s, 5 s when tags are deaf here (A2).
  int get _signWaitMs => _memo.deaf
      ? FriendLinkRules.deafSignWaitMs
      : FriendLinkRules.signWaitMs;

  @visibleForTesting
  int get friendOpenRestUntil => _friendOpenRestUntil;
  @visibleForTesting
  Set<String> get friendSkipped => _friendSkipUntil.keys.toSet();

  // ---------------------------------------------------- Bundle 158 bridge
  /// Device ids of LocalLink phones seen on this Wi-Fi (LAN beacons).
  Iterable<String> Function()? lanPeerIds;

  // ------------------------------------------ Bundle 260 (A1): dead group
  /// Device ids linked through the Wi-Fi Direct group now (bound by
  /// AppDependencies; null = not known, never "dead").
  Iterable<String> Function()? groupPeerIds;
  static const int groupDeadMs = 30 * 1000;
  static const int groupDeadCoolMs = 10 * 60 * 1000;
  int _memberSince = 0;
  int _groupLinkSeenAt = 0;
  String? _memberHost;
  final Map<String, int> _deadGroupUntil = <String, int>{};
  final Map<String, int> _deadGroupLeftAt = <String, int>{};
  String? _deadLoggedGroup;

  /// Bundle 260 (A3): newest time a friend that is missing now was
  /// reachable, while this phone is on the router Wi-Fi (0 = none).
  int _friendLostOnWifiAt = 0;

  @visibleForTesting
  Set<String> get deadGroupCooling => _deadGroupUntil.keys.toSet();
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
    unawaited(_loadMemo());
    // Bundle 177 (5.2): start from the real group state (the closed app may
    // already be in a group), never "leave then join again".
    unawaited(_readRealState());
    unawaited(_readBleStatus()); // Bundle 226
    if (groupMode) _armGroupTimer();
    if (_localNet != null && !_listening) {
      _listening = true;
      experiments.addListener(_onExperimentsChanged);
    }
  }

  /// Bundle 201 (A1): what the other engine (screen / background) knew.
  Future<void> _loadMemo() async {
    final read = readMemo;
    if (read == null || _memoLoaded) return;
    try {
      final raw = await read(FriendLinkMemo.settingKey);
      final now = _clock();
      final saved = FriendLinkMemo.decode(raw, now);
      _memoWritten = raw ?? '';
      // Merge: the older "missing since" wins (it is the real one).
      for (final e in saved.wantedSince.entries) {
        final mine = _friendWantedSince[e.key];
        if (mine == null || e.value < mine) _friendWantedSince[e.key] = e.value;
      }
      for (final e in saved.lastReachable.entries) {
        final mine = _memo.lastReachable[e.key] ?? 0;
        if (e.value > mine) _memo.lastReachable[e.key] = e.value;
      }
      for (final e in saved.wdAddress.entries) {
        _memo.wdAddress.putIfAbsent(e.key, () => e.value);
      }
      if (_memo.quietAt < saved.quietAt) {
        _memo.quietWindows = saved.quietWindows;
        _memo.quietAt = saved.quietAt;
      }
      AppLogger.info('WD_FRIEND_MEMO',
          detail: 'loaded missing=${saved.wantedSince.length} '
              'quiet=${_memo.quietWindows} known=${_memo.wdAddress.length}');
    } catch (_) {
    } finally {
      _memoLoaded = true;
    }
  }

  /// Writes the memo only when it changed (minute steps keep it rare).
  void _saveMemo() {
    final write = writeMemo;
    if (write == null || !_memoLoaded || _memoWriting || _disposed) return;
    final now = _clock();
    _memo.wantedSince
      ..clear()
      ..addAll(_friendWantedSince);
    final text = _memo.encode(now);
    // 'at' changes every call: compare without it.
    if (_memoBody(text) == _memoBody(_memoWritten)) return;
    _memoWriting = true;
    _memoWritten = text;
    unawaited(() async {
      try {
        await write(FriendLinkMemo.settingKey, text);
      } catch (_) {
      } finally {
        _memoWriting = false;
      }
    }());
  }

  static String _memoBody(String text) =>
      text.replaceFirst(RegExp(r'"at":\d+,'), '');

  /// Bundle 201 (A2): one tag search window ended.
  void _onTagWindow(Map<dynamic, dynamic> event) {
    final heard = (event['heard'] as num?)?.toInt() ?? 0;
    final peers = (event['peers'] as num?)?.toInt() ?? 0;
    if (_memo.tagWindow(heard: heard, peers: peers, now: _clock())) {
      AppLogger.info('WD_SIGN',
          detail: 'deaf windows=${_memo.quietWindows} '
              'wait_s=${FriendLinkRules.deafSignWaitMs ~/ 1000}');
    }
    _saveMemo();
  }

  Future<void> _readRealState() async {
    try {
      final c = await connectivity.wifiDirectConnectionInfo();
      if (_disposed) return;
      if (c.connected && _role == NearbyGroupRole.none) {
        _applyConnection(c);
      } else {
        _batteryLevel = c.batteryLevel;
        _batteryCharging = c.charging;
      }
    } catch (_) {
      // No Nearby on this phone / tests: the events fill it in later.
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
    // Bundle 223 (Q13): a name-only tag can't join silently (no password);
    // wait for the full tag like an untagged phone.
    final known = NearbyTagRegistry.instance.tagFor(address);
    final tag = _tags[address] ?? (known != null && !known.fromName ? known : null);
    if (!groupMode || tag == null) {
      // Bundle 177 (Q6): no pop-up connect. Look for the phone's tag and add
      // it the silent way as soon as the tag shows up (60 s).
      _pairWaitAddress = address;
      _pairWaitUntil = _clock() + 60 * 1000;
      AppLogger.info('NEARBY', detail: 'pair_wait_tag group_mode=$groupMode');
      unawaited(_groupDiscovery());
      return;
    }
    _pairWaitAddress = null;
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
    _mergeRecheck?.cancel(); // Bundle 224 (D2)
    _mergeRecheck = null;
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
      final all = NearbyTag.listFromEvent(event['peers']);
      // Bundle 223 (F, Q13): name-only tags have no group name / password;
      // they fill the Nearby list (registry) but never the group rules.
      final tags = [for (final t in all) if (!t.fromName) t];
      _tags
        ..clear()
        ..addAll({for (final t in tags) t.address: t});
      NearbyTagRegistry.instance.ingest(all);
      _trackTags(tags);
      // Bundle 177 (6.1): the phone we wait for now has a tag.
      final waitFor = _pairWaitAddress;
      if (waitFor != null) {
        if (_clock() > _pairWaitUntil) {
          _pairWaitAddress = null;
        } else if (groupMode && _tags.containsKey(waitFor)) {
          _pairWaitAddress = null;
          final t = _tags[waitFor]!;
          unawaited(pairTap(WifiDirectPeer(
              name: t.idHash, address: waitFor, status: 3)));
          return;
        }
      }
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
    if (type == 'state') {
      _onP2pState262(event['enabled'] == true); // Bundle 262 (B2)
      return;
    }
    if (type == 'tag_window') {
      _onTagWindow(event);
      return;
    }
    // Bundle 226 (B3/B4): Bluetooth LE.
    if (type == 'ble_state') {
      NearbyBleStatus.instance.updateFrom(event);
      return;
    }
    if (type == 'ble_seen') {
      _onBleSeen(event);
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
    _notePhoneSeen(peers);
    if (groupMode) {
      unawaited(_evaluateGroup());
    } else {
      unawaited(_tryConnect(peers));
    }
  }

  /// Bundle 201 (A3): when a phone without a tag was last in the list.
  void _notePhoneSeen(List<WifiDirectPeer> peers) {
    final now = _clock();
    final tagged = <String>{
      for (final t in _tags.values)
        if (now - t.seenAt <= NearbyGroupRules.freshMs) t.address.toLowerCase(),
    };
    if (peers.any((p) =>
        p.isAvailable &&
        !p.groupOwner &&
        p.address.isNotEmpty &&
        !tagged.contains(p.address.toLowerCase()))) {
      _phoneSeenAt = now;
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
    if (_off()) return;
    _discoveryInFlight = true;
    try {
      if (!await connectivity.isWifiDirectSupported()) {
        _record('unsupported');
        return;
      }
      if (!await connectivity.isWifiDirectPermissionGranted()) {
        // Bundle 177 (2.10): never ask from the closed app.
        if (_foreground) {
          await connectivity.requestWifiDirectEnable();
          _record('permission_requested');
        } else {
          _record('no_permission_background');
        }
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
      // Bundle 177 (Q6): the old pop-up connect is gone. Without the shared
      // group rules (no identity yet) nothing connects; the group rules take
      // over once this phone's tag is published.
      _attemptedAddresses[plan.address!.trim().toLowerCase()] = now;
      AppLogger.info('NEARBY',
          detail: 'silent_only_skip reason=${plan.reason}');
      _record('silent_only_skip');
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

  /// Bundle 224 (D2): one timer for the end of the merge wait (the rules
  /// and the 10 s wait itself are unchanged; this only saves the wait for
  /// the next 5 s tick).
  Timer? _mergeRecheck;

  @visibleForTesting
  static int mergeRecheckMs = NearbyGroupRules.mergeSeenMs + 200;

  void _armMergeRecheck() {
    if (_mergeRecheck != null || _disposed || !groupMode) return;
    _mergeRecheck = Timer(Duration(milliseconds: mergeRecheckMs), () {
      _mergeRecheck = null;
      if (_disposed || !groupMode) return;
      unawaited(_evaluateGroup());
    });
  }

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
        // Bundle 224 (D2): a host of another group appeared while we host -
        // check again the moment the 10 s merge wait ends.
        if (t.host &&
            t.group != null &&
            t.group != _myGroup &&
            _role == NearbyGroupRole.host) {
          _armMergeRecheck();
        }
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

  /// Bundle 224 (A5): in a group LinkUp did not make (Realme Share / XShare).
  bool _foreignGroup = false;

  /// Bundle 224 (A5): the last group was foreign - its end is not "our host
  /// left" (D4 has no LinkUp mates to wait for).
  bool _lastGroupForeign = false;

  void _applyMyGroup(Map<dynamic, dynamic> event) {
    // Bundle 224 (A5): older native code sends no key -> false.
    _foreignGroup = event['foreign'] == true;
    if (_foreignGroup) {
      _inFriendGroup = false;
      _lastGroupForeign = true;
    } else if ((event['name']?.toString() ?? '').isNotEmpty) {
      _lastGroupForeign = false;
    }
    final role = switch (event['role']?.toString()) {
      'host' => NearbyGroupRole.host,
      'member' => NearbyGroupRole.member,
      _ => NearbyGroupRole.none,
    };
    final name = event['name']?.toString();
    if (name != null && name.isNotEmpty && name != _myGroup) {
      _mates.clear();
      // Bundle 260 (A1): another group - its 30 s start again.
      if (_myGroup != null && _role == NearbyGroupRole.member) {
        final now = _clock();
        _memberSince = now;
        _groupLinkSeenAt = now;
      }
    }
    _myGroup = (name == null || name.isEmpty) ? null : name;
    _myMembers = (event['members'] as num?)?.toInt() ?? 0;
    // Bundle 200 (B): in the friend backup group (no D4 new host for it).
    if (_myGroup != null) _inFriendGroup = _friendGroupNames.contains(_myGroup);
    if (_inFriendGroup && _myMembers > 0) _friendIdleCloses = 0;
    // Bundle 159: on a charger = preferred host/bridge on a tie.
    if (event.containsKey('charging')) _selfCharging = event['charging'] == true;
    _setRole(role);
    if (groupMode) unawaited(_evaluateGroup());
  }

  void _applyConnection(WifiDirectConnection c) {
    _batteryLevel = c.batteryLevel;
    _batteryCharging = c.charging;
    if (c.wifiNetwork && !_onWifiNetwork) _wifiSince = _clock();
    if (!c.wifiNetwork) _wifiSince = 0;
    // Bundle 205 (P2): the router went away - look for phones at once.
    if (!c.wifiNetwork && _onWifiNetwork) _searchSoon = true;
    if (!c.wifiNetwork && _onWifiNetwork) _wifiGone261(); // Bundle 261 (G2)
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
    if (before == NearbyGroupRole.host) _rehost295.hostLeft(now); // Bundle 295 (C)
    if (role == NearbyGroupRole.host) _hostSince = now;
    if (role != NearbyGroupRole.host) _hostSince = 0;
    // Bundle 260 (A1): when this phone became a member (and of whom).
    if (role == NearbyGroupRole.member) {
      _memberSince = now;
      _groupLinkSeenAt = now;
      _memberHost = _pendingHost?.trim().toLowerCase();
    } else {
      _memberSince = 0;
      _groupLinkSeenAt = 0;
      _memberHost = null;
    }
    // Bundle 205 (P2): the group ended - look for phones at once.
    if (role == NearbyGroupRole.none) _searchSoon = true;
    if (role == NearbyGroupRole.none) {
      _myGroup = null;
      _myMembers = 0;
    }
    final leaving = _pendingKind == NearbyGroupActionKind.leave ||
        _pendingKind == NearbyGroupActionKind.leaveAndJoin;
    final foreignEnded = role == NearbyGroupRole.none && _lastGroupForeign;
    if (role == NearbyGroupRole.none) _lastGroupForeign = false;
    if (before == NearbyGroupRole.member &&
        role == NearbyGroupRole.none &&
        !leaving &&
        !_inFriendGroup &&
        !foreignEnded) {
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
    if (role == NearbyGroupRole.none && _inFriendGroup) {
      _inFriendGroup = false;
      AppLogger.info('WD_FRIEND_CLOSE',
          detail: 'reason=link_lost was=${before.name}');
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
      if (_pendingHost != null) _failedGroup261.remove(_pendingHost);
      _pendingGroup261 = null;
      final reason = _pendingReason;
      // Bundle 200 (B): the friend group is up.
      if (reason == 'friend_join' || reason == 'friend_open') {
        final skipKey = _friendPendingSkipKey;
        if (skipKey != null) _friendFailures.remove(skipKey);
        _friendPendingSkipKey = null;
        // Bundle 201 (A5): remember the friend's address for next time.
        final id = _friendPendingId;
        final address = _friendPendingAddress;
        // Bundle 226: a join by name over Bluetooth has no address to keep.
        if (reason == 'friend_join' &&
            _friendPendingReason.startsWith('ble_')) {
          AppLogger.info('BLE_JOIN',
              detail: 'friend=${id == null ? '-' : NearbyTag.idFor(id).substring(0, 8)} '
                  'after_ms=${now - _pendingSince} why=$_friendPendingReason');
        }
        if (reason == 'friend_join' &&
            id != null &&
            address != null &&
            address != BleRules.joinAddress) {
          _memo.learnAddress(id, address, now);
          if (_foreground) {
            FriendNearbyHints.instance.wdAddresses =
                _memo.knownHosts(now).values.toSet();
          }
          _saveMemo();
        }
        _friendPendingId = null;
        _friendPendingAddress = null;
        _inFriendGroup = true;
        AppLogger.info(
            reason == 'friend_join' ? 'WD_FRIEND_JOIN' : 'WD_FRIEND_OPEN',
            detail: reason == 'friend_join' ? 'linked' : 'hosting');
      }
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
    // Bundle 200 (B): a friend join that did not form - that host phone is
    // not our friend (or out of range): stop trying and skip it a while.
    final skipKey = _friendPendingSkipKey;
    _friendPendingSkipKey = null;
    final pendingFriendId = _friendPendingId;
    final pendingFriendReason = _friendPendingReason;
    _friendPendingId = null;
    _friendPendingAddress = null;
    _friendPendingReason = '';
    if (reason == 'friend_join' && skipKey != null) {
      final n = (_friendFailures[skipKey] ?? 0) + 1;
      _friendFailures[skipKey] = n;
      if (_friendFailures.length > 64) {
        _friendFailures.remove(_friendFailures.keys.first);
      }
      final ms = n >= 2 ? FriendLinkRules.longSkipMs : FriendLinkRules.skipMs;
      _friendSkipUntil[skipKey] = now + ms;
      // Bundle 201 (A5): a remembered address that failed twice is wrong.
      if (pendingFriendReason == 'known_host' &&
          pendingFriendId != null &&
          n >= 2) {
        _memo.forgetAddress(pendingFriendId);
        _saveMemo();
      }
      AppLogger.info('WD_FRIEND_SKIP',
          detail: 'host=${skipKey.split('|').first} min=${ms ~/ 60000} fails=$n');
      unawaited(_cancelConnectQuietly());
    } else if (reason == 'friend_open') {
      AppLogger.info('WD_FRIEND_OPEN', detail: 'failed');
    }
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
      // Bundle 261 (G1): remember which group name failed.
      final tried = _pendingGroup261;
      if (tried != null && tried.isNotEmpty) _failedGroup261[host] = tried;
    }
    _pendingGroup261 = null;
    _pendingKind = null;
    _pendingHost = null;
  }

  /// Bundle 261 (G1): a host whose join failed now shows ANOTHER group name
  /// (it made a new group after the Wi-Fi went off): the failures were for
  /// the old name only - it is not "full", try it again.
  void _forgetRenamedHosts261(int now) {
    if (_failedGroup261.isEmpty) return;
    final cleared = <String, NearbyTag>{};
    _failedGroup261.forEach((address, failedGroup) {
      NearbyTag? tag = _tags[address];
      if (tag == null) {
        final low = address.toLowerCase();
        for (final t in _tags.values) {
          if (t.address.toLowerCase() == low) {
            tag = t;
            break;
          }
        }
      }
      final t = tag;
      if (t == null || !t.host || t.fromName) return;
      final g = t.group ?? '';
      if (g.isEmpty || now - t.seenAt > NearbyGroupRules.freshMs) return;
      if (g != failedGroup) cleared[address] = t;
    });
    cleared.forEach((address, t) {
      _failedGroup261.remove(address);
      _joinFailures.remove(address);
      _coolingUntil.remove(address);
      final id = t.idHash.length > 8 ? t.idHash.substring(0, 8) : t.idHash;
      AppLogger.info('NEARBY', detail: 'group renamed host=$id cool_cleared');
    });
  }

  /// Bundle 261 (G2): the Wi-Fi went off - every group name changes now, so
  /// the old "failed / full" marks say nothing (the same as an app restart).
  void _wifiGone261() {
    final n = _coolingUntil.length;
    _coolingUntil.clear();
    _joinFailures.clear();
    _failedGroup261.clear();
    AppLogger.info('NEARBY', detail: 'wifi_gone cool_cleared n=$n');
  }

  /// Bundle 262 (B2): off -> no join / create / search until it is back
  /// (no busy loop); on -> the old "failed / full" marks are cleared (all
  /// groups changed while it was off), a search starts and the group is
  /// decided again at once instead of on the next 20 s tick.
  void _onP2pState262(bool enabled) {
    final now = _clock();
    final change = _p2p262.apply(enabled, now);
    if (change == 'off') {
      _rehost295.p2pOff(wasHost: _role == NearbyGroupRole.host, now: now);
      if (_p2p262.waitLogOnce()) {
        AppLogger.info('NEARBY', detail: 'group wait why=p2p_off role=${_role.name}');
      }
      return;
    }
    if (change != 'on') return;
    final n = _coolingUntil.length;
    _coolingUntil.clear();
    _joinFailures.clear();
    _failedGroup261.clear();
    final rehost = _rehost295.p2pOn(now);
    AppLogger.info('NEARBY',
        detail: 'group resume why=p2p_on off_s=${_p2p262.offSeconds(now)} cool_cleared n=$n'
            '${rehost ? ' rehost=1' : ''}');
    if (!groupMode || _disposed) return;
    unawaited(_groupDiscovery());
    unawaited(_evaluateGroup());
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
        _activeCallTarget(now) != null ||
        _pendingKind != null ||
        (_lostAt > 0 && now - _lostAt <= NearbyGroupRules.lostWindowMs);
    // Bundle 205 (P2): linked = in a group with someone; reconnect = a
    // friend nearby lately is missing now.
    final linked = _role == NearbyGroupRole.member ||
        (_role == NearbyGroupRole.host && _myMembers > 0);
    // Bundle 260 (A3): on the router Wi-Fi, a friend's link died lately.
    final lostOnWifi = _usableWifi &&
        _friendLostOnWifiAt > 0 &&
        now >= _friendLostOnWifiAt;
    final everyMs = NearbySearchCadence.everyMs(
      urgent: urgent,
      foreground: _foreground,
      inGroup: _role != NearbyGroupRole.none,
      onWifi: _usableWifi,
      waiting: _waitingSince.isNotEmpty,
      batteryLevel: _batteryLevel,
      charging: _batteryCharging,
      linked: linked,
      reconnectAgoMs: lostOnWifi
          ? now - _friendLostOnWifiAt
          : _friendLostAt > 0 && now >= _friendLostAt
              ? now - _friendLostAt
              : -1,
      lostFriendOnWifi: lostOnWifi,
    );
    // Bundle 177 (Q2): log the battery stop once per low-battery spell.
    final batteryStop = !_foreground &&
        !_batteryCharging &&
        _batteryLevel >= 0 &&
        _batteryLevel <= NearbySearchCadence.stopBatteryLevel;
    if (batteryStop && !_batteryStopLogged) {
      _batteryStopLogged = true;
      AppLogger.info('NEARBY_BG_BATTERY_STOP', detail: 'level=$_batteryLevel');
    } else if (!batteryStop) {
      _batteryStopLogged = false;
    }
    // Bundle 226: the Bluetooth advert follows every tick (also "off").
    unawaited(_publishBle(now));
    if (_off()) return;
    if (!_discoveryInFlight &&
        NearbySearchCadence.due(
          now: now,
          lastAt: _lastGroupDiscoveryAt,
          everyMs: everyMs,
          soon: _searchSoon,
        )) {
      final why = NearbySearchCadence.dueWhy(
        now: now,
        lastAt: _lastGroupDiscoveryAt,
        everyMs: everyMs,
        soon: _searchSoon,
      );
      _searchSoon = false;
      _lastGroupDiscoveryAt = now;
      if (!_foreground || why != 'slot' || everyMs >= 60000) {
        AppLogger.info('NEARBY',
            detail: 'WD_SEARCH_SLOT every_s=${everyMs ~/ 1000} why=$why '
                'role=${_role.name} linked=$linked fg=$_foreground');
      }
      unawaited(_groupDiscovery());
    }
    await _evaluateGroup();
  }

  Future<void> _groupDiscovery() async {
    if (_discoveryInFlight || _off()) return;
    if (_p2p262.isOff(_clock())) return; // Bundle 262 (B2): Wi-Fi Direct is off
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
    if (_off()) return;
    if (_p2p262.isOff(_clock())) {
      // Bundle 262 (B2): Wi-Fi Direct is off - every try would fail busy.
      if (_p2p262.waitLogOnce()) {
        AppLogger.info('NEARBY', detail: 'group wait why=p2p_off role=${_role.name}');
      }
      return;
    }
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
      _noteGroupTick261(now); // Bundle 261 (C1)
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
      // Bundle 167 (5.5): tell nearby phones a call goes on here.
      final busy = _isBusy();
      if (busy != _callFlag) {
        _callFlag = busy;
        unawaited(_setCallFlag(busy));
      }
      final groupDead = _groupDeadNow(now, busy);
      _coolDeadGroups(now);
      _forgetRenamedHosts261(now); // Bundle 261 (G1)
      final planned = planNearbyGroup(NearbyGroupInput(
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
        cooling: {..._coolingUntil.keys, ..._deadGroupUntil.keys},
        lostAt: _lostAt,
        lostJitterMs: _lostJitterMs,
        lostMates: _lostMates,
        busy: busy,
        lanPeers: _lanHashes(),
        bridgeAllowed: !_bridging && now >= _bridgeOffUntil,
        bridgeSeen: {..._bridgeSeen},
        selfCharging: _selfCharging,
        foreignGroup: _foreignGroup,
        groupDead: groupDead,
        deafLeaveAllowed: _deafLeftAt261 <= 0 ||
            now - _deafLeftAt261 >= deafLeaveEveryMs261 ||
            now < _deafLeftAt261,
      ));
      // Bundle 295 (C): back from a short Wi-Fi Direct off as the host.
      final plan = _rehost295.choose(planned, now: now, role: _role, hasGroup: _myGroup != null);
      if (plan.reason != _lastPlanReason) {
        _lastPlanReason = plan.reason;
        AppLogger.info('NEARBY',
            detail: 'group plan=${plan.kind.name} reason=${plan.reason} '
                'role=${_role.name} members=$_myMembers '
                'tags=${_tags.length}');
      }
      if (!plan.acts) {
        // Bundle 224 (A5): no friend link either while in a foreign group.
        if (plan.reason == 'foreign_group') {
          if (_lastFriendReason != 'foreign_group') {
            _lastFriendReason = 'foreign_group';
            AppLogger.info('WD_FRIEND',
                detail: 'plan=none reason=foreign_group role=${_role.name}');
          }
          return;
        }
        // Bundle 200 (B): no tag rule acts - the friend backup link.
        await _evaluateFriendLink(group, now, busy);
        return;
      }
      // Bundle 177 (Q6): never the pop-up connect (older app on the other
      // phone). It needs the new app.
      if (plan.kind == NearbyGroupActionKind.legacyConnect) {
        if (_lastSilentSkip != plan.address) {
          _lastSilentSkip = plan.address;
          AppLogger.info('NEARBY', detail: 'silent_only_skip reason=old_app');
        }
        return;
      }
      // Bundle 261 (G3): right after the "empty and deaf" leave, no own new
      // group for 60 s (joins still go; the user's Pair tap too).
      if (plan.kind == NearbyGroupActionKind.create &&
          plan.reason != 'pair_create' &&
          now < _noCreateUntil261) {
        if (_createHeldLogged261 != plan.reason) {
          _createHeldLogged261 = plan.reason;
          AppLogger.info('NEARBY',
              detail: 'group create_held reason=${plan.reason} why=deaf_leave');
        }
        return;
      }
      if (!_backoff.mayAct(now, userTap: userTap)) return;
      if (plan.reason == 'group_dead') _markGroupDead(now);
      if (plan.reason == 'empty_group_deaf') {
        _deafLeftAt261 = now;
        _noCreateUntil261 = now + deafNoCreateMs261;
        _createHeldLogged261 = '';
      }
      if (plan.reason == HostRehost295.reason) _rehost295.used();
      await _runGroupAction(group, plan, now);
    } finally {
      _groupBusy = false;
      if (_pendingUserTap && !_disposed) unawaited(_evaluateGroup());
    }
  }

  /// Bundle 261 (C1): the group check did not run for this long (the phone
  /// froze the app; the normal tick is 5 s): that time is not "no link".
  static const int groupTickGapMs261 = 45 * 1000;
  int _groupTickAt261 = 0;

  /// Bundle 261 (C1): after a gap the 30 s "no link" count starts again, so
  /// a phone that just woke up first gets 30 s to hear its group.
  void _noteGroupTick261(int now) {
    final last = _groupTickAt261;
    _groupTickAt261 = now;
    if (last <= 0 || now < last || now - last <= groupTickGapMs261) return;
    if (_role == NearbyGroupRole.member && _groupLinkSeenAt > 0) {
      _groupLinkSeenAt = now;
      AppLogger.info('NEARBY',
          detail: 'group tick_gap s=${(now - last) ~/ 1000} dead_count_restart');
    }
  }

  /// Bundle 260 (A1): a member whose group has had no link for 30 s (the
  /// host's app was stopped, its Wi-Fi Direct group is still up). Never
  /// while a call runs, in the first 30 s, in a foreign or friend group, or
  /// while this phone also has a local-net link.
  bool _groupDeadNow(int now, bool busy) {
    final myGroup = _myGroup;
    final read = groupPeerIds;
    if (_role != NearbyGroupRole.member ||
        myGroup == null ||
        _foreignGroup ||
        _inFriendGroup ||
        _lnState != 'off' ||
        read == null) {
      return false;
    }
    var alive = false;
    try {
      alive = read().any((id) => id.trim().isNotEmpty);
    } catch (_) {
      alive = true; // not known: never "dead"
    }
    if (!alive) {
      alive = _tags.values.any((t) =>
          t.host &&
          t.group == myGroup &&
          now >= t.seenAt &&
          now - t.seenAt <= groupDeadMs);
    }
    // On the router Wi-Fi a mate's link may run over the router (a `lan`
    // route): a phone of this group that sends Wi-Fi beacons is alive.
    if (!alive && _usableWifi) {
      final lan = _lanHashes();
      if (lan.isNotEmpty) {
        alive = lan.any(_mates.contains) ||
            _tags.values
                .any((t) => t.group == myGroup && lan.contains(t.idHash));
      }
    }
    if (alive || _groupLinkSeenAt <= 0 || now < _groupLinkSeenAt) {
      _groupLinkSeenAt = now;
      return false;
    }
    if (_memberSince <= 0 || now - _memberSince < groupDeadMs) return false;
    if (now - _groupLinkSeenAt < groupDeadMs) return false;
    if (busy || _activeCallTarget(now) != null) return false;
    return true;
  }

  /// Bundle 260 (A1): this phone leaves a dead group - its host is not
  /// joined again for 10 min (a new tag from it ends that at once).
  void _markGroupDead(int now) {
    final myGroup = _myGroup;
    final addresses = <String>{
      if (_memberHost != null && _memberHost!.isNotEmpty) _memberHost!,
      for (final t in _tags.values)
        if (t.host && t.group == myGroup && t.address.isNotEmpty)
          t.address.toLowerCase(),
    };
    for (final a in addresses) {
      _deadGroupUntil[a] = now + groupDeadCoolMs;
      _deadGroupLeftAt[a] = now;
    }
    if (myGroup != _deadLoggedGroup) {
      _deadLoggedGroup = myGroup;
      AppLogger.info('NEARBY',
          detail: 'group dead grp=${myGroup ?? '-'} '
              'no_link_s=${(now - _groupLinkSeenAt) ~/ 1000} '
              'in_group_s=${(now - _memberSince) ~/ 1000}');
    }
  }

  /// Bundle 260 (A1): cooling ends after 10 min, or when that host sends a
  /// new tag (its app runs again).
  void _coolDeadGroups(int now) {
    if (_deadGroupUntil.isEmpty) return;
    final fresh = <String, int>{
      for (final t in _tags.values) t.address.toLowerCase(): t.seenAt,
    };
    _deadGroupUntil.removeWhere((a, until) {
      final left = _deadGroupLeftAt[a] ?? 0;
      return until <= now || now < left || (fresh[a] ?? 0) > left;
    });
    _deadGroupLeftAt.removeWhere((a, _) => !_deadGroupUntil.containsKey(a));
  }

  // ------------------------------------------ Bundle 200: friend link (B)

  /// Bundle G4: 10% battery or less and not charging (no group catch-up).
  bool get batteryLow =>
      !_batteryCharging &&
      _batteryLevel >= 0 &&
      _batteryLevel <= NearbySearchCadence.stopBatteryLevel;

  bool _friendAllowed() =>
      _foreground ||
      _batteryCharging ||
      _batteryLevel < 0 ||
      _batteryLevel > NearbySearchCadence.stopBatteryLevel;

  Future<void> _refreshFriendPending(int now) async {
    final read = pendingPeers;
    if (read == null) return;
    if (_friendPendingAt >= 0 && now - _friendPendingAt < 15 * 1000) return;
    _friendPendingAt = now;
    try {
      _friendPending = await read();
    } catch (_) {}
  }

  List<FriendLinkFriend> _friendList(int now) {
    Map<String, List<String>> keys;
    try {
      keys = friendLinkKeys?.call() ?? const <String, List<String>>{};
    } catch (_) {
      keys = const <String, List<String>>{};
    }
    final tagHashes = <String>{
      for (final t in _tags.values)
        if (now - t.seenAt <= NearbyGroupRules.freshMs) t.idHash,
    };
    final out = <FriendLinkFriend>[];
    final names = <String>{};
    var missingRecent = 0;
    var lostAt = 0;
    var lostOnWifiAt = 0; // Bundle 260 (A3)
    for (final entry in keys.entries) {
      final id = entry.key.trim();
      if (id.isEmpty || entry.value.isEmpty) continue;
      final hex = entry.value.first;
      final creds =
          _friendCreds[hex] ?? FriendLinkCredentials.fromKeyHex(hex);
      if (creds == null) continue;
      if (_friendCreds.length >= 32) _friendCreds.clear();
      _friendCreds[hex] = creds;
      names.add(creds.name);
      final hash = NearbyTag.idFor(id);
      final reachable = _reachableLocally(id);
      final tagSeen = tagHashes.contains(hash);
      // Bundle 201 (D): reachable nearby lately, missing now.
      if (reachable) {
        _memo.lastReachable[id] = FriendLinkMemo.minute(now);
      } else if (!tagSeen &&
          now - (_memo.lastReachable[id] ?? -FriendLinkRules.recentFriendMs - 1) <=
              FriendLinkRules.recentFriendMs) {
        missingRecent += 1;
      }
      // Bundle 205 (P2): a friend that was reachable is missing now.
      if (!reachable && !tagSeen && !_usableWifi) {
        final was = _memo.lastReachable[id] ?? 0;
        if (was > lostAt) lostAt = was;
      }
      // Bundle 260 (A3): the same on the router Wi-Fi (he walked off it).
      if (!reachable && !tagSeen && _usableWifi) {
        final was = _memo.lastReachable[id] ?? 0;
        if (was > lostOnWifiAt) lostOnWifiAt = was;
      }
      if (reachable || tagSeen || _usableWifi) {
        _friendWantedSince.remove(id);
        _friendSignLogged.remove(id);
      } else {
        _friendWantedSince.putIfAbsent(id, () => now);
      }
      out.add(FriendLinkFriend(
        id: id,
        hash: hash,
        creds: creds,
        reachable: reachable,
        tagSeen: tagSeen,
        wantedSince: _friendWantedSince[id] ?? 0,
        // Bundle 225 (P3): only the friend an away call waits for (a live
        // call no longer marks every friend).
        pending: id == _callTarget || _friendPending.contains(id),
      ));
    }
    _friendWantedSince.removeWhere((id, _) => !keys.containsKey(id));
    _friendSignLogged.removeWhere((id) => !keys.containsKey(id));
    _memo.lastReachable.removeWhere((id, _) => !keys.containsKey(id));
    _memo.wdAddress.removeWhere((id, _) => !keys.containsKey(id));
    _friendGroupNames = names;
    _friendLostAt = lostAt;
    _friendLostOnWifiAt = lostOnWifiAt;
    // Bundle 201 (D): hints for the Nearby list (open app only).
    if (_foreground) {
      FriendNearbyHints.instance
        ..wdAddresses = _memo.knownHosts(now).values.toSet()
        ..missingRecent = _usableWifi ? 0 : missingRecent;
    }
    return out;
  }

  Future<void> _evaluateFriendLink(
      NearbyGroupControl group, int now, bool busy) async {
    if (friendLinkKeys == null || _selfHash == null) return;
    await _refreshFriendPending(now);
    _friendSkipUntil.removeWhere((_, until) => until <= now);
    final friends = _friendList(now);
    for (final f in friends) {
      if (f.wantedSince > 0 &&
          now - f.wantedSince >= _signWaitMs &&
          _friendSignLogged.add(f.id)) {
        // Part C: one search window passed without this friend's tag.
        AppLogger.info('WD_SIGN',
            detail: 'none friend=${f.hash.substring(0, 8)} '
                'after_s=${(now - f.wantedSince) ~/ 1000} '
                'peers=${_lastPeers.length}');
      }
    }
    final plan = planFriendLink(FriendLinkInput(
      now: now,
      selfHash: _selfHash!,
      role: _role,
      myGroup: _myGroup,
      myMembers: _myMembers,
      hostSince: _hostSince,
      onWifi: _usableWifi,
      wifiSince: _wifiSince,
      busy: busy,
      allowed: _friendAllowed(),
      friends: friends,
      peers: _lastPeers,
      taggedAddresses: <String>{
        for (final t in _tags.values)
          if (now - t.seenAt <= NearbyGroupRules.freshMs)
            t.address.toLowerCase(),
      },
      skip: _friendSkipUntil.keys.toSet(),
      openRestUntil: _friendOpenRestUntil,
      signWaitMs: _signWaitMs,
      // Bundle 260 (A1): never the host of a group just left as dead.
      knownHosts: <String, String>{
        for (final e in _memo.knownHosts(now).entries)
          if (!_deadGroupUntil.containsKey(e.value.trim().toLowerCase()))
            e.key: e.value,
      },
      phoneSeenAt: _phoneSeenAt,
      callTargetId: _activeCallTarget(now),
      ble: _ble.fresh(now), // Bundle 226 (B4)
    ));
    _saveMemo();
    if (plan.reason != _lastFriendReason) {
      _lastFriendReason = plan.reason;
      if (plan.acts || friends.any((f) => f.wantedSince > 0)) {
        AppLogger.info('WD_FRIEND',
            detail: 'plan=${plan.kind.name} reason=${plan.reason} '
                'role=${_role.name} friends=${friends.length} '
                'peers=${_lastPeers.length} '
                'hosts=${_lastPeers.where((p) => p.groupOwner).length}');
      }
    }
    if (!plan.acts) return;
    if (!_backoff.mayAct(now)) return;
    await _runFriendAction(group, plan, now);
  }

  Future<void> _runFriendAction(
      NearbyGroupControl group, FriendLinkAction plan, int now) async {
    final friend = plan.friend;
    final who = friend == null ? '-' : friend.hash.substring(0, 8);
    _backoff.acted(now);
    _pendingSince = now;
    _pendingHost = null;
    _friendPendingSkipKey = null;
    try {
      switch (plan.kind) {
        case FriendLinkKind.open:
          final c = connectivity;
          if (c is! NearbyFriendGroupControl || friend == null) return;
          _pendingKind = NearbyGroupActionKind.create;
          _pendingReason = 'friend_open';
          AppLogger.info('WD_FRIEND_OPEN',
              detail: 'friend=$who grp=${friend.creds.shortName} '
                  'reason=${plan.reason}');
          await (c as NearbyFriendGroupControl)
              .createFriendGroup(name: friend.creds.name, key: friend.creds.pass);
        case FriendLinkKind.join:
        case FriendLinkKind.leaveAndJoin:
          if (friend == null || plan.address == null) return;
          final leave = plan.kind == FriendLinkKind.leaveAndJoin;
          _pendingKind = leave
              ? NearbyGroupActionKind.leaveAndJoin
              : NearbyGroupActionKind.join;
          _pendingReason = 'friend_join';
          _friendPendingSkipKey = friendSkipKey(plan.address!, friend.hash);
          _friendPendingId = friend.id;
          _friendPendingAddress = plan.address;
          _friendPendingReason = plan.reason;
          AppLogger.info('WD_FRIEND_JOIN',
              detail: 'friend=$who host=${plan.address} '
                  'grp=${friend.creds.shortName} leave=${leave ? 1 : 0} '
                  'reason=${plan.reason}');
          await group.joinNearbyGroup(
            name: friend.creds.name,
            key: friend.creds.pass,
            address: plan.address!,
            leave: leave,
          );
        case FriendLinkKind.close:
          _pendingKind = NearbyGroupActionKind.leave;
          _pendingReason = 'friend_close';
          var restS = 0;
          if (plan.reason == 'idle') {
            _friendIdleCloses += 1;
            final rest = _friendIdleCloses >= FriendLinkRules.longRestAfterCloses
                ? FriendLinkRules.openLongRestMs
                : FriendLinkRules.openRestMs;
            _friendOpenRestUntil = now + rest;
            restS = rest ~/ 1000;
          }
          AppLogger.info('WD_FRIEND_CLOSE',
              detail: 'reason=${plan.reason} rest_s=$restS');
          await connectivity.disconnectWifiDirect();
        case FriendLinkKind.none:
          return;
      }
    } catch (error) {
      AppLogger.info('WD_FRIEND',
          detail: '${plan.kind.name} failed error=$error');
      _failPending(now);
    }
  }

  // ------------------------------------------ Bundle 226: Bluetooth LE (B4)

  Future<void> _readBleStatus() async {
    final c = connectivity;
    if (c is! NearbyBleControl) return;
    try {
      NearbyBleStatus.instance
          .updateFrom(await (c as NearbyBleControl).bleStatus());
    } catch (_) {}
  }

  void _onBleSeen(Map<dynamic, dynamic> event) {
    final now = _clock();
    final s = BleSighting.fromEvent(event, now);
    final self = _selfHash;
    if (s == null || self == null) return;
    final self8 = NearbyTag.wantedIdFor(self);
    if (s.id8 == self8) return;
    _ble.add(s);
    // Is it a friend (we have a link key)?
    String? friendId;
    try {
      for (final id in (friendLinkKeys?.call() ?? const <String, List<String>>{}).keys) {
        if (NearbyTag.wantedIdFor(NearbyTag.idFor(id)) == s.id8) {
          friendId = id;
          break;
        }
      }
    } catch (_) {}
    final linked = friendId != null
        ? _reachableLocally(friendId)
        : _myGroup != null &&
            _tags.values.any((t) =>
                NearbyTag.wantedIdFor(t.idHash) == s.id8 && t.group == _myGroup);
    // Any LinkUp phone searching now: search too (both at the same moment).
    if (bleSearchEcho(
      s: s,
      now: now,
      lastEchoAt: _bleEchoAt,
      linkedToIt: linked,
      onRouter: _usableWifi,
      liveCall: _isBusy(),
      allowed: _friendAllowed() && !_off(),
    )) {
      _bleEchoAt = now;
      _searchSoon = true;
      AppLogger.info('NEARBY', detail: 'BLE search_echo id=${s.id8}');
    }
    if (friendId == null || linked) return;
    // A friend who wants me (or that I want): act now, not at the next tick.
    final wantsMe = s.wants(self8);
    if (wantsMe && !s.pair) _searchSoon = true; // its host flag comes soon
    final mine = wantsMe ||
        friendId == _callTarget ||
        _friendPending.contains(friendId) ||
        _waitingSince.containsKey(friendId);
    if (mine && groupMode && !_disposed) unawaited(_evaluateGroup());
  }

  /// What my Bluetooth advert says (sent when it changed, or every 60 s).
  BleWants _bleWants(int now) {
    final self = _selfHash;
    if (self == null || _off() || !_friendAllowed()) {
      return const BleWants(self: '');
    }
    final call = _activeCallTarget(now);
    String? pairFriendId;
    final myGroup = _myGroup;
    if (_role == NearbyGroupRole.host && myGroup != null) {
      Map<String, List<String>> keys;
      try {
        keys = friendLinkKeys?.call() ?? const <String, List<String>>{};
      } catch (_) {
        keys = const <String, List<String>>{};
      }
      for (final e in keys.entries) {
        if (e.value.isEmpty) continue;
        final creds =
            _friendCreds[e.value.first] ?? FriendLinkCredentials.fromKeyHex(e.value.first);
        if (creds != null && creds.name == myGroup) {
          pairFriendId = e.key.trim();
          break;
        }
      }
    }
    String id8(String id) => NearbyTag.wantedIdFor(NearbyTag.idFor(id));
    final list = <BleWant>[];
    void add(String id, {bool isCall = false}) {
      final w = id8(id);
      if (list.any((x) => x.id8 == w) || list.length >= 3) return;
      list.add(BleWant(w, call: isCall, pair: id == pairFriendId));
    }

    if (call != null) add(call, isCall: true);
    if (pairFriendId != null) add(pairFriendId);
    for (final id in _friendPending) {
      if (!_reachableLocally(id)) add(id);
    }
    final waiting = _waitingSince.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final e in waiting) {
      add(e.key);
    }
    return BleWants(
      self: NearbyTag.wantedIdFor(self),
      wanted: list,
      urgent: call != null || _pairTarget != null,
      searching: _lastGroupDiscoveryAt > 0 &&
          now - _lastGroupDiscoveryAt <= BleRules.searchWindowMs,
      host: _role == NearbyGroupRole.host,
      member: _role == NearbyGroupRole.member,
      router: _usableWifi,
      foreground: _foreground,
    );
  }

  Future<void> _publishBle(int now) async {
    final c = connectivity;
    if (c is! NearbyBleControl) return;
    final wants = _bleWants(now);
    if (wants == _bleSent && now - _bleSentAt < 60 * 1000) return;
    final first = !_bleAsked;
    _bleAsked = true;
    _bleSent = wants;
    _bleSentAt = now;
    if (first || wants.wanted.isNotEmpty || wants.self.isEmpty) {
      AppLogger.info('NEARBY',
          detail: 'BLE wants=${wants.wanted.join(',')} '
              'urgent=${wants.urgent ? 1 : 0} on=${wants.self.isEmpty ? 0 : 1}');
    }
    try {
      await (c as NearbyBleControl).setBleWanted(wants);
    } catch (_) {}
  }

  Future<void> _cancelConnectQuietly() async {
    try {
      await connectivity.cancelWifiDirectConnect();
    } catch (_) {}
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
    _pendingGroup261 = plan.host?.group; // Bundle 261 (G1)
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
          // Bundle 177 (Q6): always the silent password join (the classic
          // connect fallback showed a pop-up). Failures use the backoff.
          await group.joinNearbyGroup(
            name: host.group,
            key: host.key,
            address: host.address,
            leave: plan.kind == NearbyGroupActionKind.leaveAndJoin,
          );
        case NearbyGroupActionKind.create:
          await group.createNearbyGroup();
        case NearbyGroupActionKind.leave:
          await connectivity.disconnectWifiDirect();
        case NearbyGroupActionKind.legacyConnect:
          // Bundle 177 (Q6): never planned into an action (see above).
          break;
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

  /// Bundle 167: last `call=1` flag sent to the native tag.
  bool _callFlag = false;

  Future<void> _setCallFlag(bool on) async {
    final c = connectivity;
    if (c is! NearbyCallFlagControl) return;
    AppLogger.info('NEARBY', detail: 'call flag ${on ? 'on' : 'off'}');
    try {
      await (c as NearbyCallFlagControl).setNearbyInCall(on);
    } catch (_) {}
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
    // Bundle 210: the hotspot can belong to Share LinkUp too. Only events
    // for the mesh owner count here (old events with no `for` = mesh), or
    // this code would switch the share hotspot off at once.
    if (!hotspotEventIsForMesh(event)) return;
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

/// Bundle 210: true when a native `hotspot` event concerns the mesh owner.
/// Events without `for` come from older code and count as mesh.
bool hotspotEventIsForMesh(Map<dynamic, dynamic> event) {
  final owners = event['for'];
  if (owners is! List) return true;
  return owners.map((e) => e.toString()).contains('mesh');
}
