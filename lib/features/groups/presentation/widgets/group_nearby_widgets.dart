import 'package:flutter/material.dart';

import 'package:locallink/core/models/group_join_code.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';

/// Bundle G3: Nearby group parts of the approved mock (G0 screens 6 / 7).
///
/// * [GroupAddingBanner]      mock 6 - "Adding Ali, Sara…" under the top bar.
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

/// Mock 6: light blue box with a small spinner.
class GroupAddingBanner extends StatelessWidget {
  const GroupAddingBanner({super.key, required this.invites, required this.onTap});

  final List<GroupInviteState> invites;
  final VoidCallback onTap;

  static const _bg = Color(0xFFEEF2FF);
  static const _border = Color(0xFFD5DEFF);
  static const _text = Color(0xFF24304F);
  static const _sub = Color(0xFF5B5C64);
  static const _blue = Color(0xFF1E5BFF);
  static const _ring = Color(0xFFBFCBFF);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Material(
        color: _bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _border),
        ),
        child: InkWell(
          key: const ValueKey('group_adding_banner'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: _blue,
                    backgroundColor: _ring,
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
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _text)),
                      const Text('They are added when Nearby or Online',
                          style: TextStyle(fontSize: 12, color: _sub)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Text('›', style: TextStyle(fontSize: 16, color: _text)),
              ],
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

/// Mock 7: "Adding people" - Added ✓ / Waiting 🕓 / couldn't be added
/// (after 7 days) with Try again.
Future<void> showAddingPeopleSheet(
  BuildContext context, {
  required List<GroupInviteState> invites,
  required String myName,
  Future<void> Function(String memberId)? onRetry,
}) {
  final waiting = invites.where((i) => i.state != 'added').toList();
  final example = waiting.isEmpty ? '' : waiting.first.name;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (c) {
      final colors = Theme.of(c).colorScheme;
      Widget row(GroupInviteState i, bool last) {
        final String line;
        final Widget trailing;
        switch (i.state) {
          case 'added':
            line = 'Added · ${_clock(c, i.atMs)}';
            trailing = const Icon(Icons.check_rounded,
                color: Color(0xFF1FB57A), size: 22);
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
            line = 'Waiting · added when Nearby or Online';
            trailing = const Icon(Icons.schedule_rounded,
                color: Color(0xFF8A8B93), size: 22);
        }
        return Container(
          key: ValueKey('group_invite_${i.memberId}'),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              AccountAvatar(name: i.name, radius: 21),
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
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
              child: Text('Adding people',
                  style: Theme.of(c).textTheme.titleLarge?.copyWith(
                      fontSize: 18, fontWeight: FontWeight.w700, height: 1.3)),
            ),
            for (var n = 0; n < invites.length; n++)
              row(invites[n], n == invites.length - 1),
            if (example.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
                child: Text(
                    'You can write now. $example gets "$myName added you" '
                    'first, then your messages.\n'
                    'Not reached in 7 days → "$example couldn\'t be added" '
                    '+ Try again.',
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: colors.onSurfaceVariant)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextButton(
                onPressed: () => Navigator.pop(c),
                style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0)),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Mock 6: the grey chip with a thin border.
class GroupSealedChip extends StatelessWidget {
  const GroupSealedChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Center(
        child: Container(
          key: const ValueKey('group_sealed_chip'),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F1F6),
            border: Border.all(color: const Color(0xFFE2E2EA)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('🔒 Messages are sealed for group members only',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Color(0xFF5B5C64))),
        ),
      ),
    );
  }
}
