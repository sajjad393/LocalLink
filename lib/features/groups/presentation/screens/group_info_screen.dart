import 'package:locallink/features/groups/presentation/widgets/group_media_strip.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/groups/data/group_mute_book.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/group_people_hub.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart'
    show GroupInviteState, GroupJoinRequest;
import 'package:locallink/features/groups/presentation/screens/group_qr_screens.dart';
import 'package:locallink/features/groups/presentation/screens/new_group_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_info_sheets.dart';
import 'package:locallink/features/groups/presentation/widgets/group_nearby_widgets.dart';
import 'package:locallink/features/groups/presentation/widgets/group_sheets.dart';
import 'package:locallink/features/groups/data/group_invite_link.dart';
import 'package:locallink/features/groups/presentation/screens/group_link_screens.dart'
    show GroupInviteLinkScreen;

/// Bundle G2: Group info (mock 27 + 28 = one scrolling page), Group
/// settings (mock 33) and Add members (mock 35).
///
/// G4: "Invite with QR" (mock 36), "Approve new members" (mock 33) and
/// the "1 request to join" card (mock 37) - Nearby groups, admins.
/// G5: "Media, links and docs · 24" strip (mock d1).
///
/// Pops with 'search' (open search in the chat) or 'deleted' (the group is
/// gone from this phone).
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    super.key,
    required this.group,
    required this.localDeviceId,
    required this.groups,
  });

  final LocalGroup group;
  final String localDeviceId;
  final GroupRepositoryContract groups;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "3 Nov 2026".
String groupDateLabel(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// Mock 28 / 4: the grey line under "Group settings".
String groupSettingsLine(LocalGroup g, {bool both = false}) {
  final add = g.addMembers == 'admins'
      ? 'Only admins add people'
      : 'All members add people';
  final send = g.sendMessages == 'admins'
      ? 'Only admins send'
      : 'Everyone can send';
  if (both || g.sendMessages == 'admins') return '$add · $send';
  return add;
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late LocalGroup _group = widget.group;
  List<GroupMember> _members = const [];
  Set<String> _friends = const {};
  final ScrollController _scroll = ScrollController();
  bool _barTitle = false;
  StreamSubscription<String>? _changes;
  bool _busy = false;
  List<GroupJoinRequest> _requests = const [];

  /// Bundle 215 (B1): people this phone added who have not got the group
  /// yet (member id → invite). Only phone-made groups have them.
  Map<String, GroupInviteState> _pending = const {};

  /// Bundle G4: QR join works for groups made on phones (Nearby).
  bool get _qrGroup =>
      _group.worksNearby && GroupNearbyHub.inviteCode != null;

  GroupRules get _rules => GroupRules(_group, _members, widget.localDeviceId);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > 170;
      if (show != _barTitle) setState(() => _barTitle = show);
    });
    _changes = GroupChangeHub.instance.changes.listen((id) {
      if (id == _group.id) unawaited(_reload(network: false));
    });
    unawaited(_reload(network: true));
    unawaited(_loadFriends());
  }

  @override
  void dispose() {
    _changes?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final hub = GroupPeopleHub.instance;
    if (hub == null) return;
    try {
      final list = await hub.loadFriends();
      if (mounted) setState(() => _friends = {for (final f in list) f.deviceId});
    } catch (_) {}
  }

  Future<void> _reload({required bool network}) async {
    try {
      final g = network
          ? await widget.groups.refreshGroup(_group.id)
          : await widget.groups.localGroup(_group.id);
      if (g != null && mounted) setState(() => _group = g);
    } catch (_) {}
    try {
      final members = await widget.groups.listMembers(_group.id);
      if (mounted) setState(() => _members = members);
    } catch (_) {}
    await _loadRequests();
    await _loadPending();
  }

  /// Bundle 215 (B1): who is still "Pending" (waiting or not reached).
  Future<void> _loadPending() async {
    final load = GroupNearbyHub.loadInvites;
    if (load == null || !_group.worksNearby) return;
    try {
      final rows = await load(_group.id);
      final next = {
        for (final i in rows)
          if (groupInvitePending(i)) i.memberId: i,
      };
      if (mounted) setState(() => _pending = next);
    } catch (_) {}
  }

  int get _pendingCount =>
      _members.where((m) => _pending.containsKey(m.deviceId)).length;

  Future<void> _loadRequests() async {
    final load = GroupNearbyHub.loadRequests;
    final out = <GroupJoinRequest>[];
    if (load != null && _group.worksNearby) {
      try {
        out.addAll(await load(_group.id));
      } catch (_) {}
    }
    // Bundle G6: people who asked with the invite link (server).
    final link = GroupInviteService.instance;
    if (link != null && !_group.nearbyOnly && _rules.isAdmin) {
      try {
        await link.autoApprove(_group);
        final seen = {for (final r in out) r.memberId};
        out.addAll((await link.requests(_group))
            .where((r) => !seen.contains(r.memberId)));
      } catch (_) {}
    }
    if (load == null && link == null) return;
    if (mounted) setState(() => _requests = out);
  }

  Future<void> _inviteLink() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => GroupInviteLinkScreen(group: _group)),
    );
  }

  Future<void> _inviteQr() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInviteQrScreen(
          groupId: _group.id,
          groupName: _group.name,
          photoVersion: _group.photoVersion,
        ),
      ),
    );
  }

  Future<void> _openRequest() async {
    if (_requests.isEmpty) return;
    final r = _requests.first;
    final add = await showJoinRequestSheet(context, r);
    if (add == null || !mounted) return;
    await _run(add ? 'join_add' : 'join_ignore', () async {
      final link = GroupInviteService.instance;
      if (r.via == 'link' && link != null) {
        if (add) {
          await link.approve(_group, r);
        } else {
          await link.decline(_group.id, r.memberId);
        }
        return;
      }
      if (add) {
        await GroupNearbyHub.addJoiner?.call(_group.id, r.memberId);
      } else {
        await GroupNearbyHub.ignoreJoiner?.call(_group.id, r.memberId);
      }
    });
    await _reload(network: false);
  }

  Widget _requestCard(BuildContext context) {
    final n = _requests.length;
    final first = _requests.first.name;
    final how = _requests.first.via == 'link'
        ? 'opened the invite link'
        : 'scanned the group QR';
    final sub = n == 1 ? '$first $how' : '$first and ${n - 1} more asked to join';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
      child: Material(
        color: const Color(0xFFFFF7EA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFF5DDB0)),
        ),
        child: InkWell(
          key: const ValueKey('info_join_requests'),
          borderRadius: BorderRadius.circular(18),
          onTap: _openRequest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.person_add_alt_1_outlined,
                    color: Color(0xFFC77A00), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n == 1 ? '1 request to join' : '$n requests to join',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(sub,
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF6A6B73))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: Color(0xFF6A6B73)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Runs one server action; a refusal is shown in simple words.
  Future<bool> _run(String what, Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      AppLogger.info('GROUP_INFO_ACTION', detail: 'what=$what ok=y');
      return true;
    } catch (error) {
      AppLogger.warning('GROUP_INFO_ACTION', detail: 'what=$what ok=n');
      if (mounted) showErrorToast(context, error: error);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(_reload(network: false));
    }
  }

  String _nameOf(String deviceId) {
    if (deviceId == widget.localDeviceId) return 'You';
    for (final m in _members) {
      if (m.deviceId == deviceId) {
        return m.name.trim().isEmpty ? 'Group member' : m.name.trim();
      }
    }
    return '';
  }

  String get _myName {
    for (final m in _members) {
      if (m.deviceId == widget.localDeviceId && m.name.trim().isNotEmpty) {
        return m.name.trim();
      }
    }
    return 'You';
  }

  // ---- actions -------------------------------------------------------

  Future<void> _photo() async {
    if (!_rules.canEdit) return;
    final pick =
        await showGroupPhotoSheet(context, hasPhoto: _group.photoVersion > 0);
    if (pick == null || !mounted) return;
    await _run('photo', () => widget.groups.setPhoto(_group.id, pick.bytes));
  }

  Future<void> _edit() async {
    if (!_rules.canEdit) return;
    final result = await showEditGroupSheet(context,
        name: _group.name, description: _group.description);
    if (result == null || !mounted) return;
    final name = result.name != _group.name ? result.name : null;
    final desc =
        result.description != _group.description ? result.description : null;
    if (name == null && desc == null) return;
    await _run('edit', () async {
      final g = await widget.groups
          .updateGroup(_group.id, name: name, description: desc);
      if (mounted) setState(() => _group = g);
    });
  }

  Future<void> _mute() async {
    if (GroupMuteBook.instance.isMuted(_group.id)) {
      await GroupMuteBook.instance.unmute(_group.id);
      return;
    }
    final choice = await showGroupMuteSheet(context);
    if (choice == null) return;
    await GroupMuteBook.instance.mute(_group.id, choice.length);
  }

  Future<void> _settings() async {
    // Bundle G4 (mock 33): "Approve new members" for Nearby groups.
    bool? approve;
    if (_qrGroup && GroupNearbyHub.approveOf != null) {
      try {
        approve = await GroupNearbyHub.approveOf!(_group.id);
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupSettingsScreen(
          groupName: _group.name,
          editInfo: _group.editInfo,
          sendMessages: _group.sendMessages,
          addMembers: _group.addMembers,
          approve: approve,
          onApprove: approve == null
              ? null
              : (on) async => GroupNearbyHub.setApprove?.call(_group.id, on),
          onChange: (field, value) async {
            final g = await widget.groups.updateGroup(_group.id,
                editInfo: field == 'edit_info' ? value : null,
                sendMessages: field == 'send_messages' ? value : null,
                addMembers: field == 'add_members' ? value : null);
            if (mounted) setState(() => _group = g);
          },
        ),
      ),
    );
  }

  Future<void> _add() async {
    if (!_rules.canAdd) return;
    final hub = GroupPeopleHub.instance;
    final picked = await Navigator.push<List<GroupFriend>>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupAddMembersScreen(
          groupName: _group.name,
          memberIds: {for (final m in _members) m.deviceId},
          loadFriends: hub?.loadFriends ?? () async => const <GroupFriend>[],
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _run('add', () async {
      for (final f in picked) {
        await widget.groups.addMember(_group.id, f.deviceId);
      }
    });
  }

  Future<void> _member(GroupMember m) async {
    if (m.deviceId == widget.localDeviceId) return;
    final hub = GroupPeopleHub.instance;
    final friend = _friends.contains(m.deviceId);
    final rules = _rules;
    final pending = _pending[m.deviceId];
    final retry = GroupNearbyHub.retry;
    final choice = await showGroupMemberSheet(
      context,
      member: m,
      // Bundle 215 (C): Pending text + Try again.
      pending: pending,
      canRetry: pending != null && retry != null && rules.active,
      friend: friend,
      canMessage: hub?.chatRoute(m.deviceId) != null,
      canAddFriend: hub != null && m.userId.isNotEmpty,
      canMakeAdmin: rules.canMakeAdmin(m),
      canDismissAdmin: rules.canDismissAdmin(m),
      canRemove: rules.canRemove(m),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case GroupMemberChoice.message:
        final route = hub?.chatRoute(m.deviceId);
        if (route != null) await Navigator.push<void>(context, route);
      case GroupMemberChoice.profile:
        await showGroupMemberProfile(context, member: m);
      case GroupMemberChoice.addFriend:
        if (hub != null) {
          await hub.addFriend(context, m);
          await _loadFriends();
        }
      case GroupMemberChoice.makeAdmin:
        await _run('admin',
            () => widget.groups.setAdmin(_group.id, m.deviceId, admin: true));
      case GroupMemberChoice.dismissAdmin:
        await _run('unadmin',
            () => widget.groups.setAdmin(_group.id, m.deviceId, admin: false));
      case GroupMemberChoice.retry:
        if (retry == null) return;
        final name = _nameOf(m.deviceId);
        final messenger = ScaffoldMessenger.maybeOf(context);
        final ok = await _run('retry', () => retry(_group.id, m.deviceId));
        if (ok) {
          messenger?.showSnackBar(
              SnackBar(content: Text('Sending the group to $name again')));
        }
      case GroupMemberChoice.remove:
        final name = _nameOf(m.deviceId);
        final ok = await showRemoveMemberSheet(context,
            name: name, groupName: _group.name, me: _myName);
        if (!ok || !mounted) return;
        await _run(
            'remove', () => widget.groups.removeMember(_group.id, m.deviceId));
    }
  }

  Future<void> _exit() async {
    final rules = _rules;
    final next = rules.isOwner ? rules.nextOwner : null;
    final ok = await showExitGroupSheet(
      context,
      groupName: _group.name,
      me: _myName,
      owner: rules.isOwner,
      nextOwner: next == null ? '' : _nameOf(next.deviceId),
      nextIsAdmin: next?.role == 'admin',
    );
    if (!ok || !mounted) return;
    await _run('exit', () => widget.groups.leave(_group.id));
  }

  Future<void> _delete() async {
    final ok = await showDeleteGroupSheet(context, groupName: _group.name);
    if (!ok || !mounted) return;
    final done =
        await _run('delete', () => widget.groups.deleteLocal(_group.id));
    if (done && mounted) Navigator.pop(context, 'deleted');
  }

  // ---- UI ------------------------------------------------------------

  List<GroupMember> get _sortedMembers {
    int rank(GroupMember m) {
      if (m.deviceId == widget.localDeviceId) return 0;
      return switch (m.role) { 'owner' => 1, 'admin' => 2, _ => 3 };
    }

    final list = List<GroupMember>.from(_members);
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rules = _rules;
    final count = _members.length;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _barTitle
            ? Row(
                key: const ValueKey('info_bar_title'),
                children: [
                  GroupAvatar(
                      radius: 16,
                      groupId: _group.id,
                      photoVersion: _group.photoVersion),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ],
              )
            : null,
        actions: [_menu(rules)],
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _header(context, rules, count),
          _quickActions(context, rules),
          _description(context, rules),
          // Bundle G5 (mock d1): newest photos / videos + "+21".
          GroupMediaStrip(
            groupId: _group.id,
            onOpenAll: (files) => openGroupMedia(context,
                groupId: _group.id, name: _group.name, files: files),
            onOpenFile: (f, files) => openGroupMediaFile(context, f,
                groupId: _group.id, name: _group.name, files: files),
          ),
          ListenableBuilder(
            listenable: GroupMuteBook.instance,
            builder: (context, _) => MessengerListGroup(
              dividerIndent: 58,
              children: [
                _InfoRow(
                  key: const ValueKey('info_mute_row'),
                  icon: Icons.notifications_off_outlined,
                  title: 'Mute notifications',
                  subtitle: _muteLine,
                  trailing: Switch(
                    key: const ValueKey('info_mute_switch'),
                    value: GroupMuteBook.instance.isMuted(_group.id),
                    onChanged: (_) => _mute(),
                  ),
                  onTap: _mute,
                ),
                if (rules.active && rules.isAdmin)
                  _InfoRow(
                    key: const ValueKey('info_settings'),
                    icon: Icons.settings_outlined,
                    title: 'Group settings',
                    subtitle: groupSettingsLine(_group),
                    onTap: _settings,
                  ),
                if (rules.active && rules.isAdmin && _qrGroup)
                  _InfoRow(
                    key: const ValueKey('info_invite_qr'),
                    icon: Icons.qr_code_2_rounded,
                    title: 'Invite with QR',
                    subtitle: 'Friends of friends scan to join',
                    onTap: _inviteQr,
                  ),
                // Bundle G6 (mock L1): server groups; Nearby-only shows L5.
                if (rules.active &&
                    rules.isAdmin &&
                    GroupInviteService.instance != null)
                  _InfoRow(
                    key: const ValueKey('info_invite_link'),
                    icon: Icons.link_rounded,
                    title: 'Invite with link',
                    subtitle: 'Anyone with the link can ask to join',
                    onTap: _inviteLink,
                  ),
              ],
            ),
          ),
          if (rules.active && rules.isAdmin && _requests.isNotEmpty)
            _requestCard(context),
          // Bundle 215 (B2): "3 members · 1 pending".
          MessengerGroupLabel(
              '$count ${count == 1 ? 'member' : 'members'}'
              '${_pendingCount > 0 ? ' · $_pendingCount pending' : ''}',
              top: 16),
          ListenableBuilder(
            listenable: PresenceHub.instance,
            builder: (context, _) => MessengerListGroup(
              children: [
                if (rules.canAdd)
                  InkWell(
                    key: const ValueKey('info_add_members'),
                    onTap: _add,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 21,
                            backgroundColor:
                                colors.primaryContainer.withValues(alpha: .6),
                            child: Icon(Icons.person_add_alt_1_outlined,
                                color: colors.primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Text('Add members',
                              style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: colors.primary)),
                        ],
                      ),
                    ),
                  ),
                for (final m in _sortedMembers)
                  _MemberRow(
                    key: ValueKey('member_${m.deviceId}'),
                    member: m,
                    you: m.deviceId == widget.localDeviceId,
                    pending: _pending[m.deviceId],
                    onTap: () => _member(m),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          MessengerListGroup(
            dividerIndent: 58,
            children: [
              if (rules.active)
                _InfoRow(
                  key: const ValueKey('info_exit'),
                  icon: Icons.logout_rounded,
                  title: 'Exit group',
                  subtitle: 'Your old messages stay on this phone',
                  red: true,
                  chevron: false,
                  onTap: _exit,
                )
              else
                _InfoRow(
                  key: const ValueKey('info_delete'),
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete group',
                  subtitle: "You're no longer a participant in this group.",
                  red: true,
                  chevron: false,
                  onTap: _delete,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String get _muteLine {
    if (!GroupMuteBook.instance.isMuted(_group.id)) return 'Off';
    final until = GroupMuteBook.instance.mutedUntil(_group.id);
    if (until == null || until == GroupMuteBook.always) return 'Always';
    final t = DateTime.fromMillisecondsSinceEpoch(until);
    final hh = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return 'Until ${t.day} ${_months[t.month - 1]}, $hh:$mm $ampm';
  }

  Widget _menu(GroupRules rules) {
    return PopupMenuButton<String>(
      key: const ValueKey('info_more_menu'),
      tooltip: 'More options',
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        if (rules.canEdit)
          const PopupMenuItem(value: 'edit', child: Text('Edit group')),
        if (rules.active && rules.isAdmin)
          const PopupMenuItem(value: 'settings', child: Text('Group settings')),
        if (rules.active)
          const PopupMenuItem(
              value: 'exit',
              child: Text('Exit group', style: TextStyle(color: Color(0xFFB3261E))))
        else
          const PopupMenuItem(
              value: 'delete',
              child:
                  Text('Delete group', style: TextStyle(color: Color(0xFFB3261E)))),
      ],
      onSelected: (v) {
        switch (v) {
          case 'edit':
            unawaited(_edit());
          case 'settings':
            unawaited(_settings());
          case 'exit':
            unawaited(_exit());
          case 'delete':
            unawaited(_delete());
        }
      },
    );
  }

  Widget _header(BuildContext context, GroupRules rules, int count) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        children: [
          GestureDetector(
            key: const ValueKey('info_photo'),
            onTap: rules.canEdit ? _photo : null,
            child: GroupAvatar(
                radius: 52,
                groupId: _group.id,
                photoVersion: _group.photoVersion),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            key: const ValueKey('info_name'),
            onTap: rules.canEdit ? _edit : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(_group.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                ),
                if (rules.canEdit) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.edit_outlined,
                      key: const ValueKey('info_name_edit'),
                      size: 18,
                      color: colors.onSurfaceVariant),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
              count > 0
                  ? 'Group · $count ${count == 1 ? 'member' : 'members'}'
                  : 'Group',
              key: const ValueKey('info_count'),
              style: TextStyle(fontSize: 13.5, color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context, GroupRules rules) {
    return ListenableBuilder(
      listenable: GroupMuteBook.instance,
      builder: (context, _) {
        final muted = GroupMuteBook.instance.isMuted(_group.id);
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (rules.canAdd) ...[
                _QuickAction(
                    key: const ValueKey('info_add'),
                    icon: Icons.person_add_alt_outlined,
                    label: 'Add',
                    onTap: _add),
                const SizedBox(width: 12),
              ],
              _QuickAction(
                  key: const ValueKey('info_search'),
                  icon: Icons.search,
                  label: 'Search',
                  onTap: () => Navigator.pop(context, 'search')),
              const SizedBox(width: 12),
              _QuickAction(
                  key: const ValueKey('info_mute'),
                  icon: muted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  label: muted ? 'Unmute' : 'Mute',
                  onTap: _mute),
            ],
          ),
        );
      },
    );
  }

  Widget _description(BuildContext context, GroupRules rules) {
    final colors = Theme.of(context).colorScheme;
    final desc = _group.description.trim();
    final creatorId =
        _group.createdBy.isNotEmpty ? _group.createdBy : _group.ownerId;
    final creator = _nameOf(creatorId);
    final date = groupDateLabel(_group.createdAt);
    final parts = <String>[
      if (creator.isNotEmpty) 'Created by $creator',
      if (date.isNotEmpty) date,
    ];
    if (desc.isEmpty && !rules.canEdit && parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Material(
        color: colors.surfaceContainer.withValues(alpha: .65),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('info_description'),
          onTap: rules.canEdit ? _edit : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (desc.isNotEmpty)
                  Text(desc, style: const TextStyle(fontSize: 14, height: 1.4))
                else if (rules.canEdit)
                  Text('Add group description',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.primary)),
                if (parts.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                        top: desc.isNotEmpty || rules.canEdit ? 4 : 0),
                    child: Text(parts.join(' · '),
                        style: TextStyle(
                            fontSize: 12, color: colors.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mock .qa: light card, blue icon + label.
class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 92,
      child: Material(
        color: colors.surfaceContainer.withValues(alpha: .65),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
            child: Column(
              children: [
                Icon(icon, size: 22, color: colors.primary),
                const SizedBox(height: 5),
                Text(label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mock srow2: plain icon, bold title, grey line, chevron / switch.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.red = false,
    this.chevron = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool red;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = red ? colors.error : colors.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: red ? colors.error : colors.onSurfaceVariant),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12.5, color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (chevron)
              Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Mock mrow: photo, name ("You"), status dot, Owner / Admin label.
class _MemberRow extends StatelessWidget {
  const _MemberRow(
      {super.key,
      required this.member,
      required this.you,
      required this.onTap,
      this.pending});
  final GroupMember member;
  final bool you;
  final VoidCallback onTap;

  /// Bundle 215 (B3): set while this member has not got the group yet.
  final GroupInviteState? pending;

  static const Color nearbyGreen = Color(0xFF1FB57A);
  static const Color offlineGrey = Color(0xFFB9BAC2);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = member.name.trim().isEmpty ? 'Group member' : member.name.trim();
    final status = you
        ? PresenceStatus.nearby
        : PresenceHub.instance.statusOf(member.deviceId);
    final dot = switch (status) {
      PresenceStatus.nearby => nearbyGreen,
      PresenceStatus.online => colors.primary,
      PresenceStatus.offline => offlineGrey,
    };
    final badge = switch (member.role) {
      'owner' => 'Owner',
      'admin' => 'Admin',
      _ => '',
    };
    final wait = you ? null : pending;
    final near = wait != null &&
        wait.state == 'waiting' &&
        groupMemberNearNow(member.deviceId);
    return InkWell(
      onTap: you ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            AccountAvatar(name: name, radius: 21, peerId: member.deviceId),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(you ? 'You' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                      // Bundle 215 (B3): "Pending" right after the name.
                      if (wait != null) ...[
                        const SizedBox(width: 6),
                        GroupPendingTag(
                            key: ValueKey('member_pending_${member.deviceId}')),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (wait != null)
                    Row(
                      children: [
                        if (near)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: const BoxDecoration(
                                color: nearbyGreen, shape: BoxShape.circle),
                          ),
                        Flexible(
                          child: Text(groupPendingLine(wait, near: near),
                              key: ValueKey('member_pending_line_${member.deviceId}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.onSurfaceVariant)),
                        ),
                      ],
                    )
                  else
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(status.label,
                          style: TextStyle(
                              fontSize: 12.5, color: colors.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            if (badge.isNotEmpty)
              Container(
                key: ValueKey('member_badge_${member.deviceId}'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badge == 'Owner'
                      ? const Color(0xFFECE6FF)
                      : const Color(0xFFDDE6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: badge == 'Owner'
                            ? const Color(0xFF6A4BD8)
                            : const Color(0xFF1E4FE0))),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- mock 33

/// Mock 33: three "All members / Only admins" choices. [onChange] saves one
/// change (server for a group, memory while making one); a failure puts
/// the old choice back.
class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({
    super.key,
    required this.groupName,
    required this.editInfo,
    required this.sendMessages,
    required this.addMembers,
    required this.onChange,
    this.approve,
    this.onApprove,
  });

  /// Bundle G4 (mock 33): null = not shown (server-only groups).
  final bool? approve;
  final Future<void> Function(bool on)? onApprove;

  final String groupName;
  final String editInfo;
  final String sendMessages;
  final String addMembers;
  final Future<void> Function(String field, String value) onChange;

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late final Map<String, String> _values = {
    'edit_info': widget.editInfo,
    'send_messages': widget.sendMessages,
    'add_members': widget.addMembers,
  };
  late bool _approve = widget.approve ?? false;

  Future<void> _setApprove(bool on) async {
    final save = widget.onApprove;
    if (save == null || on == _approve) return;
    setState(() => _approve = on);
    try {
      await save(on);
    } catch (error) {
      if (!mounted) return;
      setState(() => _approve = !on);
      showErrorToast(context, error: error);
    }
  }

  Future<void> _set(String field, String value) async {
    final old = _values[field];
    if (old == value) return;
    setState(() => _values[field] = value);
    try {
      await widget.onChange(field, value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _values[field] = old ?? 'admins');
      showErrorToast(context, error: error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: NewGroupTitle(title: 'Group settings', subtitle: widget.groupName),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const MessengerGroupLabel('Admins decide', top: 8),
          MessengerListGroup(
            dividerIndent: 0,
            children: [
              _seg('edit_info', 'Edit group info', 'Name, photo and description'),
              _seg('send_messages', 'Send messages',
                  'Only admins = announcement group'),
              _seg('add_members', 'Add members', 'Includes the group QR code'),
            ],
          ),
          if (widget.approve != null && widget.onApprove != null) ...[
            const SizedBox(height: 12),
            MessengerListGroup(
              dividerIndent: 58,
              children: [
                _InfoRow(
                  key: const ValueKey('set_approve_row'),
                  icon: Icons.shield_outlined,
                  title: 'Approve new members',
                  subtitle: 'Admins approve people who join by QR',
                  chevron: false,
                  trailing: Switch(
                    key: const ValueKey('set_approve_switch'),
                    value: _approve,
                    onChanged: _setApprove,
                  ),
                  onTap: () => _setApprove(!_approve),
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
            child: Text('Only admins can see and change these.',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _seg(String field, String title, String sub) {
    final colors = Theme.of(context).colorScheme;
    final value = _values[field];
    Widget option(String v, String label) {
      final on = value == v;
      return Expanded(
        child: GestureDetector(
          key: ValueKey('set_${field}_$v'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _set(field, v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            decoration: BoxDecoration(
              color: on ? colors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: on
                  ? const [
                      BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 3,
                          offset: Offset(0, 1))
                    ]
                  : null,
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                    color: on ? colors.primary : colors.onSurfaceVariant)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 1),
          Text(sub,
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                option('all', 'All members'),
                option('admins', 'Only admins'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- mock 35

/// Mock 35: "Add members · Office · N of 32". Friends already in the group
/// are dim with "Already in the group". Pops with the picked friends.
class GroupAddMembersScreen extends StatefulWidget {
  const GroupAddMembersScreen({
    super.key,
    required this.groupName,
    required this.memberIds,
    required this.loadFriends,
  });

  final String groupName;
  final Set<String> memberIds;
  final Future<List<GroupFriend>> Function() loadFriends;

  @override
  State<GroupAddMembersScreen> createState() => _GroupAddMembersScreenState();
}

class _GroupAddMembersScreenState extends State<GroupAddMembersScreen> {
  List<GroupFriend>? _friends;
  final List<GroupFriend> _picked = [];
  bool _searching = false;
  final _search = TextEditingController();

  /// Members other than me count against the 32.
  int get _others =>
      widget.memberIds.isNotEmpty ? widget.memberIds.length - 1 : 0;

  @override
  void initState() {
    super.initState();
    widget.loadFriends().then((list) {
      if (mounted) setState(() => _friends = list);
    }, onError: (_) {
      if (mounted) setState(() => _friends = const []);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isPicked(GroupFriend f) => _picked.any((p) => p.deviceId == f.deviceId);

  void _toggle(GroupFriend f) {
    setState(() {
      if (_isPicked(f)) {
        _picked.removeWhere((p) => p.deviceId == f.deviceId);
      } else if (_others + _picked.length >= kNewGroupMax) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You can add up to $kNewGroupMax people')));
      } else {
        _picked.add(f);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final friends = _friends;
    final q = _search.text.trim().toLowerCase();
    final shown = (friends ?? const <GroupFriend>[])
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _searching
            ? TextField(
                key: const ValueKey('add_members_search'),
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    hintText: 'Search friends',
                    filled: false,
                    border: InputBorder.none),
              )
            : NewGroupTitle(
                title: 'Add members',
                subtitle:
                    '${widget.groupName} · ${_others + _picked.length} of $kNewGroupMax'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              _search.clear();
            }),
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
        ],
      ),
      floatingActionButton: SquareGradientFab(
        key: const ValueKey('add_members_done'),
        icon: Icons.check_rounded,
        tooltip: 'Add',
        onPressed: _picked.isEmpty
            ? null
            : () => Navigator.pop(context, List<GroupFriend>.from(_picked)),
      ),
      body: friends == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (_picked.isNotEmpty)
                  SizedBox(
                    key: const ValueKey('add_members_chips'),
                    height: 86,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      itemCount: _picked.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (_, i) {
                        final f = _picked[i];
                        return GestureDetector(
                          onTap: () => _toggle(f),
                          child: SizedBox(
                            width: 52,
                            child: Column(
                              children: [
                                AccountAvatar(name: f.name, radius: 23, peerId: f.deviceId),
                                const SizedBox(height: 4),
                                Text(f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const MessengerGroupLabel('Your friends', top: 10),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No friend found',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant)),
                  )
                else
                  ListenableBuilder(
                    listenable: PresenceHub.instance,
                    builder: (context, _) => MessengerListGroup(
                      children: [
                        for (final f in shown)
                          FriendPickRow(
                            key: ValueKey('add_pick_${f.deviceId}'),
                            name: f.name,
                            peerId: f.deviceId,
                            status: PresenceHub.instance.statusOf(f.deviceId),
                            picked: _isPicked(f),
                            enabled: !widget.memberIds.contains(f.deviceId),
                            note: widget.memberIds.contains(f.deviceId)
                                ? 'Already in the group'
                                : null,
                            onTap: () => _toggle(f),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
