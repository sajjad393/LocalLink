import 'package:flutter/material.dart';

import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';

import 'bubble_layout.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final FileTransferRepositoryContract files;
  final VoidCallback? onLongPress;
  final List<MessageReaction> reactions;

  /// Bundle 162 (4.6): tap on a failed (red !) message of mine.
  final VoidCallback? onFailedTap;

  /// Bundle 182: the friend is Offline right now. My photo/video that is not
  /// sent yet shows a clock + "Waiting" instead of the turning ring.
  final bool peerOffline;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.files,
    this.onLongPress,
    this.reactions = const [],
    this.onFailedTap,
    this.peerOffline = false,
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
          child: Padding(
            padding: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
            // Bundle 182: emoji chips on the bottom edge, bubble fits content.
            child: BubbleReactionEdge(
              chips: reactions.isEmpty ? const <Widget>[] : _reactionCounts(context),
              bubble: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                padding: EdgeInsets.fromLTRB(
                  LocalLinkSpacing.md,
                  LocalLinkSpacing.sm,
                  LocalLinkSpacing.md,
                  LocalLinkSpacing.xs +
                      (reactions.isEmpty ? 0 : BubbleReactionEdge.bubblePad),
                ),
                decoration: BoxDecoration(
                  color: isMine
                      ? colors.surfaceContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: radius,
                ),
                child: BubbleContent(
                  body: message.body.isEmpty
                      ? null
                      : Text(message.body, style: TextStyle(color: foreground)),
                  media: [
                    for (final attachment in message.attachments)
                      AttachmentTile(
                        key: ValueKey<String>('att:${message.id}:${attachment.id}'),
                        attachment: attachment,
                        transfer: files,
                        messageId: message.id,
                        // Outgoing media that the outbox is still flushing gets the
                        // upload ring; once delivered the ring lifts.
                        uploading: _uploading,
                        // Bundle 182: friend Offline -> "Waiting", no ring.
                        waiting: _uploading && peerOffline,
                        // Bundle 174 (6): cancelled / failed own media.
                        failed: isMine && message.status.toLowerCase() == 'failed',
                        onRetry: _canResend ? onFailedTap : null,
                      ),
                  ],
                  footer: Row(
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// My message is still waiting in the outbox.
  bool get _uploading =>
      isMine &&
      (message.status == 'queued' ||
          message.status == 'sending' ||
          message.status == 'pending');

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

  String _time(DateTime raw) {
    // Bundle 174 (7): always the phone's own time. A message still being
    // sent / just received carried a UTC time (7:01 PM instead of 12:01 AM).
    final value = raw.toLocal();
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
