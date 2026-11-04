import 'package:flutter/foundation.dart';

/// Bundle G5 (mock 10 / 17): groups with an unread message that names me
/// (or says @all from an admin). Chats shows a blue "@" until I open the
/// group. Kept in settings so it survives a restart.
class GroupMentionBook extends ChangeNotifier {
  GroupMentionBook._();

  static final GroupMentionBook instance = GroupMentionBook._();
  static const String key = 'group_mentions';

  final Set<String> _groups = <String>{};
  Future<void> Function(String key, String value)? _write;

  bool has(String groupId) => _groups.contains(groupId);

  Future<void> load({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _write = write;
    try {
      final raw = await read(key) ?? '';
      _groups
        ..clear()
        ..addAll(raw.split(',').where((g) => g.isNotEmpty));
      notifyListeners();
    } catch (_) {}
  }

  void add(String groupId) {
    if (groupId.isEmpty || !_groups.add(groupId)) return;
    notifyListeners();
    _save();
  }

  void clear(String groupId) {
    if (!_groups.remove(groupId)) return;
    notifyListeners();
    _save();
  }

  void _save() {
    final w = _write;
    if (w == null) return;
    w(key, _groups.join(',')).catchError((Object _) {});
  }

  @visibleForTesting
  void debugReset() {
    _groups.clear();
    _write = null;
    notifyListeners();
  }
}
