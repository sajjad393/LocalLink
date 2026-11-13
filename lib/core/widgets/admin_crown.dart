import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';

import 'crown_tip_290.dart';

/// Bundle 216 (A): crown style A colours (UI_SPEC_216 §1.2).
const Color kCrownRing216 = Color(0xFFE7B416);
const Color kCrownFill216 = Color(0xFFFFC727);
const Color kCrownBand216 = Color(0xFFEFA300);
const Color kCrownLine216 = Color(0xFFA87400);
const Color kCrownGem216 = Color(0xFFE5484D);

/// Bundle 217: extra colours of the new crown (TODO_217 §2.3).
const Color kCrownTop217 = Color(0xFFFFE985);
const Color kCrownLow217 = Color(0xFFE09A12);
/// Pearl colour of the 217 crown (crown C since 290 has no pearls).
const Color kCrownPearl217 = Color(0xFFFFF1B0);
const Color kCrownBlue217 = Color(0xFF3B82F6);

/// TODO 290: the colours of one admin level's crown, photo ring, "Admin ·
/// level" tag and tip bubble. Owner = the 216/217 gold (unchanged); Operator
/// blue, Security red, Auditor silver. An unknown level gets the gold set.
@immutable
class CrownColors290 {
  final Color top;
  final Color fill;
  final Color low;
  final Color band;
  final Color line;
  final Color gem;
  final Color side;
  final Color ring;
  final Color tagBg;
  final Color tagBorder;
  final Color tagText;

  /// Level name colour in the tip bubble (dark / light theme).
  final Color tipDark;
  final Color tipLight;

  const CrownColors290({
    required this.top,
    required this.fill,
    required this.low,
    required this.band,
    required this.line,
    required this.gem,
    required this.side,
    required this.ring,
    required this.tagBg,
    required this.tagBorder,
    required this.tagText,
    required this.tipDark,
    required this.tipLight,
  });

  static const CrownColors290 gold = CrownColors290(
    top: kCrownTop217,
    fill: kCrownFill216,
    low: kCrownLow217,
    band: kCrownBand216,
    line: kCrownLine216,
    gem: kCrownGem216,
    side: kCrownBlue217,
    ring: kCrownRing216,
    tagBg: Color(0xFFFFF6DB),
    tagBorder: Color(0xFFF2D27A),
    tagText: Color(0xFF7A5200),
    tipDark: Color(0xFFF5C542),
    tipLight: Color(0xFF9A6A00),
  );

  static const CrownColors290 blue = CrownColors290(
    top: Color(0xFFDBEAFE),
    fill: Color(0xFF60A5FA),
    low: Color(0xFF2563EB),
    band: Color(0xFF1D4ED8),
    line: Color(0xFF1E3A8A),
    gem: Color(0xFFFBBF24),
    side: Color(0xFFE0F2FE),
    ring: Color(0xFF3B82F6),
    tagBg: Color(0xFFDBEAFE),
    tagBorder: Color(0xFF93C5FD),
    tagText: Color(0xFF1E3A8A),
    tipDark: Color(0xFF60A5FA),
    tipLight: Color(0xFF1D4ED8),
  );

  static const CrownColors290 red = CrownColors290(
    top: Color(0xFFFECACA),
    fill: Color(0xFFF87171),
    low: Color(0xFFDC2626),
    band: Color(0xFFB91C1C),
    line: Color(0xFF7F1D1D),
    gem: Color(0xFFFBBF24),
    side: Color(0xFFFFFFFF),
    ring: Color(0xFFEF4444),
    tagBg: Color(0xFFFEE2E2),
    tagBorder: Color(0xFFFCA5A5),
    tagText: Color(0xFF7F1D1D),
    tipDark: Color(0xFFF87171),
    tipLight: Color(0xFFB91C1C),
  );

  static const CrownColors290 silver = CrownColors290(
    top: Color(0xFFFFFFFF),
    fill: Color(0xFFD5DCE6),
    low: Color(0xFF97A3B6),
    band: Color(0xFF8C98AB),
    line: Color(0xFF4B5565),
    gem: Color(0xFF3B82F6),
    side: Color(0xFFE0F2FE),
    ring: Color(0xFFA8B3C2),
    tagBg: Color(0xFFF1F5F9),
    tagBorder: Color(0xFFCBD5E1),
    tagText: Color(0xFF334155),
    tipDark: Color(0xFFCBD5E1),
    tipLight: Color(0xFF475569),
  );

  /// 'owner' / 'operator' / 'security' / 'auditor' from a role id or its
  /// label ("Operator"); '' when unknown.
  static String norm(String? roleOrLabel) {
    final v = (roleOrLabel ?? '').trim().toLowerCase();
    return switch (v) {
      'owner' || 'operator' || 'security' || 'auditor' => v,
      _ => '',
    };
  }

  /// The set for [role] (role id or label); unknown = gold.
  static CrownColors290 of(String? role) => switch (norm(role)) {
        'operator' => blue,
        'security' => red,
        'auditor' => silver,
        _ => gold,
      };
}

/// Bundle 217 / TODO 290: draws the crown with its box top-centre at
/// [topCentre] and width [w]. Since 290 it is crown C ("round soft crown"):
/// the box is 0.50 w tall, rounded points, no pearls. [halo] paints a
/// background outline first (crowns on photos). [colors] = the admin
/// level's colours (default the owner gold).
void paintCrown217(Canvas canvas, Offset topCentre, double w,
    {Color? halo, CrownColors290 colors = CrownColors290.gold}) {
  final ox = topCentre.dx - w / 2;
  final oy = topCentre.dy;
  final u = w / 100;
  Offset p(double x, double y) => Offset(ox + x * u, oy + y * u);
  final a = p(9, 42);
  final body = Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(p(6, 17).dx, p(6, 17).dy)
    ..quadraticBezierTo(p(6, 11).dx, p(6, 11).dy, p(11, 14).dx, p(11, 14).dy)
    ..lineTo(p(29, 27).dx, p(29, 27).dy)
    ..lineTo(p(45, 7).dx, p(45, 7).dy)
    ..quadraticBezierTo(p(50, 1).dx, p(50, 1).dy, p(55, 7).dx, p(55, 7).dy)
    ..lineTo(p(71, 27).dx, p(71, 27).dy)
    ..lineTo(p(89, 14).dx, p(89, 14).dy)
    ..quadraticBezierTo(p(94, 11).dx, p(94, 11).dy, p(94, 17).dx, p(94, 17).dy)
    ..lineTo(p(91, 42).dx, p(91, 42).dy)
    ..close();
  final band = Path()
    ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(ox + 6 * u, oy + 37 * u, ox + 94 * u, oy + 49 * u),
        Radius.circular(6 * u)));
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
  }
  // Shadow under body + band.
  canvas.drawPath(
      outline.shift(Offset(.03 * w, .05 * w)),
      Paint()
        ..color = Colors.black.withValues(alpha: .43)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(.3, .04 * w)));
  final line = Paint()
    ..color = colors.line
    ..style = PaintingStyle.stroke
    ..strokeWidth = ol
    ..strokeJoin = StrokeJoin.round;
  final rect = Rect.fromLTWH(ox, oy + 1 * u, w, 41 * u);
  canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.top, colors.fill, colors.low],
          stops: const [0, .5, 1],
        ).createShader(rect));
  canvas.drawPath(body, line);
  canvas.drawPath(band, Paint()..color = colors.band);
  canvas.drawPath(band, line);
  final thin = Paint()
    ..color = colors.line
    ..style = PaintingStyle.stroke
    ..strokeWidth = ol / 2;
  final hi = Paint()..color = Colors.white.withValues(alpha: .65);
  void jewel(double x, double rx, double ry, Color color) {
    final r = Rect.fromCenter(center: p(x, 43), width: rx * 2 * u, height: ry * 2 * u);
    canvas.drawOval(r, Paint()..color = color);
    canvas.drawOval(r, thin);
    canvas.drawCircle(Offset(r.center.dx - rx * u * .35, r.center.dy - ry * u * .35), .2 * rx * u, hi);
  }
  jewel(50, 5, 4.2, colors.gem);
  jewel(27, 3.5, 3, colors.side);
  jewel(73, 3.5, 3, colors.side);
  canvas.drawLine(
      p(19, 31),
      p(16, 20),
      Paint()
        ..color = Colors.white.withValues(alpha: .47)
        ..strokeWidth = .03 * w
        ..strokeCap = StrokeCap.round);
}

/// Bundle 216 (A) / 217 / TODO 290: the painted crown ([paintCrown217]);
/// height = 0.50 × width (crown C).
class CrownPainter216 extends CustomPainter {
  /// Background colour for the halo; null = no halo (tags).
  final Color? halo;

  /// TODO 290: the admin level's colours.
  final CrownColors290 colors;
  const CrownPainter216({this.halo, this.colors = CrownColors290.gold});

  static double heightFor(double w) => w * 0.50;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    paintCrown217(canvas, Offset(w / 2, (size.height - heightFor(w)) / 2), w,
        halo: halo, colors: colors);
  }

  @override
  bool shouldRepaint(CrownPainter216 old) => old.halo != halo || old.colors != colors;
}

/// Ring (R + 2.6) in the level colour with a gap in the background colour
/// (R + 1.0), painted round the centre of the box, outside it (no clip).
class _CrownRingPainter extends CustomPainter {
  final double radius;
  final Color gap;
  final Color ring;
  const _CrownRingPainter(this.radius, this.gap, this.ring);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, radius + 2.6, Paint()..color = ring);
    canvas.drawCircle(c, radius + 1.0, Paint()..color = gap);
  }

  @override
  bool shouldRepaint(_CrownRingPainter old) =>
      old.radius != radius || old.gap != gap || old.ring != ring;
}

/// Bundle 214 / 216 (A) / 217: the admin crown — a thin ring round the
/// photo and the painted crown sitting on the ring, top centre. TODO 290:
/// both in the admin level's colour; tapping the crown shows the tip.
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

  /// TODO 290: the admin level when the caller knows it; null = the level
  /// on the admin card of [id] / [otherId].
  final String? role;

  const AdminCrown({
    super.key,
    required this.id,
    this.otherId,
    required this.radius,
    required this.child,
    this.background,
    this.role,
  });

  /// Crown width on a photo of [radius]: 0.9·R, never under 11
  /// (Bundle 256 F1: about 18 % smaller than 217's 1.1·R / 13).
  static double sizeFor(double radius) => math.max(11.0, radius * 0.9);

  /// Bundle 222 (mock C-1): the height the crown needs ABOVE a photo of
  /// [radius] (crown + halo), so a card or list edge never cuts it.
  static double room(double radius) {
    final w = sizeFor(radius);
    return (CrownPainter216.heightFor(w) + w * 0.10).ceilToDouble();
  }

  /// The crown on its own (map nodes, titles, tags). [halo] null = none.
  /// [role] = the admin level (TODO 290 colours; null = gold).
  static Widget mark(double size, {Color? halo = Colors.white, String? role}) => SizedBox(
        key: const ValueKey('admin_crown'),
        width: size,
        height: CrownPainter216.heightFor(size),
        child: CustomPaint(
            painter: CrownPainter216(halo: halo, colors: CrownColors290.of(role))),
      );

  /// TODO 290: the admin level of [id] / [otherId] from the admin cards.
  static String? roleFor(String? id, [String? otherId]) {
    final badges = AdminBadgeBook.instance;
    return badges.roleOf(id) ?? badges.roleOf(otherId);
  }

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
  /// web-style lists that already know who is admin). TODO 290: [role]
  /// picks the colours (null = gold); [tip] = tapping the crown shows what
  /// this admin can do (CrownTip290).
  static Widget decorate({
    required double radius,
    required Widget child,
    required Color background,
    Key? key,
    String? role,
    bool tip = true,
  }) {
    final w = sizeFor(radius);
    final h = CrownPainter216.heightFor(w);
    final colors = CrownColors290.of(role);
    // TODO 290: a finger-size tap area on the crown; its bottom is 4 px
    // into the photo, so the rest of the photo keeps its own tap.
    final tw = math.max(32.0, w + 12);
    final th = math.max(24.0, h + 12);
    final tTop = 0.4 + 4 - th;
    return Stack(
      key: key ?? const ValueKey('admin_crown_stack'),
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
                key: const ValueKey('admin_crown_ring'),
                painter: _CrownRingPainter(radius, background, colors.ring)),
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
              child: Center(child: mark(w, halo: background, role: role))),
        ),
        if (tip)
          Positioned(
            top: tTop,
            left: -100,
            right: -100,
            height: th,
            child: Center(
              child: SizedBox(
                width: tw,
                height: th,
                child: CrownTapTarget290(role: role, below: 2 * radius - 4.4),
              ),
            ),
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
          role: role ?? roleFor(id, otherId),
        );
      },
    );
  }
}

/// Bundle 216 (A): "Admin · Owner" tag with the painted crown
/// (UI_SPEC_216 §2.23). [small] = the Settings card size. TODO 290: the tag
/// takes the colours of [level] and a tap shows the tip bubble.
class AdminRoleTag216 extends StatelessWidget {
  final String level;
  final bool small;
  const AdminRoleTag216({super.key, required this.level, this.small = false});

  @override
  Widget build(BuildContext context) {
    final h = small ? 22.0 : 24.0;
    final colors = CrownColors290.of(level);
    return CrownTipTap290(
      role: level,
      child: Container(
      key: const ValueKey('a216_role_tag'),
      height: h,
      padding: EdgeInsets.only(left: small ? 8 : 9, right: small ? 9 : 10),
      decoration: BoxDecoration(
        color: colors.tagBg,
        borderRadius: BorderRadius.circular(h / 2),
        border: Border.all(color: colors.tagBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: small ? 12 : 13,
            height: CrownPainter216.heightFor(small ? 12 : 13),
            child: CustomPaint(painter: CrownPainter216(colors: colors)),
          ),
          SizedBox(width: small ? 5 : 5.5),
          Text('Admin · $level',
              style: TextStyle(
                  fontFamily: 'Roboto216',
                  fontSize: small ? 11 : 12,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: colors.tagText)),
        ],
      ),
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
