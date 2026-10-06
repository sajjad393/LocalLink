import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';

class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onPickAttachments;
  final VoidCallback onSend;
  final VoidCallback? onVoiceNote;
  final bool isRecording;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.isSending,
    required this.onPickAttachments,
    required this.onSend,
    this.onVoiceNote,
    this.isRecording = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        LocalLinkSpacing.sm,
        LocalLinkSpacing.xs,
        LocalLinkSpacing.sm,
        LocalLinkSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          LocalLinkIconButton(
            onPressed: isSending ? null : onPickAttachments,
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
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                hintText: 'Message',
                maxLines: 5,
                minLines: 1,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: LocalLinkSpacing.lg,
                    vertical: LocalLinkSpacing.md,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              if (!hasText && onVoiceNote != null) {
                return LocalLinkIconButton(
                  onPressed: isSending ? null : onVoiceNote,
                  filled: isRecording,
                  icon: Icon(isRecording ? Icons.stop_rounded : Icons.mic_none_rounded),
                  tooltip: isRecording ? 'Stop voice note' : 'Record voice note',
                );
              }
              return LocalLinkIconButton(
                onPressed: isSending ? null : onSend,
                filled: true,
                icon: isSending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                tooltip: 'Send message',
              );
            },
          ),
        ],
      ),
    );
  }
}
