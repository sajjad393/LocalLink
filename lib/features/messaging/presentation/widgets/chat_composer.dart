import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recorder_controller.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recording_widgets.dart';

class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onPickAttachments;
  final VoidCallback onSend;

  /// Bundle 181 (approved mock `mocks/bundle181_full_mock.svg`): the voice
  /// recorder - hold the mic to record, slide left = cancel, slide up = lock.
  /// Null = no voice notes (mic hidden).
  final VoiceRecorderController? voice;

  /// True when files are staged in the composer — the Send button must then
  /// appear even with an empty text field (image-without-caption send).
  final bool hasAttachments;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.isSending,
    required this.onPickAttachments,
    required this.onSend,
    this.voice,
    this.hasAttachments = false,
  });

  @override
  Widget build(BuildContext context) {
    final voice = this.voice;
    if (voice == null) return _bar(context, null);
    return AnimatedBuilder(
      animation: voice,
      builder: (context, _) {
        switch (voice.state) {
          case VoiceRecState.locked:
            return VoiceLockedPanel(voice: voice);
          case VoiceRecState.paused:
            return VoicePausedPanel(voice: voice);
          case VoiceRecState.idle:
          case VoiceRecState.holding:
            return _bar(context, voice);
        }
      },
    );
  }

  Widget _bar(BuildContext context, VoiceRecorderController? voice) {
    final colors = Theme.of(context).colorScheme;
    final holding = voice?.state == VoiceRecState.holding;
    final barWidth = MediaQuery.sizeOf(context).width;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        LocalLinkSpacing.sm,
        LocalLinkSpacing.xs,
        LocalLinkSpacing.sm,
        LocalLinkSpacing.md,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Attach lives INSIDE the pill, like WhatsApp/Telegram.
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: .78),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: .45),
                    ),
                  ),
                  // Bundle 181 (mock screen 1): while holding, the pill shows
                  // the red dot, the timer and "< Slide to cancel".
                  child: holding
                      ? VoiceHoldingContent(voice: voice!)
                      : Row(
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
                              child: LocalLinkTextField(
                                controller: controller,
                                enabled: !isSending,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => onSend(),
                                hintText: 'Message',
                                maxLines: 5,
                                minLines: 1,
                                decoration: const InputDecoration(
                                  // Bundle 181: the "Message" hint (mock screen 4)
                                  // was lost because this decoration replaced it.
                                  hintText: 'Message',
                                  // Bundle 130: the global input theme fills every
                                  // field (filled:true) — inside this pill that
                                  // fill painted as a SQUARE slab whose two
                                  // corners peeked out past the pill's rounded
                                  // right end. Kill the fill here.
                                  filled: false,
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
                  final micMode = voice != null &&
                      (holding || (!hasText && !hasAttachments && !isSending));
                  final Widget child;
                  if (holding) {
                    // Bundle 181: the big gradient mic under the finger.
                    // Bundle 198: it follows the finger up to the lock.
                    child = Transform.translate(
                      offset: Offset(0, voice!.slideDy),
                      child: AnimatedScale(
                      key: const ValueKey('voice_big_mic'),
                      scale: 1.45,
                      // Grows to the left so it stays fully on screen (mock).
                      alignment: Alignment.centerRight,
                      duration: const Duration(milliseconds: 120),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LocalLinkBrand.linearGradient,
                        ),
                        child: const Icon(Icons.mic_rounded, color: Colors.white, size: 26),
                      ),
                    ),
                    );
                  } else if (voice != null && !hasText && !hasAttachments) {
                    child = Tooltip(
                      message: 'Hold to record voice note',
                      child: Container(
                        key: const ValueKey('voice_mic'),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.surfaceContainerHighest,
                        ),
                        child: Icon(Icons.mic_none_rounded, color: colors.onSurfaceVariant, size: 24),
                      ),
                    );
                  } else {
                    child = _RoundAction(
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
                  }
                  // One fixed touch area for every state, so a hold is never
                  // lost when the bar changes under the finger.
                  return _VoiceMicSlot(
                    voice: voice,
                    micMode: micMode,
                    barWidth: barWidth,
                    // Holding: the pill gets shorter so the big mic has room.
                    child: Padding(
                      padding: EdgeInsets.only(left: holding ? 28 : 0),
                      child: child,
                    ),
                  );
                },
              ),
            ],
          ),
          if (holding)
            // Bundle 198: the lock box rises a little as the finger goes up.
            Positioned(
              right: 6,
              bottom: 74 + 16 * voice!.lockProgress,
              child: VoiceLockBox(progress: voice.lockProgress),
            ),
          if (voice != null && voice.hintVisible && !holding)
            const Positioned(right: 0, bottom: 58, child: VoiceHintBubble()),
        ],
      ),
    );
  }
}

/// Bundle 181: raw finger tracking on the mic (hold, slide, lock, let go).
class _VoiceMicSlot extends StatefulWidget {
  const _VoiceMicSlot({
    required this.voice,
    required this.micMode,
    required this.barWidth,
    required this.child,
  });

  final VoiceRecorderController? voice;
  final bool micMode;
  final double barWidth;
  final Widget child;

  @override
  State<_VoiceMicSlot> createState() => _VoiceMicSlotState();
}

class _VoiceMicSlotState extends State<_VoiceMicSlot> {
  Offset? _down;
  int? _pointer;

  @override
  Widget build(BuildContext context) {
    final voice = widget.voice;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (voice == null || !widget.micMode || _pointer != null) return;
        _pointer = e.pointer;
        _down = e.position;
        voice.pressDown();
      },
      onPointerMove: (e) {
        final down = _down;
        if (voice == null || e.pointer != _pointer || down == null) return;
        voice.pressMove(e.position - down, widget.barWidth);
      },
      onPointerUp: (e) {
        if (voice == null || e.pointer != _pointer) return;
        _pointer = null;
        _down = null;
        voice.pressUp();
      },
      onPointerCancel: (e) {
        if (voice == null || e.pointer != _pointer) return;
        _pointer = null;
        _down = null;
        voice.pressCancel();
      },
      child: widget.child,
    );
  }
}

class _RoundAction extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  final Widget icon;
  final Gradient? gradient;

  const _RoundAction({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
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
