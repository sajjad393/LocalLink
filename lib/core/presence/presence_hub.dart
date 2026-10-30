import 'dart:async';

import 'package:flutter/foundation.dart';
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
  }) {
    this.localDeviceId = localDeviceId ?? this.localDeviceId;
    this.userResolver = userResolver ?? this.userResolver;
    this.nameResolver = nameResolver ?? this.nameResolver;
    if (_subs.isNotEmpty) return;
    _subs
      ..add(directEvents.listen(onDirectEvent, onError: (Object _) {}))
      ..add(serverMessages.listen(onServerMessage, onError: (Object _) {}))
      ..add(
        serverConnection.listen((connected) {
          if (!connected) serverLinkLost();
        }, onError: (Object _) {}),
      );
    _tick ??= Timer.periodic(const Duration(seconds: 5), (_) => checkExpiry());
  }

  /// Account reset: forget everyone (streams stay attached).
  void forgetPeople() {
    _seen.clear();
    _userOf.clear();
    _devicesOf.clear();
    _names.clear();
    _resolving.clear();
    _lastShown.clear();
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
    (_seen[deviceId] ??= _Seen()).nearbyAt = _now();
    _changed(deviceId);
  }

  /// We received something from [deviceId] through the server.
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

  /// Status of this one device only (no merging).
  PresenceStatus statusOfDevice(String deviceId) => _deviceStatus(deviceId);

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
    for (final id in <String>{..._seen.keys, ..._lastShown.keys}) {
      final now = _deviceStatus(id);
      if (_lastShown[id] != now) {
        _lastShown[id] = now;
        changed = true;
      }
    }
    if (changed) _queueNotify();
  }

  // ------------------------------------------------------------- internals

  PresenceStatus _deviceStatus(String id) {
    final seen = _seen[id];
    if (seen == null) return PresenceStatus.offline;
    final now = _now();
    bool fresh(DateTime? at) => at != null && now.difference(at) <= window;
    if (fresh(seen.nearbyAt)) return PresenceStatus.nearby;
    if (fresh(seen.serverAt)) return PresenceStatus.online;
    return PresenceStatus.offline;
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
