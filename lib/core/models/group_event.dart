import 'dart:convert';
import 'package:locallink/l10n/l10n.dart';

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
      if (id == self) return L.t.you3;
      final local = nameOf?.call(id)?.trim() ?? '';
      if (local.isNotEmpty && local != 'Group member' && local != L.t.groupMember) return local;
      return names[id] ?? L.t.someone;
    }

    String whoObj(String id) => id == self ? L.t.youObject304 : who(id);
    String list(List<String> ids) {
      final parts = ids.map(whoObj).toList();
      if (parts.isEmpty) return '';
      if (parts.length == 1) return parts.first;
      return L.t.and(parts.sublist(0, parts.length - 1).join(', '), parts.last);
    }

    final actor = who(by);
    final mine = by == self;
    switch (kind) {
      case 'create':
        final made = mine
            ? L.t.youCreatedGroup(name)
            : L.t.createdGroup(actor, name);
        if (targets.isEmpty) return [made];
        if (mine) return [made, L.t.youAdded(list(targets))];
        if (targets.contains(self)) return [made, L.t.addedYou(actor)];
        return [made];
      case 'add':
        return [L.t.addedMembers304(actor, list(targets))];
      case 'remove':
        return [L.t.removed4(actor, list(targets))];
      // Bundle G6: someone opened the invite link (no approval needed).
      case 'link_join':
        return [
          mine
              ? L.t.youJoinedUsingThisGroupS
              : L.t.joinedUsingThisGroupSInvite(actor)
        ];
      case 'leave':
        final left = mine ? L.t.youLeft : L.t.left(actor);
        if (owner.isEmpty) return [left];
        if (owner == self) return [left, L.t.youAreNowTheGroupOwner];
        return [left, L.t.isNowTheGroupOwner(who(owner))];
      case 'admin':
        if (targets.contains(self)) return [L.t.madeYouAGroupAdmin(actor)];
        return [L.t.madeAGroupAdmin(actor, list(targets))];
      case 'unadmin':
        if (targets.contains(self)) {
          return [L.t.dismissedYouAsGroupAdmin(actor)];
        }
        return [L.t.dismissedAsGroupAdmin(actor, list(targets))];
      case 'name':
        return [L.t.changedTheGroupNameTo(actor, name)];
      case 'desc':
        return [L.t.changedTheGroupDescription(actor)];
      case 'photo':
        return [L.t.changedThisGroupSPhoto(actor)];
      case 'photo_removed':
        return [L.t.deletedThisGroupSPhoto(actor)];
      // Bundle G5b (mock P3): written on the phones, never by the server.
      case 'pin':
        return [L.t.pinnedAMessage(actor)];
      case 'set':
        final admins = value == 'admins';
        switch (field) {
          case 'send_messages':
            return [
              admins
                  ? L.t.changedThisGroupSoOnlyAdmins3(actor)
                  : L.t.changedThisGroupSoAllMembers3(actor)
            ];
          case 'edit_info':
            return [
              admins
                  ? L.t.changedThisGroupSoOnlyAdmins2(actor)
                  : L.t.changedThisGroupSoAllMembers2(actor)
            ];
          case 'add_members':
            return [
              admins
                  ? L.t.changedThisGroupSoOnlyAdmins(actor)
                  : L.t.changedThisGroupSoAllMembers(actor)
            ];
        }
        return [L.t.changedTheGroupSettings(actor)];
    }
    return [L.t.changedTheGroup(actor)];
  }

  /// One line for the Chats list / notifications (the newest line).
  String preview(String self, {String? Function(String id)? nameOf}) =>
      lines(self, nameOf: nameOf).last;
}
