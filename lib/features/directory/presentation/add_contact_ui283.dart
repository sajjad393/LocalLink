// Bundle 283 (mock `mocks/add_contact_improved_283.html` + `_light.html`):
// the Add Contact look - same on every phone (Roboto, fixed colours, light
// version of the same design). Words and keys are locked by tests.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';

/// Fixed values from the mock CSS.
abstract final class AddUi283 {
  /// Mock `#23E0D8` (scanner corners, waves).
  static const Color teal = Color(0xFF23E0D8);

  /// Mock `.me` / `.hero .c`: `linear-gradient(135deg,#1E5BFF,#23E0D8)`.
  static const LinearGradient meGradient = LinearGradient(
    colors: [Color(0xFF1E5BFF), Color(0xFF23E0D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Mock avatar `linear-gradient(135deg,#7C6BF0,#E74BC8)`.
  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFF7C6BF0), Color(0xFFE74BC8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Mock avatar `linear-gradient(135deg,#2F6FF6,#1FD7D4)`.
  static const LinearGradient blueGradient = LinearGradient(
    colors: [Color(0xFF2F6FF6), Color(0xFF1FD7D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Mock `cubic-bezier(.2,.8,.2,1)` (cards sliding in).
  static const Curve easeOut = Cubic(.2, .8, .2, 1);

  /// Mock `.opt .ch` / outlines: `#5d6178` (light `#9aa0b4`).
  static Color chevron(LinkPalette p) => p.isDark ? const Color(0xFF5D6178) : const Color(0xFF9AA0B4);

  /// S-3: small phones (ZTE, 320 dp) shrink the scene, not the text.
  /// 320 dp -> 184, 360 dp and wider -> 212 (mock).
  static double sceneHeight(double width) {
    if (width >= 360) return 212;
    if (width <= 320) return 184;
    return 184 + (width - 320) / 40 * 28;
  }

  /// Avatar colours: the same name always gets the same of the two mock
  /// gradients (blue/teal or purple/pink).
  static LinearGradient avatarGradient(String name) {
    final c = LocalLinkAvatarColor.forName(name);
    const blues = {0xFF1FD7D4, 0xFF2F6FF6, 0xFF2BA0F0, 0xFF00A8B5};
    return blues.contains(c.toARGB32()) ? blueGradient : purpleGradient;
  }
}

/// S-4: one clock for a painted animation, at most 30 frames a second. It
/// stops with "Remove animations" (still frame) and when the screen is not
/// visible (the ticker follows TickerMode).
mixin Clock283<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  final ValueNotifier<double> seconds = ValueNotifier<double>(0);
  Ticker? _ticker283;
  Duration _last283 = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calm = LinkKit.calm(context);
    if (calm) {
      _ticker283?.stop();
      seconds.value = 0;
      return;
    }
    _ticker283 ??= createTicker((elapsed) {
      if (elapsed - _last283 < const Duration(milliseconds: 33)) return;
      _last283 = elapsed;
      seconds.value = elapsed.inMicroseconds / 1e6;
    });
    if (!_ticker283!.isActive) {
      _last283 = Duration.zero;
      _ticker283!.start();
    }
  }

  @override
  void dispose() {
    _ticker283?.dispose();
    seconds.dispose();
    super.dispose();
  }
}

/// Mock `.bar`: 60 high, back arrow, 21 sp bold title, round buttons right.
PreferredSizeWidget addBar283(BuildContext context, {required String title, List<Widget> actions = const []}) {
  final p = LinkKit.of(context);
  return AppBar(
    toolbarHeight: 60,
    backgroundColor: p.screen,
    surfaceTintColor: Colors.transparent,
    foregroundColor: p.isDark ? const Color(0xFFE3E2E9) : const Color(0xFF1B1B1F),
    elevation: 0,
    scrolledUnderElevation: 0,
    titleSpacing: 4,
    title: Text(title,
        style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: p.isDark ? const Color(0xFFE3E2E9) : const Color(0xFF1B1B1F))),
    actions: [...actions, const SizedBox(width: 12)],
  );
}

/// Mock `.qr`: 42 round button at the top right.
class RoundTopButton283 extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const RoundTopButton283({super.key, required this.tooltip, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.isDark ? const Color(0xFF262A3A) : const Color(0xFFE3E8FF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 20, color: p.isDark ? const Color(0xFFDBE3FF) : const Color(0xFF1E3A8A)),
          ),
        ),
      ),
    );
  }
}

/// Mock `.search` / `.search.f`: 50 high pill, 2 dp blue ring when focused.
class SearchBox283 extends StatefulWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onClear;

  const SearchBox283({super.key, required this.controller, required this.busy, required this.onClear});

  @override
  State<SearchBox283> createState() => _SearchBox283State();
}

class _SearchBox283State extends State<SearchBox283> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_redraw);
    widget.controller.addListener(_redraw);
  }

  @override
  void didUpdateWidget(covariant SearchBox283 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_redraw);
      widget.controller.addListener(_redraw);
    }
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_redraw);
    _focus
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final focused = _focus.hasFocus;
    final hasText = widget.controller.text.isNotEmpty;
    final bg = focused
        ? (p.isDark ? const Color(0xFF1B1D26) : Colors.white)
        : (p.isDark ? const Color(0xFF1F2027) : const Color(0xFFECEEF4));
    final hint = p.isDark ? const Color(0xFF8E91A0) : const Color(0xFF6B7080);
    final iconColor = focused ? (p.isDark ? const Color(0xFFC9CBD6) : const Color(0xFF374151)) : hint;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 50,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: focused ? p.focus : Colors.transparent, width: 2),
      ),
      child: Row(children: [
        SizedBox(
          width: 22,
          height: 22,
          child: widget.busy
              ? Padding(
                  padding: const EdgeInsets.all(2),
                  child: CircularProgressIndicator(strokeWidth: 2, color: p.focus),
                )
              : Icon(Icons.search, size: 22, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            cursorColor: p.focus,
            cursorWidth: 2,
            style: TextStyle(fontSize: 14.5, color: p.text),
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Search name or @username',
              hintStyle: TextStyle(fontSize: 14.5, color: hint),
            ),
          ),
        ),
        if (hasText)
          IconButton(
            onPressed: widget.busy ? null : widget.onClear,
            icon: Icon(Icons.close, size: 20, color: iconColor),
            tooltip: 'Clear',
          )
        else
          const SizedBox(width: 10),
      ]),
    );
  }
}

/// Mock `.live`: pulsing teal dot + "Searching".
class LivePill283 extends StatefulWidget {
  final String text;
  const LivePill283({super.key, this.text = 'Searching'});

  @override
  State<LivePill283> createState() => _LivePill283State();
}

class _LivePill283State extends State<LivePill283> with SingleTickerProviderStateMixin, Clock283<LivePill283> {
  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final dot = p.isDark ? const Color(0xFF2DD4BF) : const Color(0xFF14A3A0);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0x2414A3A0) : const Color(0x1F14A3A0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 7,
          height: 7,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: dot, shape: BoxShape.circle))),
            if (!LinkKit.calm(context))
              Positioned(
                left: -4,
                top: -4,
                right: -4,
                bottom: -4,
                child: ValueListenableBuilder<double>(
                  valueListenable: seconds,
                  builder: (_, s, __) {
                    final v = Curves.easeOut.transform((s % 1.6) / 1.6);
                    return Transform.scale(
                      scale: .6 + 1.2 * v,
                      child: Opacity(
                        opacity: .9 * (1 - v),
                        child: DecoratedBox(
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: dot, width: 2)),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
        const SizedBox(width: 6),
        Text(widget.text,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.isDark ? p.teal : const Color(0xFF0F766E))),
      ]),
    );
  }
}

/// Mock `.sec`: small grey capitals (12 sp, 1 dp letter spacing) + an
/// optional live "Searching" pill.
class SectionTitle283 extends StatelessWidget {
  final String text;
  final bool live;

  const SectionTitle283(this.text, {super.key, this.live = false});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(children: [
        Flexible(
          child: Text(text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: p.isDark ? const Color(0xFF8B8FA0) : const Color(0xFF6B7080))),
        ),
        if (live) ...[const SizedBox(width: 10), const LivePill283()],
      ]),
    );
  }
}

/// Mock `.add`: gradient "Add" / "Add friend" chip.
class GradientChip283 extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onPressed;

  const GradientChip283({super.key, required this.text, this.icon = Icons.person_add_alt_1, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final off = onPressed == null;
    return Semantics(
      button: true,
      enabled: !off,
      child: Opacity(
        opacity: off ? .55 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinkKit.brandGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: off ? null : const [BoxShadow(color: Color(0x4D1E5BFF), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 8, 14, 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mock `.pill`: green "✓ Contact".
class ContactPill283 extends StatelessWidget {
  final String text;
  const ContactPill283(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final fg = p.isDark ? const Color(0xFF86EFAC) : const Color(0xFF067647);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0x2122C55E) : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check, size: 14, color: fg),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

/// Mock `.av` (+ `.dot`): 44 gradient circle with the first letter.
class LetterAvatar283 extends StatelessWidget {
  final String name;
  final String initial;
  final Color? dot;
  final Gradient? gradient;

  const LetterAvatar283({super.key, required this.name, required this.initial, this.dot, this.gradient});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient ?? AddUi283.avatarGradient(name)),
            child: Center(
              child: Text(initial,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ),
        if (dot != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: p.card, width: 2.5),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Mock `.card`: one person row (radius 20, 12/14 padding, 9 apart).
class PersonCard283 extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget avatar;
  final String title;
  final Color? titleColor;
  final Widget subtitle;
  final Widget? trailing;

  const PersonCard283({
    super.key,
    this.onTap,
    required this.avatar,
    required this.title,
    this.titleColor,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: p.cardShadow),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(children: [
                avatar,
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: titleColor ?? p.text)),
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.muted),
                        child: subtitle,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 10), trailing!],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mock `.nf`: 'No one called "X" on LinkUp'.
class NotFoundCard283 extends StatelessWidget {
  final String query;
  const NotFoundCard283({super.key, required this.query});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Container(
      key: const ValueKey('search_not_found_283'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), boxShadow: p.cardShadow),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.isDark ? const Color(0xFF262A3A) : const Color(0xFFE3E8FF),
          ),
          child: Icon(Icons.search, size: 18, color: p.isDark ? const Color(0xFFA9B8FF) : const Color(0xFF1E5BFF)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'No one called '),
              TextSpan(
                  text: '"$query"',
                  style: TextStyle(fontWeight: FontWeight.w700, color: p.isDark ? Colors.white : const Color(0xFF111111))),
              const TextSpan(text: ' on LinkUp'),
            ]),
            style: TextStyle(fontSize: 13.5, color: p.isDark ? const Color(0xFFCFD1DB) : const Color(0xFF374151)),
          ),
        ),
      ]),
    );
  }
}

/// Mock `.quiet`: one calm line with a green tick.
class QuietLine283 extends StatelessWidget {
  final String text;
  const QuietLine283(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final fg = p.isDark ? const Color(0xFF86EFAC) : const Color(0xFF067647);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: p.note, borderRadius: BorderRadius.circular(18), boxShadow: p.noteShadow),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.isDark ? const Color(0x2422C55E) : const Color(0xFFDCFCE7),
          ),
          child: Icon(Icons.check, size: 16, color: fg),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: p.noteText))),
      ]),
    );
  }
}

/// Mock `.hint`: dashed box "Not here? Ask them to open My QR code, then
/// tap Scan QR code below."
class QrHint283 extends StatelessWidget {
  const QrHint283({super.key});

  static const String text = 'Not here? Ask them to open My QR code, then tap Scan QR code below.';

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final bold = TextStyle(
        fontWeight: FontWeight.w700, color: p.isDark ? const Color(0xFFDBE3FF) : const Color(0xFF1E3A8A));
    return Padding(
      key: const ValueKey('search_qr_hint_283'),
      padding: const EdgeInsets.only(top: 14),
      child: DashedBorder283(
        color: p.isDark ? const Color(0xFF343850) : const Color(0xFFC7CCE0),
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            Icon(Icons.qr_code_2_rounded, size: 22, color: p.isDark ? const Color(0xFFA9B8FF) : const Color(0xFF1E5BFF)),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Not here? Ask them to open '),
                  TextSpan(text: 'My QR code', style: bold),
                  const TextSpan(text: ', then tap '),
                  TextSpan(text: 'Scan QR code', style: bold),
                  const TextSpan(text: ' below.'),
                ]),
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: p.isDark ? const Color(0xFFB5B8C5) : const Color(0xFF4B5563)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A 1 dp dashed rounded border (mock `border:1px dashed`).
class DashedBorder283 extends StatelessWidget {
  final Color color;
  final double radius;
  final Widget child;

  const DashedBorder283({super.key, required this.color, required this.radius, required this.child});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DashedPainter283(color, radius), child: child);
}

class _DashedPainter283 extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedPainter283(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(.5), Radius.circular(radius)));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), paint);
        d += 6;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter283 old) => old.color != color || old.radius != radius;
}

enum WarnKind283 { wifi, nearby }

/// Mock `.warn`: "Wi-Fi is off" / "Find phones near you" with one button.
class WarnCard283 extends StatelessWidget {
  final WarnKind283 kind;
  final String title;
  final String text;
  final String action;
  final VoidCallback? onPressed;

  const WarnCard283({
    super.key,
    required this.kind,
    required this.title,
    required this.text,
    required this.action,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final (bg, fg, icon) = switch (kind) {
      WarnKind283.wifi => (const Color(0x24FACC15), const Color(0xFFFDE047), Icons.wifi_rounded),
      WarnKind283.nearby => (const Color(0x248EA6FF), const Color(0xFFA9B8FF), Icons.near_me_rounded),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: p.cardShadow),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, size: 22, color: fg),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: p.text)),
            const SizedBox(height: 2),
            Text(text, style: TextStyle(fontSize: 12.5, color: p.muted)),
          ]),
        ),
        const SizedBox(width: 10),
        Material(
          color: p.isDark ? const Color(0xFF8EA6FF) : const Color(0xFF1E5BFF),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              child: Text(action,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.isDark ? const Color(0xFF14215C) : Colors.white)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Mock `.opt`: big action row (gradient icon tile, title, small line, ›).
class OptionRow283 extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const OptionRow283({
    super.key,
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Container(
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: p.cardShadow),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
              ),
              Text('›', style: TextStyle(fontSize: 20, color: AddUi283.chevron(p))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Mock `.hero`: glowing circle with two breathing rings and sparks.
class EmptyHero283 extends StatefulWidget {
  final IconData icon;
  const EmptyHero283({super.key, this.icon = Icons.check});

  @override
  State<EmptyHero283> createState() => _EmptyHero283State();
}

class _EmptyHero283State extends State<EmptyHero283> with SingleTickerProviderStateMixin, Clock283<EmptyHero283> {
  @override
  Widget build(BuildContext context) {
    final calm = LinkKit.calm(context);
    return Padding(
      padding: const EdgeInsets.only(top: 44, bottom: 18),
      child: Center(
        child: SizedBox(
          width: 132,
          height: 132,
          child: ValueListenableBuilder<double>(
            valueListenable: seconds,
            builder: (context, s, _) {
              double breath(double delay) {
                if (calm) return 0;
                final v = ((s - delay) % 3.2) / 3.2;
                return math.sin(v * math.pi);
              }

              double spark(double delay) {
                if (calm) return 1;
                final v = ((s - delay) % 2.4) / 2.4;
                return math.sin(v * math.pi);
              }

              Widget ring(double inset, Color color, double delay) {
                final b = breath(delay);
                return Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(inset),
                    child: Transform.scale(
                      scale: 1 + .06 * b,
                      child: Opacity(
                        opacity: 1 - .4 * b,
                        child: DecoratedBox(
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
                        ),
                      ),
                    ),
                  ),
                );
              }

              Widget dot(double? left, double? right, double? top, double? bottom, double delay) {
                final v = spark(delay);
                return Positioned(
                  left: left,
                  right: right,
                  top: top,
                  bottom: bottom,
                  child: Transform.scale(
                    scale: .4 + .6 * v,
                    child: Opacity(
                      opacity: v.clamp(0.0, 1.0),
                      child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: AddUi283.teal)),
                    ),
                  ),
                );
              }

              return Stack(children: [
                ring(0, const Color(0x4023E0D8), 0),
                ring(14, const Color(0x591E5BFF), .4),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AddUi283.meGradient,
                        boxShadow: [BoxShadow(color: Color(0x731E5BFF), blurRadius: 30, offset: Offset(0, 10))],
                      ),
                      child: Icon(widget.icon, size: 44, color: Colors.white),
                    ),
                  ),
                ),
                dot(6, null, 30, null, 0),
                dot(null, 2, 60, null, .8),
                dot(40, null, null, 0, 1.6),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// Mock section 1: nobody to add -> hero, title, words, two actions.
class EmptyAdd283 extends StatelessWidget {
  final String title;
  final String text;
  final Key? textKey;
  final IconData icon;
  final VoidCallback? onMyQr;
  final VoidCallback? onNearby;

  const EmptyAdd283({
    super.key,
    required this.title,
    required this.text,
    this.textKey,
    this.icon = Icons.check,
    this.onMyQr,
    this.onNearby,
  });

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmptyHero283(icon: icon),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: p.isDark ? const Color(0xFFF2F1F7) : const Color(0xFF111827))),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Text(text,
              key: textKey,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: p.isDark ? const Color(0xFF9A9DAA) : const Color(0xFF6B7080))),
        ),
        const SizedBox(height: 26),
        if (onMyQr != null)
          SlideIn283(
            delay: const Duration(milliseconds: 150),
            child: OptionRow283(
              key: const ValueKey('add283_opt_qr'),
              icon: Icons.qr_code_2_rounded,
              gradient: LinkKit.brandGradient,
              title: 'Show my QR code',
              subtitle: 'Let a friend scan you',
              onTap: onMyQr,
            ),
          ),
        if (onMyQr != null && onNearby != null) const SizedBox(height: 10),
        if (onNearby != null)
          SlideIn283(
            delay: const Duration(milliseconds: 300),
            child: OptionRow283(
              key: const ValueKey('add283_opt_nearby'),
              icon: Icons.near_me_rounded,
              gradient: AddUi283.purpleGradient,
              title: 'Find people nearby',
              subtitle: 'Phones around you with LinkUp',
              onTap: onNearby,
            ),
          ),
      ],
    );
  }
}

/// Mock `.in`: fade + slide up 18 dp in 0.55 s after [delay] (one
/// controller, no timers; still with "Remove animations").
class SlideIn283 extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const SlideIn283({super.key, this.delay = Duration.zero, required this.child});

  @override
  State<SlideIn283> createState() => _SlideIn283State();
}

class _SlideIn283State extends State<SlideIn283> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + const Duration(milliseconds: 550),
  );
  late final Animation<double> _v = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMicroseconds / _c.duration!.inMicroseconds,
      1,
      curve: AddUi283.easeOut,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (LinkKit.calm(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _v,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _v.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 18 * (1 - _v.value)), child: child),
        ),
      );
}

/// Mock `.lk`: "Looking for phones near you" + dots that count up.
class LookingText283 extends StatefulWidget {
  final String text;
  const LookingText283(this.text, {super.key});

  @override
  State<LookingText283> createState() => _LookingText283State();
}

class _LookingText283State extends State<LookingText283>
    with SingleTickerProviderStateMixin, Clock283<LookingText283> {
  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final style = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Flexible(child: Text(widget.text, textAlign: TextAlign.center, style: style)),
      SizedBox(
        width: 14,
        child: ValueListenableBuilder<double>(
          valueListenable: seconds,
          builder: (_, s, __) {
            final n = LinkKit.calm(context) ? 3 : ((s % 1.5) / 1.5 * 4).floor();
            return Text('.' * n, style: style);
          },
        ),
      ),
    ]);
  }
}

/// Mock section 4: "you" in the middle, soft waves going out, two slow
/// dashed orbits, five grey phones floating. [found] 0..1: a curved dashed
/// line draws to one phone, that phone turns into the person's letter.
/// One painter, 30 fps, no blur (S-4); a still frame with "Remove animations".
class NearbyScene283 extends StatefulWidget {
  final double found;
  final String foundInitial;
  final String meInitial;

  const NearbyScene283({super.key, this.found = 0, this.foundInitial = '', this.meInitial = ''});

  @override
  State<NearbyScene283> createState() => _NearbyScene283State();
}

class _NearbyScene283State extends State<NearbyScene283>
    with SingleTickerProviderStateMixin, Clock283<NearbyScene283> {
  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final calm = LinkKit.calm(context);
    return LayoutBuilder(builder: (context, c) {
      final h = AddUi283.sceneHeight(MediaQuery.sizeOf(context).width);
      return ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: SizedBox(
          height: h,
          width: double.infinity,
          child: RepaintBoundary(
            child: ValueListenableBuilder<double>(
              valueListenable: seconds,
              builder: (_, s, __) => CustomPaint(
                painter: _ScenePainter283(
                  t: calm ? 0 : s,
                  dark: p.isDark,
                  found: widget.found.clamp(0.0, 1.0),
                  foundInitial: widget.foundInitial,
                  meInitial: widget.meInitial,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _ScenePainter283 extends CustomPainter {
  final double t;
  final bool dark;
  final double found;
  final String foundInitial;
  final String meInitial;

  _ScenePainter283({
    required this.t,
    required this.dark,
    required this.found,
    required this.foundInitial,
    required this.meInitial,
  });

  static const _ghosts = <Offset>[
    Offset(.18, .30),
    Offset(.84, .24),
    Offset(.14, .76),
    Offset(.86, .72),
    Offset(.50, .12),
  ];
  static const _ghostDelay = <double>[0, 1.1, 2.2, .6, 1.7];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = rect.center;

    // Background: radial glow.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          math.max(size.width, size.height) * .72,
          dark
              ? const [Color(0xFF1B2550), Color(0xFF141A33), Color(0xFF12141F)]
              : const [Color(0xFFDFE6FF), Color(0xFFEEF2FF), Color(0xFFF5F7FD)],
          dark ? const [0, .45, 1] : const [0, .5, 1],
        ),
    );

    // Two slow dashed orbits (150 / 250 wide, 40 s / 60 s a turn).
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = dark ? const Color(0x388EA6FF) : const Color(0x381E5BFF);
    _dashedCircle(canvas, c, 75, orbit, t / 40 * 2 * math.pi);
    _dashedCircle(canvas, c, 125, orbit, t / 60 * 2 * math.pi);

    // Three waves (64 -> x3.6, 3.6 s, 1.2 s apart).
    const wave = Cubic(.15, .6, .3, 1);
    final waveColor = dark ? const Color(0xFF23E0D8) : const Color(0xFF14A3A0);
    for (var i = 0; i < 3; i++) {
      final raw = ((t - i * 1.2) % 3.6) / 3.6;
      if (t == 0 && i > 0) continue;
      final v = wave.transform(raw.clamp(0.0, 1.0));
      final scale = .9 + (3.6 - .9) * v;
      final alpha = (.8 * (1 - v)) * .55 / .8;
      canvas.drawCircle(
        c,
        32 * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = waveColor.withValues(alpha: t == 0 ? .3 : alpha),
      );
    }

    // The line to the found phone (mock path M153 106 Q 215 95 257 51 in a
    // 306 x 212 box).
    final target = Offset(size.width * _ghosts[1].dx, size.height * _ghosts[1].dy);
    final lineP = (found / .6).clamp(0.0, 1.0);
    if (lineP > 0) {
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..quadraticBezierTo(size.width * 215 / 306, size.height * 95 / 212, target.dx, target.dy);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(c, target, const [Color(0xFF23E0D8), Color(0xFFE74BC8)]);
      for (final m in path.computeMetrics()) {
        final end = m.length * lineP;
        var d = 0.0;
        while (d < end) {
          canvas.drawPath(m.extractPath(d, math.min(d + 6, end)), paint);
          d += 12;
        }
      }
    }

    // Five grey phones floating (4 s), fading .35 <-> .85.
    final ghostBg = dark ? const Color(0xFF2A3050) : const Color(0xFFDFE3F0);
    final ghostFg = dark ? const Color(0xFF59608A) : const Color(0xFF8A90AD);
    for (var i = 0; i < _ghosts.length; i++) {
      final ph = ((t - _ghostDelay[i]) % 4) / 4;
      final wave = math.sin(ph * math.pi);
      final at = Offset(size.width * _ghosts[i].dx, size.height * _ghosts[i].dy - (t == 0 ? 0 : 6 * wave));
      final pop = i == 1 && foundInitial.isNotEmpty ? ((found - .5) / .15).clamp(0.0, 1.0) : 0.0;
      final alpha = t == 0 ? .6 : .35 + .5 * wave;
      canvas.drawCircle(at, 15, Paint()..color = ghostBg.withValues(alpha: alpha));
      _icon(canvas, Icons.people_alt_rounded, at, 15, ghostFg.withValues(alpha: alpha));
      if (pop > 0) {
        final s = pop < .6 ? pop / .6 * 1.25 : 1.25 - (pop - .6) / .4 * .25;
        final r = 15 * s;
        canvas.drawCircle(
          at,
          r,
          Paint()..shader = ui.Gradient.linear(at - Offset(r, r), at + Offset(r, r), AddUi283.purpleGradient.colors),
        );
        _text(canvas, foundInitial, at, 13 * s, FontWeight.w600);
      }
    }

    // Me: 60 circle, breathing glow ring (3.6 s).
    final b = t == 0 ? 0.0 : math.sin(((t % 3.6) / 3.6) * math.pi);
    canvas.drawCircle(c, 30 + 6 + 6 * b, Paint()..color = const Color(0xFF23E0D8).withValues(alpha: .12 - .06 * b));
    canvas.drawCircle(c, 30, Paint()..shader = ui.Gradient.linear(c - const Offset(30, 30), c + const Offset(30, 30), AddUi283.meGradient.colors));
    if (meInitial.isNotEmpty) {
      _text(canvas, meInitial, c, 22, FontWeight.w700);
    } else {
      _icon(canvas, Icons.person_rounded, c, 26, Colors.white);
    }
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Paint paint, double turn) {
    const dashes = 48;
    const step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      final a = turn + i * step;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, step * .5, false, paint);
    }
  }

  void _text(Canvas canvas, String text, Offset at, double size, FontWeight weight) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, fontWeight: weight, color: Colors.white, fontFamily: LocalLinkLook.fontFamily),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  void _icon(Canvas canvas, IconData icon, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontSize: size, fontFamily: icon.fontFamily, package: icon.fontPackage, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ScenePainter283 old) =>
      old.t != t ||
      old.dark != dark ||
      old.found != found ||
      old.foundInitial != foundInitial ||
      old.meInitial != meInitial;
}

/// Mock `.scan`: the big gradient "Scan QR code" button at the bottom.
class ScanButton283 extends StatelessWidget {
  final VoidCallback? onPressed;
  const ScanButton283({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final off = onPressed == null;
    return Opacity(
      opacity: off ? .55 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinkKit.brandGradient,
          borderRadius: BorderRadius.circular(26),
          boxShadow: off ? null : const [BoxShadow(color: Color(0x591E5BFF), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('add_contact_scan_283'),
            borderRadius: BorderRadius.circular(26),
            onTap: onPressed,
            child: const SizedBox(
              height: 52,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.qr_code_scanner, size: 22, color: Colors.white),
                SizedBox(width: 10),
                Text('Scan QR code', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Test hook: true when [color] is one of the two mock avatar gradients.
@visibleForTesting
bool isMockAvatarGradient283(LinearGradient g) => g == AddUi283.blueGradient || g == AddUi283.purpleGradient;
