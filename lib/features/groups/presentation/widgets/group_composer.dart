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
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(LocalLinkSpacing.sm, LocalLinkSpacing.xs, LocalLinkSpacing.sm, LocalLinkSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending.isNotEmpty)
            SizedBox(
              height: 50,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.sm),
                scrollDirection: Axis.horizontal,
                itemCount: pending.length,
                separatorBuilder: (_, __) => const SizedBox(width: LocalLinkSpacing.xs),
                itemBuilder: (_, index) => Chip(
                  backgroundColor: colors.surfaceContainerHighest,
                  avatar: const Icon(Icons.attach_file, size: 16),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(pending[index].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  onDeleted: () => onRemove(index),
                ),
              ),
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
                    color: colors.surfaceContainerHighest.withOpacity(.62),
                    borderRadius: BorderRadius.circular(LocalLinkRadius.xl),
                  ),
                  child: LocalLinkTextField(
                    controller: controller,
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
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
