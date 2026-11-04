import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/messaging/presentation/widgets/pending_attachment_strip.dart';
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

  /// Bundle 199: focus for the message box (reply opens the keyboard).
  final FocusNode? focusNode;

  const GroupComposer({
    super.key,
    required this.controller,
    required this.pending,
    required this.isSending,
    required this.onPick,
    required this.onRemove,
    required this.onSend,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(LocalLinkSpacing.sm, LocalLinkSpacing.xs, LocalLinkSpacing.sm, LocalLinkSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bundle 202 (mock F1): same review strip as the 1-to-1 chat.
          if (pending.isNotEmpty)
            PendingAttachmentStrip(
              attachments: pending,
              onRemove: onRemove,
              onAdd: isSending ? null : onPick,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LocalLinkIconButton(
                onPressed: isSending ? null : onPick,
                icon: const Icon(Icons.add),
                tooltip: 'Attach',
              ),
              const SizedBox(width: LocalLinkSpacing.xs),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(LocalLinkRadius.xl),
                  ),
                  child: LocalLinkTextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !isSending,
                    onSubmitted: (_) => onSend(),
                    textInputAction: TextInputAction.send,
                    maxLines: 5,
                    minLines: 1,
                    hintText: 'Message group',
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: LocalLinkSpacing.lg, vertical: LocalLinkSpacing.md),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: LocalLinkSpacing.sm),
              LocalLinkIconButton(
                onPressed: isSending ? null : onSend,
                filled: true,
                icon: isSending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                tooltip: 'Send message',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
