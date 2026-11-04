import 'package:flutter/material.dart';

import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/groups/presentation/screens/new_group_screen.dart';

/// Bundle G2: what Group info needs from the rest of the app (friends,
/// open a 1:1 chat, add a friend). The Home screen fills it in; without it
/// those rows are simply not shown.
class GroupPeopleHub {
  GroupPeopleHub({
    required this.loadFriends,
    required this.chatRoute,
    required this.addFriend,
  });

  static GroupPeopleHub? instance;

  /// My friends (not blocked), sorted by name.
  final Future<List<GroupFriend>> Function() loadFriends;

  /// The 1:1 chat with this phone (null = not possible).
  final Route<void>? Function(String deviceId) chatRoute;

  /// "Add friend" from a group member (asks for the name like People).
  final Future<void> Function(BuildContext context, GroupMember member)
      addFriend;
}

/// Bundle G2: who may do what (server rules, shown the same in the app).
class GroupRules {
  const GroupRules(this.group, this.members, this.self);

  final LocalGroup group;
  final List<GroupMember> members;
  final String self;

  GroupMember? get me {
    for (final m in members) {
      if (m.deviceId == self) return m;
    }
    return null;
  }

  bool get isOwner =>
      me?.role == 'owner' || (me == null && group.ownerId == self);
  bool get isAdmin => isOwner || (me?.isAdmin ?? false);
  bool get active => group.isActive;

  bool get canEdit => active && (group.editInfo == 'all' || isAdmin);
  bool get canAdd => active && (group.addMembers == 'all' || isAdmin);
  bool get canSend => active && (group.sendMessages == 'all' || isAdmin);

  /// Make / dismiss admin: admins; never on the owner; only the owner
  /// dismisses an admin.
  bool canMakeAdmin(GroupMember m) =>
      active && isAdmin && m.deviceId != self && m.role == 'member';
  bool canDismissAdmin(GroupMember m) =>
      active && isOwner && m.deviceId != self && m.role == 'admin';

  /// Remove: admins remove members; only the owner removes admins.
  bool canRemove(GroupMember m) {
    if (!active || m.deviceId == self || m.role == 'owner') return false;
    if (m.role == 'admin') return isOwner;
    return isAdmin;
  }

  /// The next owner when the owner exits: the oldest admin, else the
  /// oldest member (same as the server).
  GroupMember? get nextOwner {
    GroupMember? pick(bool admins) {
      GroupMember? best;
      for (final m in members) {
        if (m.deviceId == self) continue;
        if (admins && m.role != 'admin') continue;
        if (best == null || m.joinedAt.compareTo(best.joinedAt) < 0) best = m;
      }
      return best;
    }

    return pick(true) ?? pick(false);
  }
}
