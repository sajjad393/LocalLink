/// Bundle 195c: "anyone know this name?" asked to nearby LinkUp phones that
/// are NOT friends. Pure rules (no store, no transport).
///
/// - Only a name question: never the full list.
/// - The answer has only matching profiles, max [maxRows].
/// - Never private contacts, never people with "find me by name" off,
///   never unsigned / hidden profiles, phone numbers only when public
///   (the repository removes them).
/// - Max 1 question per [gapMs] per asking phone; at least [minLetters].
class NameQuestionPolicy {
  NameQuestionPolicy._();

  static const String questionType = 'DIRECTORY_NAME_QUESTION';
  static const String answerType = 'DIRECTORY_NAME_ANSWER';
  static const int minLetters = 3;
  static const int maxLetters = 64;
  static const int maxRows = 10;
  static const int gapMs = 10 * 1000;
  static const int waitMs = 4 * 1000;

  static bool isNameType(String? type) =>
      type == questionType || type == answerType;

  /// The question text to send / answer, or null when it is not allowed.
  static String? cleanQuery(Object? raw) {
    final q = raw?.toString().trim() ?? '';
    if (q.length < minLetters || q.length > maxLetters) return null;
    return q;
  }

  /// Max 1 per [gapMs] per phone. Updates [lastAt] when allowed.
  static bool allow(Map<String, int> lastAt, String phoneId, int nowMs) {
    if (phoneId.isEmpty) return false;
    final last = lastAt[phoneId];
    if (last != null && nowMs - last >= 0 && nowMs - last < gapMs) return false;
    if (lastAt.length > 200) lastAt.clear();
    lastAt[phoneId] = nowMs;
    return true;
  }

  /// May this saved profile row go into an answer?
  /// [privateIds]: contacts the owner marked private.
  static bool rowShareable(
    Map<String, dynamic> row, {
    required Set<String> privateIds,
    required String askerUserId,
  }) {
    final id = row['user_id']?.toString() ?? '';
    if (id.isEmpty || id == askerUserId) return false;
    if (privateIds.contains(id)) return false;
    // same reading as DirectoryProfile.fromMap ("find me by name" must be on)
    final byName = row['discoverable_by_name'];
    if (!(byName == true || byName?.toString() == '1')) return false;
    final sync = row['directory_sync_enabled'];
    if (sync == false || sync?.toString() == '0') return false;
    if ((row['signature']?.toString() ?? '').isEmpty) return false;
    if ((row['signing_public_key']?.toString() ?? '').isEmpty) return false;
    return true;
  }

  /// Linked phones that are not friends (trust "relay") from a topology map.
  static List<String> nearbyNonFriends(Map<String, dynamic> topology) {
    final peers = topology['peers'];
    if (peers is! List) return const [];
    final out = <String>[];
    for (final p in peers.whereType<Map>()) {
      if (p['trust']?.toString() != 'relay') continue;
      final id = (p['peer_id'] ?? p['node_id'])?.toString() ?? '';
      if (id.isNotEmpty && !out.contains(id)) out.add(id);
    }
    return out;
  }
}
