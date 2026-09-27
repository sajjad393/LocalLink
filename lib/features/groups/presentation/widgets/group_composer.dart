import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';

class GroupComposer extends StatelessWidget {
  final TextEditingController controller;
  final List<PickedFile> pending;
  final bool isSending;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;
  final VoidCallback onSend;

  const GroupComposer({
    super.key,
    required this.controller,
    required this.pending,
    required this.isSending,
    required this.onPick,
    required this.onRemove,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending.isNotEmpty)
            SizedBox(
              height: 54,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.sm),
                itemCount: pending.length,
                separatorBuilder: (_, __) => const SizedBox(width: LocalLinkSpacing.xs),
                itemBuilder: (_, index) => Chip(
                  avatar: const Icon(Icons.attach_file, size: 16),
                  label: SizedBox(
                    width: 140,
                    child: Text(pending[index].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  onDeleted: () => onRemove(index),
                ),
              ),
            ),
          Row(
            children: [
              LocalLinkIconButton(
                onPressed: isSending ? null : onPick,
                icon: const Icon(Icons.attach_file),
                tooltip: 'Attach file',
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: LocalLinkTextField(
                    controller: controller,
                    enabled: !isSending,
                    onSubmitted: (_) => onSend(),
                    textInputAction: TextInputAction.send,
                    hintText: 'Message group',
                  ),
                ),
              ),
              LocalLinkIconButton(
                onPressed: isSending ? null : onSend,
                filled: true,
                icon: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                tooltip: 'Send message',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
