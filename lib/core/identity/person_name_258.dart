import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:locallink/core/identity/display_label.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 258 (B2/C1): one rule for the name of a person, on every screen.
///
/// Order: custom name -> card display name -> card username -> the last name
/// this phone saw for that person -> "LinkUp user". Never the phone model
/// ("RMX3938") and never "Unknown user" when anything is known.
///
/// After a reinstall / fresh login the friends' cards come back slowly (or
/// not at all while the server can't be reached), so the last known name is
/// kept in settings `name_cache_258` (phone id and account id -> name, max
/// [maxNames]) and survives a logout of the same app data.
class NameBook258 {
  NameBook258();
  static NameBook258 instance = NameBook258();

  static const String settingKey = 'name_cache_258';
  static const int maxNames = 500;
  static const String noName = 'LinkUp user';

  Future<void> Function(String key, String value)? _write;
  final Map<String, String> _names = <String, String>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final Map<String, int> _missingLogged = <String, int>{};
  Timer? _saveTimer;

  /// A friend card / name came in (the chat list re-reads its names).
  Stream<void> get changes => _changes.stream;

  void notifyChanged() {
    try {
      _changes.add(null);
    } catch (_) {}
  }

  Future<void> load({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _write = write;
    _names.clear();
    try {
      final raw = await read(settingKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) {
          for (final e in map.entries) {
            final v = e.value?.toString().trim() ?? '';
            if (v.isNotEmpty) _names[e.key.toString()] = v;
          }
        }
      }
    } catch (_) {}
  }

  /// The last name seen for [id] (phone id or account id), or null.
  String? lastKnown(String id) {
    final key = id.trim();
    if (key.isEmpty) return null;
    return _names[key];
  }

  /// Keep [name] for every id given (empty ids are skipped).
  void remember(String name, List<String> ids) {
    final n = name.trim();
    if (n.isEmpty) return;
    var changed = false;
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      if (_names[id] == n) continue;
      _names.remove(id); // newest last (the oldest go first when full)
      _names[id] = n;
      changed = true;
    }
    if (!changed) return;
    while (_names.length > maxNames) {
      _names.remove(_names.keys.first);
    }
    _scheduleSave();
  }

  void _scheduleSave() {
    if (_write == null) return;
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 2), () => unawaited(saveNow()));
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final w = _write;
    if (w == null) return;
    try {
      await w(settingKey, jsonEncode(_names));
    } catch (_) {}
  }

  /// The name for a person: [custom] -> [profile] (display name, username)
  /// -> the last known name for any of [ids] -> null. A name from the card
  /// is remembered for all [ids] (and the card's own ids).
  String? pick({
    String? custom,
    Map<String, dynamic>? profile,
    List<String> ids = const <String>[],
  }) {
    final c = custom?.trim() ?? '';
    if (c.isNotEmpty) return c;
    final fromCard = displayNameFromProfile(profile);
    final all = <String>[
      ...ids,
      profile?['user_id']?.toString() ?? '',
      profile?['device_id']?.toString() ?? '',
    ];
    if (fromCard != null && fromCard.isNotEmpty) {
      remember(fromCard, all);
      return fromCard;
    }
    for (final id in all) {
      final known = lastKnown(id);
      if (known != null) return known;
    }
    return null;
  }

  /// [pick], else "LinkUp user" (with one log line per person per hour).
  String nameOrDefault({
    String? custom,
    Map<String, dynamic>? profile,
    List<String> ids = const <String>[],
    String why = 'no_card',
  }) {
    final n = pick(custom: custom, profile: profile, ids: ids);
    if (n != null) return n;
    noteMissing(ids.isEmpty ? '' : ids.first, why: why);
    return noName;
  }

  /// `NAME_MISSING peer=<6> why=..` at most once an hour per person.
  void noteMissing(String id, {String why = 'no_card'}) {
    final key = id.trim();
    if (key.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _missingLogged[key] ?? 0;
    if (now - last < const Duration(hours: 1).inMilliseconds) return;
    _missingLogged[key] = now;
    final tail = key.length <= 6 ? key : key.substring(key.length - 6);
    AppLogger.info('NAME_MISSING', detail: 'peer=$tail why=$why');
  }

  @visibleForTesting
  Map<String, String> get debugNames => _names;

  @visibleForTesting
  void resetForTest() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _names.clear();
    _missingLogged.clear();
    _write = null;
  }
}
