import 'package:locallink/features/directory/domain/directory_models.dart';

/// Bundle 195a: name search shows saved profiles AND server profiles
/// together (saved first, one card per account).
List<DirectoryProfile> mergeSearchResults(
    List<DirectoryProfile> saved, List<DirectoryProfile> server) {
  final seen = <String>{};
  final out = <DirectoryProfile>[];
  for (final p in [...saved, ...server]) {
    final id = p.userId.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    out.add(p);
  }
  return out;
}

/// Bundle 195a: one log line per search (no names, only the length).
String friendSearchLogLine({
  required int queryLength,
  required int saved,
  required int? server,
  required bool friendsAsked,
  required int shown,
  int? nearby, // Bundle 195c: rows from nearby non-friend phones (-1 = not asked)
}) =>
    'len=$queryLength saved=$saved server=${server ?? 'off'} '
    'friends_asked=${friendsAsked ? 'y' : 'n'} shown=$shown'
    '${nearby == null ? '' : ' nearby=${nearby < 0 ? 'off' : nearby}'}';

/// Bundle 195a: what the last name search could reach (for the hint).
class DirectorySearchInfo {
  DirectorySearchInfo._();

  /// false = the server could not be reached (offline / no internet).
  static bool serverReached = true;

  /// The "not found" hint only when the server could not be asked.
  static bool showOfflineHint({required bool noMatch}) =>
      noMatch && !serverReached;

  static const String offlineHint =
      "Not found. Try again when you're online or near friends.";
}
