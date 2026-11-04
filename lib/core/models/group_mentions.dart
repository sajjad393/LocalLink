/// Bundle G5 (mock 16 / 17): @mentions in group messages.
///
/// In the message text a mention is kept as `@[Ali](device-id)`; every
/// screen shows it as a blue "@Ali". `@[all](all)` = "@all" (admins only:
/// it notifies everyone, even when the group is muted).
class GroupMentions {
  GroupMentions._();

  static const String allId = 'all';

  static final RegExp token =
      RegExp(r'@\[([^\]\n]{1,40})\]\(([A-Za-z0-9_\-:.]{1,128})\)');

  static String tokenFor(String name, String id) =>
      '@[${name.replaceAll(']', '').replaceAll('\n', ' ').trim()}]($id)';

  /// "@Ali" instead of the stored token (previews, copy, notifications).
  static String plain(String text) {
    if (!text.contains('@[')) return text;
    return text.replaceAllMapped(token, (m) => '@${m.group(1)}');
  }

  /// Ids named in the text (may include [allId]).
  static Set<String> ids(String text) {
    if (!text.contains('@[')) return const <String>{};
    return {for (final m in token.allMatches(text)) m.group(2)!};
  }

  /// True when [text] names me, or says @all and the writer may do that.
  static bool mentionsMe(String text, String selfId,
      {bool writerIsAdmin = false}) {
    if (selfId.isEmpty) return false;
    final found = ids(text);
    return found.contains(selfId) || (writerIsAdmin && found.contains(allId));
  }

  /// Turns the "@Name" words picked from the list into tokens before
  /// sending. [picks] = shown name -> device id (or [allId] for "all").
  static String encode(String text, Map<String, String> picks) {
    if (picks.isEmpty || !text.contains('@')) return text;
    final names = picks.keys.where((n) => n.trim().isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var out = text;
    for (final name in names) {
      final id = picks[name]!;
      final re = RegExp('(^|[\\s(])@${RegExp.escape(name)}(?![\\w])');
      out = out.replaceAllMapped(
          re, (m) => '${m.group(1)}${tokenFor(name, id)}');
    }
    return out;
  }

  /// The word being typed after "@" at the cursor, or null (no list).
  /// "Please check @A|" -> "A"; "@" -> "".
  static String? queryAt(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return null;
    final before = text.substring(0, cursor);
    final m = RegExp(r'(^|\s)@([^\s@]{0,30})$').firstMatch(before);
    return m?.group(2);
  }

  /// Puts "@Name " in place of the "@que" before the cursor. Returns the
  /// new text and the new cursor.
  static (String, int) insert(String text, int cursor, String name) {
    final q = queryAt(text, cursor);
    if (q == null) return (text, cursor);
    final start = cursor - q.length - 1;
    final add = '@$name ';
    final next = text.replaceRange(start, cursor, add);
    return (next, start + add.length);
  }

  /// Pieces of [text]: (shown text, is mention).
  static List<(String, bool)> pieces(String text) {
    final out = <(String, bool)>[];
    var from = 0;
    for (final m in token.allMatches(text)) {
      if (m.start > from) out.add((text.substring(from, m.start), false));
      out.add(('@${m.group(1)}', true));
      from = m.end;
    }
    if (from < text.length) out.add((text.substring(from), false));
    return out;
  }
}
