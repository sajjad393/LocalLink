import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bundle 290 (PLAN_3.0.90 Phase 2, mocks 283/284/286/287/288): ONE set of
/// colours and parts for every new screen, so every phone shows the same
/// design. Dark = the colours sampled from the owner's screenshots; light =
/// the light version of the same design.
@immutable
class LinkPalette {
  final bool isDark;
  final Color screen;
  final Color card;
  final List<BoxShadow> cardShadow;
  final Color field;
  final Color fieldFocus;
  final Color focus;
  final Color text;
  final Color muted;
  final Color hint;
  final Color link;
  final Color ok;
  final Color okBg;
  final Color error;
  final Color errBg;
  final Color errBorder;
  final Color errText;
  final Color teal;
  final Color tealBg;
  final Color orange;
  final Color orangeBg;
  final Color note;
  final Color noteText;
  final List<BoxShadow> noteShadow;
  final Color segTrack;
  final Color segBorder;
  final Color line;
  final Color stepBg;
  final Color stepFg;
  final Color waitText;
  final Color meterOff;
  final Color meterOn;
  final Color outlineBorder;
  final Color outlineText;
  final Color outlineBg;

  const LinkPalette._({
    required this.isDark,
    required this.screen,
    required this.card,
    required this.cardShadow,
    required this.field,
    required this.fieldFocus,
    required this.focus,
    required this.text,
    required this.muted,
    required this.hint,
    required this.link,
    required this.ok,
    required this.okBg,
    required this.error,
    required this.errBg,
    required this.errBorder,
    required this.errText,
    required this.teal,
    required this.tealBg,
    required this.orange,
    required this.orangeBg,
    required this.note,
    required this.noteText,
    required this.noteShadow,
    required this.segTrack,
    required this.segBorder,
    required this.line,
    required this.stepBg,
    required this.stepFg,
    required this.waitText,
    required this.meterOff,
    required this.meterOn,
    required this.outlineBorder,
    required this.outlineText,
    required this.outlineBg,
  });

  static const LinkPalette dark = LinkPalette._(
    isDark: true,
    screen: Color(0xFF121318),
    card: Color(0xFF1A1B22),
    cardShadow: <BoxShadow>[],
    field: Color(0xFF1F2027),
    fieldFocus: Color(0xFF1B1D26),
    focus: Color(0xFF8EA6FF),
    text: Color(0xFFECEBF2),
    muted: Color(0xFF9497A5),
    hint: Color(0xFF8E91A0),
    link: Color(0xFFA9B8FF),
    ok: Color(0xFF86EFAC),
    okBg: Color(0x2122C55E),
    error: Color(0xFFF87171),
    errBg: Color(0x1FF87171),
    errBorder: Color(0x59F87171),
    errText: Color(0xFFFCA5A5),
    teal: Color(0xFF5EEAD4),
    tealBg: Color(0x2414A3A0),
    orange: Color(0xFFFBBF24),
    orangeBg: Color(0x24F59E0B),
    note: Color(0xFF16171D),
    noteText: Color(0xFFB5B8C5),
    noteShadow: <BoxShadow>[],
    segTrack: Color(0xFF1A1B22),
    segBorder: Color(0xFF23252F),
    line: Color(0xFF2A2D3C),
    stepBg: Color(0xFF262A3A),
    stepFg: Color(0xFFA9B8FF),
    waitText: Color(0xFF7D8090),
    meterOff: Color(0xFF2A2C36),
    meterOn: Color(0xFF22C55E),
    outlineBorder: Color(0xFF343A55),
    outlineText: Color(0xFFDBE3FF),
    outlineBg: Color(0x00000000),
  );

  static const LinkPalette light = LinkPalette._(
    isDark: false,
    screen: Color(0xFFF7F8FC),
    card: Color(0xFFFFFFFF),
    cardShadow: <BoxShadow>[BoxShadow(color: Color(0x14101828), blurRadius: 3, offset: Offset(0, 1))],
    field: Color(0xFFECEEF4),
    fieldFocus: Color(0xFFFFFFFF),
    focus: Color(0xFF1E5BFF),
    text: Color(0xFF1B1B1F),
    muted: Color(0xFF6B7080),
    hint: Color(0xFF6B7080),
    link: Color(0xFF1E5BFF),
    ok: Color(0xFF067647),
    okBg: Color(0xFFDCFCE7),
    error: Color(0xFFB42318),
    errBg: Color(0xFFFEF3F2),
    errBorder: Color(0xFFFECDCA),
    errText: Color(0xFFB42318),
    teal: Color(0xFF0F766E),
    tealBg: Color(0x1F14A3A0),
    orange: Color(0xFF9A5B06),
    orangeBg: Color(0xFFFEF3C7),
    note: Color(0xFFFFFFFF),
    noteText: Color(0xFF4B5563),
    noteShadow: <BoxShadow>[BoxShadow(color: Color(0x0F101828), blurRadius: 3, offset: Offset(0, 1))],
    segTrack: Color(0xFFECEEF4),
    segBorder: Color(0xFFE1E4EC),
    line: Color(0xFFE1E4EC),
    stepBg: Color(0xFFE3E8FF),
    stepFg: Color(0xFF1E3A8A),
    waitText: Color(0xFF9AA0B4),
    meterOff: Color(0xFFDFE2EA),
    meterOn: Color(0xFF16A34A),
    outlineBorder: Color(0xFFC7CCE0),
    outlineText: Color(0xFF1E3A8A),
    outlineBg: Color(0xFFFFFFFF),
  );

  /// The red border of a wrong field.
  Color get badBorder => isDark ? const Color(0xFFF87171) : const Color(0xFFD92D20);
}

abstract final class LinkKit {
  static LinkPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? LinkPalette.dark : LinkPalette.light;

  /// "Remove animations" is on: show a still frame (S-4).
  static bool calm(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Mock `linear-gradient(135deg,#1E5BFF,#23B5D8)`.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF1E5BFF), Color(0xFF23B5D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Mock `.btn.wa` (green).
  static const LinearGradient whatsAppGradient = LinearGradient(
    colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const List<BoxShadow> brandShadow = [
    BoxShadow(color: Color(0x591E5BFF), blurRadius: 22, offset: Offset(0, 8)),
  ];

  static const String mono = 'monospace';
}

/// A repeating 0..1 clock that stops when "Remove animations" is on or the
/// part is not on screen (TickerMode), so hidden screens use no battery.
mixin LinkLoop290<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController loop = AnimationController(vsync: this, duration: loopLength);

  Duration get loopLength;

  bool get loopWanted => true;

  void syncLoop() {
    if (!mounted) return;
    if (loopWanted && !LinkKit.calm(context)) {
      if (!loop.isAnimating) loop.repeat();
    } else {
      loop.stop();
      loop.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncLoop();
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }
}

/// Mock `.hero`: gradient icon tile with a breathing ring + title / words.
class HeroRow290 extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? below;

  const HeroRow290({super.key, required this.icon, required this.title, this.subtitle, this.below});

  @override
  State<HeroRow290> createState() => _HeroRow290State();
}

class _HeroRow290State extends State<HeroRow290> with SingleTickerProviderStateMixin, LinkLoop290 {
  @override
  Duration get loopLength => const Duration(milliseconds: 3200);

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 16),
      child: Row(children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: -6,
              top: -6,
              right: -6,
              bottom: -6,
              child: AnimatedBuilder(
                animation: loop,
                builder: (_, __) {
                  final k = 0.5 - 0.5 * math.cos(2 * math.pi * loop.value);
                  return Transform.scale(
                    scale: 1 + 0.07 * k,
                    child: Opacity(
                      opacity: 1 - 0.4 * k,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0x4723E0D8), width: 2),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinkKit.brandGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Color(0x611E5BFF), blurRadius: 22, offset: Offset(0, 8))],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 26),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(widget.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 3),
              Text(widget.subtitle!, style: TextStyle(fontSize: 12.5, height: 1.35, color: p.muted)),
            ],
            if (widget.below != null) ...[const SizedBox(height: 7), widget.below!],
          ]),
        ),
      ]),
    );
  }
}

/// Mock `.lhead`: the gradient logo badge + title + words (Log in, Create).
class LinkHead290 extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const LinkHead290({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 22),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: LinkKit.brandGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x661E5BFF), blurRadius: 26, offset: Offset(0, 10))],
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: p.muted)),
      ]),
    );
  }
}

enum LinkPillKind { on, off, idle }

/// Mock `.chip`: small live pill with a pinging dot.
class LivePill290 extends StatefulWidget {
  final String text;
  final LinkPillKind kind;

  const LivePill290({super.key, required this.text, this.kind = LinkPillKind.on});

  @override
  State<LivePill290> createState() => _LivePill290State();
}

class _LivePill290State extends State<LivePill290> with SingleTickerProviderStateMixin, LinkLoop290 {
  @override
  Duration get loopLength => const Duration(milliseconds: 1800);

  @override
  bool get loopWanted => widget.kind != LinkPillKind.idle;

  @override
  void didUpdateWidget(covariant LivePill290 oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncLoop();
  }

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final (fg, bg, dot) = switch (widget.kind) {
      LinkPillKind.on => (p.teal, p.tealBg, p.isDark ? const Color(0xFF2DD4BF) : const Color(0xFF14A3A0)),
      LinkPillKind.off => (p.orange, p.orangeBg, const Color(0xFFF59E0B)),
      LinkPillKind.idle => (p.muted, p.field, p.muted),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 7,
          height: 7,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: dot, shape: BoxShape.circle))),
            if (loopWanted)
              Positioned(
                left: -4,
                top: -4,
                right: -4,
                bottom: -4,
                child: AnimatedBuilder(
                  animation: loop,
                  builder: (_, __) => loop.isAnimating
                      ? Transform.scale(
                          scale: 0.6 + 1.6 * loop.value,
                          child: Opacity(
                            opacity: 0.9 * (1 - loop.value),
                            child: DecoratedBox(
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: dot, width: 2)),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(widget.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ),
      ]),
    );
  }
}

/// Mock `.seg`: two (or more) choices in one rounded track.
class SegmentSwitch290 extends StatelessWidget {
  final List<(String, IconData)> items;
  final int selected;
  final ValueChanged<int> onChanged;

  const SegmentSwitch290({super.key, required this.items, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.segTrack,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.segBorder),
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              selected: i == selected,
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 42,
                  decoration: i == selected
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: p.isDark ? null : Colors.white,
                          gradient: p.isDark
                              ? const LinearGradient(
                                  colors: [Color(0x4D1E5BFF), Color(0x3823B5D8)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          border: Border.all(color: p.isDark ? const Color(0x738EA6FF) : const Color(0x591E5BFF)),
                          boxShadow: p.isDark
                              ? null
                              : const [BoxShadow(color: Color(0x1F101828), blurRadius: 3, offset: Offset(0, 1))],
                        )
                      : BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.transparent)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(items[i].$2,
                        size: 17,
                        color: i == selected ? (p.isDark ? Colors.white : const Color(0xFF1E3A8A)) : p.muted),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        items[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: i == selected ? (p.isDark ? Colors.white : const Color(0xFF1E3A8A)) : p.muted,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Mock `.f`: 56 high rounded field, icon on the left, label that moves up,
/// optional tick / eye / "Match" on the right, red border when wrong.
class LinkField290 extends StatefulWidget {
  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int? maxLength;
  final bool enabled;
  final bool error;
  final Widget? trailing;
  final bool obscureText;
  final bool mono;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter> inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final bool autocorrect;
  final bool autofocus;

  const LinkField290({
    super.key,
    this.fieldKey,
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLength,
    this.enabled = true,
    this.error = false,
    this.trailing,
    this.obscureText = false,
    this.mono = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters = const [],
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.focusNode,
    this.autocorrect = false,
    this.autofocus = false,
  });

  @override
  State<LinkField290> createState() => _LinkField290State();
}

class _LinkField290State extends State<LinkField290> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant LinkField290 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _own)?.removeListener(_changed);
      _focus.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final focused = _focus.hasFocus;
    final border = widget.error ? p.badBorder : (focused ? p.focus : Colors.transparent);
    final textStyle = widget.mono
        ? TextStyle(fontFamily: LinkKit.mono, fontSize: 13.5, color: p.text, letterSpacing: 0.4)
        : widget.obscureText
            ? TextStyle(fontSize: 17, letterSpacing: 3, color: p.text)
            : TextStyle(fontSize: 15, color: p.text);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: focused ? p.fieldFocus : p.field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(children: [
        Icon(widget.icon, size: 20, color: focused ? p.focus : p.hint),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: _focus,
            enabled: widget.enabled,
            obscureText: widget.obscureText,
            autocorrect: widget.autocorrect,
            enableSuggestions: !widget.obscureText && widget.autocorrect,
            autofocus: widget.autofocus,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            textCapitalization: widget.textCapitalization,
            autofillHints: widget.autofillHints,
            inputFormatters: [
              if (widget.maxLength != null) LengthLimitingTextInputFormatter(widget.maxLength),
              ...widget.inputFormatters,
            ],
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            cursorColor: p.focus,
            style: textStyle,
            decoration: InputDecoration(
              labelText: widget.label,
              labelStyle: TextStyle(fontSize: 14.5, color: p.hint),
              floatingLabelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.focus),
              filled: false,
              isDense: true,
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: const EdgeInsets.only(top: 4, bottom: 4),
            ),
          ),
        ),
        if (widget.trailing != null) ...[const SizedBox(width: 8), widget.trailing!],
      ]),
    );
  }
}

/// Mock `.okt`: green tick (and an optional word like "Match").
class LinkOkMark290 extends StatelessWidget {
  final String? text;
  const LinkOkMark290({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.check_circle_rounded, size: 18, color: p.ok),
      if (text != null) ...[
        const SizedBox(width: 4),
        Text(text!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ok)),
      ],
    ]);
  }
}

/// The eye on a password field.
class LinkEye290 extends StatelessWidget {
  final bool hidden;
  final VoidCallback? onTap;
  const LinkEye290({super.key, required this.hidden, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Semantics(
      button: true,
      label: hidden ? 'Show password' : 'Hide password',
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: p.hint),
        ),
      ),
    );
  }
}

/// Password strength: 0 empty, 1 Weak, 2 Fair, 3 Good, 4 Strong.
int linkPasswordScore290(String password) {
  if (password.isEmpty) return 0;
  if (password.length < 8) return 1;
  var s = 1;
  if (RegExp(r'\d').hasMatch(password)) s++;
  if (RegExp(r'[a-z]').hasMatch(password) && RegExp(r'[A-Z]').hasMatch(password)) s++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(password) || password.length >= 14) s++;
  return s.clamp(1, 4);
}

String linkPasswordWord290(int score) => switch (score) {
      <= 0 => '',
      1 => 'Weak',
      2 => 'Fair',
      3 => 'Good',
      _ => 'Strong',
    };

/// Mock `.under .meter`: 4 bars + the word.
class LinkStrength290 extends StatelessWidget {
  final String password;
  const LinkStrength290({super.key = const ValueKey('link290-strength'), required this.password});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final score = linkPasswordScore290(password);
    final color = switch (score) {
      1 => p.error,
      2 => p.orange,
      _ => p.ok,
    };
    final bar = switch (score) {
      1 => p.error,
      2 => const Color(0xFFF59E0B),
      _ => p.meterOn,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
      child: Row(children: [
        Expanded(
          child: Row(children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < score ? bar : p.meterOff,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Text(linkPasswordWord290(score), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

/// Mock `.rules span`: a rule with a tick that turns green.
class LinkRule290 extends StatelessWidget {
  final String text;
  final bool ok;
  const LinkRule290(this.text, {super.key, required this.ok});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final c = ok ? p.ok : p.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ok ? Icons.check_rounded : Icons.circle_outlined, size: ok ? 15 : 11, color: c),
      const SizedBox(width: 4),
      Flexible(child: Text(text, style: TextStyle(fontSize: 12, color: c))),
    ]);
  }
}

/// Mock `.rules`: the row of rules under a field.
class LinkRules290 extends StatelessWidget {
  final List<LinkRule290> rules;
  const LinkRules290({super.key, required this.rules});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
        child: Wrap(spacing: 12, runSpacing: 6, children: rules),
      );
}

/// Mock `.under`: a line under a field (red when [error]).
class LinkUnderLine290 extends StatelessWidget {
  final String text;
  final bool error;
  const LinkUnderLine290(this.text, {super.key, this.error = false});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final c = error ? p.error : p.muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (error) ...[Icon(Icons.error_outline_rounded, size: 15, color: c), const SizedBox(width: 8)],
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, height: 1.35, color: c))),
      ]),
    );
  }
}

/// Mock `.errc`: red card above the fields.
class LinkErrorCard290 extends StatelessWidget {
  final String text;
  const LinkErrorCard290(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: p.errBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.errBorder),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, size: 18, color: p.errText),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: p.errText))),
      ]),
    );
  }
}

/// Mock `.note`: soft info box with a blue sign.
class LinkNote290 extends StatelessWidget {
  final String text;
  final IconData icon;
  const LinkNote290(this.text, {super.key, this.icon = Icons.info_outline_rounded});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: p.note, borderRadius: BorderRadius.circular(16), boxShadow: p.noteShadow),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 17, color: p.focus)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.45, color: p.noteText))),
      ]),
    );
  }
}

enum LinkStepState { todo, done, now, wait }

/// Mock `.steps`: numbered steps joined by a line.
class StepList290 extends StatelessWidget {
  final List<(String, String?, LinkStepState)> steps;
  const StepList290({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: p.cardShadow),
      child: Column(children: [
        for (var i = 0; i < steps.length; i++)
          _Step290(n: i + 1, step: steps[i], last: i == steps.length - 1, p: p),
      ]),
    );
  }
}

class _Step290 extends StatefulWidget {
  final int n;
  final (String, String?, LinkStepState) step;
  final bool last;
  final LinkPalette p;
  const _Step290({required this.n, required this.step, required this.last, required this.p});

  @override
  State<_Step290> createState() => _Step290State();
}

class _Step290State extends State<_Step290> with SingleTickerProviderStateMixin, LinkLoop290 {
  @override
  Duration get loopLength => const Duration(milliseconds: 1800);

  @override
  bool get loopWanted => widget.step.$3 == LinkStepState.now;

  @override
  void didUpdateWidget(covariant _Step290 oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncLoop();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final (title, sub, state) = widget.step;
    final done = state == LinkStepState.done;
    final now = state == LinkStepState.now;
    final circle = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: now ? null : (done ? p.okBg : p.stepBg),
        gradient: now ? LinkKit.brandGradient : null,
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 17, color: p.ok)
          : Text('${widget.n}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: now ? Colors.white : p.stepFg)),
    );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 30,
          child: Column(children: [
            Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              if (now)
                Positioned(
                  left: -5,
                  top: -5,
                  right: -5,
                  bottom: -5,
                  child: AnimatedBuilder(
                    animation: loop,
                    builder: (_, __) => loop.isAnimating
                        ? Transform.scale(
                            scale: 0.6 + 0.6 * loop.value,
                            child: Opacity(
                              opacity: 0.9 * (1 - loop.value),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0x9923B5D8), width: 2),
                                ),
                              ),
                            ),
                          )
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0x5523B5D8), width: 2),
                            ),
                          ),
                  ),
                ),
              circle,
            ]),
            if (!widget.last)
              Expanded(
                child: Container(
                  width: 2,
                  margin: const EdgeInsets.only(top: 2, bottom: 2),
                  color: done ? p.meterOn.withValues(alpha: 0.5) : p.line,
                ),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5, bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: state == LinkStepState.wait ? p.waitText : p.text)),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 12, color: p.muted)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Mock `.btn`: the gradient button. Faded (and not tappable) with no
/// [onPressed]; faded but still tappable when [dimmed] (it then says what is
/// missing). While [loading] it shows ONE small ring + [text] with a soft
/// shine, and taps do nothing.
class BrandButton290 extends StatefulWidget {
  final VoidCallback? onPressed;
  final String text;
  final IconData? icon;
  final bool loading;
  final bool dimmed;
  final Gradient gradient;
  final List<BoxShadow> shadow;

  const BrandButton290({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.loading = false,
    this.dimmed = false,
    this.gradient = LinkKit.brandGradient,
    this.shadow = LinkKit.brandShadow,
  });

  @override
  State<BrandButton290> createState() => _BrandButton290State();
}

class _BrandButton290State extends State<BrandButton290> with SingleTickerProviderStateMixin, LinkLoop290 {
  @override
  Duration get loopLength => const Duration(milliseconds: 1600);

  @override
  bool get loopWanted => widget.loading;

  @override
  void didUpdateWidget(covariant BrandButton290 oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncLoop();
  }

  @override
  Widget build(BuildContext context) {
    final faded = !widget.loading && (widget.onPressed == null || widget.dimmed);
    final tap = widget.loading ? null : widget.onPressed;
    return Semantics(
      button: true,
      enabled: tap != null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: faded ? 0.38 : 1,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(27),
            boxShadow: faded ? const [] : widget.shadow,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(27),
              onTap: tap,
              child: Stack(children: [
                if (widget.loading)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(27),
                      child: AnimatedBuilder(
                        animation: loop,
                        builder: (_, __) => DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-2.2 + 4.4 * loop.value, -0.3),
                              end: Alignment(-1.2 + 4.4 * loop.value, 0.3),
                              colors: const [Color(0x00FFFFFF), Color(0x2EFFFFFF), Color(0x00FFFFFF)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (widget.loading) ...[
                        const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                            backgroundColor: Color(0x59FFFFFF),
                          ),
                        ),
                        const SizedBox(width: 9),
                      ] else if (widget.icon != null) ...[
                        Icon(widget.icon, size: 19, color: Colors.white),
                        const SizedBox(width: 9),
                      ],
                      Flexible(
                        child: Text(
                          widget.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mock `.btn2`: the outlined second button.
class OutlineButton290 extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  const OutlineButton290({super.key, required this.onPressed, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: p.outlineBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: p.outlineBorder, width: 1.5),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          onTap: onPressed,
          child: SizedBox(
            height: 52,
            child: Center(
              child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.outlineText)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mock `.alt`: "New here? **Create an account**" (faded while busy).
class LinkAltLine290 extends StatelessWidget {
  final String lead;
  final String action;
  final VoidCallback? onTap;
  const LinkAltLine290({super.key, required this.lead, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$lead '),
              TextSpan(text: action, style: TextStyle(color: p.link, fontWeight: FontWeight.w700)),
            ]),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: p.muted),
          ),
        ),
      ),
    );
  }
}

/// Recovery code: capitals + a dash every 5 (K7QM2-XPA9T-RC4WN-E8D3F).
class RecoveryCodeFormatter290 extends TextInputFormatter {
  const RecoveryCodeFormatter290();

  static String format(String raw) {
    final clean = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final cut = clean.length > 20 ? clean.substring(0, 20) : clean;
    final b = StringBuffer();
    for (var i = 0; i < cut.length; i++) {
      if (i > 0 && i % 5 == 0) b.write('-');
      b.write(cut[i]);
    }
    return b.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = format(newValue.text);
    // Keep the caret after the same number of letters.
    final before = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .length;
    var at = 0;
    var seen = 0;
    while (at < text.length && seen < before) {
      if (text[at] != '-') seen++;
      at++;
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at));
  }
}

bool recoveryCodeLooksRight290(String text) =>
    RegExp(r'^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$').hasMatch(text.trim().toUpperCase());
