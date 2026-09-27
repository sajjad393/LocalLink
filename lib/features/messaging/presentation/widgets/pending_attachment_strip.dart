import 'package:flutter/material.dart';
import 'package:locallink/core/models/attachment.dart';

class PendingAttachmentStrip extends StatelessWidget {
  final List<PickedFile> attachments;
  final ValueChanged<int> onRemove;

  const PendingAttachmentStrip({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: attachments.length,
        itemBuilder: (_, index) {
          final file = attachments[index];
          return Chip(
            avatar: const Icon(Icons.attach_file, size: 16),
            label: SizedBox(
              width: 140,
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            onDeleted: () => onRemove(index),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 4),
      ),
    );
  }
}
