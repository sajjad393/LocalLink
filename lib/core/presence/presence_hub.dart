import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/presence/switch_rules.dart';
import 'package:locallink/core/services/app_logger.dart';

/// What every screen shows for a person.
enum PresenceStatus { nearby, online, offline }

extension PresenceStatusX on PresenceStatus {
  /// Same values the widgets always used: 'nearby' | 'server' | 'offline'.
  String get channel => switch (this) {
    PresenceStatus.nearby => 'nearby',
    PresenceStatus.online => 'server',
    PresenceStatus.offline => 'offline',
  };

  String get label => switch (this) {
    PresenceStatus.nearby => 'Nearby',
    PresenceStatus.online => 'Online',
    PresenceStatus.offline => 'Offline',
  };
}

/// Bundle 201 (F, mock ST): HOW a person is reached. Only for words and the
/// photo badge - [PresenceStatus] stays the one rule for filters and logic.
enum PresenceWay { wifi, wifiDirect, mesh, nearby, connecting, online, offline }

/// Bundle 201 (F): one local route report. [kind] = 'lan' | 'wifi_direct' |
/// 'mesh' | 'none'; [hops] = hops to them on a mesh route (null = unknown);
/// [via] = the next phone's device id on a mesh route.
class PresenceRoute {
  final String deviceId;
  final String kind;
  final int? hops;
  final String? via;
  const PresenceRoute(this.deviceId, this.kind, {this.hops, this.via});

  bool sameAs(PresenceRoute? o) =>
      o != null && o.kind == kind && o.hops == hops && o.via == via;
}

/// Bundle 201 (F): the way + mesh details for the words.
class PresenceWayInfo {
  final PresenceWay way;
  final int? hops;
  final String? via;
  const PresenceWayInfo(this.way, {this.hops, this.via});

  /// Phones in between on a mesh route (at least 1), null when unknown.
  int? get phonesBetween {
    final h = hops;
    if (h == null || h <= 0) return null;
    return h - 1 < 1 ? 1 : h - 1;
  }

  /// The words under a name (mock ST).
  String get label => switch (way) {
        PresenceWay.wifi => 'Nearby · Wi-Fi',
        PresenceWay.wifiDirect => 'Nearby · Wi-Fi Direct',
        PresenceWay.mesh => phonesBetween == null
            ? 'Nearby · Mesh'
            : 'Nearby · Mesh, via $phonesBetween '
                '${phonesBetween == 1 ? 'phone' : 'phones'}',
        PresenceWay.nearby => 'Nearby',
        PresenceWay.connecting => 'Connecting…',
        PresenceWay.online => 'Online',
        PresenceWay.offline => 'Offline',
      };
}

class _Seen {
  DateTime? nearbyAt;
  DateTime? serverAt;
}

/// Bundle 148: ONE live presence source for the whole app.
///
/// Before, every screen judged status on its own (Chats list from memory,
/// chat header from a DB row polled every 5 s, Calls tab never, Nearby screen
/// from the radio list) and "Nearby" was the OTHER phone's claim about itself.
/// Now:
/// * **Nearby** = WE received something from that person over the direct
///   link (Wi-Fi Direct / same Wi-Fi / mesh) within [window].
/// * **Online** = WE received something via the server within [window], or
///   the server says they are connected right now.
/// * **Offline** = neither.
/// Server events only touch the server path, so a server drop never turns a
/// nearby person Offline. One 5 s tick flips every screen at the same time.
/// Several devices of one person share the best status of any of them.
///
/// Bundle 158 (true status): once the mesh reports paths, **Nearby** means
/// "there is a local path to them right now" — direct (same Wi-Fi / Wi-Fi
/// Direct) or relayed through other phones.
///
/// Bundle 296 (H, true live data): a path is not enough any more.
/// * A direct link counts only while it is proven (our own pong in the last
///   10 s, [noteLinkProof]).
/// * A friend through other phones counts, while LinkUp is open on screen,
///   only with an answer (or anything else from them) in the last 15 s
///   ([reachProof]). Background and old apps keep the path rule.
/// * No grace any more: proof gone = Online / Offline at once.
class PresenceHub extends ChangeNotifier {
  PresenceHub({
    DateTime Function()? clock,
    this.window = const Duration(seconds: 70),
  }) : _now = clock ?? DateTime.now;

  static final PresenceHub instance = PresenceHub();

  /// Presence is sent every 30 s; 70 s survives one lost packet.
  final Duration window;
  final DateTime Function() _now;

  final Map<String, _Seen> _seen = <String, _Seen>{};
  final Map<String, String> _userOf = <String, String>{}; // '' = no user
  final Map<String, Set<String>> _devicesOf = <String, Set<String>>{};
  final Map<String, String> _names = <String, String>{};
  final Set<String> _resolving = <String>{};
  final Map<String, PresenceStatus> _lastShown = <String, PresenceStatus>{};

  /// Bundle 158: is there a local path (direct or relayed) right now?
  final Map<String, bool> _pathUp = <String, bool>{};

  /// Bundle 201 (F): last route report per device (words only).
  final Map<String, PresenceRoute> _routeOf = <String, PresenceRoute>{};

  /// Bundle 296 (H1): direct link proof from the native side (null = no
  /// report, e.g. an old snapshot: the path rule stays).
  final Map<String, bool> _linkProof = <String, bool>{};

  /// Bundle 296 (H2): phones whose app answers the reach check.
  final Set<String> _reachCapable = <String>{};

  /// Bundle 296 (H2): the real way the last answer took (via / hops).
  final Map<String, PresenceRoute> _reachWay = <String, PresenceRoute>{};
  final Map<String, DateTime> _reachWayAt = <String, DateTime>{};

  /// Bundle 296 (H2): reach checks run since (LinkUp open on screen).
  DateTime? _reachSince;

  /// Bundle 205 (P4): the shown way per person ('u:<user>' / 'd:<device>').
  final Map<String, WayShowState> _wayShown = <String, WayShowState>{};
  final Map<String, String> _wayDevice = <String, String>{};
  final Map<String, PresenceWay> _loggedWay = <String, PresenceWay>{};

  /// Bundle 158: Nearby was kept 20 s after the last local path ended.
  /// Bundle 296 (H3): no grace - lost proof shows at once.
  static const Duration pathGrace = Duration.zero;

  /// Bundle 296 (H2): a friend through other phones is Nearby (LinkUp open)
  /// only with an answer or packet from them this recent. One check every
  /// 10 s, so one lost answer never makes them flicker.
  static const Duration reachProof = Duration(seconds: 15);

  /// Bundle 295 (G1): a call to these devices got no answer in 6 s while a
  /// way was stored. They are not Nearby (no grace) until proof comes FROM
  /// them: a packet they sent or a direct link ([noteNearby]). A neighbour's
  /// "I can reach them" (a path report) is not proof.
  final Set<String> _unproven = <String>{};

  /// Bundle 158: re-reads the mesh paths (routes also expire silently).
  Future<void> Function()? refreshPaths;
  int _tickCount = 0;

  Future<String?> Function(String deviceId)? userResolver;
  Future<String?> Function(String deviceId)? nameResolver;
  String? Function()? localDeviceId;

  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];
  Timer? _tick;
  bool _notifyQueued = false;

  /// Wires the hub to the live streams once (app shell).
  void attach({
    required Stream<Map<String, dynamic>> directEvents,
    required Stream<Map<String, dynamic>> serverMessages,
    required Stream<bool> serverConnection,
    String? Function()? localDeviceId,
    Future<String?> Function(String deviceId)? userResolver,
    Future<String?> Function(String deviceId)? nameResolver,
    Stream<MapEntry<String, bool>>? localPaths,
    Iterable<MapEntry<String, bool>> initialPaths =
        const <MapEntry<String, bool>>[],
    Future<void> Function()? refreshPaths,
    // Bundle 201 (F): route kind + hops (words / badge only).
    Stream<PresenceRoute>? localRoutes,
    Iterable<PresenceRoute> initialRoutes = const <PresenceRoute>[],
    // Bundle 296 (H1): direct link proof.
    Stream<MapEntry<String, bool>>? linkProofs,
    Iterable<MapEntry<String, bool>> initialLinkProofs =
        const <MapEntry<String, bool>>[],
  }) {
    this.localDeviceId = localDeviceId ?? this.localDeviceId;
    this.userResolver = userResolver ?? this.userResolver;
    this.nameResolver = nameResolver ?? this.nameResolver;
    this.refreshPaths = refreshPaths ?? this.refreshPaths;
    if (_subs.isNotEmpty) return;
    for (final p in initialPaths) {
      notePath(p.key, up: p.value);
    }
    for (final r in initialRoutes) {
      noteRoute(r);
    }
    if (localRoutes != null) {
      _subs.add(localRoutes.listen(noteRoute, onError: (Object _) {}));
    }
    for (final p in initialLinkProofs) {
      noteLinkProof(p.key, proven: p.value);
    }
    if (linkProofs != null) {
      _subs.add(linkProofs.listen(
        (p) => noteLinkProof(p.key, proven: p.value),
        onError: (Object _) {},
      ));
    }
    if (localPaths != null) {
      _subs.add(
        localPaths.listen(
          (p) => notePath(p.key, up: p.value),
          onError: (Object _) {},
        ),
      );
    }
    _subs
      ..add(directEvents.listen(onDirectEvent, onError: (Object _) {}))
      ..add(serverMessages.listen(onServerMessage, onError: (Object _) {}))
      ..add(
        serverConnection.listen((connected) {
          if (!connected) serverLinkLost();
        }, onError: (Object _) {}),
      );
    _tick ??= Timer.periodic(const Duration(seconds: 5), (_) {
      // Bundle 158: every 10 s re-read the paths (expired routes).
      if ((_tickCount++).isOdd) {
        final refresh = this.refreshPaths;
        if (refresh != null) {
          unawaited(refresh().catchError((Object _) {}));
        }
      }
      checkExpiry();
    });
  }

  /// Account reset: forget everyone (streams stay attached).
  void forgetPeople() {
    _seen.clear();
    _userOf.clear();
    _devicesOf.clear();
    _names.clear();
    _resolving.clear();
    _lastShown.clear();
    _pathUp.clear();
    _linkProof.clear();
    _reachCapable.clear();
    _reachWay.clear();
    _reachWayAt.clear();
    _routeOf.clear();
    _wayShown.clear();
    _wayDevice.clear();
    _loggedWay.clear();
    _unproven.clear();
    _queueNotify();
  }

  @visibleForTesting
  void resetForTest() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _tick?.cancel();
    _tick = null;
    _seen.clear();
    _userOf.clear();
    _devicesOf.clear();
    _names.clear();
    _resolving.clear();
    _lastShown.clear();
    _pathUp.clear();
    _linkProof.clear();
    _reachCapable.clear();
    _reachWay.clear();
    _reachWayAt.clear();
    _routeOf.clear();
    _wayShown.clear();
    _wayDevice.clear();
    _loggedWay.clear();
    _unproven.clear();
    _reachSince = null;
    _tickCount = 0;
    refreshPaths = null;
    userResolver = null;
    nameResolver = null;
    localDeviceId = null;
  }

  // ------------------------------------------------------------- inputs

  /// Anything from the direct (local) transport. `sender_id` is the device
  /// id of the phone the packet came from (also over several mesh hops).
  void onDirectEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString();
    if (type == 'message') {
      noteNearby(event['sender_id']?.toString() ?? '');
    } else if (type == 'peer_connected') {
      noteNearby(event['peer_id']?.toString() ?? '');
    }
  }

  /// Server socket traffic: `presence_update` decides only the server path.
  void onServerMessage(Map<String, dynamic> message) {
    if (message['type'] != 'presence_update') return;
    final id =
        message['device_id']?.toString() ??
        message['sender_id']?.toString() ??
        '';
    serverReport(id, connected: message['server_connected'] == true);
  }

  /// We received something from [deviceId] over the direct link.
  void noteNearby(String deviceId) {
    if (!_accept(deviceId)) return;
    // Bundle 295 (G1): proof from them.
    if (_unproven.remove(deviceId)) {
      AppLogger.info('PRESENCE_PROVEN', detail: 'peer=${_short(deviceId)}');
    }
    (_seen[deviceId] ??= _Seen()).nearbyAt = _now();
    _changed(deviceId);
  }

  /// Bundle 158: the mesh says there is ([up]) or is no longer a local path
  /// (direct or relayed) to [deviceId].
  void notePath(String deviceId, {required bool up}) {
    if (!_accept(deviceId)) return;
    final was = _pathUp[deviceId];
    if (was == up) return;
    _pathUp[deviceId] = up;
    _changed(deviceId);
  }

  /// Bundle 296 (H1): the native side says the direct link to [deviceId] is
  /// ([proven]) or is not proven (no own pong in the last 10 s).
  void noteLinkProof(String deviceId, {required bool proven}) {
    if (!_accept(deviceId)) return;
    if (_linkProof[deviceId] == proven) return;
    _linkProof[deviceId] = proven;
    _changed(deviceId);
  }

  /// Bundle 296 (H2): reach checks run (true, LinkUp open on screen) or
  /// stop (false, background: the path rule again, no extra packets).
  void setReachActive(bool active) {
    if (active == (_reachSince != null)) return;
    _reachSince = active ? _now() : null;
    AppLogger.info('REACH_CHECK', detail: active ? 'on' : 'off');
    _changed(null);
  }

  bool get reachActive => _reachSince != null;

  /// Bundle 296 (H2): the phone's app answers reach checks (also learned
  /// from a saved list after a restart).
  void noteReachCapable(String deviceId) {
    if (!_accept(deviceId)) return;
    if (_reachCapable.add(deviceId)) _changed(deviceId);
  }

  Set<String> get reachCapableIds => Set.unmodifiable(_reachCapable);

  /// Bundle 296 (H2): an answer to our reach check (or their own check) came
  /// from [deviceId]. [path] = the phones it passed ([sender, relay, ...]);
  /// the last relay is the phone next to us = the real "via".
  void noteReachAnswer(String deviceId, {List<String> path = const []}) {
    if (!_accept(deviceId)) return;
    _reachCapable.add(deviceId);
    final clean = <String>[
      for (final p in path)
        if (p.trim().isNotEmpty) p.trim(),
    ];
    if (clean.isNotEmpty && clean.first != deviceId) clean.insert(0, deviceId);
    if (clean.length >= 2) {
      _reachWay[deviceId] =
          PresenceRoute(deviceId, 'mesh', hops: clean.length, via: clean.last);
      _reachWayAt[deviceId] = _now();
    }
    noteNearby(deviceId);
  }

  /// Bundle 296 (H2): the local way to [deviceId] goes through other phones
  /// right now (reach checks go only to these).
  bool isMeshPath(String deviceId) =>
      _pathUp[deviceId] == true && _routeOf[deviceId]?.kind == 'mesh';

  @visibleForTesting
  PresenceRoute? reachWayForTest(String deviceId) => _reachWay[deviceId];

  /// Bundle 295 (G1): a call to [deviceId] was not answered in 6 s and the
  /// stored way was dropped: not Nearby any more, at once (no 20 s grace).
  void markUnproven(String deviceId) {
    if (!_accept(deviceId)) return;
    if (!_unproven.add(deviceId)) return;
    AppLogger.info('PRESENCE_UNPROVEN', detail: 'peer=${_short(deviceId)}');
    _changed(deviceId);
  }

  @visibleForTesting
  bool isUnprovenForTest(String deviceId) => _unproven.contains(deviceId);

  /// We received something from [deviceId] through the server.
  /// Bundle 201 (F): how the local path goes. Tells listeners only when the
  /// kind / hops changed (route reports come in bursts during calls).
  void noteRoute(PresenceRoute route) {
    if (!_accept(route.deviceId)) return;
    if (route.sameAs(_routeOf[route.deviceId])) return;
    _routeOf[route.deviceId] = route;
    _queueNotify();
  }

  void noteServer(String deviceId) {
    if (!_accept(deviceId)) return;
    (_seen[deviceId] ??= _Seen()).serverAt = _now();
    _changed(deviceId);
  }

  /// The server says [deviceId] is (not) connected to it. Never touches the
  /// nearby path.
  void serverReport(String deviceId, {required bool connected}) {
    if (!_accept(deviceId)) return;
    if (connected) {
      noteServer(deviceId);
      return;
    }
    final seen = _seen[deviceId];
    if (seen?.serverAt == null) return;
    seen!.serverAt = null;
    _changed(deviceId);
  }

  /// OUR server connection dropped: nobody is reachable via the server now.
  /// Nearby people stay Nearby.
  void serverLinkLost() {
    var any = false;
    for (final s in _seen.values) {
      if (s.serverAt != null) {
        s.serverAt = null;
        any = true;
      }
    }
    if (any) {
      AppLogger.info('PRESENCE_SERVER_PATH_CLEARED');
      _changed(null);
    }
  }

  /// Known owner of a device (collapses several devices of one person).
  void linkUser(String deviceId, String? userId) {
    if (deviceId.isEmpty) return;
    final user = userId?.trim() ?? '';
    final old = _userOf[deviceId];
    if (old == user) return;
    if (old != null && old.isNotEmpty) _devicesOf[old]?.remove(deviceId);
    _userOf[deviceId] = user;
    if (user.isNotEmpty) (_devicesOf[user] ??= <String>{}).add(deviceId);
    _changed(null);
  }

  // ------------------------------------------------------------- outputs

  /// Status of the PERSON behind [deviceId] (best of all their devices).
  PresenceStatus statusOf(String deviceId) {
    if (deviceId.isEmpty) return PresenceStatus.offline;
    _resolveUser(deviceId);
    final user = _userOf[deviceId] ?? '';
    final ids = user.isEmpty
        ? <String>{deviceId}
        : (_devicesOf[user] ?? {deviceId});
    var best = _deviceStatus(deviceId);
    for (final id in ids) {
      final s = _deviceStatus(id);
      if (s.index < best.index) best = s; // nearby < online < offline
    }
    return best;
  }

  /// Bundle 170: owner (user id) of a device, or null while unknown. Starts
  /// the lookup on first ask; listeners are told when it arrives.
  String? userOf(String deviceId) {
    if (deviceId.isEmpty) return null;
    _resolveUser(deviceId);
    final user = _userOf[deviceId] ?? '';
    return user.isEmpty ? null : user;
  }

  /// Status of this one device only (no merging).
  PresenceStatus statusOfDevice(String deviceId) => _deviceStatus(deviceId);

  /// Bundle 201 (F): HOW the person is reached (best of their devices:
  /// Wi-Fi, then Wi-Fi Direct, then Mesh). Bundle 296 (H3): no grace, so
  /// "Connecting" no longer shows for a lost way (Online / Offline at once).
  ///
  /// Bundle 205 (P4): the shown way follows [SwitchRules] (a better way
  /// must stay up 5 s first; a worse way shows at once).
  PresenceWayInfo wayInfoOf(String deviceId) {
    final raw = _rawWayInfoOf(deviceId);
    if (deviceId.isEmpty) return raw;
    final user = _userOf[deviceId] ?? '';
    final key = user.isEmpty ? 'd:$deviceId' : 'u:$user';
    final state = _wayShown[key];
    if (state == null) {
      _wayShown[key] = WayShowState(raw);
      _wayDevice[key] = deviceId;
      _loggedWay[key] = raw.way;
      return raw;
    }
    _wayDevice[key] = deviceId;
    final shown = state.update(raw, _now());
    final logged = _loggedWay[key];
    if (logged != shown.way) {
      _loggedWay[key] = shown.way;
      if (logged != null &&
          SwitchRules.isNearbyWay(logged) &&
          SwitchRules.isNearbyWay(shown.way)) {
        AppLogger.info(
          'SWITCH',
          detail: 'peer=${_short(deviceId)} from=${logged.name} '
              'to=${shown.way.name}',
        );
      }
    }
    return shown;
  }

  PresenceWayInfo _rawWayInfoOf(String deviceId) {
    final status = statusOf(deviceId);
    if (status == PresenceStatus.offline) {
      return const PresenceWayInfo(PresenceWay.offline);
    }
    if (status == PresenceStatus.online) {
      return const PresenceWayInfo(PresenceWay.online);
    }
    final user = _userOf[deviceId] ?? '';
    final ids = user.isEmpty
        ? <String>{deviceId}
        : <String>{deviceId, ...?_devicesOf[user]};
    PresenceWayInfo? best;
    for (final id in ids) {
      if (_deviceStatus(id) != PresenceStatus.nearby) continue;
      final info = _deviceWay(id);
      if (best == null || info.way.index < best.way.index) best = info;
    }
    return best ?? const PresenceWayInfo(PresenceWay.nearby);
  }

  PresenceWay wayOf(String deviceId) => wayInfoOf(deviceId).way;
  String wayLabelOf(String deviceId) => wayInfoOf(deviceId).label;

  PresenceWayInfo _deviceWay(String id) {
    final path = _pathUp[id];
    if (path == false) return const PresenceWayInfo(PresenceWay.connecting);
    if (path == null) return const PresenceWayInfo(PresenceWay.nearby);
    final r = _routeOf[id];
    return switch (r?.kind) {
      'lan' => const PresenceWayInfo(PresenceWay.wifi),
      'wifi_direct' => const PresenceWayInfo(PresenceWay.wifiDirect),
      // Bundle 205 (P1): a linked group / hotspot is phone to phone too.
      'local_net' => const PresenceWayInfo(PresenceWay.wifiDirect),
      'mesh' => _meshWay(id, r!),
      _ => const PresenceWayInfo(PresenceWay.nearby),
    };
  }

  /// Bundle 296 (H2): the "via" is the way the last answer really took (when
  /// fresh), not a guess from the route table.
  PresenceWayInfo _meshWay(String id, PresenceRoute r) {
    final real = _reachWay[id];
    final at = _reachWayAt[id];
    if (real != null && at != null && _now().difference(at) <= reachProof) {
      return PresenceWayInfo(PresenceWay.mesh, hops: real.hops, via: real.via);
    }
    return PresenceWayInfo(PresenceWay.mesh, hops: r.hops, via: r.via);
  }

  String channelOf(String deviceId) => statusOf(deviceId).channel;
  String labelOf(String deviceId) => statusOf(deviceId).label;
  bool isReachable(String deviceId) =>
      statusOf(deviceId) != PresenceStatus.offline;

  /// Person's name for a device id (directory / custom name), or null while
  /// unknown. Listeners are told when it arrives.
  String? nameOf(String deviceId) {
    if (deviceId.isEmpty) return null;
    final cached = _names[deviceId];
    if (cached != null) return cached.isEmpty ? null : cached;
    final resolve = nameResolver;
    if (resolve != null && _resolving.add('n:$deviceId')) {
      unawaited(
        resolve(deviceId).then(
          (name) {
            _names[deviceId] = name?.trim() ?? '';
            if ((name?.trim() ?? '').isNotEmpty) _queueNotify();
          },
          onError: (Object _) {
            _names[deviceId] = '';
          },
        ),
      );
    }
    return null;
  }

  /// Runs every 5 s: people whose proof got too old flip on every screen at
  /// the same moment.
  void checkExpiry() {
    var changed = false;
    for (final id in <String>{
      ..._seen.keys,
      ..._lastShown.keys,
      ..._pathUp.keys,
      ..._unproven,
    }) {
      final now = _deviceStatus(id);
      final before = _lastShown[id];
      if (before != now) {
        _lastShown[id] = now;
        changed = true;
        // Bundle 201 (E2): the timed flip is logged too (it was silent).
        if (before != null) {
          AppLogger.info(
            'PRESENCE_CHANGED',
            detail: 'peer=${_short(id)} ${before.label}>${now.label} why=expiry',
          );
        }
      }
    }
    // Bundle 205 (P4): a better way that is now steady shows on its own
    // (no new event may come).
    for (final entry in _wayDevice.entries.toList()) {
      final before = _wayShown[entry.key]?.shown.way;
      final after = wayInfoOf(entry.value).way;
      if (before != after) changed = true;
    }
    if (changed) _queueNotify();
  }

  // ------------------------------------------------------------- internals

  PresenceStatus _deviceStatus(String id) {
    final seen = _seen[id];
    final path = _pathUp[id];
    if (seen == null && path == null) return PresenceStatus.offline;
    final now = _now();
    bool fresh(DateTime? at) => at != null && now.difference(at) <= window;
    if (_nearbyNow(id, seen, path, now)) return PresenceStatus.nearby;
    if (fresh(seen?.serverAt)) return PresenceStatus.online;
    return PresenceStatus.offline;
  }

  bool _nearbyNow(String id, _Seen? seen, bool? path, DateTime now) {
    // Bundle 295 (G1): no proof since the unanswered call.
    if (_unproven.contains(id)) return false;
    if (path == true) {
      if (_routeOf[id]?.kind == 'mesh') return _meshProven(id, seen, now);
      // Bundle 296 (H1): a direct link needs a fresh own pong.
      return _linkProof[id] != false;
    }
    // Bundle 296 (H3): the mesh knows there is no path: not Nearby, at once
    // (the 20 s grace is gone).
    if (path == false) return false;
    // No path report yet (mesh not running): what we received directly.
    final at = seen?.nearbyAt;
    return at != null && now.difference(at) <= window;
  }

  /// Bundle 296 (H2): a friend through other phones.
  bool _meshProven(String id, _Seen? seen, DateTime now) {
    final since = _reachSince;
    // Background or an app without reach checks: the path rule (no false
    // grey for old apps).
    if (since == null || !_reachCapable.contains(id)) return true;
    final at = seen?.nearbyAt;
    if (at != null && now.difference(at) <= reachProof) return true;
    // Just opened: the first answers are on their way.
    return now.difference(since) < reachProof;
  }

  bool _accept(String deviceId) {
    if (deviceId.isEmpty) return false;
    final self = localDeviceId?.call();
    return self == null || self != deviceId;
  }

  void _changed(String? deviceId) {
    if (deviceId != null) {
      final now = _deviceStatus(deviceId);
      final before = _lastShown[deviceId];
      _lastShown[deviceId] = now;
      if (before == now) return;
      AppLogger.info(
        'PRESENCE_CHANGED',
        detail: 'peer=${_short(deviceId)} ${before?.label ?? '-'}>${now.label}',
      );
    }
    _queueNotify();
  }

  void _resolveUser(String deviceId) {
    if (_userOf.containsKey(deviceId)) return;
    final resolve = userResolver;
    if (resolve == null || !_resolving.add('u:$deviceId')) return;
    unawaited(
      resolve(deviceId).then(
        (user) => linkUser(deviceId, user),
        onError: (Object _) => linkUser(deviceId, null),
      ),
    );
  }

  /// Listeners may be widgets in the middle of a build; tell them right
  /// after instead.
  void _queueNotify() {
    if (_notifyQueued) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      notifyListeners();
    });
  }

  static String _short(String id) =>
      id.length > 8 ? id.substring(id.length - 8) : id;
}
