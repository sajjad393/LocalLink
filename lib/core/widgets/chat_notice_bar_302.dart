import 'package:flutter/material.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/peer_mark_302.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';

/// Bundle 302 (B, mock labels_footer_302.html): the bar that replaces the
/// message box when I can't send. A floating rounded card (no top line):
/// round tinted icon, bold title, one short line, optional pill button.
/// The same card for every case, in chats and group chats.
enum NoticeTone302 { red, amber, grey }

/// One footer case: tone, icon, title, line.
class ChatNotice302 {
  const ChatNotice302({
    required this.tone,
    required this.icon,
    required this.title,
    this.line = '',
  });

  final NoticeTone302 tone;
  final IconData icon;
  final String title;
  final String line;

  /// My account is blocked by admin.
  static const ChatNotice302 selfAdmin = ChatNotice302(
    tone: NoticeTone302.red,
    icon: Icons.shield_rounded,
    title: 'Blocked by admin',
    line: "You can read chats but can't send.",
  );

  /// My app version is stopped by admin.
  static const ChatNotice302 selfOld = ChatNotice302(
    tone: NoticeTone302.red,
    icon: Icons.system_update_rounded,
    title: 'Your LinkUp is old',
    line: 'Stopped by admin. Update to send and call.',
  );

  /// The other person is blocked by admin.
  static ChatNotice302 peerAdmin(String name) => ChatNotice302(
        tone: NoticeTone302.red,
        icon: Icons.shield_rounded,
        title: '$name is blocked by admin',
        line: "You can't message or call $name.",
      );

  /// The other person's app version is stopped by admin (not a block).
  static ChatNotice302 peerOld(String name) => ChatNotice302(
        tone: NoticeTone302.amber,
        icon: Icons.system_update_rounded,
        title: '$name has an old LinkUp',
        line: 'You can message and call after they update.',
      );
}

/// The footer for a chat with [name] (same order as [adminBlockBarText]),
/// or null when no admin rule applies.
ChatNotice302? chatNotice302(String name,
    {String peerId = '', String peerUserId = ''}) {
  final book = AdminBlockBook.instance;
  if (book.selfBlocked) return ChatNotice302.selfAdmin;
  if (VersionGuard.instance.stopped) return ChatNotice302.selfOld;
  if (book.isBlocked(peerId) || book.isBlocked(peerUserId)) {
    return ChatNotice302.peerAdmin(name);
  }
  if (VersionGuard.instance.isPeerDropped(peerId)) {
    return ChatNotice302.peerOld(name);
  }
  return null;
}

/// The card itself. [action]: a pill button (Unblock / Update) or null.
class ChatNoticeBar302 extends StatelessWidget {
  const ChatNoticeBar302({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    this.line = '',
    this.action,
  });

  ChatNoticeBar302.of(ChatNotice302 notice, {Key? key, Widget? action})
      : this(
          key: key,
          tone: notice.tone,
          icon: notice.icon,
          title: notice.title,
          line: notice.line,
          action: action,
        );

  final NoticeTone302 tone;
  final IconData icon;
  final String title;
  final String line;
  final Widget? action;

  static (Color ink, Color tint) colorsOf(BuildContext context, NoticeTone302 tone) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (tone) {
      NoticeTone302.red => (
          scheme.error,
          scheme.error.withValues(alpha: dark ? 0.18 : 0.10)
        ),
      NoticeTone302.amber => (oldInk302(context), oldTint302(context)),
      NoticeTone302.grey => (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (ink, tint) = colorsOf(context, tone);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 11, 12, 11),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: ink),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: scheme.onSurface,
                      letterSpacing: 0,
                    ),
                  ),
                  if (line.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      line,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 8),
              action!,
            ],
          ]),
        ),
      ),
    );
  }
}

/// Bundle 302: the small pill button on the card / banner.
class NoticeButton302 extends StatelessWidget {
  const NoticeButton302({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    const style = ButtonStyle(
      shape: WidgetStatePropertyAll(StadiumBorder()),
      padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
      minimumSize: WidgetStatePropertyAll(Size(0, 36)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStatePropertyAll(TextStyle(
          fontFamily: LocalLinkLook.fontFamily,
          fontSize: 13.5,
          fontWeight: FontWeight.w700)),
    );
    final child = Text(label);
    return filled
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : FilledButton.tonal(onPressed: onPressed, style: style, child: child);
  }
}
