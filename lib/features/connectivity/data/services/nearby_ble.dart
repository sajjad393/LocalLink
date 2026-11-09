import 'package:flutter/foundation.dart';

/// Bundle 226 (B3/B4/B5): Bluetooth LE finds LinkUp friends; Wi-Fi still
/// carries everything (chats, files, calls).
///
/// Native side: `NearbyBle.kt` advertises a 10-byte packet (my short id,
/// the wanted friend's short id, host / member / searching / router flags,
/// call + "I host OUR pair group" bits) and scans with a filter. It sends
/// `ble_seen` and `ble_state` events on the Nearby event stream.
///
/// Short ids are the same 8 hex the Wi-Fi Direct tag already shows
/// (`NearbyTag.wantedIdFor(NearbyTag.idFor(deviceId))`). No name, no
/// password, no account data.

/// Native controls (own interface, so older fakes keep working).
abstract interface class NearbyBleControl {
  /// `{state: on|off|no_permission|unsupported|scan_only, sdk: int}`.
  Future<Map<String, Object?>> bleStatus();

  /// What this phone advertises now.
  Future<void> setBleWanted(BleWants wants);

  /// The Allow card: Android's pop-up (Android 12+; on 13+ none when
  /// "Nearby devices" is already allowed). Returns the new status plus
  /// `blocked: true` when Android won't show the pop-up again.
  Future<Map<String, Object?>> askBlePermission();

  /// Opens Bluetooth settings ([app] = this app's settings page). The app
  /// never turns Bluetooth on by itself.
  Future<bool> openBluetoothSettings({bool app = false});
}

/// One wanted friend in my advert.
@immutable
class BleWant {
  final String id8;
  final bool call;

  /// I host OUR pair's friend group now (the friend may join it by name).
  final bool pair;

  const BleWant(this.id8, {this.call = false, this.pair = false});

  Map<String, Object?> toMap() =>
      <String, Object?>{'id': id8, 'call': call, 'pair': pair};

  @override
  bool operator ==(Object other) =>
      other is BleWant &&
      other.id8 == id8 &&
      other.call == call &&
      other.pair == pair;

  @override
  int get hashCode => Object.hash(id8, call, pair);

  @override
  String toString() => '$id8${call ? '/call' : ''}${pair ? '/pair' : ''}';
}

/// Everything the native advert needs.
@immutable
class BleWants {
  final String self;
  final List<BleWant> wanted;
  final bool urgent;
  final bool searching;
  final bool host;
  final bool member;
  final bool router;
  final bool foreground;

  const BleWants({
    required this.self,
    this.wanted = const <BleWant>[],
    this.urgent = false,
    this.searching = false,
    this.host = false,
    this.member = false,
    this.router = false,
    this.foreground = false,
  });

  Map<String, Object?> toMap() => <String, Object?>{
        'self': self,
        'wanted': [for (final w in wanted) w.toMap()],
        'urgent': urgent,
        'searching': searching,
        'host': host,
        'member': member,
        'router': router,
        'fg': foreground,
      };

  @override
  bool operator ==(Object other) =>
      other is BleWants &&
      other.self == self &&
      listEquals(other.wanted, wanted) &&
      other.urgent == urgent &&
      other.searching == searching &&
      other.host == host &&
      other.member == member &&
      other.router == router &&
      other.foreground == foreground;

  @override
  int get hashCode => Object.hash(self, Object.hashAll(wanted), urgent,
      searching, host, member, router, foreground);
}

/// One phone heard over Bluetooth.
@immutable
class BleSighting {
  final String id8;
  final String? wanted8;
  final bool host;
  final bool member;
  final bool searching;
  final bool router;
  final bool call;
  final bool pair;
  final int rssi;
  final int at;

  const BleSighting({
    required this.id8,
    this.wanted8,
    this.host = false,
    this.member = false,
    this.searching = false,
    this.router = false,
    this.call = false,
    this.pair = false,
    this.rssi = 0,
    this.at = 0,
  });

  static final RegExp _hex8 = RegExp(r'^[0-9a-f]{8}$');

  static bool validId(String? id) =>
      id != null && _hex8.hasMatch(id) && id != '00000000';

  /// Null for a broken event. Never throws.
  static BleSighting? fromEvent(Map<dynamic, dynamic> e, int now) {
    try {
      final id = e['id']?.toString().trim().toLowerCase();
      if (!validId(id)) return null;
      final w = e['wanted']?.toString().trim().toLowerCase();
      final rssi = e['rssi'];
      return BleSighting(
        id8: id!,
        wanted8: validId(w) ? w : null,
        host: e['host'] == true,
        member: e['member'] == true,
        searching: e['searching'] == true,
        router: e['router'] == true,
        call: e['call'] == true,
        pair: e['pair'] == true,
        rssi: rssi is int ? rssi : 0,
        at: now,
      );
    } catch (_) {
      return null;
    }
  }

  /// This phone asks [selfId8] to come.
  bool wants(String selfId8) => wanted8 != null && wanted8 == selfId8;

  /// It hosts OUR pair group for me: join it by name now.
  bool hostsPairFor(String selfId8) => wants(selfId8) && pair;
}

/// Bundle 226 rule constants.
abstract final class BleRules {
  /// A sighting this old still counts.
  static const int freshMs = 15 * 1000;

  /// "Searching now" from another phone starts my search at most this often.
  static const int searchEchoMs = 60 * 1000;

  /// One Wi-Fi Direct search window: the "searching now" flag lasts this long.
  static const int searchWindowMs = 20 * 1000;

  /// The skip key "address" of a join by name (no Wi-Fi Direct address).
  static const String joinAddress = 'ble';

  /// × on a card hides it this long.
  static const int cardHideMs = 7 * 24 * 60 * 60 * 1000;

  /// Max sightings kept.
  static const int maxSightings = 64;
}

/// Keeps the latest sighting per phone (fresh ones only).
class BleSightings {
  final Map<String, BleSighting> _byId = <String, BleSighting>{};

  void add(BleSighting s) {
    if (_byId.length >= BleRules.maxSightings && !_byId.containsKey(s.id8)) {
      final oldest = _byId.values.reduce((a, b) => a.at <= b.at ? a : b);
      _byId.remove(oldest.id8);
    }
    _byId[s.id8] = s;
  }

  /// Fresh sightings by short id.
  Map<String, BleSighting> fresh(int now) {
    _byId.removeWhere((_, s) => now - s.at > BleRules.freshMs || s.at > now);
    return Map<String, BleSighting>.unmodifiable(_byId);
  }

  void clear() => _byId.clear();
}

/// B4 row "any LinkUp phone searching now": start my Wi-Fi Direct search at
/// once, so both phones search at the same moment. Not when we are already
/// linked to it, not when both are on the router (the LAN beacon links in
/// ~3 s), not during a live call, at most once per 60 s.
bool bleSearchEcho({
  required BleSighting s,
  required int now,
  required int lastEchoAt,
  required bool linkedToIt,
  required bool onRouter,
  required bool liveCall,
  required bool allowed,
}) {
  if (!s.searching || linkedToIt || liveCall || !allowed) return false;
  if (onRouter && s.router) return false;
  if (lastEchoAt > 0 && now - lastEchoAt < BleRules.searchEchoMs) return false;
  return true;
}

/// B5: which Bluetooth card Add Contact → Nearby shows (one at a time).
enum BleCard { none, allow, off }

BleCard bleCardFor({
  required String state,
  required int sdk,
  required bool wifiCardShown,
  required int now,
  int allowHiddenUntil = 0,
  int offHiddenUntil = 0,
}) {
  // The Wi-Fi "Allow nearby" card wins (one card at a time).
  if (wifiCardShown) return BleCard.none;
  if (sdk < 29) return BleCard.none;
  switch (state) {
    case 'no_permission':
      // Android 10-11: "no permission" = the Wi-Fi permission (that card).
      if (sdk < 31) return BleCard.none;
      return now < allowHiddenUntil ? BleCard.none : BleCard.allow;
    case 'off':
      return now < offHiddenUntil ? BleCard.none : BleCard.off;
    default:
      return BleCard.none;
  }
}

/// Bundle 226 (B5): the native controls for the Add Contact cards (set by
/// app_dependencies; null in tests = no Bluetooth card).
abstract final class NearbyBleActions {
  static NearbyBleControl? control;
}

/// Bundle 226: the Bluetooth state for the screen (Add Contact cards).
class NearbyBleStatus extends ChangeNotifier {
  NearbyBleStatus._();
  static final NearbyBleStatus instance = NearbyBleStatus._();

  String _state = 'unknown';
  int _sdk = 0;

  String get state => _state;
  int get sdk => _sdk;

  void update(String state, int sdk) {
    final s = state.trim().isEmpty ? 'unknown' : state.trim();
    if (s == _state && (sdk <= 0 || sdk == _sdk)) return;
    _state = s;
    if (sdk > 0) _sdk = sdk;
    notifyListeners();
  }

  /// From a `bleStatus` reply or a `ble_state` event.
  void updateFrom(Map<dynamic, dynamic>? m) {
    if (m == null) return;
    final sdk = m['sdk'];
    update(m['state']?.toString() ?? 'unknown', sdk is int ? sdk : 0);
  }

  @visibleForTesting
  void resetForTest() {
    _state = 'unknown';
    _sdk = 0;
  }
}
