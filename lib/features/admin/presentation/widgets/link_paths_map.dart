import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which link one map edge represents. Drives colour + placement sector.
enum LinkTag { server, wifiDirect, mesh, localWifi }

/// One device on the link map.
class LinkNode {
  final String id;
  final String label;
  final LinkTag tag;

  const LinkNode({
    required this.id,
    required this.label,
    required this.tag,
  });
}

/// Tints matching the app’s transport language (chips / dividers).
const kLinkTagColors = <LinkTag, Color>{
  LinkTag.server: Color(0xFF2E9B5B),
  LinkTag.wifiDirect: Color(0xFFE8A317),
  LinkTag.mesh: Color(0xFF7C5CDB),
  LinkTag.localWifi: Color(0xFF2AA9A0),
};

String linkTagLabel(LinkTag tag) => switch (tag) {
      LinkTag.server => 'Server',
      LinkTag.wifiDirect => 'Wi-Fi Direct',
      LinkTag.mesh => 'Mesh',
      LinkTag.localWifi => 'Local Wi-Fi',
    };

/// Bundle 134: “Link paths” — the offline admin link map. Shows one blue hub
/// (this phone), the server cloud, and every known device as a labelled node
/// with a colour-coded arc by transport. Pure painting, no dependencies, and
/// deterministic placement (sorted by id) so the map doesn’t reshuffle on
/// each poll tick.
class LinkPathsMap extends StatelessWidget {
  final List<LinkNode> nodes;
  final bool serverOnline;

  const LinkPathsMap({super.key, required this.nodes, required this.serverOnline});

  @override
  Widget build(BuildContext context) {
    const tags = LinkTag.values;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 300,
            color: scheme.surfaceContainerHigh.withOpacity(0.55),
            child: CustomPaint(
              painter: _LinkPathsPainter(
                nodes: nodes,
                serverOnline: serverOnline,
                labelColor: scheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final tag in tags)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                        color: kLinkTagColors[tag], shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(linkTagLabel(tag),
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withOpacity(0.72))),
              ]),
          ],
        ),
      ],
    );
  }
}

class _LinkPathsPainter extends CustomPainter {
  final List<LinkNode> nodes;
  final bool serverOnline;
  final Color labelColor;

  _LinkPathsPainter({
    required this.nodes,
    required this.serverOnline,
    required this.labelColor,
  });

  static const _selfRadius = 24.0;
  static const _nodeRadius = 11.0;

  Offset _self(Size size) => Offset(size.width * 0.47, size.height * 0.66);
  Offset _server(Size size) => Offset(size.width * 0.15, size.height * 0.18);

  /// Deterministic placement: yellow WD fan to the left, purple mesh chains
  /// up-right, teal LAN down-right, green cloud near the server.
  Map<String, Offset> _placements(Size size) {
    final sorted = [...nodes]..sort((a, b) => a.id.compareTo(b.id));
    final byTag = <LinkTag, List<LinkNode>>{
      for (final tag in LinkTag.values)
        tag: [for (final n in sorted) if (n.tag == tag) n],
    };
    final result = <String, Offset>{};
    final s = _self(size);
    final sv = _server(size);

    // sector definitions: (startAngleDeg, endAngleDeg) with screen coords
    // (0deg = right, 90deg = down, 180deg = left, 270deg = up).
    const sectors = <LinkTag, (double, double)>{
      LinkTag.wifiDirect: (150, 245),
      LinkTag.mesh: (295, 348),
      LinkTag.localWifi: (18, 68),
      LinkTag.server: (0, 0), // placed around the cloud instead
    };
    for (final tag in LinkTag.values) {
      final list = byTag[tag]!;
      if (list.isEmpty) continue;
      for (var i = 0; i < list.length; i++) {
        if (tag == LinkTag.server) {
          // Small fan hugging the cloud edge.
          final angle = (-55 + (88 / math.max(1, list.length - 1)) * i) *
              math.pi /
              180;
          final ring = 62 + 18 * (i % 3);
          result[list[i].id] =
              Offset(sv.dx + math.cos(angle) * ring, sv.dy + math.sin(angle) * ring * 0.75 + 4);
          continue;
        }
        final (startDeg, endDeg) = sectors[tag]!;
        final span = (endDeg - startDeg) / math.max(1, list.length - 1);
        final jitter = ((list[i].id.hashCode % 21) - 10) / 10.0;
        final angleDeg = startDeg + span * i + jitter * 4;
        final angle = angleDeg * math.pi / 180;
        final rings = tag == LinkTag.mesh ? 3 : 2;
        final ringBase = tag == LinkTag.mesh ? 74.0 : 92.0;
        final ringStep = tag == LinkTag.mesh ? 30.0 : 44.0;
        final r = ringBase + ringStep * (i % rings) + jitter * 6;
        final x = s.dx + math.cos(angle) * r;
        final y = s.dy + math.sin(angle) * r * 0.82;
        result[list[i].id] = Offset(
            x.clamp(16.0, size.width - 16.0), y.clamp(16.0, size.height - 34.0));
      }
    }
    return result;
  }

  Path _arc(Offset from, Offset to, {double bend = 0.22}) {
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.max(1.0, math.sqrt(dx * dx + dy * dy));
    final nx = -dy / len;
    final ny = dx / len;
    final control = Offset(mid.dx + nx * len * bend, mid.dy + ny * len * bend);
    return Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
  }

  void _stroke(Canvas canvas, Path path, Color color, double width) {
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round);
  }

  void _dashedServerLink(Canvas canvas, Offset from, Offset to) {
    // Offline server: alternating grey / red dashes, unmistakable.
    final path = _arc(from, to, bend: 0.10);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final total = metric.length;
      const seg = 9.0;
      var d = 0.0;
      var red = false;
      while (d < total) {
        final end = math.min(total, d + seg);
        _stroke(canvas, metric.extractPath(d, end),
            red ? const Color(0xFFD6453B) : const Color(0xFF9AA7B8), 2.6);
        d = end + 5.5;
        red = !red;
      }
    }
  }

  void _grid(Canvas canvas, Size size) {
    final paint = Paint()..color = labelColor.withOpacity(0.06);
    const gap = 22.0;
    for (var y = gap; y < size.height; y += gap) {
      for (var x = gap; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _grid(canvas, size);
    final s = _self(size);
    final sv = _server(size);
    final place = _placements(size);
    final byId = {for (final n in nodes) n.id: n};

    // ---- edges ---------------------------------------------------------
    // Server link from self (dashed red/grey when down, green when up).
    final serverEdge = _arc(s, sv, bend: 0.10);
    if (serverOnline) {
      _stroke(canvas, serverEdge, kLinkTagColors[LinkTag.server]!, 2.6);
    } else {
      _dashedServerLink(canvas, s, sv);
    }

    // Green arcs: server → the devices it reaches.
    for (final n in nodes) {
      if (n.tag != LinkTag.server) continue;
      final pos = place[n.id]!;
      _stroke(
          canvas,
          _arc(sv, pos, bend: 0.16),
          kLinkTagColors[LinkTag.server]!.withOpacity(0.85),
          1.6);
    }

    // Purple mesh CHAINS: sorted links node→node marching inward to self.
    final meshNodes = [
      for (final n in nodes) if (n.tag == LinkTag.mesh) place[n.id]!
    ];
    if (meshNodes.isNotEmpty) {
      meshNodes.sort((a, b) => (b - s).distance.compareTo((a - s).distance));
      var from = meshNodes.first;
      for (var i = 1; i < meshNodes.length; i++) {
        _stroke(canvas, _arc(from, meshNodes[i], bend: 0.10),
            kLinkTagColors[LinkTag.mesh]!.withOpacity(0.75), 1.8);
        from = meshNodes[i];
      }
      _stroke(canvas, _arc(from, s, bend: 0.12),
          kLinkTagColors[LinkTag.mesh]!.withOpacity(0.75), 1.8);
    }

    // Yellow / teal arcs straight: self → device.
    for (final n in nodes) {
      if (n.tag == LinkTag.mesh || n.tag == LinkTag.server) continue;
      final color = kLinkTagColors[n.tag]!;
      _stroke(canvas, _arc(s, place[n.id]!, bend: 0.20),
          color.withOpacity(0.80), 1.9);
    }

    // ---- server cloud --------------------------------------------------
    _glassyCircle(canvas, sv, 26, const Color(0xFFE6F1FF),
        const Color(0xFF3B82C4));
    _text(canvas, Icons.cloud_outlined, sv,
        size: 26, color: const Color(0xFF3B82C4));
    _label(canvas, sv + const Offset(0, 30), 'Server',
        strong: true);
    _label(canvas, sv + const Offset(0, 46), serverOnline ? 'online' : 'offline',
        strong: false, tiny: true);

    // ---- device nodes + labels ----------------------------------------
    for (final n in nodes) {
      final pos = place[n.id]!;
      final color = kLinkTagColors[n.tag]!;
      _glassyCircle(canvas, pos, _nodeRadius, color.withOpacity(0.25),
          color.withOpacity(0.9));
      _text(canvas, Icons.person, pos,
          size: 12, color: Color.lerp(color, Colors.black, 0.25)!);
      _label(canvas, pos + const Offset(0, _nodeRadius + 11), n.label);
    }

    // ---- self hub ------------------------------------------------------
    final hub = Paint()..color = const Color(0xFF2F6BFF);
    canvas.drawCircle(s, _selfRadius + 5, Paint()..color = Colors.white);
    canvas.drawCircle(s, _selfRadius, hub);
    _text(canvas, Icons.person, s, size: 26, color: Colors.white);
    _label(canvas, s + const Offset(0, _selfRadius + 14), 'This phone',
        strong: true);
  }

  void _glassyCircle(Canvas canvas, Offset c, double r, Color fill, Color ring) {
    canvas.drawCircle(c, r + 2.5, Paint()..color = Colors.white);
    canvas.drawCircle(c, r, Paint()..color = fill);
    canvas.drawCircle(c, r, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = 1.6);
  }

  void _text(Canvas canvas, IconData icon, Offset center,
      {required double size, required Color color}) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
            inherit: false,
            fontSize: size,
            color: color,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _label(Canvas canvas, Offset center, String text,
      {bool strong = false, bool tiny = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            inherit: false,
            fontSize: tiny ? 8.5 : (strong ? 11.5 : 9.5),
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: labelColor.withOpacity(strong ? 0.9 : 0.75)),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 92);
    final pad = const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    final pill = Rect.fromCenter(
        center: center,
        width: tp.width + pad.horizontal,
        height: tp.height + pad.vertical);
    canvas.drawRRect(
        RRect.fromRectAndRadius(pill, const Radius.circular(6)),
        Paint()..color = Colors.white.withOpacity(0.85));
    tp.paint(
        canvas,
        center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_LinkPathsPainter old) =>
      old.nodes.length != nodes.length ||
      old.serverOnline != serverOnline ||
      old.nodes.map((e) => e.tag).join(',') != nodes.map((e) => e.tag).join(',');
}
