import 'package:flutter/material.dart';

import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';

import 'package:locallink/features/groups/data/group_invite_link.dart'
    show GroupInviteLink;
import 'package:locallink/features/groups/presentation/screens/group_link_screens.dart'
    show GroupInviteCard;

import 'bubble_layout.dart';
import 'bubble_media.dart';
import 'message_options.dart';
import 'pinch_text_zoom.dart';

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

  /// Bundle 197a: held / picked bubble = grey + ring (bubble only).
  final bool highlighted;

  /// Bundle 197a: key on the bubble itself (the dimmer leaves a hole there).
  final Key? bubbleKey;

  /// Bundle 197a: Select mode - a tap picks / unpicks.
  final VoidCallback? onTap;

  /// Bundle 197a: quote of a reply (name shown in the box).
  final String quoteName;
  final bool quoteIsYou;
  final bool quoteMissing;
  final VoidCallback? onQuoteTap;

  /// Bundle 197b: the friend's name ("Ask Sajjad to send it again.").
  final String senderName;

  /// Bundle 199: blue border for 2 s after a reply box jumped here.
  final bool flashed;

  /// Bundle 199: small picture of the quoted photo / video (null = none).
  final Widget? quoteThumb;

  /// Bundle 202: quote words from this phone's copy ("📷 5 photos").
  /// Null = the words carried by the reply.
  final String? quoteLine;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.files,
    this.onLongPress,
    this.reactions = const [],
    this.onFailedTap,
    this.peerOffline = false,
    this.highlighted = false,
    this.bubbleKey,
    this.onTap,
    this.quoteName = '',
    this.quoteIsYou = false,
    this.quoteMissing = false,
    this.onQuoteTap,
    this.senderName = '',
    this.flashed = false,
    this.quoteThumb,
    this.quoteLine,
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
    // Bundle 202: photos / videos -> grid, 3 px edge, caption under them.
    final media = BubbleMedia.of(message.attachments,
        hasCaption: message.text.isNotEmpty);
    final tight = media.tight;
    final header = _header(tight);
    final body = message.text.isEmpty
        ? null
        : ChatBodyText(message.text, color: foreground);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        label: message.text.isEmpty ? 'Message with attachment' : message.text,
        button: onLongPress != null || _canResend,
        hint: _canResend
            ? 'Message not sent. Tap to resend or delete'
            : (onLongPress != null ? 'Long press for message actions' : null),
        child: GestureDetector(
          onTap: onTap ?? (_canResend ? onFailedTap : null),
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
            // Bundle 182: emoji chips on the bottom edge, bubble fits content.
            child: BubbleReactionEdge(
              chips: reactions.isEmpty ? const <Widget>[] : _reactionCounts(context),
              bubble: FlashRing(
                on: flashed,
                radius: radius,
                child: Container(
                key: bubbleKey,
                constraints: BoxConstraints(maxWidth: maxWidth),
                padding: BubbleMedia.padding(
                  tight: tight,
                  extraBottom:
                      reactions.isEmpty ? 0 : BubbleReactionEdge.bubblePad,
                ),
                decoration: highlightBubble(
                  BoxDecoration(
                    color: isMine
                        ? colors.surfaceContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: radius,
                  ),
                  colors,
                  on: highlighted,
                ),
                child: BubbleContent(
                  header: header,
                  body: body == null
                      ? null
                      : (tight ? BubbleMedia.caption(body) : body),
                  bodyAfterMedia: tight,
                  footerGap: media.timeOnMedia ? 0 : 3,
                  media: [
                    // Bundle G6 (mock L3): a group invite link -> card.
                    if (GroupInviteLink.tokenIn(message.text) case final t?)
                      GroupInviteCard(
                          key: ValueKey<String>('inv:${message.id}'), token: t),
                    ...media.build(
                    context,
                    isMine: isMine,
                    hasHeader: header != null,
                    bubbleMaxWidth: maxWidth,
                    viewerTitle: isMine ? 'You' : senderName,
                    viewerSubtitle: _time(message.createdAt),
                    timeOverlay: () => _footer(theme, foreground, onMedia: true),
                    tile: (attachment, {cell, onOpen}) =>
                      AttachmentTile(
                        key: ValueKey<String>('att:${message.id}:${attachment.id}'),
                        cell: cell,
                        onOpen: onOpen,
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
                        mine: isMine,
                        senderName: senderName,
                        // Bundle 198: small mic on my own voice notes.
                        playedMark: _playedMark,
                      ),
                  ),
                  ],
                  footer: media.timeOnMedia
                      ? const SizedBox.shrink()
                      : (tight
                          ? BubbleMedia.footer(_footer(theme, foreground))
                          : _footer(theme, foreground)),
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Bundle 198: my own voice note - grey mic once delivered, blue once
  /// the friend played it (also when Read receipts is OFF). Null = no mic.
  bool? get _playedMark {
    if (!isMine) return null;
    return switch (message.status.toLowerCase()) {
      'played' => true,
      'delivered' || 'direct_delivered' || 'read' => false,
      _ => null,
    };
  }

  /// Time + ticks. [onMedia] = white, drawn on the picture (Bundle 202).
  Widget _footer(ThemeData theme, Color foreground, {bool onMedia = false}) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _time(message.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: onMedia ? Colors.white : foreground.withValues(alpha: .62),
            ),
          ),
          if (isMine) ...[
            const SizedBox(width: LocalLinkSpacing.xs),
            _StatusIcon(
                status: message.status,
                channel: message.channel,
                onMedia: onMedia),
          ],
        ],
      );

  /// Bundle 197a: "Forwarded" label and / or the quote box.
  Widget? _header(bool tight) {
    final reply = message.replyTo;
    final forwarded = message.forwarded;
    if (reply == null && !forwarded) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (forwarded)
          tight
              ? BubbleMedia.headerLine(const ForwardedLabel())
              : const ForwardedLabel(),
        if (reply != null)
          QuoteBox(
            name: quoteName,
            line: quoteLine ?? replyLine(reply),
            isYou: quoteIsYou,
            notAvailable: quoteMissing,
            onTap: onQuoteTap,
            thumb: quoteThumb,
          ),
      ],
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

  /// Bundle 202: on a picture - white ticks, light blue when read.
  final bool onMedia;

  const _StatusIcon({required this.status, this.channel, this.onMedia = false});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    // Bundle 198: blue ticks follow the Read receipts switch.
    if (s == 'read' || s == 'played') {
      return ListenableBuilder(
        listenable: ReadReceiptsSetting.instance,
        builder: (context, _) => _build(context, s),
      );
    }
    return _build(context, s);
  }

  Widget _build(BuildContext context, String s) {
    final theme = Theme.of(context).colorScheme;
    final colors = onMedia
        ? theme.copyWith(
            onSurfaceVariant: Colors.white,
            primary: const Color(0xFF8FD3FF),
            error: const Color(0xFFFFB4AB))
        : theme;
    final receiptsOn = ReadReceiptsSetting.instance.on;
    final glyph = switch (s) {
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
      'read' || 'played' => Icon(
          // double check, blue = read (Bundle 198: grey when receipts OFF)
          Icons.done_all_rounded,
          key: ValueKey(receiptsOn ? 'tick_read' : 'tick_read_off'),
          size: 15,
          color: receiptsOn ? colors.primary : colors.onSurfaceVariant,
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
