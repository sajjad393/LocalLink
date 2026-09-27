import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final FileTransferRepositoryContract files;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.files,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: isMine
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
              ),
            ),
            if (isMine)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _statusText(message.status),
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _statusText(String status) {
    switch (status) {
      case 'delivered':
        return '✓✓';
      case 'sent':
        return '✓';
      default:
        return '…';
    }
  }
}
