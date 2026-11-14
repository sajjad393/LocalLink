import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/chat_notice_bar_302.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/admin/data/services/version_rule_service.dart';
import 'package:locallink/features/share_app/presentation/update_sheet.dart';

/// Bundle 213 (mock pages 4-5): this app version is old.
/// - Yellow: "Update needed in 3 days ..." + Update + × (hidden for today).
/// - Red: "Stopped by admin" + "Read chats only ..." + Update (no close).
/// Bundle 302 (C): a rounded card like the chat footer.
/// [offers]: also the "X is sharing LinkUp" card (Chats tab).
class VersionBanner extends StatelessWidget {
  const VersionBanner({super.key, this.offers = true});

  final bool offers;

  static const Color warnTint = Color(0xFFFDF1DD);
  static const Color warnInk = Color(0xFF9A5B06);
  static const Color stopTint = Color(0xFFFDEBE9);
  static const Color stopInk = Color(0xFFB42318);

  static String warnText(int? days) {
    if (days == null) return 'A newer LinkUp is needed. Please update.';
    final d = days == 1 ? '1 day' : '$days days';
    return 'Update needed in $d. After that this version can only read chats.';
  }

  /// Bundle 302 (C): short title + one line (mock labels_footer_302.html).
  static const String stopTitle = 'Stopped by admin';
  static const String stopText = 'Read chats only. Update to send and call.';
  static const String warnTitle = 'Update LinkUp soon';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: VersionGuard.instance,
        builder: (context, _) {
          final g = VersionGuard.instance;
          final stopped = g.stopped && !AdminBlockBook.instance.selfBlocked;
          final warn = g.showWarn;
          final card = offers ? const UpdateOfferCard() : const SizedBox.shrink();
          if (!stopped && !warn) return card;
          final dark = Theme.of(context).brightness == Brightness.dark;
          final scheme = Theme.of(context).colorScheme;
          // Bundle 302 (C): the same card look as the chat footer.
          final ink = stopped
              ? (dark ? const Color(0xFFFF8A80) : stopInk)
              : (dark ? const Color(0xFFF5B547) : warnInk);
          final tint = stopped
              ? (dark ? const Color(0x2EFF6E64) : stopTint)
              : (dark ? const Color(0x29F5B547) : warnTint);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              key: ValueKey(stopped ? 'version_stop_banner' : 'version_warn_banner'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Container(
                padding: EdgeInsets.fromLTRB(11, 11, stopped ? 12 : 4, 11),
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                    child: Icon(stopped ? Icons.block : Icons.system_update_rounded, size: 18, color: ink),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stopped ? stopTitle : warnTitle,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, height: 1.25, color: ink, letterSpacing: 0)),
                        const SizedBox(height: 2),
                        Text(stopped ? stopText : warnText(g.daysLeft),
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.3,
                                color: scheme.onSurface.withValues(alpha: 0.8),
                                letterSpacing: 0)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  NoticeButton302(
                    key: const ValueKey('version_banner_update'),
                    label: 'Update',
                    onPressed: () => VersionGuard.openUpdate?.call(context),
                  ),
                  if (!stopped)
                    IconButton(
                      key: const ValueKey('version_banner_close'),
                      tooltip: 'Hide for today',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final svc = VersionRuleService.instance;
                        if (svc != null) {
                          svc.hideWarnToday();
                        } else {
                          g.hideWarnToday();
                        }
                      },
                      icon: Icon(Icons.close, size: 18, color: ink),
                    ),
                ]),
              ),
            ),
            card,
          ]);
        },
      );
}

/// Opens "Get the new LinkUp" (set as [VersionGuard.openUpdate] at start).
void openUpdateSheet(BuildContext context) => showUpdateSheet(context);
