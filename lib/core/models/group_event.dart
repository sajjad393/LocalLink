import 'dart:convert';

/// Bundle G2: a group system line ("Sajjad added Ali", "Ali left" ...).
///
/// The server writes it as a normal group message with the body
/// `llev:v1:{json}` so every phone gets it the same way as messages
/// (live, from history and from sync). Keys:
///   k  kind: create, add, remove, leave, admin, unadmin, name, desc,
///      photo, photo_removed, set
///   by who did it
///   t  targets (device ids)
///   n  new group name (create / name)
///   f  setting field (set): edit_info / send_messages / add_members
///   v  setting value "all" / "admins" (set) or photo version
///   o  new owner (leave)
///   nm names of by / t / o, so a phone can name someone who already left
class GroupEvent {
  const GroupEvent({
    required this.kind,
    required this.by,
    this.targets = const [],
    this.name = '',
    this.field = '',
    this.value = '',
    this.owner = '',
    this.names = const {},
  });

  static const prefix = 'llev:v1:';

  final String kind;
  final String by;
  final List<String> targets;
  final String name;
  final String field;
  final String value;
  final String owner;
  final Map<String, String> names;

  static bool isEvent(String body) => body.startsWith(prefix);

  /// Bundle G3: the body of a system line made on a phone (Nearby groups).
  String encode() => prefix +
      jsonEncode({
        'k': kind,
        'by': by,
        if (targets.isNotEmpty) 't': targets,
        if (name.isNotEmpty) 'n': name,
        if (field.isNotEmpty) 'f': field,
        if (value.isNotEmpty) 'v': value,
        if (owner.isNotEmpty) 'o': owner,
        if (names.isNotEmpty) 'nm': names,
      });

  static GroupEvent? parse(String body) {
    if (!isEvent(body)) return null;
    try {
      final raw = jsonDecode(body.substring(prefix.length));
      if (raw is! Map) return null;
      final names = <String, String>{};
      final nm = raw['nm'];
      if (nm is Map) {
        nm.forEach((k, v) {
          final s = v?.toString().trim() ?? '';
          if (s.isNotEmpty) names[k.toString()] = s;
        });
      }
      final t = raw['t'];
      return GroupEvent(
        kind: raw['k']?.toString() ?? '',
        by: raw['by']?.toString() ?? '',
        targets: t is List ? t.map((e) => e.toString()).toList() : const [],
        name: raw['n']?.toString() ?? '',
        field: raw['f']?.toString() ?? '',
        value: raw['v']?.toString() ?? '',
        owner: raw['o']?.toString() ?? '',
        names: names,
      );
    } catch (_) {
      return null;
    }
  }

  /// I was added (create / add with me as a target).
  bool addsMe(String self) =>
      self.isNotEmpty &&
      (((kind == 'create' || kind == 'add') && targets.contains(self)) ||
          (kind == 'link_join' && by == self));

  /// I was removed by someone else.
  bool removesMe(String self) =>
      self.isNotEmpty && kind == 'remove' && targets.contains(self);

  /// The members list / roles / info changed: read them again.
  bool get changesGroup => kind.isNotEmpty;

  /// Counted as unread + notified: only "X added you" (mock 8).
  bool countsAsUnread(String self) => addsMe(self) && by != self;

  /// The system lines, oldest first (create by me = 2 lines, mock 6).
  /// [nameOf] can give a better (local) name; the server name is the
  /// fallback, then "Someone".
  List<String> lines(String self, {String? Function(String id)? nameOf}) {
    String who(String id) {
      if (id == self) return 'You';
      final local = nameOf?.call(id)?.trim() ?? '';
      if (local.isNotEmpty && local != 'Group member') return local;
      return names[id] ?? 'Someone';
    }

    String whoObj(String id) => id == self ? 'you' : who(id);
    String list(List<String> ids) {
      final parts = ids.map(whoObj).toList();
      if (parts.isEmpty) return '';
      if (parts.length == 1) return parts.first;
      return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
    }

    final actor = who(by);
    final mine = by == self;
    switch (kind) {
      case 'create':
        final made = mine
            ? 'You created group "$name"'
            : '$actor created group "$name"';
        if (targets.isEmpty) return [made];
        if (mine) return [made, 'You added ${list(targets)}'];
        if (targets.contains(self)) return [made, '$actor added you'];
        return [made];
      case 'add':
        return ['$actor added ${list(targets)}'];
      case 'remove':
        return ['$actor removed ${list(targets)}'];
      // Bundle G6: someone opened the invite link (no approval needed).
      case 'link_join':
        return [
          mine
              ? "You joined using this group's invite link"
              : "$actor joined using this group's invite link"
        ];
      case 'leave':
        final left = mine ? 'You left' : '$actor left';
        if (owner.isEmpty) return [left];
        if (owner == self) return [left, 'You are now the group owner'];
        return [left, '${who(owner)} is now the group owner'];
      case 'admin':
        if (targets.contains(self)) return ['$actor made you a group admin'];
        return ['$actor made ${list(targets)} a group admin'];
      case 'unadmin':
        if (targets.contains(self)) {
          return ['$actor dismissed you as group admin'];
        }
        return ['$actor dismissed ${list(targets)} as group admin'];
      case 'name':
        return ['$actor changed the group name to "$name"'];
      case 'desc':
        return ['$actor changed the group description'];
      case 'photo':
        return ["$actor changed this group's photo"];
      case 'photo_removed':
        return ["$actor deleted this group's photo"];
      // Bundle G5b (mock P3): written on the phones, never by the server.
      case 'pin':
        return ['$actor pinned a message'];
      case 'set':
        final admins = value == 'admins';
        switch (field) {
          case 'send_messages':
            return [
              admins
                  ? '$actor changed this group so only admins can send messages'
                  : '$actor changed this group so all members can send messages'
            ];
          case 'edit_info':
            return [
              admins
                  ? "$actor changed this group so only admins can edit the group info"
                  : "$actor changed this group so all members can edit the group info"
            ];
          case 'add_members':
            return [
              admins
                  ? '$actor changed this group so only admins can add members'
                  : '$actor changed this group so all members can add members'
            ];
        }
        return ['$actor changed the group settings'];
    }
    return ['$actor changed the group'];
  }

  /// One line for the Chats list / notifications (the newest line).
  String preview(String self, {String? Function(String id)? nameOf}) =>
      lines(self, nameOf: nameOf).last;
}
