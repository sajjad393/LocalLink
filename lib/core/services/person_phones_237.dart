import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Bundle 237: the old phone ids of each friend, so a friend on a new phone
/// keeps ONE chat with the old and the new messages.
///
/// Kept in the settings table as JSON (no database change):
/// `{"<user id>": [{"id": "<old phone id>", "at": "<iso time>"}, ...]}`,
/// newest first, at most [maxPerPerson] per person.
///
/// Learned ONLY from trusted places (LocalStore.saveDirectoryProfile after
/// the card checks, LocalStore.addContact, the server contacts list
/// `past_device_ids`). A phone that is now another person's current phone
/// (235 "New owner") is never used for the old person (checked by
/// LocalStore when it reads the list, and [forgetForOthers] on save).
class PersonPhones237 extends ChangeNotifier {
  PersonPhones237();

  static final PersonPhones237 instance = PersonPhones237();

  static const String settingKey = 'person_phones_237';
  static const int maxPerPerson = 10;
  static const int maxPeople = 2000;

  Future<String?> Function(String key)? _read;
  Future<void> Function(String key, String value)? _write;

  // user id -> old phones, newest first.
  final Map<String, List<PastPhone237>> _byUser = <String, List<PastPhone237>>{};

  bool get isEmpty => _byUser.isEmpty;
  int get people => _byUser.length;

  /// Load once from the settings table (LocalStore.init).
  Future<void> load({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _read = read;
    _write = write;
    _byUser.clear();
    try {
      final raw = await read(settingKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) {
          for (final e in map.entries) {
            final user = e.key.toString();
            final list = e.value;
            if (user.isEmpty || list is! List) continue;
            final phones = <PastPhone237>[];
            for (final p in list) {
              final phone = PastPhone237.fromJson(p);
              if (phone != null && !phones.any((x) => x.id == phone.id)) {
                phones.add(phone);
              }
            }
            if (phones.isNotEmpty) {
              _byUser[user] = phones.take(maxPerPerson).toList();
            }
          }
        }
      }
    } catch (_) {
      _byUser.clear();
    }
    notifyListeners();
  }

  /// Old phones of [userId], newest first.
  List<String> pastOf(String userId) =>
      [for (final p in _byUser[userId] ?? const <PastPhone237>[]) p.id];

  /// The person whose old phone [deviceId] was (null = none).
  String? ownerOf(String deviceId) {
    if (deviceId.isEmpty) return null;
    for (final e in _byUser.entries) {
      if (e.value.any((p) => p.id == deviceId)) return e.key;
    }
    return null;
  }

  bool isPast(String deviceId) => ownerOf(deviceId) != null;

  /// [oldDeviceId] was a phone of [userId]; [currentDeviceId] is the phone
  /// the person uses now (never kept as "old"). True when the list changed.
  Future<bool> remember(String userId, String oldDeviceId,
      {String currentDeviceId = '', DateTime? at}) async {
    final changed = _add(userId, oldDeviceId, currentDeviceId,
        (at ?? DateTime.now()).toUtc());
    if (changed) await _save();
    return changed;
  }

  /// Many old phones at once (server list, newest first).
  Future<bool> rememberAll(String userId, List<String> oldDeviceIds,
      {String currentDeviceId = '', DateTime? at}) async {
    var changed = false;
    final when = (at ?? DateTime.now()).toUtc();
    // Oldest first, so the newest ends on top.
    for (final id in oldDeviceIds.reversed) {
      if (_add(userId, id, currentDeviceId, when, keepOrder: true)) {
        changed = true;
      }
    }
    if (changed) await _save();
    return changed;
  }

  /// [deviceId] is now the current phone of [userId]: it is nobody's old
  /// phone any more except this person's own (and not even theirs, it is
  /// current again). True when something was removed.
  Future<bool> forgetForOthers(String deviceId, {required String userId}) async {
    if (deviceId.isEmpty) return false;
    var changed = false;
    for (final user in _byUser.keys.toList()) {
      final list = _byUser[user]!;
      final before = list.length;
      list.removeWhere((p) => p.id == deviceId);
      if (list.length != before) changed = true;
      if (list.isEmpty) _byUser.remove(user);
    }
    if (changed) await _save();
    return changed;
  }

  bool _add(String userId, String oldId, String currentId, DateTime at,
      {bool keepOrder = false}) {
    final user = userId.trim();
    final old = oldId.trim();
    if (user.isEmpty || old.isEmpty || old == currentId.trim()) return false;
    final list = _byUser.putIfAbsent(user, () => <PastPhone237>[]);
    final i = list.indexWhere((p) => p.id == old);
    if (i == 0 || (keepOrder && i >= 0)) return false;
    if (i > 0) list.removeAt(i);
    list.insert(0, PastPhone237(old, at));
    while (list.length > maxPerPerson) {
      list.removeLast();
    }
    while (_byUser.length > maxPeople) {
      _byUser.remove(_byUser.keys.first);
    }
    return true;
  }

  Future<void> _save() async {
    notifyListeners();
    final write = _write;
    if (write == null) return;
    try {
      await write(settingKey, jsonEncode(toJson()));
    } catch (_) {}
  }

  Map<String, dynamic> toJson() => {
        for (final e in _byUser.entries)
          e.key: [for (final p in e.value) p.toJson()],
      };

  @visibleForTesting
  void clearForTest() {
    _byUser.clear();
    _read = null;
    _write = null;
  }

  @visibleForTesting
  bool get loaded => _read != null;
}

class PastPhone237 {
  const PastPhone237(this.id, this.at);
  final String id;
  final DateTime at;

  static PastPhone237? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = v['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final at = DateTime.tryParse(v['at']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return PastPhone237(id, at);
  }

  Map<String, dynamic> toJson() => {'id': id, 'at': at.toIso8601String()};
}
