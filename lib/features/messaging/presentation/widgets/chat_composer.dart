import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';

class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onPickAttachments;
  final VoidCallback onSend;
  final VoidCallback? onVoiceNote;
  final bool isRecording;

  /// Live mic level 0..32767 while [isRecording]; powers the in-composer
  /// WhatsApp-style wave so recording never looks frozen.
  final int recordingAmplitude;

  /// True when files are staged in the composer — the Send button must then
  /// appear even with an empty text field (image-without-caption send).
  final bool hasAttachments;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.isSending,
    required this.onPickAttachments,
    required this.onSend,
    this.onVoiceNote,
    this.hasAttachments = false,
    this.isRecording = false,
    this.recordingAmplitude = 0,
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
        LocalLinkSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attach lives INSIDE the pill, like WhatsApp/Telegram.
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withOpacity(.78),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: colors.outlineVariant.withOpacity(.45),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: isSending ? null : onPickAttachments,
                    tooltip: 'Attach',
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      color: colors.onSurfaceVariant,
                      size: 26,
                    ),
                  ),
                  Expanded(
                    child: isRecording
                        ? _RecordingWaveBars(amplitude: recordingAmplitude)
                        : LocalLinkTextField(
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
                              contentPadding: EdgeInsets.only(
                                top: LocalLinkSpacing.md,
                                bottom: LocalLinkSpacing.md,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: LocalLinkSpacing.xs),
                ],
              ),
            ),
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          // Right-hand action: gradient send orb when there's content, a
          // plain mic circle otherwise.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              if (!hasText && !hasAttachments && onVoiceNote != null) {
                return _RoundAction(
                  onPressed: isSending ? null : onVoiceNote,
                  tooltip: isRecording ? 'Stop voice note' : 'Record voice note',
                  background: isRecording
                      ? colors.errorContainer
                      : colors.surfaceContainerHighest,
                  icon: Icon(
                    isRecording
                        ? Icons.stop_rounded
                        : Icons.mic_none_rounded,
                    color: isRecording
                        ? colors.onErrorContainer
                        : colors.onSurfaceVariant,
                    size: 24,
                  ),
                );
              }
              return _RoundAction(
                onPressed: isSending ? null : onSend,
                tooltip: 'Send message',
                gradient: LocalLinkBrand.linearGradient,
                icon: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 22),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  final Widget icon;
  final Color? background;
  final Gradient? gradient;

  const _RoundAction({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
    this.background,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: gradient == null ? background : null,
            gradient: gradient,
          ),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact recording visual: fixed bar count (WhatsApp-like); heights follow
/// the real mic amplitude with per-bar lag so motion reads smoothly at the
/// 8 fps poll cadence.
class _RecordingWaveBars extends StatelessWidget {
  final int amplitude;
  const _RecordingWaveBars({required this.amplitude});

  static const _bars = 16;
  static const _shapes = [0.62, 1.0, 0.72, 0.9, 0.5, 0.8, 1.0, 0.66];

  @override
  Widget build(BuildContext context) {
    final level = (amplitude / 32767.0).clamp(0.0, 1.0);
    final children = <Widget>[
      Icon(Icons.mic_rounded, size: 18, color: Theme.of(context).colorScheme.error),
      const SizedBox(width: 8),
    ];
    for (var i = 0; i < _bars; i++) {
      final h = 4.0 + 16.0 * (level * _shapes[i % _shapes.length]).clamp(0.05, 1.0);
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          width: 3,
          height: h,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error.withOpacity(.85),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ));
    }
    children.add(const SizedBox(width: 8));
    children.add(Text(
      'Recording…',
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ));
    return SizedBox(
      height: 52,
      child: Row(children: children),
    );
  }
}
