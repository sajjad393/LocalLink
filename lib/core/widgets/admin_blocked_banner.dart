import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/chat_notice_bar_302.dart';
import 'package:locallink/core/widgets/version_banner.dart';
import 'package:locallink/features/admin/data/actions/admin_action_doers.dart' show AdminClosedFlag;
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';

/// Bundle 212 (F2, mock page 8): red banner on the blocked user's own phone
/// (Chats, Calls, People). Home banner style, red tint, no close button.
/// Nothing when this account is not blocked.
class AdminBlockedBanner extends StatelessWidget {
  const AdminBlockedBanner({super.key});

  static const Color tint = Color(0xFFFDEBE9);
  static const Color ink = Color(0xFFB42318);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // Bundle 220: + "closed by admin" (Off).
        listenable: Listenable.merge([AdminBlockBook.instance, AdminClosedFlag.closed]),
        builder: (context, _) {
          if (!AdminBlockBook.instance.selfBlocked) {
            return const SizedBox.shrink();
          }
          final theme = Theme.of(context);
          return Padding(
            key: const ValueKey('admin_blocked_banner'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Material(
              color: tint,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(children: [
                  const Icon(Icons.block, size: 18, color: ink),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AdminClosedFlag.closed.value
                          ? "Account closed by admin. You can read old chats but can't send or call."
                          : "Your account is blocked by admin. You can read old chats but can't send or call.",
                      style: theme.textTheme.bodySmall?.copyWith(color: ink),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      );
}

/// Bundle 212: puts [AdminBlockedBanner] above a whole tab (Calls, People)
/// while this account is blocked; otherwise [child] as it is.
class AdminBlockedTop extends StatelessWidget {
  const AdminBlockedTop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // Bundle 213: + the app version banner (yellow / red).
        listenable:
            Listenable.merge([AdminBlockBook.instance, VersionGuard.instance]),
        builder: (context, _) {
          final version =
              VersionGuard.instance.stopped || VersionGuard.instance.showWarn;
          if (!AdminBlockBook.instance.selfBlocked && !version) return child;
          return Column(children: [
            const SafeArea(
                bottom: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AdminBlockedBanner(),
                  VersionBanner(offers: false),
                ])),
            Expanded(
              child: MediaQuery.removePadding(
                  context: context, removeTop: true, child: child),
            ),
          ]);
        },
      );
}

/// Bundle 212 (F1): the one-line bar that replaces the message box (same
/// look as the 196 blocked bar), no Unblock.
/// Bundle 213: + an Update button when this app version is stopped.
class AdminBlockedBar extends StatelessWidget {
  const AdminBlockedBar({super.key, required this.text, this.notice});

  /// The 212/213 words ([adminBlockBarText]); shown as the title when no
  /// [notice] is given.
  final String text;

  /// Bundle 302 (B): title + line + tone for the new card.
  final ChatNotice302? notice;

  static bool get _showUpdate =>
      VersionGuard.instance.stopped && !AdminBlockBook.instance.selfBlocked;

  @override
  Widget build(BuildContext context) {
    final n = notice;
    final update = _showUpdate
        ? NoticeButton302(
            key: const ValueKey('chat_version_update'),
            label: 'Update',
            onPressed: () => VersionGuard.openUpdate?.call(context),
          )
        : null;
    // Bundle 302 (B): the floating card instead of the flat strip.
    return ChatNoticeBar302(
      key: const ValueKey('chat_admin_blocked_bar'),
      tone: n?.tone ?? NoticeTone302.red,
      icon: n?.icon ?? (_showUpdate ? Icons.system_update_rounded : Icons.block),
      title: n?.title ?? text,
      line: n?.line ?? '',
      action: update,
    );
  }
}
