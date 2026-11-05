import 'package:flutter/material.dart';

import 'package:locallink/core/models/group_join_code.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';

/// Bundle G3: Nearby group parts of the approved mock (G0 screens 6 / 7).
///
/// * [GroupAddingBanner]      mock 6 - "Adding Ali, Sara…" (bundle 215: no
///   longer shown on the chat page; kept for its old tests).
/// * [GroupPendingTag]        bundle 215 - "Pending" in Group info.
/// * [showAddingPeopleSheet]  mock 7 - who is added / waiting.
/// * [GroupSealedChip]        mock 6 - "🔒 Messages are sealed for group
///   members only" after the first system lines.

/// Bundle G3: the screens reach the Nearby group service here (set in
/// app start; tests put their own loaders).
class GroupNearbyHub {
  GroupNearbyHub._();

  static Future<List<GroupInviteState>> Function(String gid)? loadInvites;
  static Future<void> Function(String gid, String memberId)? retry;

  // Bundle G4: Join with QR (mocks 2 / 33 / 36 / 37 / 38).
  static Future<GroupJoinCode> Function(String gid, bool reset)? inviteCode;
  static Future<bool> Function(String gid)? approveOf;
  static Future<void> Function(String gid, bool on)? setApprove;
  static Future<List<GroupJoinRequest>> Function(String gid)? loadRequests;
  static Future<void> Function(String gid, String memberId)? addJoiner;
  static Future<void> Function(String gid, String memberId)? ignoreJoiner;
  static Future<String> Function(String gid)? joinState;
  static Future<void> Function(GroupJoinCode code)? askToJoin;
  static Future<bool> Function(String gid)? inGroup;

  static void bind(GroupNearbyService? service) {
    if (service == null) return;
    loadInvites = service.invites;
    retry = service.retryInvite;
    inviteCode = (gid, reset) => service.inviteCode(gid, reset: reset);
    approveOf = (gid) async => (await service.card(gid))?.approve ?? false;
    setApprove = (gid, on) => service.update(gid, approve: on);
    loadRequests = service.joinRequests;
    addJoiner = service.addJoiner;
    ignoreJoiner = service.ignoreJoiner;
    joinState = service.joinState;
    askToJoin = service.askToJoin;
    inGroup = service.inGroup;
  }
}

/// "Ali, Sara…" for the banner: the people still waiting.
String addingNames(List<GroupInviteState> invites) {
  final waiting = [
    for (final i in invites)
      if (i.state != 'added') i.name
  ];
  return '${waiting.join(', ')}…';
}

/// Bundle 207 (F/M): is this member Nearby right now? (PresenceHub;
/// tests can swap it.)
bool Function(String memberId) groupMemberNearNow =
    (id) => PresenceHub.instance.statusOf(id) == PresenceStatus.nearby;

/// Bundle 215 (B): is this member still waiting for the group (not yet
/// on her phone)? `waiting` and `failed` are pending; `added` is not.
bool groupInvitePending(GroupInviteState? invite) =>
    invite != null && invite.state != 'added';

/// Bundle 215 (B3): the line under a pending member's name.
String groupPendingLine(GroupInviteState invite, {required bool near}) {
  if (invite.state == 'failed') return 'Not reached in 7 days · tap to try again';
  if (near) return 'Nearby now · adding…';
  return 'Gets the group when Nearby or Online';
}

/// Bundle 215 (B3, mock 215 page 3): small orange "Pending" pill.
class GroupPendingTag extends StatelessWidget {
  const GroupPendingTag({super.key});

  static const Color text = Color(0xFFC26A00);
  static const Color bg = Color(0xFFFFF1DC);
  static const Color darkText = Color(0xFFFFB547);
  static const Color darkBg = Color(0xFF3A2A12);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? darkText : text;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      decoration: BoxDecoration(
        color: dark ? darkBg : bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 12, color: fg),
          const SizedBox(width: 3),
          Text('Pending',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

/// Bundle 207 (M, mock 207 page 2): strip colours that work in light and
/// dark.
class _AddingColors {
  _AddingColors(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    bg = dark ? const Color(0xFF1C2742) : const Color(0xFFEEF2FF);
    border = dark ? const Color(0xFF2C3A63) : const Color(0xFFD5DEFF);
    ring = border;
  }
  late final Color bg;
  late final Color border;
  late final Color ring;
  static const Color blue = Color(0xFF1E5BFF);
  static const Color green = Color(0xFF1FB57A);
}

Widget _greenDot() => Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(right: 5),
      decoration: const BoxDecoration(
          color: _AddingColors.green, shape: BoxShape.circle),
    );

/// Mock 6 / 207 page 2: "Adding sumaira…" strip with a small spinner.
/// "Nearby now · a few seconds" when one of them is near.
class GroupAddingBanner extends StatelessWidget {
  const GroupAddingBanner({super.key, required this.invites, required this.onTap});

  final List<GroupInviteState> invites;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final c = _AddingColors(context);
    final near = invites
        .any((i) => i.state == 'waiting' && groupMemberNearNow(i.memberId));
    return ListenableBuilder(
      listenable: PresenceHub.instance,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
        child: Material(
          color: c.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.border),
          ),
          child: InkWell(
            key: const ValueKey('group_adding_banner'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: _AddingColors.blue,
                      backgroundColor: c.ring,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Adding ${addingNames(invites)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface)),
                        Row(children: [
                          if (near) _greenDot(),
                          Flexible(
                            child: Text(
                                near
                                    ? 'Nearby now · a few seconds'
                                    : 'They are added when Nearby or Online',
                                key: const ValueKey('group_adding_banner_line'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: colors.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _clock(BuildContext context, int ms) {
  final t = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms));
  return MaterialLocalizations.of(context).formatTimeOfDay(t);
}

/// Mock 7 / 207 page 2: "Adding people" - Added ✓ / Adding now (Nearby,
/// spinner) / Waiting / couldn't be added (after 7 days) with Try again.
Future<void> showAddingPeopleSheet(
  BuildContext context, {
  required List<GroupInviteState> invites,
  required String myName,
  Future<void> Function(String memberId)? onRetry,
}) {
  final waiting = invites.where((i) => i.state != 'added').toList();
  final added = invites.length - waiting.length;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (c) {
      final colors = Theme.of(c).colorScheme;
      final ac = _AddingColors(c);
      Widget row(GroupInviteState i, bool last) {
        final String line;
        final Widget trailing;
        final near = i.state == 'waiting' && groupMemberNearNow(i.memberId);
        switch (i.state) {
          case 'added':
            line = 'Added · ${_clock(c, i.atMs)}';
            trailing = Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                  color: _AddingColors.green, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 16),
            );
          case 'failed':
            line = "Couldn't be added";
            trailing = TextButton(
              key: ValueKey('group_invite_retry_${i.memberId}'),
              onPressed: onRetry == null
                  ? null
                  : () async {
                      Navigator.pop(c);
                      await onRetry(i.memberId);
                    },
              child: const Text('Try again'),
            );
          default:
            if (near) {
              line = 'Adding now · Nearby';
              trailing = SizedBox(
                key: ValueKey('group_invite_adding_${i.memberId}'),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _AddingColors.blue,
                    backgroundColor: ac.ring),
              );
            } else {
              line = 'Waiting · not near or online yet';
              trailing = Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Waiting',
                    style: TextStyle(
                        fontSize: 12, color: colors.onSurfaceVariant)),
              );
            }
        }
        return Container(
          key: ValueKey('group_invite_${i.memberId}'),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              AccountAvatar(name: i.name, radius: 21, peerId: i.memberId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700)),
                    Text(line,
                        style: TextStyle(
                            fontSize: 13, color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        );
      }

      return SingleChildScrollView(
        key: const ValueKey('group_adding_sheet'),
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
              child: Text('Adding people',
                  style: Theme.of(c).textTheme.titleLarge?.copyWith(
                      fontSize: 19, fontWeight: FontWeight.w700, height: 1.3)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
              child: Text('$added of ${invites.length} added',
                  key: const ValueKey('group_adding_count'),
                  style:
                      TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
            ),
            for (var n = 0; n < invites.length; n++)
              row(invites[n], n == invites.length - 1),
            if (waiting.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 18, color: colors.onSurfaceVariant),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                          // Bundle 207 (M2): short and clear (mock 207 p2).
                          'You can write now. They get your messages right '
                          'after they join.',
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: colors.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: () => Navigator.pop(c),
                style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0)),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Mock 6 / 207 page 2: a light blue-tinted chip with a lock (works in
/// dark mode too).
class GroupSealedChip extends StatelessWidget {
  const GroupSealedChip({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? const Color(0xFFA9BBFF) : const Color(0xFF3D5BB8);
    final bg = dark
        ? const Color(0xFF7896FF).withValues(alpha: .12)
        : const Color(0xFF1E5BFF).withValues(alpha: .10);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Center(
        child: Container(
          key: const ValueKey('group_sealed_chip'),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 12, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text('Messages are sealed for group members only',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
