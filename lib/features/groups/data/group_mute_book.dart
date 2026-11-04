import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle G1 (mock 34): "Mute notifications" for a group, on THIS phone
/// only. 8 hours / 1 week / Always. Messages still arrive and still count
/// as unread; only the notification (sound + pop-up) is skipped.
///
/// Saved in the settings table as JSON: {groupId: untilMs}, -1 = Always.
class GroupMuteBook extends ChangeNotifier {
  GroupMuteBook._();

  static final GroupMuteBook instance = GroupMuteBook._();

  static const String key = 'group_mutes_v1';

  /// -1 = Always (no end).
  static const int always = -1;

  final Map<String, int> _until = <String, int>{};
  Future<void> Function(String key, String value)? _write;

  /// Test clock.
  @visibleForTesting
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  /// Called once at start with the store's settings functions.
  Future<void> load({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _write = write;
    try {
      final raw = await read(key);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      _until.clear();
      map.forEach((k, v) {
        final at = v is int ? v : int.tryParse('$v');
        if (at != null) _until['$k'] = at;
      });
      notifyListeners();
    } catch (_) {}
  }

  bool isMuted(String groupId) {
    final at = _until[groupId];
    if (at == null) return false;
    if (at == always) return true;
    return at > now();
  }

  /// End time in ms, [always], or null when not muted.
  int? mutedUntil(String groupId) => isMuted(groupId) ? _until[groupId] : null;

  Future<void> mute(String groupId, Duration? length) async {
    if (groupId.isEmpty) return;
    _until[groupId] = length == null ? always : now() + length.inMilliseconds;
    notifyListeners();
    AppLogger.info('GROUP_MUTE',
        detail: 'group=$groupId for=${length == null ? 'always' : '${length.inHours}h'}');
    await _save();
  }

  Future<void> unmute(String groupId) async {
    if (_until.remove(groupId) == null) return;
    notifyListeners();
    AppLogger.info('GROUP_MUTE', detail: 'group=$groupId off');
    await _save();
  }

  Future<void> _save() async {
    // Drop ended mutes so the list stays small.
    final t = now();
    _until.removeWhere((_, at) => at != always && at <= t);
    try {
      await _write?.call(key, jsonEncode(_until));
    } catch (_) {}
  }

  @visibleForTesting
  void debugReset() {
    _until.clear();
    _write = null;
    now = () => DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }
}
