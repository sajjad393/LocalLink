import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

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

  const NearbyTag({
    required this.address,
    required this.idHash,
    this.host = false,
    this.member = false,
    this.members = 0,
    this.full = false,
    this.seenAt = 0,
  });

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
    );
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
              '${e.value.idHash}|${e.value.host}|${e.value.member}|${e.value.members}|${e.value.full}',
      };

  @visibleForTesting
  void resetForTest() {
    _byAddress.clear();
  }
}
