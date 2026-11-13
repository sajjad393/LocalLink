import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:locallink/core/theme/app_tokens.dart';

import 'admin_crown.dart';

/// TODO 290: tap a crown -> a small bubble says the admin level and what
/// this admin can do for you (owner picks, mock admin_crowns_290.html §5).
///
/// The crown is painted ABOVE the photo, outside the photo's box, and
/// Flutter only hit-tests inside a box. [CrownTapScope290] (one, round the
/// whole app) therefore checks the crown tap areas first: a tap lands on a
/// crown only when the crown is really visible there (inside every clip,
/// on the current screen) and nothing else is drawn on top of it. The
/// normal hit path is still added behind it, so a drag that starts on a
/// crown still scrolls the list.
abstract final class CrownTip290 {
  /// Title + line for each level (code: backend adminPermission, 6e3427c).
  static String title(String? role) {
    final r = CrownColors290.norm(role);
    if (r.isEmpty) return 'Admin';
    return 'Admin \u00b7 ${r[0].toUpperCase()}${r.substring(1)}';
  }

  static String line(String? role) => switch (CrownColors290.norm(role)) {
        'owner' =>
          'Developer and creator of LinkUp. Built this app so you can chat and call, even without internet.',
        'operator' =>
          'Can help if you forget your password, lose a phone, or your Wi-Fi settings need fixing.',
        'security' =>
          'Keeps LinkUp safe. Can help you get back in if you forget your password.',
        'auditor' =>
          'Checks that LinkUp works well. Can only look, can not change your account.',
        _ => 'Helps run LinkUp.',
      };

  static const Duration shownFor = Duration(seconds: 3);

  static OverlayEntry? _entry;
  static Timer? _timer;
  static Object? _owner;
  static Object? _closedOwner;
  static DateTime _closedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _routed = false;

  /// The bubble is on screen now.
  static bool get showing => _entry != null;

  /// Shows the bubble for [role] pointing at [anchor] (global rect of the
  /// crown or tag). [below] = how far under [anchor] the bubble goes when
  /// there is no room above (the photo under a crown). [owner] = who asked
  /// (a second tap on the same crown closes the bubble instead).
  static void show(BuildContext context,
      {required String? role, required Rect anchor, double below = 0, Object? owner}) {
    if (owner != null &&
        identical(owner, _closedOwner) &&
        DateTime.now().difference(_closedAt) < const Duration(milliseconds: 450)) {
      _closedOwner = null;
      return;
    }
    hide();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final box = overlay.context.findRenderObject();
    final local = box is RenderBox && box.hasSize
        ? Rect.fromPoints(box.globalToLocal(anchor.topLeft), box.globalToLocal(anchor.bottomRight))
        : anchor;
    final entry = OverlayEntry(
        builder: (_) => _CrownTipBubble(role: role, anchor: local, below: below));
    _entry = entry;
    _owner = owner;
    overlay.insert(entry);
    _timer = Timer(shownFor, hide);
    if (!_routed) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
      _routed = true;
    }
  }

  /// Closes the bubble (no-op when none is open).
  static void hide() {
    _timer?.cancel();
    _timer = null;
    if (_routed) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      _routed = false;
    }
    final e = _entry;
    _entry = null;
    _owner = null;
    if (e != null && e.mounted) e.remove();
  }

  /// Closes the bubble when [owner] goes away (its screen closed).
  static void hideFor(Object owner) {
    if (identical(owner, _owner)) hide();
  }

  // Any new finger on the screen closes the bubble (tap, scroll, back).
  static void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent || _entry == null) return;
    _closedOwner = _owner;
    _closedAt = DateTime.now();
    hide();
  }
}

/// TODO 290: put once round the app (MaterialApp builder). Lets the crown
/// tap areas, which stick out above their photos, get the tap.
class CrownTapScope290 extends SingleChildRenderObjectWidget {
  const CrownTapScope290({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderCrownTapScope290();
}

class RenderCrownTapScope290 extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_RenderCrownTarget290._live.isNotEmpty && size.contains(position)) {
      final target = _crownAt(position);
      if (target != null) {
        result.addWithPaintTransform(
          transform: target.getTransformTo(this),
          position: position,
          hitTest: (r, p) => target.hitTest(r, position: p),
        );
      }
    }
    return super.hitTest(result, position: position);
  }

  _RenderCrownTarget290? _crownAt(Offset position) {
    final live = _RenderCrownTarget290._live.toList();
    for (final t in live.reversed) {
      if (!t.attached || !t.hasSize || !t.active) continue;
      // Inside the tap area?
      final inv = Matrix4.tryInvert(t.getTransformTo(this));
      if (inv == null) continue;
      final local = MatrixUtils.transformPoint(inv, position);
      if (!(Offset.zero & t.size).contains(local)) continue;
      // Under this scope, painted, and inside every clip on the way up.
      final chain = <RenderObject>[t];
      RenderObject child = t;
      RenderObject? p = t.parent;
      var ok = true;
      while (p != null && !identical(p, this)) {
        if (!p.paintsChild(child)) {
          ok = false;
          break;
        }
        final clip = p.describeApproximatePaintClip(child);
        if (clip != null &&
            !MatrixUtils.transformRect(p.getTransformTo(this), clip).contains(position)) {
          ok = false;
          break;
        }
        chain.add(p);
        child = p;
        p = p.parent;
      }
      if (!ok || p == null) continue;
      final on = _onTop(t, chain, position);
      if (on == null) return null; // the normal path already reaches it
      if (on) return t;
    }
    return null;
  }

  /// True = nothing else is drawn over the crown at [position]; false =
  /// something is (app bar, sheet, a later map node...); null = the normal
  /// hit path already lands inside the crown tap area.
  bool? _onTop(_RenderCrownTarget290 t, List<RenderObject> chain, Offset position) {
    final kid = child;
    if (kid == null) return false;
    final scratch = BoxHitTestResult();
    kid.hitTest(scratch, position: position);
    RenderObject? d;
    for (final e in scratch.path) {
      final x = e.target;
      if (x is RenderObject) {
        d = x;
        break;
      }
    }
    if (d == null) return true;
    final mine = <RenderObject>{...chain, this};
    RenderObject? x = d;
    RenderObject? below;
    while (x != null && !mine.contains(x)) {
      below = x;
      x = x.parent;
    }
    if (x == null) return false;
    if (identical(x, t)) return null;
    if (below == null) {
      // The deepest hit holds the crown (row, list, page).
      return true;
    }
    final at = chain.indexOf(x);
    final branch = at > 0 ? chain[at - 1] : (identical(x, this) ? chain.last : null);
    if (branch == null) return false;
    // Two slivers of one list only overlap for a pinned / floating header,
    // which is drawn on top: the crown never wins there.
    if (x is RenderViewportBase) return false;
    final order = <RenderObject>[];
    x.visitChildren(order.add);
    // Later children are drawn on top (hit first).
    order.setAll(0, order.reversed.toList());
    final iT = order.indexOf(branch);
    final iD = order.indexOf(below);
    return iT >= 0 && iD >= 0 && iT < iD;
  }
}

class _CrownTargetBox290 extends SingleChildRenderObjectWidget {
  final bool Function() active;
  const _CrownTargetBox290({required this.active, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderCrownTarget290(active);

  @override
  void updateRenderObject(BuildContext context, _RenderCrownTarget290 renderObject) {
    renderObject.isActive = active;
  }
}

class _RenderCrownTarget290 extends RenderProxyBox {
  static final Set<_RenderCrownTarget290> _live = <_RenderCrownTarget290>{};

  bool Function() isActive;
  _RenderCrownTarget290(this.isActive);

  bool get active => isActive();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _live.add(this);
  }

  @override
  void detach() {
    _live.remove(this);
    super.detach();
  }
}

/// TODO 290: the tap area on a photo crown (see [AdminCrown.decorate]).
/// [below] = distance from this area's bottom to the photo's bottom.
class CrownTapTarget290 extends StatefulWidget {
  final String? role;
  final double below;
  const CrownTapTarget290({super.key, required this.role, this.below = 0});

  @override
  State<CrownTapTarget290> createState() => _CrownTapTarget290State();
}

class _CrownTapTarget290State extends State<CrownTapTarget290> {
  ModalRoute<Object?>? _route;

  bool _active() => mounted && (_route == null || _route!.isCurrent);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    CrownTip290.hideFor(this);
    super.dispose();
  }

  void _tap() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    CrownTip290.show(context,
        role: widget.role, anchor: rect, below: widget.below, owner: this);
  }

  @override
  Widget build(BuildContext context) {
    return _CrownTargetBox290(
      active: _active,
      child: Semantics(
        key: const ValueKey('crown_tip_target'),
        button: true,
        label: '${CrownTip290.title(widget.role)} crown. Shows what they can do',
        onTap: _tap,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// TODO 290: tap [child] (the "Admin · level" tag) -> the same bubble.
class CrownTipTap290 extends StatefulWidget {
  final String? role;
  final Widget child;
  const CrownTipTap290({super.key, required this.role, required this.child});

  @override
  State<CrownTipTap290> createState() => _CrownTipTap290State();
}

class _CrownTipTap290State extends State<CrownTipTap290> {
  @override
  void dispose() {
    CrownTip290.hideFor(this);
    super.dispose();
  }

  void _tap() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    CrownTip290.show(context,
        role: widget.role, anchor: box.localToGlobal(Offset.zero) & box.size, owner: this);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: const ValueKey('crown_tip_tag_tap'),
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: widget.child,
      );
}

class _CrownTipBubble extends StatelessWidget {
  final String? role;
  final Rect anchor;
  final double below;
  const _CrownTipBubble({required this.role, required this.anchor, required this.below});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = CrownColors290.of(role);
    final bg = dark ? const Color(0xFF2A2B35) : Colors.white;
    final ink = dark ? const Color(0xFFD9DAE3) : const Color(0xFF3A3D48);
    final border = colors.ring.withValues(alpha: 0.4);
    final g = CrownTipGeometry290.of(
      anchor: anchor,
      below: below,
      screen: mq.size,
      padding: mq.padding,
      scaler: mq.textScaler,
      role: role,
    );
    final titleStyle = CrownTipGeometry290.titleStyle(dark ? colors.tipDark : colors.tipLight);
    final lineStyle = CrownTipGeometry290.lineStyle(ink);
    final card = Container(
      key: const ValueKey('crown_tip_bubble'),
      width: g.rect.width,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
              color: dark ? const Color(0x8C000000) : const Color(0x38141828),
              blurRadius: 22,
              offset: const Offset(0, 7)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 15,
                height: CrownPainter216.heightFor(15),
                child: CustomPaint(painter: CrownPainter216(colors: colors)),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(CrownTip290.title(role),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
              ),
            ]),
            const SizedBox(height: 7),
            Text(CrownTip290.line(role), style: lineStyle),
          ],
        ),
      ),
    );
    Widget bubble = Stack(clipBehavior: Clip.none, children: [
      card,
      Positioned(
        left: g.arrowX - 8,
        top: g.under ? -8 : null,
        bottom: g.under ? null : -8,
        width: 16,
        height: 9,
        child: CustomPaint(painter: _ArrowPainter(up: g.under, fill: bg, line: border)),
      ),
    ]);
    if (!mq.disableAnimations) {
      bubble = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        builder: (_, v, c) => Opacity(
            opacity: v,
            child: Transform.scale(
                scale: 0.96 + 0.04 * v,
                alignment: g.under ? Alignment.topLeft : Alignment.bottomLeft,
                child: c)),
        child: bubble,
      );
    }
    return Positioned(
      left: g.rect.left,
      top: g.rect.top,
      width: g.rect.width,
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          label: '${CrownTip290.title(role)}. ${CrownTip290.line(role)}',
          excludeSemantics: true,
          child: bubble,
        ),
      ),
    );
  }
}

/// Where the bubble goes: above the anchor (8 px gap for the arrow); below
/// the photo when there is no room above; always 8 px inside the screen.
@visibleForTesting
class CrownTipGeometry290 {
  final Rect rect;
  final bool under;

  /// Arrow tip x inside the bubble.
  final double arrowX;
  const CrownTipGeometry290(this.rect, this.under, this.arrowX);

  static TextStyle titleStyle(Color c) => TextStyle(
      fontFamily: LocalLinkLook.fontFamily,
      fontSize: 14,
      height: 1,
      fontWeight: FontWeight.w700,
      color: c);

  static TextStyle lineStyle(Color c) => TextStyle(
      fontFamily: LocalLinkLook.fontFamily,
      fontSize: 13,
      height: 1.42,
      fontWeight: FontWeight.w400,
      color: c);

  static CrownTipGeometry290 of({
    required Rect anchor,
    required double below,
    required Size screen,
    required EdgeInsets padding,
    required TextScaler scaler,
    required String? role,
  }) {
    final width = math.min(262.0, screen.width - 16);
    final inner = width - 26 - 2;
    final t = TextPainter(
        text: TextSpan(text: CrownTip290.title(role), style: titleStyle(Colors.black)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1)
      ..layout(maxWidth: math.max(0, inner - 22));
    final l = TextPainter(
        text: TextSpan(text: CrownTip290.line(role), style: lineStyle(Colors.black)),
        textDirection: TextDirection.ltr,
        textScaler: scaler)
      ..layout(maxWidth: math.max(0, inner));
    final h = 2 + 11 + math.max(t.height, CrownPainter216.heightFor(15)) + 7 + l.height + 12;
    t.dispose();
    l.dispose();
    final top = padding.top + 8;
    final bottom = screen.height - padding.bottom - 8;
    final under = anchor.top - 8 - h < top;
    var y = under ? anchor.bottom + below + 9 : anchor.top - 8 - h;
    y = y.clamp(top, math.max(top, bottom - h)).toDouble();
    final left = (anchor.center.dx - 30).clamp(8.0, math.max(8.0, screen.width - width - 8)).toDouble();
    final ax = (anchor.center.dx - left).clamp(16.0, width - 16.0).toDouble();
    return CrownTipGeometry290(Rect.fromLTWH(left, y, width, h), under, ax);
  }
}

class _ArrowPainter extends CustomPainter {
  final bool up;
  final Color fill;
  final Color line;
  const _ArrowPainter({required this.up, required this.fill, required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final edge = Path();
    final body = Path();
    if (up) {
      body
        ..moveTo(0, h)
        ..lineTo(w / 2, 0)
        ..lineTo(w, h)
        ..close();
      edge
        ..moveTo(0, h)
        ..lineTo(w / 2, 0)
        ..lineTo(w, h);
    } else {
      body
        ..moveTo(0, 0)
        ..lineTo(w / 2, h)
        ..lineTo(w, 0)
        ..close();
      edge
        ..moveTo(0, 0)
        ..lineTo(w / 2, h)
        ..lineTo(w, 0);
    }
    canvas.drawPath(body, Paint()..color = fill);
    canvas.drawPath(
        edge,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.up != up || old.fill != fill || old.line != line;
}
