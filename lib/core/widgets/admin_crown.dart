import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';

/// Bundle 216 (A): crown style A colours (UI_SPEC_216 §1.2).
const Color kCrownRing216 = Color(0xFFE7B416);
const Color kCrownFill216 = Color(0xFFFFC727);
const Color kCrownBand216 = Color(0xFFEFA300);
const Color kCrownLine216 = Color(0xFFA87400);
const Color kCrownGem216 = Color(0xFFE5484D);

/// Bundle 217: extra colours of the new crown (TODO_217 §2.3).
const Color kCrownTop217 = Color(0xFFFFE985);
const Color kCrownLow217 = Color(0xFFE09A12);
const Color kCrownPearl217 = Color(0xFFFFF1B0);
const Color kCrownBlue217 = Color(0xFF3B82F6);

/// Bundle 217: draws the new crown (TODO_217 §2.3) with its box top-centre at
/// [topCentre] and width [w]; the box is 0.88 w tall. Pearls may stick out by
/// 0.05 w (no clip). [halo] paints a background outline first (tags on photos).
void paintCrown217(Canvas canvas, Offset topCentre, double w, {Color? halo}) {
  final ox = topCentre.dx - w / 2;
  final oy = topCentre.dy;
  Offset p(double x, double y) => Offset(ox + x * w, oy + y * w);
  final body = Path()..addPolygon([
      p(.10, .715), p(.03, .235), p(.30, .475), p(.50, .095),
      p(.70, .475), p(.97, .235), p(.90, .715)], true);
  final band = Path()
    ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(ox + .08 * w, oy + .675 * w, ox + .92 * w, oy + .875 * w),
        Radius.circular(.05 * w)));
  final pearls = [p(.03, .215), p(.50, .075), p(.97, .215)];
  final pearlR = .075 * w;
  final ol = math.max(0.8, .035 * w);
  final outline = Path()
    ..addPath(body, Offset.zero)
    ..addPath(band, Offset.zero);
  if (halo != null) {
    final hw = math.max(1.2, w * .07);
    canvas.drawPath(
        outline,
        Paint()
          ..color = halo
          ..style = PaintingStyle.stroke
          ..strokeWidth = hw * 2 + ol
          ..strokeJoin = StrokeJoin.round);
    for (final c in pearls) {
      canvas.drawCircle(c, pearlR + hw + ol / 2, Paint()..color = halo);
    }
  }
  // Shadow under body + band.
  canvas.drawPath(
      outline.shift(Offset(.03 * w, .05 * w)),
      Paint()
        ..color = Colors.black.withValues(alpha: .43)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(.3, .04 * w)));
  final line = Paint()
    ..color = kCrownLine216
    ..style = PaintingStyle.stroke
    ..strokeWidth = ol
    ..strokeJoin = StrokeJoin.round;
  final rect = Rect.fromLTWH(ox, oy + .095 * w, w, .62 * w);
  canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kCrownTop217, kCrownFill216, kCrownLow217],
          stops: [0, .5, 1],
        ).createShader(rect));
  canvas.drawPath(body, line);
  canvas.drawPath(band, Paint()..color = kCrownBand216);
  canvas.drawPath(band, line);
  for (final c in pearls) {
    canvas.drawCircle(c, pearlR, Paint()..color = kCrownPearl217);
    canvas.drawCircle(c, pearlR, line);
  }
  final thin = Paint()
    ..color = kCrownLine216
    ..style = PaintingStyle.stroke
    ..strokeWidth = ol / 2;
  final hi = Paint()..color = Colors.white.withValues(alpha: .65);
  void jewel(double x, double rx, double ry, Color color) {
    final r = Rect.fromCenter(center: p(x, .775), width: rx * 2 * w, height: ry * 2 * w);
    canvas.drawOval(r, Paint()..color = color);
    canvas.drawOval(r, thin);
    canvas.drawCircle(Offset(r.center.dx - rx * w * .35, r.center.dy - ry * w * .35), .2 * rx * w, hi);
  }
  jewel(.50, .065, .055, kCrownGem216);
  jewel(.27, .045, .038, kCrownBlue217);
  jewel(.73, .045, .038, kCrownBlue217);
  canvas.drawLine(
      p(.20, .635),
      p(.14, .355),
      Paint()
        ..color = Colors.white.withValues(alpha: .47)
        ..strokeWidth = .03 * w
        ..strokeCap = StrokeCap.round);
}

/// Bundle 216 (A) / 217: the painted crown. Since 217 it draws the new crown
/// ([paintCrown217]); height = 0.88 × width.
class CrownPainter216 extends CustomPainter {
  /// Background colour for the halo; null = no halo (tags).
  final Color? halo;
  const CrownPainter216({this.halo});

  static double heightFor(double w) => w * 0.88;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    paintCrown217(canvas, Offset(w / 2, (size.height - heightFor(w)) / 2), w,
        halo: halo);
  }

  @override
  bool shouldRepaint(CrownPainter216 old) => old.halo != halo;
}

/// Gold ring (R + 2.6) with a gap in the background colour (R + 1.0),
/// painted round the centre of the box, outside it (no clip).
class _CrownRingPainter extends CustomPainter {
  final double radius;
  final Color gap;
  const _CrownRingPainter(this.radius, this.gap);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, radius + 2.6, Paint()..color = kCrownRing216);
    canvas.drawCircle(c, radius + 1.0, Paint()..color = gap);
  }

  @override
  bool shouldRepaint(_CrownRingPainter old) =>
      old.radius != radius || old.gap != gap;
}

/// Bundle 214 / 216 (A) / 217: the admin crown — a thin gold ring round the
/// photo and the painted crown sitting on the ring, top centre.
/// Does not change the photo's size or layout (Stack, no clip). Shows only
/// while [id] (account id or phone id) has a live server card, and never on
/// a photo blocked by admin.
class AdminCrown extends StatelessWidget {
  final String? id;
  final String? otherId;
  final double radius;
  final Widget child;

  /// Colour behind the photo (ring gap + crown halo). Null = surface.
  final Color? background;

  const AdminCrown({
    super.key,
    required this.id,
    this.otherId,
    required this.radius,
    required this.child,
    this.background,
  });

  /// Crown width on a photo of [radius]: 0.9·R, never under 11
  /// (Bundle 256 F1: about 18 % smaller than 217's 1.1·R / 13).
  static double sizeFor(double radius) => math.max(11.0, radius * 0.9);

  /// Bundle 222 (mock C-1): the height the crown needs ABOVE a photo of
  /// [radius] (crown + halo + pearls), so a card or list edge never cuts it.
  static double room(double radius) {
    final w = sizeFor(radius);
    return (CrownPainter216.heightFor(w) + w * 0.10).ceilToDouble();
  }

  /// The crown on its own (map nodes, titles, tags). [halo] null = none.
  static Widget mark(double size, {Color? halo = Colors.white}) => SizedBox(
        key: const ValueKey('admin_crown'),
        width: size,
        height: CrownPainter216.heightFor(size),
        child: CustomPaint(painter: CrownPainter216(halo: halo)),
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

  /// Ring + crown round [child] without the badge check (UI check data,
  /// web-style lists that already know who is admin).
  static Widget decorate({
    required double radius,
    required Widget child,
    required Color background,
    Key? key,
  }) {
    final w = sizeFor(radius);
    final h = CrownPainter216.heightFor(w);
    return Stack(
      key: key ?? const ValueKey('admin_crown_stack'),
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
                key: const ValueKey('admin_crown_ring'),
                painter: _CrownRingPainter(radius, background)),
          ),
        ),
        child,
        // Bundle 217: the band sits on the gold ring (outer edge R + 2.6);
        // its bottom touches the photo edge (0.4 px in).
        Positioned(
          top: 0.4 - h,
          left: 0,
          right: 0,
          child: IgnorePointer(
              child: Center(child: mark(w, halo: background))),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if ((id ?? '').isEmpty && (otherId ?? '').isEmpty) return child;
    return ListenableBuilder(
      listenable: AdminBadgeBook.instance,
      builder: (context, _) {
        if (!showFor(id, otherId)) return child;
        return decorate(
          radius: radius,
          child: child,
          background: background ?? Theme.of(context).colorScheme.surface,
        );
      },
    );
  }
}

/// Bundle 216 (A): "Admin · Owner" tag with the painted crown
/// (UI_SPEC_216 §2.23). [small] = the Settings card size.
class AdminRoleTag216 extends StatelessWidget {
  final String level;
  final bool small;
  const AdminRoleTag216({super.key, required this.level, this.small = false});

  @override
  Widget build(BuildContext context) {
    final h = small ? 22.0 : 24.0;
    return Container(
      key: const ValueKey('a216_role_tag'),
      height: h,
      padding: EdgeInsets.only(left: small ? 8 : 9, right: small ? 9 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DB),
        borderRadius: BorderRadius.circular(h / 2),
        border: Border.all(color: const Color(0xFFF2D27A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: small ? 12 : 13,
            height: CrownPainter216.heightFor(small ? 12 : 13),
            child: const CustomPaint(painter: CrownPainter216()),
          ),
          SizedBox(width: small ? 5 : 5.5),
          Text('Admin · $level',
              style: TextStyle(
                  fontFamily: 'Roboto216',
                  fontSize: small ? 11 : 12,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF7A5200))),
        ],
      ),
    );
  }
}

/// Bundle 214 (D7) / 216 (A): "Admin · Owner" under an admin's name on a
/// profile, now as the painted-crown tag.
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
            key: const ValueKey('admin_role_line'),
            padding: const EdgeInsets.only(top: 6),
            child: Center(child: AdminRoleTag216(level: card.roleLabel)),
          );
        },
      );
}

/// Bundle 222 (mock C-1): top space for the crown, only while it shows (an
/// account that is not admin sees no change). [already] = space that is
/// already there above the photo (card padding), so only the rest is added.
class AdminCrownRoom extends StatelessWidget {
  final String? id;
  final String? otherId;
  final double radius;
  final double already;
  final Widget child;

  const AdminCrownRoom({
    super.key,
    required this.id,
    this.otherId,
    required this.radius,
    this.already = 0,
    required this.child,
  });

  /// Extra top space for a photo of [radius] with [already] space above it.
  static double extraFor(double radius, {double already = 0}) =>
      math.max(0.0, AdminCrown.room(radius) - already);

  @override
  Widget build(BuildContext context) {
    if ((id ?? '').isEmpty && (otherId ?? '').isEmpty) return child;
    return ListenableBuilder(
      listenable: Listenable.merge([AdminBadgeBook.instance, AdminBlockBook.instance]),
      builder: (context, _) => Padding(
        key: const ValueKey('admin_crown_room'),
        padding: EdgeInsets.only(
            top: AdminCrown.showFor(id, otherId) ? extraFor(radius, already: already) : 0),
        child: child,
      ),
    );
  }
}
