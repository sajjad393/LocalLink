import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// D9: soft limit of members per group host (never kick anyone above it).
const int nearbyGroupSoftLimit = 8;

/// Bundle 155: a LocalLink "who is who" tag seen over Wi-Fi Direct service
/// discovery. Maps a Wi-Fi Direct address to a LocalLink person (by a short
/// hash of the device id — the raw id never goes over the air).
@immutable
class NearbyTag {
  final String address;
  final String idHash;
  final bool host;
  final bool member;
  final int members;
  final bool full;
  final int seenAt;

  /// Bundle 157: this phone's app joins shared groups by itself.
  final bool groupAware;

  /// Bundle 157: the Wi-Fi Direct group it hosts or is a member of.
  final String? group;

  /// Bundle 157: the host's group password (host tags only).
  final String? key;

  /// Bundle 157: short ids (8 hex) of people this phone wants in its group.
  final List<String> wanted;

  /// Bundle 158: this phone is its group's bridge to a normal Wi-Fi network.
  final bool bridge;

  /// Bundle 159: this phone is on a charger (`pwr=1`).
  final bool charging;

  /// Bundle 160: this phone is on a normal Wi-Fi network (`wf=1`).
  final bool wifi;

  const NearbyTag({
    required this.address,
    required this.idHash,
    this.host = false,
    this.member = false,
    this.members = 0,
    this.full = false,
    this.seenAt = 0,
    this.groupAware = false,
    this.group,
    this.key,
    this.wanted = const <String>[],
    this.bridge = false,
    this.charging = false,
    this.wifi = false,
  });

  /// Bundle 157: the short id used in the `w` (wanted) list.
  static String wantedIdFor(String idHash) =>
      idHash.length > 8 ? idHash.substring(0, 8) : idHash;

  /// Does this tag ask [idHash] to join its group?
  bool wants(String idHash) => wanted.contains(wantedIdFor(idHash));

  /// A host that others can join right now.
  bool get openHost => host && !full && members < nearbyGroupSoftLimit;

  /// Short, stable hash of a device id (first 16 hex chars of SHA-256).
  /// Same value on every phone, so a tag can be matched to a contact.
  static String idFor(String deviceId) =>
      sha256.convert(utf8.encode(deviceId.trim())).toString().substring(0, 16);

  static NearbyTag? fromMap(Map<dynamic, dynamic> map) {
    final address = map['address']?.toString().trim().toLowerCase() ?? '';
    final id = map['id']?.toString().trim().toLowerCase() ?? '';
    if (address.isEmpty || !RegExp(r'^[0-9a-f]{8,32}$').hasMatch(id)) {
      return null;
    }
    return NearbyTag(
      address: address,
      idHash: id,
      host: map['host'] == true,
      member: map['member'] == true,
      members: (map['members'] as num?)?.toInt() ?? 0,
      full: map['full'] == true,
      seenAt: (map['seen_at'] as num?)?.toInt() ?? 0,
      groupAware: map['gv'] == true,
      group: _text(map['group']),
      key: _text(map['key']),
      wanted: map['wanted'] is List
          ? [
              for (final w in map['wanted'] as List)
                if (RegExp(r'^[0-9a-f]{8}$').hasMatch(w.toString())) w.toString()
            ]
          : const <String>[],
      bridge: map['bridge'] == true,
      charging: map['charging'] == true,
      wifi: map['wifi'] == true,
    );
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static List<NearbyTag> listFromEvent(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map(NearbyTag.fromMap)
          .whereType<NearbyTag>()
          .toList(growable: false)
      : const <NearbyTag>[];
}

/// Bundle 155: the latest tags, shared by the Nearby screen and the
/// automatic reconnect. Fed from Wi-Fi Direct "services" events.
class NearbyTagRegistry extends ChangeNotifier {
  NearbyTagRegistry._();
  static final NearbyTagRegistry instance = NearbyTagRegistry._();

  final Map<String, NearbyTag> _byAddress = <String, NearbyTag>{};

  Map<String, NearbyTag> get byAddress => Map.unmodifiable(_byAddress);

  NearbyTag? tagFor(String address) => _byAddress[address.trim().toLowerCase()];

  /// Replaces the known tags with the native snapshot (it already drops
  /// stale ones).
  void ingest(List<NearbyTag> tags) {
    final next = <String, NearbyTag>{for (final t in tags) t.address: t};
    if (mapEquals(_simplify(next), _simplify(_byAddress))) {
      _byAddress
        ..clear()
        ..addAll(next);
      return;
    }
    _byAddress
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  static Map<String, String> _simplify(Map<String, NearbyTag> tags) => {
        for (final e in tags.entries)
          e.key:
              '${e.value.idHash}|${e.value.host}|${e.value.member}|${e.value.members}|${e.value.full}|${e.value.group}',
      };

  @visibleForTesting
  void resetForTest() {
    _byAddress.clear();
  }
}
