import 'package:flutter/material.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/admin/data/services/version_rule_service.dart';
import 'package:locallink/features/share_app/presentation/update_sheet.dart';

/// Bundle 213 (mock pages 4-5): this app version is old.
/// - Yellow: "Update needed in 3 days ..." + Update + × (hidden for today).
/// - Red: "This version is stopped by admin ..." + Update (no close).
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

  static const String stopText =
      'This version is stopped by admin. You can read old chats. Update to send and call.';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: VersionGuard.instance,
        builder: (context, _) {
          final g = VersionGuard.instance;
          final stopped = g.stopped && !AdminBlockBook.instance.selfBlocked;
          final warn = g.showWarn;
          final card = offers ? const UpdateOfferCard() : const SizedBox.shrink();
          if (!stopped && !warn) return card;
          final theme = Theme.of(context);
          final tint = stopped ? stopTint : warnTint;
          final ink = stopped ? stopInk : warnInk;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              key: ValueKey(stopped ? 'version_stop_banner' : 'version_warn_banner'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Material(
                color: tint,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  child: Row(children: [
                    Icon(stopped ? Icons.block : Icons.system_update, size: 18, color: ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(stopped ? stopText : warnText(g.daysLeft),
                          style: theme.textTheme.bodySmall?.copyWith(color: ink)),
                    ),
                    TextButton(
                      key: const ValueKey('version_banner_update'),
                      onPressed: () => VersionGuard.openUpdate?.call(context),
                      style: TextButton.styleFrom(foregroundColor: ink),
                      child: const Text('Update'),
                    ),
                    if (!stopped)
                      IconButton(
                        key: const ValueKey('version_banner_close'),
                        tooltip: 'Hide for today',
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
            ),
            card,
          ]);
        },
      );
}

/// Opens "Get the new LinkUp" (set as [VersionGuard.openUpdate] at start).
void openUpdateSheet(BuildContext context) => showUpdateSheet(context);
