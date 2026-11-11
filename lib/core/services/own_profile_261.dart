/// Bundle 261 (A1): one own profile row on this phone - the one for my
/// account.
///
/// `profile_cache` is keyed by `user_id`. After an offline account moved to
/// its server id, saving the profile with the new id added a SECOND row and
/// `LocalStore.profile()` (limit 1, no order) kept giving the old offline
/// row back. My signed card then carried the old offline id, so friends
/// refused it (ID_MOVED_OLD_CARD_SKIP) and could not open my messages.
abstract final class OwnProfile261 {
  /// A real server account id (not empty, not an offline id).
  static bool isServerId(String? id) {
    final v = id?.trim() ?? '';
    return v.isNotEmpty && !v.startsWith('offline_');
  }

  /// The row that is "me": the one for my server account first, else the
  /// first row (as before). An offline row read while I have a server id is
  /// given my server id.
  static Map<String, dynamic>? pick(
      List<Map<String, dynamic>> rows, String? accountId) {
    if (rows.isEmpty) return null;
    if (!isServerId(accountId)) return rows.first;
    final me = accountId!.trim();
    for (final r in rows) {
      if ((r['user_id']?.toString() ?? '') == me) return r;
    }
    final first = rows.first;
    final id = first['user_id']?.toString() ?? '';
    if (id.isEmpty || id.startsWith('offline_')) {
      return <String, dynamic>{...first, 'user_id': me};
    }
    return first;
  }

  static int _version(Map<String, dynamic> r) =>
      int.tryParse(r['profile_version']?.toString() ?? '') ?? 0;

  static String _updated(Map<String, dynamic> r) =>
      r['updated_at']?.toString() ?? '';

  /// What to store when the rows are not "one row for my account": the row
  /// with the highest version (newest on a tie) under my server id, one
  /// version above all rows, so friends take it over any old copy. Null =
  /// nothing to fix (offline-only account, or already one right row).
  static Map<String, dynamic>? repair(
      List<Map<String, dynamic>> rows, String? accountId,
      {required String now}) {
    if (!isServerId(accountId) || rows.isEmpty) return null;
    final me = accountId!.trim();
    if (rows.length == 1 && (rows.first['user_id']?.toString() ?? '') == me) {
      return null;
    }
    var best = rows.first;
    var maxVersion = _version(best);
    for (final r in rows.skip(1)) {
      final v = _version(r);
      if (v > maxVersion) maxVersion = v;
      final bv = _version(best);
      if (v > bv || (v == bv && _updated(r).compareTo(_updated(best)) > 0)) {
        best = r;
      }
    }
    final keep = <String, dynamic>{
      ...best,
      'user_id': me,
      'profile_version': maxVersion + 1,
      'updated_at': now,
    };
    // A picture kept only on another row is not lost.
    if ((keep['local_avatar_path']?.toString() ?? '').isEmpty) {
      for (final r in rows) {
        final path = r['local_avatar_path']?.toString() ?? '';
        if (path.isNotEmpty) {
          keep['local_avatar_path'] = path;
          break;
        }
      }
    }
    return keep;
  }

  /// The old id that was fixed (for the log line), '' when none.
  static String oldId(List<Map<String, dynamic>> rows, String accountId) {
    for (final r in rows) {
      final id = r['user_id']?.toString() ?? '';
      if (id != accountId) return id;
    }
    return '';
  }
}
