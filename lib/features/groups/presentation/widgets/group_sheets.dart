import 'package:flutter/material.dart';

import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/group_avatar.dart';

/// Bundle G1: the bottom sheets of the approved group mock (G0).
///
/// * [showStartSheet]       mock 2  - Chats + button: New chat / New group.
/// * [showGroupRowSheet]    mock 11 - hold a group row in Chats.
/// * [showGroupMuteSheet]   mock 34 - 8 hours / 1 week / Always.
/// * [showGroupReactionsSheet] mock 21 - who reacted.

enum StartChoice { newChat, newGroup, joinQr }

enum GroupRowChoice { markRead, mute, unmute, info, clear, exit, delete }

/// One row of a sheet: icon, title, optional small grey line.
class GroupSheetAction extends StatelessWidget {
  const GroupSheetAction({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.red = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool red;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = red ? colors.error : colors.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: red ? colors.error : colors.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w500, color: fg)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12.5, color: colors.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _sheetTitle(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3)),
    );

Widget _closeButton(BuildContext context, String label) => Center(
      child: TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );

/// Mock 2: the Chats + button (G4: "Join group with QR").
Future<StartChoice?> showStartSheet(BuildContext context) {
  return showModalBottomSheet<StartChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetTitle(sheetContext, 'Start'),
            GroupSheetAction(
              key: const ValueKey('start_new_chat'),
              icon: Icons.chat_bubble_outline_rounded,
              title: 'New chat',
              subtitle: 'Message one friend',
              onTap: () => Navigator.pop(sheetContext, StartChoice.newChat),
            ),
            GroupSheetAction(
              key: const ValueKey('start_new_group'),
              icon: Icons.group_outlined,
              title: 'New group',
              subtitle: 'Up to 32 people Nearby, 100 Online',
              onTap: () => Navigator.pop(sheetContext, StartChoice.newGroup),
            ),
            // Bundle G4 (mock 2).
            GroupSheetAction(
              key: const ValueKey('start_join_qr'),
              icon: Icons.qr_code_2_rounded,
              title: 'Join group with QR',
              subtitle: 'Scan a group code',
              onTap: () => Navigator.pop(sheetContext, StartChoice.joinQr),
            ),
            _closeButton(sheetContext, 'Close'),
          ],
        ),
      ),
    ),
  );
}

/// Mock 11: hold a group row. G2: "Exit group" (red), or "Delete group"
/// when I already left / was removed.
Future<GroupRowChoice?> showGroupRowSheet(
  BuildContext context, {
  required String name,
  required int memberCount,
  required bool muted,
  bool active = true,
  String? groupId,
  int photoVersion = 0,
}) {
  return showModalBottomSheet<GroupRowChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final text = Theme.of(sheetContext).textTheme;
      final colors = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Row(
                  children: [
                    GroupAvatar(
                        radius: 23, groupId: groupId, photoVersion: photoVersion),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700, fontSize: 15.5)),
                          Text(
                              memberCount > 0
                                  ? 'Group · $memberCount members'
                                  : 'Group',
                              style: text.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              GroupSheetAction(
                key: const ValueKey('group_row_read'),
                icon: Icons.mark_chat_read_outlined,
                title: 'Mark as read',
                onTap: () => Navigator.pop(sheetContext, GroupRowChoice.markRead),
              ),
              if (muted)
                GroupSheetAction(
                  key: const ValueKey('group_row_unmute'),
                  icon: Icons.notifications_active_outlined,
                  title: 'Unmute notifications',
                  onTap: () => Navigator.pop(sheetContext, GroupRowChoice.unmute),
                )
              else
                GroupSheetAction(
                  key: const ValueKey('group_row_mute'),
                  icon: Icons.notifications_off_outlined,
                  title: 'Mute notifications',
                  onTap: () => Navigator.pop(sheetContext, GroupRowChoice.mute),
                ),
              GroupSheetAction(
                key: const ValueKey('group_row_info'),
                icon: Icons.info_outline_rounded,
                title: 'Group info',
                onTap: () => Navigator.pop(sheetContext, GroupRowChoice.info),
              ),
              GroupSheetAction(
                key: const ValueKey('chat_row_clear'),
                icon: Icons.clear_all_rounded,
                title: 'Clear chat',
                onTap: () => Navigator.pop(sheetContext, GroupRowChoice.clear),
              ),
              if (active)
                GroupSheetAction(
                  key: const ValueKey('group_row_exit'),
                  icon: Icons.logout_rounded,
                  title: 'Exit group',
                  red: true,
                  onTap: () => Navigator.pop(sheetContext, GroupRowChoice.exit),
                )
              else
                GroupSheetAction(
                  key: const ValueKey('group_row_delete'),
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete group',
                  red: true,
                  onTap: () => Navigator.pop(sheetContext, GroupRowChoice.delete),
                ),
              _closeButton(sheetContext, 'Close'),
            ],
          ),
        ),
      );
    },
  );
}

/// Result of the mute sheet: [length] null = Always.
class GroupMuteChoice {
  const GroupMuteChoice(this.length);
  final Duration? length;
}

/// Mock 34: Mute notifications - 8 hours / 1 week (picked) / Always.
Future<GroupMuteChoice?> showGroupMuteSheet(BuildContext context) {
  return showModalBottomSheet<GroupMuteChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => const _MuteSheet(),
  );
}

class _MuteSheet extends StatefulWidget {
  const _MuteSheet();

  @override
  State<_MuteSheet> createState() => _MuteSheetState();
}

class _MuteSheetState extends State<_MuteSheet> {
  static const _options = <(String, Duration?)>[
    ('8 hours', Duration(hours: 8)),
    ('1 week', Duration(days: 7)),
    ('Always', null),
  ];
  int _picked = 1;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Mute notifications',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('You still get messages. A mention of you (@) still notifies you.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: colors.onSurfaceVariant)),
            const SizedBox(height: 12),
            for (var i = 0; i < _options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  key: ValueKey('mute_opt_$i'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _picked = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: i == _picked
                          ? colors.primary.withValues(alpha: .06)
                          : null,
                      border: Border.all(
                          width: 1.5,
                          color: i == _picked
                              ? colors.primary
                              : colors.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            i == _picked
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 22,
                            color: i == _picked
                                ? colors.primary
                                : colors.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Text(_options[i].$1,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  key: const ValueKey('mute_confirm'),
                  onPressed: () => Navigator.pop(
                      context, GroupMuteChoice(_options[_picked].$2)),
                  child: const Text('Mute',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mock 21: tap the reaction chip - who reacted. Tabs: All N / one per
/// emoji. My own row says "Tap to remove".
Future<void> showGroupReactionsSheet(
  BuildContext context, {
  required List<MessageReaction> reactions,
  required String localDeviceId,
  required String Function(String deviceId) nameOf,
  required Future<void> Function() onRemoveMine,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _ReactionsSheet(
      reactions: reactions,
      localDeviceId: localDeviceId,
      nameOf: nameOf,
      onRemoveMine: onRemoveMine,
    ),
  );
}

class _ReactionsSheet extends StatefulWidget {
  const _ReactionsSheet({
    required this.reactions,
    required this.localDeviceId,
    required this.nameOf,
    required this.onRemoveMine,
  });

  final List<MessageReaction> reactions;
  final String localDeviceId;
  final String Function(String deviceId) nameOf;
  final Future<void> Function() onRemoveMine;

  @override
  State<_ReactionsSheet> createState() => _ReactionsSheetState();
}

class _ReactionsSheetState extends State<_ReactionsSheet> {
  String? _emoji; // null = All

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final r in widget.reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    final rows = widget.reactions
        .where((r) => _emoji == null || r.emoji == _emoji)
        .toList(growable: false);
    Widget tab(String label, String? emoji) {
      final on = _emoji == emoji;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _emoji = emoji),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: on
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest.withValues(alpha: .6),
              border: Border.all(
                  color: on
                      ? colors.primary.withValues(alpha: .25)
                      : colors.outlineVariant),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                    color: on ? colors.primary : colors.onSurface)),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reactions',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  tab('All ${widget.reactions.length}', null),
                  for (final e in counts.entries) tab('${e.key} ${e.value}', e.key),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final r in rows) _row(context, r),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, MessageReaction r) {
    final colors = Theme.of(context).colorScheme;
    final mine = r.reactorId == widget.localDeviceId;
    final name = widget.nameOf(r.reactorId);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: Row(
        children: [
          AccountAvatar(name: name, radius: 17, peerId: r.reactorId),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mine ? 'You' : name,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
                if (mine)
                  Text('Tap to remove',
                      style: TextStyle(fontSize: 12.5, color: colors.primary)),
              ],
            ),
          ),
          Text(r.emoji, style: const TextStyle(fontSize: 20)),
        ],
      ),
    );
    if (!mine) return content;
    return InkWell(
      key: const ValueKey('reaction_remove_mine'),
      onTap: () async {
        Navigator.pop(context);
        await widget.onRemoveMine();
      },
      child: content,
    );
  }
}
