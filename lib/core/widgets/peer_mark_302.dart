import 'package:flutter/material.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';

/// Bundle 302 (A): why a person can't be reached, so every screen shows the
/// right words. Before 302 all three cases said "Blocked" / "You blocked …"
/// because [BlockHub] keeps one list for my blocks, admin blocks and phones
/// with an app version stopped by admin.
enum PeerMark302 {
  /// Nothing to show.
  none,

  /// I blocked them (red "Blocked", "You blocked …", Unblock).
  blocked,

  /// Admin blocked them (red "Admin blocked" / "Blocked by admin").
  admin,

  /// Admin stopped their app version (amber "Old LinkUp"). Not a block.
  old,
}

/// The mark for a phone ([deviceId]) and, when known, its account
/// ([userId]). Order: my own block > admin block > old version.
PeerMark302 peerMark302(String deviceId, {String userId = ''}) {
  final hub = BlockHub.instance;
  final mine = hub.personForDevice(deviceId) != null ||
      (userId.isNotEmpty && hub.personForUser(userId) != null);
  if (mine) return PeerMark302.blocked;
  final book = AdminBlockBook.instance;
  if (book.isBlocked(deviceId) || book.isBlocked(userId)) {
    return PeerMark302.admin;
  }
  if (VersionGuard.instance.isPeerDropped(deviceId)) return PeerMark302.old;
  if (hub.isBlockedDevice(deviceId)) {
    // In the hub list but not mine and not old: an admin-blocked account's
    // phone (known only from its saved profile), else my own block.
    return book.blockedIds.isNotEmpty ? PeerMark302.admin : PeerMark302.blocked;
  }
  return PeerMark302.none;
}

/// Amber for "Old LinkUp" (light / dark).
Color oldInk302(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF5B547)
        : const Color(0xFF9A5B06);

Color oldTint302(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0x29F5B547)
        : const Color(0xFFFDF1DD);

class _Pill302 extends StatelessWidget {
  const _Pill302({
    super.key,
    required this.text,
    required this.icon,
    required this.ink,
    this.tint,
    this.outline = false,
  });

  final String text;
  final IconData icon;
  final Color ink;
  final Color? tint;
  final bool outline;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(outline ? 4 : 5, outline ? 0 : 1, outline ? 6 : 7, outline ? 0 : 1),
        decoration: BoxDecoration(
          color: tint,
          border: outline ? Border.all(color: ink) : null,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: ink),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ink,
                  letterSpacing: 0,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Red outline "Admin blocked" (Chats / Calls rows).
class AdminBlockedPill302 extends StatelessWidget {
  const AdminBlockedPill302({super.key});

  @override
  Widget build(BuildContext context) => _Pill302(
        key: const ValueKey('pill_admin_blocked_302'),
        text: 'Admin blocked',
        icon: Icons.shield_rounded,
        ink: Theme.of(context).colorScheme.error,
        outline: true,
      );
}

/// Amber "Old LinkUp" (their app version is stopped by admin).
class OldAppPill302 extends StatelessWidget {
  const OldAppPill302({super.key});

  @override
  Widget build(BuildContext context) => _Pill302(
        key: const ValueKey('pill_old_linkup_302'),
        text: 'Old LinkUp',
        icon: Icons.system_update_rounded,
        ink: oldInk302(context),
        tint: oldTint302(context),
      );
}

/// The small label for a Chats / Calls row, or null (none / my own block:
/// that row keeps the 196 [BlockedPill]).
Widget? markPill302(PeerMark302 mark) => switch (mark) {
      PeerMark302.admin => const AdminBlockedPill302(),
      PeerMark302.old => const OldAppPill302(),
      _ => null,
    };
