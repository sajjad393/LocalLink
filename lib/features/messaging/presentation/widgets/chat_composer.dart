import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';

class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onPickAttachments;
  final VoidCallback onSend;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.isSending,
    required this.onPickAttachments,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.sm, LocalLinkSpacing.xs, LocalLinkSpacing.sm, LocalLinkSpacing.sm),
        child: Row(
          children: [
            LocalLinkIconButton(
              onPressed: isSending ? null : onPickAttachments,
              icon: const Icon(Icons.attach_file),
              tooltip: 'Attach file',
            ),
            const SizedBox(width: LocalLinkSpacing.xs),
            Expanded(
              child: LocalLinkTextField(
                controller: controller,
                enabled: !isSending,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                hintText: 'Message',
              ),
            ),
            const SizedBox(width: LocalLinkSpacing.sm),
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
      ),
    );
  }
}
