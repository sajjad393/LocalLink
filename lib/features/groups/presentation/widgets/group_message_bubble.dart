import 'package:flutter/material.dart';

import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';
import 'package:locallink/features/messaging/presentation/widgets/bubble_layout.dart';
import 'package:locallink/features/messaging/presentation/widgets/bubble_media.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';
import 'package:locallink/features/messaging/presentation/widgets/pinch_text_zoom.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/features/groups/data/group_receipts.dart';
import 'package:locallink/features/groups/data/group_invite_link.dart'
    show GroupInviteLink;
import 'package:locallink/features/groups/presentation/screens/group_link_screens.dart'
    show GroupInviteCard;

/// Bundle G1 (mock 13): the group bubble looks like the 1:1 bubble.
///
/// * Both sides neutral (no blue gradient any more), same corners.
/// * Others: the FIRST bubble of a run shows a small photo (28) on the left
///   and the coloured sender name (+ "Admin" / "Owner") on top. The next
///   bubbles of the same person keep the photo space empty.
/// * Mine: time + tick. Clock = not on the server yet, ✓ = on the server.
///   Bundle G5: grey ✓✓ = every member got it, blue ✓✓ = all read it.
class GroupMessageBubble extends StatelessWidget {
  final GroupMessage message;
  final bool isMine;
  final FileTransferRepositoryContract files;
  final String senderName;
  final List<MessageReaction> reactions;

  /// Bundle 197a: held / picked bubble.
  final bool highlighted;
  final Key? bubbleKey;
  final String quoteName;
  final bool quoteIsYou;
  final bool quoteMissing;
  final VoidCallback? onQuoteTap;

  /// Bundle 199: blue border for 2 s after a reply box jumped here.
  final bool flashed;

  /// Bundle 199: small picture of the quoted photo / video (null = none).
  final Widget? quoteThumb;

  /// G1: first bubble of this person's run (photo + name).
  final bool firstOfRun;

  /// G1: "Admin" / "Owner" next to the name ('' = none).
  final String role;

  /// G1: leave room for the photo column (false in tests / previews).
  final bool avatarColumn;

  /// G1 (mock 24): search words to mark yellow.
  final String highlight;

  /// G1 (mock 21): tap the emoji chip = who reacted.
  final VoidCallback? onReactionsTap;

  /// Bundle G5: ✓ / grey ✓✓ (all got it) / blue ✓✓ (all read). Null = ✓.
  final GroupTick? tick;

  /// Bundle G5b: drawn instead of the text (a poll).
  final Widget? content;

  /// Bundle 202: quote words from this phone's copy ("📷 5 photos").
  final String? quoteLine;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.files,
    required this.senderName,
    this.reactions = const [],
    this.highlighted = false,
    this.bubbleKey,
    this.quoteName = '',
    this.quoteIsYou = false,
    this.quoteMissing = false,
    this.onQuoteTap,
    this.flashed = false,
    this.quoteThumb,
    this.firstOfRun = true,
    this.role = '',
    this.avatarColumn = true,
    this.highlight = '',
    this.onReactionsTap,
    this.tick,
    this.content,
    this.quoteLine,
  });

  /// Photo column width: 28 photo + 6 gap (mock .grow2).
  static const double avatarSlot = 34;

  static Color nameColor(String name) => LocalLinkAvatarColor.forName(name);

  /// My message is not on the server yet.
  bool get _pending => isMine && message.notSentYet; // Bundle G3

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final slot = !isMine && avatarColumn ? avatarSlot : 0.0;
    final maxWidth =
        ((MediaQuery.sizeOf(context).width - slot) * .82).clamp(160.0, 620.0);
    final foreground = colors.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(LocalLinkRadius.chat),
      topRight: const Radius.circular(LocalLinkRadius.chat),
      bottomLeft: Radius.circular(isMine ? LocalLinkRadius.chat : 6),
      bottomRight: Radius.circular(isMine ? 6 : LocalLinkRadius.chat),
    );
    // Bundle 202: photos / videos -> grid, 3 px edge, caption under them.
    final hasText = content == null && message.text.isNotEmpty;
    final media = BubbleMedia.of(message.attachments, hasCaption: hasText);
    final tight = media.tight;
    final header = _header(context, colors, tight);
    final Widget? body = !hasText
        ? null
        : ChatBodyText(message.text,
            color: foreground, highlight: highlight, mentions: true);
    final bubble = Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
      // Bundle 182: bubble fits its content, emoji chips on the bottom edge.
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
                    reactions.isEmpty ? 0 : BubbleReactionEdge.bubblePad),
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
              headerGap: 3,
              header: header,
              // Bundle G5b: a poll sits in the media slot (time under it).
              body: body == null
                  ? null
                  : (tight ? BubbleMedia.caption(body) : body),
              bodyAfterMedia: tight,
              footerGap: media.timeOnMedia ? 0 : 3,
              media: [
                if (content != null) content!,
                // Bundle G6 (mock L3): a group invite link -> card.
                if (content == null)
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
                  timeOverlay: () =>
                      _footer(theme, colors, foreground, onMedia: true),
                  tile: (attachment, {cell, onOpen}) => AttachmentTile(
                    key: ValueKey<String>('att:${message.id}:${attachment.id}'),
                    cell: cell,
                    onOpen: onOpen,
                    attachment: attachment,
                    transfer: files,
                    messageId: message.id,
                    groupMessageId: message.id,
                    // My photo / voice note still going up: upload ring.
                    uploading: _pending,
                    mine: isMine,
                    senderName: senderName,
                  ),
                ),
              ],
              footer: media.timeOnMedia
                  ? const SizedBox.shrink()
                  : (tight
                      ? BubbleMedia.footer(_footer(theme, colors, foreground))
                      : _footer(theme, colors, foreground)),
            ),
          ),
        ),
      ),
    );
    if (isMine) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    if (!avatarColumn) {
      return Align(alignment: Alignment.centerLeft, child: bubble);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: avatarSlot,
          child: firstOfRun
              ? Align(
                  alignment: Alignment.topLeft,
                  child: AccountAvatar(
                      key: const ValueKey('group_sender_photo'),
                      name: senderName,
                      radius: 14),
                )
              : null,
        ),
        Flexible(
          child: Align(alignment: Alignment.centerLeft, child: bubble),
        ),
      ],
    );
  }

  /// Time + ticks. [onMedia] = white on the picture (Bundle 202): white
  /// ticks, light blue when all read.
  Widget _footer(ThemeData theme, ColorScheme colors, Color foreground,
      {bool onMedia = false}) {
    final grey = onMedia ? Colors.white : colors.onSurfaceVariant;
    final blue = onMedia ? const Color(0xFF8FD3FF) : colors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_time(message.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
                color: onMedia
                    ? Colors.white
                    : foreground.withValues(alpha: .62))),
        if (isMine) ...[
          const SizedBox(width: LocalLinkSpacing.xs),
          _pending
              ? Icon(Icons.schedule_rounded,
                  key: const ValueKey('group_tick_pending'),
                  size: 14,
                  color: grey)
              : switch (tick) {
                  GroupTick.read => Icon(Icons.done_all_rounded,
                      key: const ValueKey('group_tick_read'),
                      size: 15,
                      color: blue),
                  GroupTick.delivered => Icon(Icons.done_all_rounded,
                      key: const ValueKey('group_tick_delivered'),
                      size: 15,
                      color: grey),
                  _ => Icon(Icons.check_rounded,
                      key: const ValueKey('group_tick_sent'),
                      size: 15,
                      color: grey),
                },
        ],
      ],
    );
  }

  /// Coloured sender name (others, first of a run), "Forwarded", quote.
  Widget? _header(BuildContext context, ColorScheme colors, bool tight) {
    Widget line(Widget w) => tight ? BubbleMedia.headerLine(w) : w;
    final Widget? name = isMine || !firstOfRun
        ? null
        : line(Row(
            key: const ValueKey('group_sender_name'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: nameColor(senderName))),
              ),
              if (role.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(role,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant)),
              ],
            ],
          ));
    final reply = message.replyTo;
    final forwarded = message.forwarded;
    if (reply == null && !forwarded) return name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name != null) name,
        if (forwarded) line(const ForwardedLabel()),
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

  List<Widget> _reactionCounts(BuildContext context) {
    final counts = <String, int>{};
    for (final r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    final scheme = Theme.of(context).colorScheme;
    return counts.entries.map((e) {
      final chip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.outlineVariant)),
          child: Text('${e.key} ${e.value}',
              style: Theme.of(context).textTheme.labelSmall));
      if (onReactionsTap == null) return chip;
      return GestureDetector(
        key: ValueKey('group_reaction_chip_${e.key}'),
        behavior: HitTestBehavior.opaque,
        onTap: onReactionsTap,
        child: chip,
      );
    }).toList(growable: false);
  }

  String _time(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return '';
    final hour = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${parsed.hour >= 12 ? 'PM' : 'AM'}';
  }
}
