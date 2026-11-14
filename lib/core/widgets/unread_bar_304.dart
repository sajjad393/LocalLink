import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/l10n/l10n.dart';

/// 304 (H2, like WhatsApp): "N unread messages" above the first message that
/// was unread when the chat opened. A soft band across the whole chat width
/// with a small pill in the middle. Shown until you send or leave the chat.
class UnreadBar304 extends StatelessWidget {
  const UnreadBar304({super.key, required this.count, this.bleed = LocalLinkSpacing.md});

  /// How many messages were unread when the chat opened.
  final int count;

  /// The list's side padding: the band is painted over it so it reaches
  /// both screen edges.
  final double bleed;

  static String label(int count) =>
      count == 1 ? L.t.t1UnreadMessage : L.t.unreadMessages(count);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w600,
        );
    return Padding(
      key: const ValueKey('unread_bar_304'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -bleed,
            right: -bleed,
            top: 0,
            bottom: 0,
            child: ColoredBox(color: colors.primary.withValues(alpha: .10)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text(label(count), style: style),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 304 (H2): the chat opens at the bar when the unread part does not fit on
/// one screen; otherwise at the bottom as before.
/// Call after the first frame, with the list already at the bottom.
void showUnreadBar304(ScrollController controller, GlobalKey barKey, int index) {
  if (!controller.hasClients) return;
  bool visible() {
    final ctx = barKey.currentContext;
    final box = ctx?.findRenderObject();
    if (ctx == null || box is! RenderBox || !box.attached) return false;
    final viewport = Scrollable.maybeOf(ctx)?.context.findRenderObject();
    if (viewport is! RenderBox) return false;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    return top >= 0;
  }

  if (visible()) return; // everything unread fits: stay at the bottom
  final ctx = barKey.currentContext;
  if (ctx == null) {
    // Not built yet (far above): rough jump, then line it up.
    controller.jumpTo((index * 88.0).clamp(0.0, controller.position.maxScrollExtent));
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final c = barKey.currentContext;
    if (c != null && c.mounted) {
      Scrollable.ensureVisible(c, alignment: .05);
    }
  });
}
