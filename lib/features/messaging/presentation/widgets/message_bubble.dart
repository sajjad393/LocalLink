import 'package:flutter/material.dart';

import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final FileTransferRepositoryContract files;
  final VoidCallback? onLongPress;
  final List<MessageReaction> reactions;

  /// Bundle 162 (4.6): tap on a failed (red !) message of mine.
  final VoidCallback? onFailedTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.files,
    this.onLongPress,
    this.reactions = const [],
    this.onFailedTap,
  });

  bool get _canResend =>
      isMine && onFailedTap != null && message.status.toLowerCase() == 'failed';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxWidth = (MediaQuery.sizeOf(context).width * .82).clamp(160.0, 620.0);
    // No brand blue on bubbles — neutral surfaces on both sides, so both
    // share scheme text colors.
    final foreground = colors.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(LocalLinkRadius.chat),
      topRight: const Radius.circular(LocalLinkRadius.chat),
      bottomLeft: Radius.circular(isMine ? LocalLinkRadius.chat : 6),
      bottomRight: Radius.circular(isMine ? 6 : LocalLinkRadius.chat),
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        label: message.body.isEmpty ? 'Message with attachment' : message.body,
        button: onLongPress != null || _canResend,
        hint: _canResend
            ? 'Message not sent. Tap to resend or delete'
            : (onLongPress != null ? 'Long press for message actions' : null),
        child: GestureDetector(
          onTap: _canResend ? onFailedTap : null,
          onLongPress: onLongPress,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            margin: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
            padding: const EdgeInsets.fromLTRB(
              LocalLinkSpacing.md,
              LocalLinkSpacing.sm,
              LocalLinkSpacing.md,
              LocalLinkSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: isMine
                  ? colors.surfaceContainer
                  : colors.surfaceContainerHighest,
              borderRadius: radius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.body.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(message.body, style: TextStyle(color: foreground)),
                  ),
                ...message.attachments.map(
                  (attachment) => AttachmentTile(
                    key: ValueKey<String>('att:${message.id}:${attachment.id}'),
                    attachment: attachment,
                    transfer: files,
                    messageId: message.id,
                    // Outgoing media that the outbox is still flushing gets the
                    // upload ring; once delivered the ring lifts.
                    uploading: isMine &&
                        (message.status == 'queued' ||
                            message.status == 'sending' ||
                            message.status == 'pending'),
                  ),
                ),
                if (reactions.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _reactionCounts(context),
                      ),
                    ),
                  ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _time(message.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: foreground.withValues(alpha: .62),
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: LocalLinkSpacing.xs),
                      _StatusIcon(status: message.status, channel: message.channel),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _reactionCounts(BuildContext context) {
    final counts = <String, int>{};
    for (final reaction in reactions) { counts[reaction.emoji] = (counts[reaction.emoji] ?? 0) + 1; }
    return counts.entries.map((entry) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text('${entry.key} ${entry.value}', style: Theme.of(context).textTheme.labelSmall),
    )).toList(growable: false);
  }

  String _time(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

}

/// WhatsApp-style delivery ticks: ⌛ queued, ✓ sent (grey), ✓✓ delivered
/// (grey), ✓✓ read (blue).
class _StatusIcon extends StatelessWidget {
  final String status;
  final String? channel;

  const _StatusIcon({required this.status, this.channel});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final glyph = switch (status.toLowerCase()) {
      'queued' || 'pending' || 'sending' => Icon(
          Icons.schedule_rounded,
          size: 14,
          color: colors.onSurfaceVariant,
        ),
      'failed' => Icon(
          Icons.error_outline_rounded,
          size: 14,
          color: colors.error,
        ),
      'read' => Icon(
          // double check, blue = read
          Icons.done_all_rounded,
          size: 15,
          color: colors.primary,
        ),
      'delivered' || 'direct_delivered' => Icon(
          // double check, grey = delivered
          Icons.done_all_rounded,
          size: 15,
          color: colors.onSurfaceVariant,
        ),
      // single grey check = sent to server
      _ => Icon(
          Icons.check_rounded,
          size: 15,
          color: colors.onSurfaceVariant,
        ),
    };
    if (channel == null) return glyph;
    // Bundle 52C: tiny path glyph beside the ticks — antenna for messages
    // that traveled the direct link, globe for the server path.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          channel == 'direct' ? Icons.wifi_rounded : Icons.public_rounded,
          size: 11,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        glyph,
      ],
    );
  }
}
