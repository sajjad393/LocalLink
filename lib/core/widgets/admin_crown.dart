import 'package:flutter/material.dart';

import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';

/// Bundle 214: the admin crown 👑, centred on the top edge of a photo.
/// Does not change the photo's size or layout (Stack, no clip). Shows
/// only while [id] (account id or phone id) has a live server card, and
/// never on a photo blocked by admin.
class AdminCrown extends StatelessWidget {
  final String? id;
  final String? otherId;
  final double radius;
  final Widget child;

  const AdminCrown({
    super.key,
    required this.id,
    this.otherId,
    required this.radius,
    required this.child,
  });

  static double sizeFor(double radius) => radius * 0.75 < 12 ? 12 : radius * 0.75;

  /// The crown on its own (map nodes, titles).
  static Widget mark(double size) => Text(
        '\u{1F451}',
        key: const ValueKey('admin_crown'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size,
          height: 1,
          shadows: const [Shadow(color: Colors.white, blurRadius: 2)],
        ),
      );

  static bool showFor(String? id, [String? otherId]) {
    final badges = AdminBadgeBook.instance;
    final blocks = AdminBlockBook.instance;
    for (final x in [id, otherId]) {
      if (x == null || x.isEmpty) continue;
      if (blocks.isBlocked(x)) return false;
    }
    return badges.isAdmin(id) || badges.isAdmin(otherId);
  }

  @override
  Widget build(BuildContext context) {
    if ((id ?? '').isEmpty && (otherId ?? '').isEmpty) return child;
    return ListenableBuilder(
      listenable: AdminBadgeBook.instance,
      builder: (context, _) {
        if (!showFor(id, otherId)) return child;
        final size = sizeFor(radius);
        return Stack(
          key: const ValueKey('admin_crown_stack'),
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            child,
            Positioned(
              top: -size * 0.62,
              left: 0,
              right: 0,
              child: IgnorePointer(child: Center(child: mark(size))),
            ),
          ],
        );
      },
    );
  }
}

/// Bundle 214 (D7): "👑 Admin · Owner" under an admin's name on a profile.
class AdminRoleLine extends StatelessWidget {
  final String? id;
  const AdminRoleLine({super.key, required this.id});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AdminBadgeBook.instance,
        builder: (context, _) {
          if (!AdminCrown.showFor(id)) return const SizedBox.shrink();
          final card = AdminBadgeBook.instance.adminOf(id)!;
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('\u{1F451} Admin · ${card.roleLabel}',
                key: const ValueKey('admin_role_line'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9A6A00))),
          );
        },
      );
}
