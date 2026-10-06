import 'package:flutter/material.dart';

import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';

class GroupMessageBubble extends StatelessWidget {
  final GroupMessage message;
  final bool isMine;
  final FileTransferRepositoryContract files;
  final String senderName;
  final List<MessageReaction> reactions;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.files,
    required this.senderName,
    this.reactions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.sizeOf(context).width * .82;
    final bubbleColor = isMine ? colors.primaryContainer : colors.surfaceContainerHighest;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth.clamp(220.0, 620.0)),
        margin: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
        padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.md, LocalLinkSpacing.sm, LocalLinkSpacing.md, LocalLinkSpacing.xs),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(LocalLinkRadius.chat),
            topRight: const Radius.circular(LocalLinkRadius.chat),
            bottomLeft: Radius.circular(isMine ? LocalLinkRadius.chat : 6),
            bottomRight: Radius.circular(isMine ? 6 : LocalLinkRadius.chat),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(senderName, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.primary)),
                ),
              ),
            if (message.body.isNotEmpty)
              Align(alignment: Alignment.centerLeft, child: Text(message.body)),
            ...message.attachments.map((attachment) => AttachmentTile(
                  attachment: attachment,
                  transfer: files,
                  messageId: message.id,
                  groupMessageId: message.id,
                )),
            if (reactions.isNotEmpty)
              Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 4, children: _reactionCounts(context))),
            const SizedBox(height: 3),
            Text(_time(message.createdAt), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ),
      ),
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
