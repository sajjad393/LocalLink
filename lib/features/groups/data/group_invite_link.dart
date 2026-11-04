import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';

/// Bundle G6 (mock L1-L5): "Invite with link" for groups on the server.
///
/// * Admins get one link per group (`linkup://join/<token>`); "Reset link"
///   makes a new one and the old one stops working.
/// * Server-only groups: opening the link joins at once.
/// * Groups that also work Nearby (signed card): opening the link asks to
///   join; an admin phone adds the person to the card (keys come with the
///   request). "Approve new members" off = the first admin phone that sees
///   the request adds them by itself.
/// * Nearby-only groups: no link (mock L5) - use Invite with QR.
class GroupInviteLink {
  GroupInviteLink._();

  static final RegExp _re = RegExp(
      r'(?:linkup://join/|/join/)([A-HJ-NP-Za-km-z2-9]{8,64})(?![A-Za-z0-9])');

  /// The token of the first invite link in [text], or null.
  static String? tokenIn(String text) {
    if (!text.contains('join/')) return null;
    return _re.firstMatch(text)?.group(1);
  }

  static String link(String token) => 'linkup://join/$token';

  /// Tappable in other apps (WhatsApp / SMS don't open linkup://): the
  /// server page with an "Open in LinkUp" button.
  static String webLink(String serverBase, String token) {
    final base = serverBase.trim().replaceAll(RegExp(r'/+$'), '');
    return base.isEmpty ? '' : '$base/join/$token';
  }

  static String shareText(String groupName, String token, String serverBase) {
    final web = webLink(serverBase, token);
    return [
      'Join my LinkUp group "$groupName":',
      if (web.isNotEmpty) web,
      if (web.isNotEmpty) '',
      if (web.isNotEmpty) 'In LinkUp: ${link(token)}' else link(token),
    ].join('\n');
  }

  // ---- links opened from other apps (Android intent) --------------------

  static const MethodChannel _channel = MethodChannel('locallink/join_link');

  /// The token of a `linkup://join/…` link that opened the app (once).
  static Future<String?> takeOpenedLink() async {
    try {
      final raw = await _channel.invokeMethod<String>('take');
      if (raw == null || raw.isEmpty) return null;
      return tokenIn(raw);
    } catch (_) {
      return null;
    }
  }
}

/// What the link opens (mock L3 / L4).
class GroupJoinPreview {
  const GroupJoinPreview({
    required this.groupId,
    required this.name,
    this.description = '',
    this.members = 0,
    this.memberNames = const [],
    this.invitedBy = '',
    this.approve = false,
    this.status = 'none',
  });

  factory GroupJoinPreview.fromJson(Map<String, dynamic> j) => GroupJoinPreview(
        groupId: j['group_id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Group',
        description: j['description']?.toString() ?? '',
        members: (j['members'] as num?)?.toInt() ?? 0,
        memberNames: [
          for (final n in (j['member_names'] as List? ?? const []))
            if (n.toString().trim().isNotEmpty) n.toString().trim()
        ],
        invitedBy: j['invited_by']?.toString() ?? '',
        approve: j['approve'] == true,
        status: j['status']?.toString() ?? 'none',
      );

  final String groupId;
  final String name;
  final String description;
  final int members;
  final List<String> memberNames;
  final String invitedBy;
  final bool approve;

  /// member | requested | none
  final String status;

  GroupJoinPreview withStatus(String s) => GroupJoinPreview(
      groupId: groupId,
      name: name,
      description: description,
      members: members,
      memberNames: memberNames,
      invitedBy: invitedBy,
      approve: approve,
      status: s);

  /// "Group · 4 members · invite link from Sajjad"
  String get line {
    final parts = <String>[
      'Group',
      '$members ${members == 1 ? 'member' : 'members'}',
      if (invitedBy.isNotEmpty) 'invite link from $invitedBy',
    ];
    return parts.join(' · ');
  }
}

class GroupInviteService {
  GroupInviteService({
    required this.api,
    this.nearby,
    this.refreshGroup,
    this.selfId,
  });

  /// Set by app_dependencies; null in widget tests (UI shows "can't open").
  static GroupInviteService? instance;

  /// Opens the group chat after a join (set by the app shell).
  static Future<void> Function(String gid)? openGroup;

  final LocalLinkApi api;
  final GroupNearbyService? nearby;
  final Future<void> Function(String gid)? refreshGroup;
  final String Function()? selfId;

  final Map<String, GroupJoinPreview> _previews = {};

  String get serverBase {
    try {
      return api.baseUrl;
    } catch (_) {
      return '';
    }
  }

  /// Admins: the link token. Card groups always ask first (only an admin
  /// phone can sign the card).
  Future<String> token(LocalGroup g, {bool reset = false}) async {
    final t = await api.groupInviteToken(g.id,
        approve: g.worksNearby, reset: reset);
    AppLogger.info('GROUP_LINK', detail: 'made=${reset ? 'reset' : 'y'}');
    return t;
  }

  /// Cached for the chat card; [fresh] = read again (Join screen).
  Future<GroupJoinPreview> preview(String token, {bool fresh = false}) async {
    final old = _previews[token];
    if (old != null && !fresh) return old;
    final p = GroupJoinPreview.fromJson(await api.groupJoinPreview(token));
    _previews[token] = p;
    return p;
  }

  GroupJoinPreview? cached(String token) => _previews[token];

  /// "Join group" / "Ask to join". Returns member | joined | requested.
  Future<String> join(String token) async {
    var seal = '', sign = '';
    final n = nearby;
    if (n != null) {
      try {
        (seal, sign) = await n.ownCardKeys();
      } catch (_) {}
    }
    final res = await api.joinGroupByLink(token, seal: seal, sign: sign);
    final status = res['status']?.toString() ?? '';
    final gid = res['group_id']?.toString() ?? '';
    AppLogger.info('GROUP_LINK_JOIN', detail: 'status=$status');
    final old = _previews[token];
    if (old != null) {
      _previews[token] = old.withStatus(status == 'joined' ? 'member' : status);
    }
    if ((status == 'joined' || status == 'member') && gid.isNotEmpty) {
      try {
        await refreshGroup?.call(gid);
      } catch (_) {}
      GroupChangeHub.instance.changed(gid);
    }
    return status;
  }

  /// Admins: people who asked by link (shown with the QR ones, mock 37).
  Future<List<GroupJoinRequest>> requests(LocalGroup g) async {
    if (g.nearbyOnly) return const [];
    try {
      final rows = await api.groupLinkRequests(g.id);
      return [
        for (final r in rows)
          GroupJoinRequest(
            memberId: r['device_id']?.toString() ?? '',
            name: (r['name']?.toString().trim().isNotEmpty ?? false)
                ? r['name'].toString().trim()
                : 'LinkUp user',
            username: '',
            atMs: DateTime.tryParse(r['created_at']?.toString() ?? '')
                    ?.millisecondsSinceEpoch ??
                0,
            via: 'link',
            seal: r['seal']?.toString() ?? '',
            sign: r['sign']?.toString() ?? '',
          )
      ];
    } catch (_) {
      return const [];
    }
  }

  /// "Add to group" for a link request.
  Future<void> approve(LocalGroup g, GroupJoinRequest r) async {
    final n = nearby;
    if (g.worksNearby && n != null) {
      if (r.seal.isEmpty || r.sign.isEmpty) {
        throw const GroupActionException('GROUP_NO_KEYS',
            'Ask them to open the link again with the newest LinkUp.');
      }
      var serverDone = false;
      try {
        await api.addGroupMember(g.id, r.memberId);
        serverDone = true;
      } on GroupActionException {
        rethrow;
      } catch (_) {}
      await n.addByKeys(g.id, r.memberId, r.name, r.seal, r.sign,
          quiet: serverDone);
    } else {
      await api.addGroupMember(g.id, r.memberId);
    }
    try {
      await refreshGroup?.call(g.id);
    } catch (_) {}
    AppLogger.info('GROUP_LINK_APPROVED', detail: 'card=${g.worksNearby}');
    GroupChangeHub.instance.changed(g.id);
  }

  /// "Ignore" (silent).
  Future<void> decline(String gid, String memberId) async {
    await api.declineGroupLinkRequest(gid, memberId);
    AppLogger.info('GROUP_LINK_DECLINED');
    GroupChangeHub.instance.changed(gid);
  }

  /// A request came in (socket) or the admin opened Group info: in a card
  /// group with "Approve new members" OFF, add the people by ourselves.
  Future<void> autoApprove(LocalGroup g) async {
    final n = nearby;
    if (n == null || !g.worksNearby || g.nearbyOnly) return;
    final c = await n.card(g.id);
    final me = selfId?.call() ?? '';
    if (c == null || c.approve || me.isEmpty || !c.isAdmin(me)) return;
    for (final r in await requests(g)) {
      if (r.seal.isEmpty || r.sign.isEmpty) continue;
      try {
        await approve(g, r);
      } catch (e) {
        AppLogger.warning('GROUP_LINK_AUTO_FAILED', detail: '$e');
      }
    }
  }

  @visibleForTesting
  void putPreview(String token, GroupJoinPreview p) => _previews[token] = p;
}
