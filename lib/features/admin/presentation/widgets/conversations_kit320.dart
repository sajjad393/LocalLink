import 'package:flutter/material.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';

/// Bundle 320 (TODO_320, mock `n320/requests_chat_mock.html`): the small
/// parts of the one-list Conversations page and the calmer chat viewer.
/// One status line (a dot + plain words), one button per row, filter chips,
/// and the grey shimmer used while a chat is loading / still coming.

/// The colour of a row's status line.
enum Tone320 { blue, orange, green, grey }

class StatusLine320 extends StatelessWidget {
  const StatusLine320(this.text, this.tone, {super.key, this.icon, this.pulse = false});

  final String text;
  final Tone320 tone;

  /// A small icon instead of the dot (the lock of a kept copy).
  final IconData? icon;

  /// Orange "waiting" dot breathes (phones with animations on only).
  final bool pulse;

  static Color colorOf(K307 k, Tone320 t) => switch (t) {
        Tone320.blue => k.blueText,
        Tone320.orange => k.orange,
        Tone320.green => k.green,
        Tone320.grey => k.grey,
      };

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final color = colorOf(k, tone);
    final dot = switch (tone) {
      Tone320.blue => k.blue,
      Tone320.orange => k.orange,
      Tone320.green => K307.ok,
      Tone320.grey => k.grey2,
    };
    // A plain grey line ("42 messages · 1 Nov", "Cancelled · 14 Nov") has no dot.
    final Widget? lead = icon != null
        ? Icon(icon, size: 14, color: k.grey)
        : (tone == Tone320.grey ? null : _Dot320(color: dot, pulse: pulse && Motion307.loops(context)));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (lead != null) ...[
        Padding(padding: EdgeInsets.only(top: icon != null ? 2 : 5), child: lead),
        const SizedBox(width: 6),
      ],
      // Full words on every phone (no "..."): the line wraps.
      Flexible(child: Text(text, style: k.text(13, FontWeight.w500, icon != null ? k.grey : color, 1.3))),
    ]);
  }
}

class _Dot320 extends StatefulWidget {
  const _Dot320({required this.color, required this.pulse});
  final Color color;
  final bool pulse;

  @override
  State<_Dot320> createState() => _Dot320State();
}

class _Dot320State extends State<_Dot320> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle));
    final c = _c;
    if (c == null) return dot;
    return FadeTransition(opacity: Tween<double>(begin: 1, end: 0.35).animate(c), child: dot);
  }
}

/// The one button at the end of a row: Open (green), New / Get chat (blue
/// tonal).
enum Pill320 { open, tonal }

class ActionPill320 extends StatelessWidget {
  const ActionPill320(this.label, this.kind, {super.key, required this.onTap, this.icon});

  final String label;
  final Pill320 kind;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final bg = kind == Pill320.open ? k.greenSoft : k.blueSoft;
    final fg = kind == Pill320.open ? k.green : k.blueText;
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 5)],
              Text(label, style: k.text(13.5, FontWeight.w700, fg, 1.2)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// All / Coming / Ready / Kept with counts (they wrap on a small phone).
class FilterChips320 extends StatelessWidget {
  const FilterChips320({super.key, required this.labels, required this.counts, required this.selected, required this.onSelected});

  final List<String> labels;
  final List<int> counts;
  final int selected;
  final ValueChanged<int> onSelected;

  static const List<String> names = ['all', 'coming', 'ready', 'kept'];

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < labels.length; i++)
        Material(
          key: ValueKey('conv320_filter_${names[i]}'),
          color: i == selected ? k.ink : k.card,
          shape: StadiumBorder(side: BorderSide(color: i == selected ? k.ink : k.dash)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => onSelected(i),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(labels[i], style: k.text(13, FontWeight.w600, i == selected ? k.bg : k.grey, 1.2)),
                  const SizedBox(width: 6),
                  Text('${counts[i]}', style: k.text(12, FontWeight.w700, i == selected ? k.bg : k.grey, 1.2)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Grey bubble shapes (left / right) while the chat loads or the rest of it
/// is still on the way. The shimmer runs only with animations on.
class BubbleSkeleton320 extends StatelessWidget {
  const BubbleSkeleton320({super.key, this.rows = 3});

  final int rows;

  static const List<(double, bool)> _shape = [
    (0.58, false), (0.40, true), (0.66, false), (0.34, true), (0.50, false), (0.44, true),
  ];

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    return Shimmer320(
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 320.0;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < rows; i++)
            Align(
              alignment: _shape[i % _shape.length].$2 ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: w * _shape[i % _shape.length].$1,
                height: 34,
                margin: const EdgeInsets.symmetric(vertical: 4),
                // Light: a bit darker than the page so the shapes show (mutedSoft is near the bg).
                decoration: BoxDecoration(
                    color: k.dark ? k.mutedSoft : const Color(0xFFE4E7EC), borderRadius: BorderRadius.circular(17)),
              ),
            ),
        ]);
      }),
    );
  }
}

/// The 307 shimmer light for any child.
class Shimmer320 extends StatefulWidget {
  const Shimmer320({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer320> createState() => _Shimmer320State();
}

class _Shimmer320State extends State<Shimmer320> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c == null && Motion307.loops(context)) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final c = _c;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment(-1 + 3 * c.value - 1, 0),
          end: Alignment(3 * c.value - 1, 0),
          colors: [Colors.transparent, Colors.white.withValues(alpha: k.dark ? 0.06 : 0.55), Colors.transparent],
        ).createShader(r),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// A section label in capitals ("NOW", "CHATS") - the mock's small grey head.
class SmallHead320 extends StatelessWidget {
  const SmallHead320(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Text(text.toUpperCase(), style: k.text(13, FontWeight.w700, k.grey, 1.2, 0.4)),
    );
  }
}
