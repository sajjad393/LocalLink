import 'package:flutter/material.dart';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';

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
  });

  // 'Completed' is the default happy path, so it stays silent (mock 99):
  // completed rows show "12:48 AM · 2:50"; everything else keeps its label.
  String _statusLine() =>
      status == 'Completed'
          ? (duration == null ? date : '$date · $duration')
          : (duration == null ? '$status, $date' : '$status, $date · $duration');

  @override
  Widget build(BuildContext context) {
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
      leading: PresenceAvatar(
        // Bundle 137: presence badge overlay, same as the chat header avatar.
        avatar: AccountAvatar(name: title, radius: 21),
        device: Device(
            id: call.peerId(selfId),
            name: title,
            platform: 'android',
            createdAt: '',
            lastSeenAt: ''),
      ),
      title: _title(context, colors),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            arrow,
            const SizedBox(width: 5),
            Expanded(
              child: Text(
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
      trailing: MessengerCallButton(tooltip: 'Call back', onPressed: onCall),
      onTap: onOpen ?? onCall,
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
            color: missed ? colors.error : colors.onSurface,
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
                color: missed ? colors.error : colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
