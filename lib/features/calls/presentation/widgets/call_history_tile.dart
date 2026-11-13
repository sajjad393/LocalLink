import 'package:flutter/material.dart';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/directory/presentation/contact_sheets.dart';

/// WhatsApp-style call history row: avatar, name, direction arrow + time.
/// Bundle 99: no trailing call-back button — the ROW itself starts the call.
class CallHistoryTile extends StatelessWidget {
  final CallRecord call;
  final String title;
  final String status;
  final String date;
  final String? duration;
  final String selfId;
  final bool missed;
  final VoidCallback? onCall;

  /// Bundle 171: how many calls this row stands for ("sajjad (4)").
  final int count;

  /// Bundle 171: row tap for a grouped row (opens the list of calls).
  /// When null the row tap calls back, as before.
  final VoidCallback? onOpen;

  /// Bundle 285: missed calls inside this row (one row per person per
  /// day). More than 0 = the name is red and the line ends "· 2 missed".
  final int missedInside;

  const CallHistoryTile({
    super.key,
    required this.call,
    required this.title,
    required this.status,
    required this.date,
    required this.duration,
    required this.selfId,
    this.missed = false,
    this.onCall,
    this.count = 1,
    this.onOpen,
    this.missedInside = 0,
  });

  /// Bundle 285: the name is red when this call or one inside is missed.
  bool get _red => missed || missedInside > 0;

  // 'Completed' is the default happy path, so it stays silent (mock 99):
  // completed rows show "12:48 AM · 2:50"; everything else keeps its label.
  String _statusLine() =>
      status == 'Completed'
          ? (duration == null ? date : '$date · $duration')
          : (duration == null ? '$status, $date' : '$status, $date · $duration');

  @override
  Widget build(BuildContext context) {
    // Bundle 196 (11.1): blocked rows follow BlockHub live.
    return ListenableBuilder(
      listenable: BlockHub.instance,
      builder: (context, _) => _row(context),
    );
  }

  Future<void> _openUnblock(BuildContext context, String peerId) async {
    final hub = BlockHub.instance;
    var person = hub.personForDevice(peerId);
    if (person == null) {
      final who = await hub.lookup(peerId);
      person = hub.personForUser(who?.userId ?? '') ??
          BlockedPerson(
            userId: who?.userId ?? peerId,
            deviceId: peerId,
            name: title,
            username: who?.username ?? '',
          );
    }
    if (!context.mounted) return;
    await runUnblockFlow(context, person, from: 'calls');
  }

  Widget _row(BuildContext context) {
    final peerId = call.peerId(selfId);
    final blocked = BlockHub.instance.isBlockedDevice(peerId);
    final blockedMe = !blocked && BlockHub.instance.hasBlockedMe(peerId);
    final outgoing = call.isOutgoing(selfId);
    final colors = Theme.of(context).colorScheme;
    const whatsGreen = Color(0xFF25D366);

    final arrow = missed
        ? Icon(Icons.call_received_rounded, size: 16, color: colors.error)
        : (outgoing
            ? const Icon(Icons.call_made_rounded, size: 16, color: whatsGreen)
            : Icon(Icons.call_received_rounded,
                size: 16, color: colors.onSurfaceVariant));

    return ListTile(
      // Bundle 153: right padding 16 so the call button lines up with Chats.
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      key: blocked ? ValueKey('calls_blocked_$peerId') : null,
      leading: blocked
          ? MutedAvatar(name: title, radius: 21)
          : PresenceAvatar(
        // Bundle 137: presence badge overlay, same as the chat header avatar.
        avatar: AccountAvatar(name: title, radius: 21, peerId: call.peerId(selfId)),
        device: Device(
            id: call.peerId(selfId),
            name: title,
            platform: 'android',
            createdAt: '',
            lastSeenAt: ''),
      ),
      title: blocked
          ? Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(width: 6),
                const BlockedPill(),
              ],
            )
          : _title(context, colors),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            arrow,
            const SizedBox(width: 5),
            Expanded(
              child: missedInside > 0
                  // Bundle 285 (mock 285): "No answer, 1:29 PM · 2 missed".
                  ? Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${_statusLine()} · '),
                        TextSpan(
                          text: '$missedInside missed',
                          style: TextStyle(color: colors.error, fontWeight: FontWeight.w600),
                        ),
                      ]),
                      // A long line wraps once, so "N missed" never hides
                      // behind the "…".
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: missed ? colors.error : colors.onSurfaceVariant,
                      ),
                    )
                  : Text(
                      _statusLine(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: missed ? colors.error : colors.onSurfaceVariant,
                      ),
                    ),
            ),
          ],
        ),
      ),
      // Bundle 153: the same light-blue call button as the Chats list (the
      // row tap keeps calling too).
      // Bundle 196: no call-back for a blocked person (either side); a tap
      // on a row I blocked opens the Unblock sheet instead of calling.
      trailing: (blocked || blockedMe)
          ? null
          : MessengerCallButton(tooltip: 'Call back', onPressed: onCall),
      onTap: blocked
          ? () => _openUnblock(context, peerId)
          : (onOpen ?? (blockedMe ? null : onCall)),
    );
  }

  Widget _title(BuildContext context, ColorScheme colors) {
    final name = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // Bundle 153: bold name, same style as the Chats list.
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: _red ? colors.error : colors.onSurface,
          ),
    );
    if (count <= 1) return name;
    // Bundle 171: grouped row — the count follows the name.
    return Row(
      children: [
        Flexible(child: name),
        const SizedBox(width: 6),
        Text(
          '($count)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w400,
                color: _red ? colors.error : colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
