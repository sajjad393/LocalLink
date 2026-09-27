import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';

class GroupMessageBubble extends StatelessWidget {
  final GroupMessage message;
  final bool isMine;
  final FileTransferRepositoryContract files;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.files,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: isMine ? colors.primaryContainer : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    message.senderId,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            if (message.body.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(message.body),
              ),
            ...message.attachments.map(
              (attachment) => AttachmentTile(
                attachment: attachment,
                transfer: files,
                messageId: message.id,
                groupMessageId: message.id,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
