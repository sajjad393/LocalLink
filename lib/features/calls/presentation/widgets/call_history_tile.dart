import 'package:flutter/material.dart';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/widgets/account_avatar.dart';

/// WhatsApp-style call history row: avatar, name, direction arrow + status,
/// trailing green call button (tap-to-redial).
class CallHistoryTile extends StatelessWidget {
  final CallRecord call;
  final String title;
  final String status;
  final String date;
  final String? duration;
  final String selfId;
  final bool missed;
  final VoidCallback? onCall;

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
  });

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
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      leading: AccountAvatar(name: title, radius: 21),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 15.5,
          color: missed ? colors.error : colors.onSurface,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            arrow,
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                duration == null ? '$status, $date' : '$status, $date · $duration',
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
      trailing: onCall == null
          ? null
          : IconButton(
              tooltip: 'Call $title',
              onPressed: onCall,
              icon: const Icon(
                Icons.call_rounded,
                color: whatsGreen,
                size: 24,
              ),
            ),
      onTap: onCall,
    );
  }
}
