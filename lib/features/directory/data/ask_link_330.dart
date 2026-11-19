import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Bundle 330: the ask, carried by hand.
///
/// When the two phones are not on the same Wi-Fi, no card can travel. So the
/// ask itself becomes a short link / QR: "Ali asks for this chat". The other
/// person scans it (or pastes it) and their phone files **the same ask** it
/// would have filed over the LAN - then it answers whenever the two phones are
/// near again.
///
/// **No server, no internet, nothing expires.** A link made today still means
/// the same thing next year: it names a chat, not a session.
class AskLink330 {
  /// Never change: it is what tells an ask apart from a group link.
  static const String prefix = 'linkup-ask-v1:';

  /// A short code the two people can also read to each other.
  static const int codeLength = 6;

  /// Build the link for one ask.
  ///
  /// [kind] is `direct` or `group`; [userA]/[userB] are the two user ids of a
  /// direct chat, [groupId] the group. [from] is the device asking.
  static String of({
    required String label,
    required String kind,
    String groupId = '',
    String userA = '',
    String userB = '',
    required String from,
    DateTime? at,
  }) {
    final chat = kind == 'group'
        ? {'kind': 'group', 'group_id': groupId}
        : {
            'kind': 'direct',
            'users': [userA, userB],
          };
    final body = {
      'v': 1,
      'label': label.trim(),
      'chat': chat,
      'from': from.trim(),
      'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
    };
    final payload = base64Url.encode(utf8.encode(jsonEncode(body))).replaceAll('=', '');
    return '$prefix$payload';
  }

  /// Read a link (or a QR of it). Returns null for anything that is not one -
  /// junk is never half-accepted.
  static ({String label, String kind, String groupId, String userA, String userB, String from, String code})?
      parse(String text) {
    var s = text.trim();
    // a scanner or a chat app can wrap it in quotes or add spaces
    s = s.replaceAll(RegExp(r'\s+'), '');
    if (!s.startsWith(prefix)) return null;
    final payload = s.substring(prefix.length);
    if (payload.isEmpty) return null;
    try {
      final pad = payload.length % 4 == 0 ? '' : '=' * (4 - payload.length % 4);
      final decoded = utf8.decode(base64Url.decode(payload + pad));
      final m = jsonDecode(decoded);
      if (m is! Map) return null;
      if (m['v'] != 1) return null;
      final chat = m['chat'];
      if (chat is! Map) return null;
      final kind = chat['kind']?.toString() ?? '';
      final groupId = chat['group_id']?.toString() ?? '';
      var userA = '';
      var userB = '';
      final users = chat['users'];
      if (users is List && users.isNotEmpty) {
        userA = users.first?.toString() ?? '';
        if (users.length > 1) userB = users[1]?.toString() ?? '';
      }
      // an ask must name a chat, or there is nothing to ask for
      final namesChat = kind == 'group' ? groupId.isNotEmpty : (userA.isNotEmpty && userB.isNotEmpty);
      if (kind != 'group' && kind != 'direct') return null;
      if (!namesChat) return null;
      return (
        label: m['label']?.toString() ?? '',
        kind: kind,
        groupId: groupId,
        userA: userA,
        userB: userB,
        from: m['from']?.toString() ?? '',
        code: codeOf(s),
      );
    } catch (_) {
      return null;
    }
  }

  /// The chat as the ask service wants it.
  static Map<String, dynamic> chatOf(
      ({String label, String kind, String groupId, String userA, String userB, String from, String code}) ask) {
    if (ask.kind == 'group') return {'kind': 'group', 'group_id': ask.groupId};
    return {
      'kind': 'direct',
      'users': [ask.userA, ask.userB],
    };
  }

  /// Six characters, the same on both phones, to read aloud when a camera is
  /// not handy: `linkup-ask-v1:…` -> `4F2A91`.
  static String codeOf(String link) {
    final s = link.trim().replaceAll(RegExp(r'\s+'), '');
    if (s.isEmpty) return '';
    final h = sha256.convert(utf8.encode('linkup-ask-code-330|$s')).toString().toUpperCase();
    return h.substring(0, codeLength);
  }

  /// True when this looks like an ask link at all (cheap check for a scanner).
  static bool looksLike(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), '').startsWith(prefix);
}
