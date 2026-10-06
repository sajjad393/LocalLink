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

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.files,
    this.onLongPress,
    this.reactions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxWidth = (MediaQuery.sizeOf(context).width * .82).clamp(160.0, 620.0);
    final bubbleColor = isMine ? colors.primaryContainer : colors.surfaceContainerHighest;
    final foreground = isMine ? colors.onPrimaryContainer : colors.onSurface;
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
        button: onLongPress != null,
        hint: onLongPress != null ? 'Long press for message actions' : null,
        child: GestureDetector(
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
            decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
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
                    attachment: attachment,
                    transfer: files,
                    messageId: message.id,
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
                        color: foreground.withOpacity(.62),
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: LocalLinkSpacing.xs),
                      Text(
                        _statusText(message.status),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _statusColor(context, message.status),
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
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

  String _statusText(String status) => switch (status.toLowerCase()) {
        'delivered' => '✓✓',
        'read' => '✓✓',
        'sent' => '✓',
        'failed' => '!',
        'queued' || 'pending' => '◷',
        _ => '✓',
      };

  Color _statusColor(BuildContext context, String status) {
    final colors = Theme.of(context).colorScheme;
    return switch (status.toLowerCase()) {
      'failed' => colors.error,
      'read' => colors.primary,
      _ => colors.onSurfaceVariant,
    };
  }
}
