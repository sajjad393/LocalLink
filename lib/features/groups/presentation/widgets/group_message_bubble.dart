import 'package:flutter/material.dart';

import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';
import 'package:locallink/features/messaging/presentation/widgets/bubble_layout.dart';
import 'package:locallink/features/messaging/presentation/widgets/bubble_media.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';
import 'package:locallink/features/messaging/presentation/widgets/pinch_text_zoom.dart';
import 'package:locallink/core/models/message_envelope.dart';

class GroupMessageBubble extends StatelessWidget {
  final GroupMessage message;
  final bool isMine;
  final FileTransferRepositoryContract files;
  final String senderName;
  final List<MessageReaction> reactions;

  /// Bundle 197a: held / picked bubble (own blue bubble: ring only).
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
    this.quoteLine,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.sizeOf(context).width * .82;
    // Outgoing = brand blue→cyan gradient pill with white text (matches the
    // direct-message bubble); incoming = neutral surface.
    final foreground = isMine ? Colors.white : colors.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(LocalLinkRadius.chat),
      topRight: const Radius.circular(LocalLinkRadius.chat),
      bottomLeft: Radius.circular(isMine ? LocalLinkRadius.chat : 6),
      bottomRight: Radius.circular(isMine ? 6 : LocalLinkRadius.chat),
    );
    // Bundle 202: photos / videos -> grid, 3 px edge, caption under them.
    final media =
        BubbleMedia.of(message.attachments, hasCaption: message.text.isNotEmpty);
    final tight = media.tight;
    final header = _header(context, colors, foreground, tight);
    final bubbleMax = maxWidth.clamp(220.0, 620.0);
    final body =
        message.text.isEmpty ? null : ChatBodyText(message.text, color: foreground);
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      // Bundle 182: bubble fits its content, emoji chips on the bottom edge.
      child: Padding(
        padding: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
        child: BubbleReactionEdge(
          chips: reactions.isEmpty ? const <Widget>[] : _reactionCounts(context),
          bubble: FlashRing(
            on: flashed,
            radius: radius,
            onBlue: isMine,
            child: Container(
            key: bubbleKey,
            constraints: BoxConstraints(maxWidth: bubbleMax),
            padding: BubbleMedia.padding(
                tight: tight,
                extraBottom:
                    reactions.isEmpty ? 0 : BubbleReactionEdge.bubblePad),
            decoration: highlightBubble(
              BoxDecoration(
                gradient: isMine ? LocalLinkBrand.linearGradient : null,
                color: isMine ? null : colors.surfaceContainerHighest,
                borderRadius: radius,
              ),
              colors,
              on: highlighted,
              gradient: isMine,
            ),
            child: BubbleContent(
              headerGap: 3,
              header: header,
              body: body == null
                  ? null
                  : (tight ? BubbleMedia.caption(body) : body),
              bodyAfterMedia: tight,
              footerGap: media.timeOnMedia ? 0 : 3,
              media: media.build(
                context,
                isMine: isMine,
                hasHeader: header != null,
                bubbleMaxWidth: bubbleMax,
                viewerTitle: isMine ? 'You' : senderName,
                viewerSubtitle: _time(message.createdAt),
                timeOverlay: () => _timeText(context, foreground, onMedia: true),
                tile: (attachment, {cell, onOpen}) =>
                  AttachmentTile(
                    key: ValueKey<String>('att:${message.id}:${attachment.id}'),
                    cell: cell,
                    onOpen: onOpen,
                    attachment: attachment,
                    transfer: files,
                    messageId: message.id,
                    groupMessageId: message.id,
                    mine: isMine,
                    senderName: senderName,
                  ),
              ),
              footer: media.timeOnMedia
                  ? const SizedBox.shrink()
                  : (tight
                      ? BubbleMedia.footer(_timeText(context, foreground))
                      : _timeText(context, foreground)),
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _timeText(BuildContext context, Color foreground,
          {bool onMedia = false}) =>
      Text(_time(message.createdAt),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color:
                  onMedia ? Colors.white : foreground.withValues(alpha: .62)));

  /// Sender name (others), Bundle 197a "Forwarded" label + quote box.
  Widget? _header(BuildContext context, ColorScheme colors, Color foreground,
      bool tight) {
    Widget line(Widget w) => tight ? BubbleMedia.headerLine(w) : w;
    final name = isMine
        ? null
        : line(Text(senderName,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: colors.primary)));
    final reply = message.replyTo;
    final forwarded = message.forwarded;
    if (reply == null && !forwarded) return name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name != null) name,
        if (forwarded)
          line(ForwardedLabel(color: isMine ? Colors.white70 : null)),
        if (reply != null)
          QuoteBox(
            name: quoteName,
            line: quoteLine ?? replyLine(reply),
            isYou: quoteIsYou,
            notAvailable: quoteMissing,
            onTap: onQuoteTap,
            onBlue: isMine,
            thumb: quoteThumb,
          ),
      ],
    );
  }

  List<Widget> _reactionCounts(BuildContext context) {
    final counts=<String,int>{}; for(final r in reactions){counts[r.emoji]=(counts[r.emoji]??0)+1;}
    return counts.entries.map((e)=>Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surface,borderRadius:BorderRadius.circular(999),border:Border.all(color:Theme.of(context).colorScheme.outlineVariant)),child:Text('${e.key} ${e.value}',style:Theme.of(context).textTheme.labelSmall))).toList(growable:false);
  }

  String _time(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return '';
    final hour = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${parsed.hour >= 12 ? 'PM' : 'AM'}';
  }
}
