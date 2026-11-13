import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';

/// Bundle 295 (F, mock 295): while the profile screen has NOTHING saved yet
/// to show, soft shimmer stands in for the photo, the name, the @username
/// and the hint line ([header] = true), or for the three boxes ([header] =
/// false). Never "LinkUp user" and never the letter L while loading.
/// Respects "reduce motion" (still grey shapes, no sweep).
class ProfileShimmer295 extends StatefulWidget {
  final bool header;
  final double radius;

  const ProfileShimmer295.header({super.key, this.radius = 52}) : header = true;
  const ProfileShimmer295.fields({super.key})
      : header = false,
        radius = 52;

  @override
  State<ProfileShimmer295> createState() => _ProfileShimmer295State();
}

class _ProfileShimmer295State extends State<ProfileShimmer295>
    with SingleTickerProviderStateMixin, LinkLoop290 {
  @override
  Duration get loopLength => const Duration(milliseconds: 1300);

  Widget _box(double? width, double height, {double? radius, bool circle = false, EdgeInsets margin = EdgeInsets.zero}) {
    final p = LinkKit.of(context);
    final base = p.isDark ? const Color(0xFF23252E) : const Color(0xFFE6E8EF);
    final glow = p.isDark ? const Color(0x17FFFFFF) : const Color(0xBFFFFFFF);
    return Container(
      width: width,
      height: height,
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: base,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius ?? height / 2),
      ),
      child: AnimatedBuilder(
        animation: loop,
        builder: (_, __) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-3 + 4 * loop.value, 0),
              end: Alignment(-1 + 4 * loop.value, 0),
              colors: [glow.withAlpha(0), glow, glow.withAlpha(0)],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.header) {
      return Column(
        key: const ValueKey('profile295_shimmer_header'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _box(widget.radius * 2, widget.radius * 2, circle: true),
          _box(150, 20, margin: const EdgeInsets.only(top: 16)),
          _box(90, 13, margin: const EdgeInsets.only(top: 9)),
          _box(120, 12, margin: const EdgeInsets.only(top: 9)),
        ],
      );
    }
    return Column(
      key: const ValueKey('profile295_shimmer_fields'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          _box(double.infinity, 56, radius: 16, margin: EdgeInsets.only(bottom: i < 2 ? 8 : 0)),
      ],
    );
  }
}
