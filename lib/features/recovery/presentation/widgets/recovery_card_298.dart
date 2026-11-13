import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Bundle 298 (I): the picture sent to WhatsApp with a new recovery code
/// (before: only a text line). Drawn by code (no asset, no network), so it
/// looks the same on every phone:
///
/// - dark navy card, soft blue / cyan glow (the LinkUp colours);
/// - the LinkUp rings + "LinkUp";
/// - "RECOVERY CODE", the @username, the code big in a glowing box;
/// - "Keep this private" and how to use it, the date it was made.
///
/// Only the code goes with it as the caption (so it can be copied).
abstract final class RecoveryCard298 {
  static const Size size = Size(1080, 1080);
  static const String font = 'Roboto216';

  static const Color _blue = Color(0xFF2F7BF6);
  static const Color _cyan = Color(0xFF22D3EE);

  /// "14 Nov 2026".
  static String day(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  /// The code on two lines when it has 4 groups ("AAAAA-BBBBB" / "CCCCC-DDDDD").
  static List<String> lines(String code) {
    final parts = code.trim().toUpperCase().split('-');
    if (parts.length == 4) return ['${parts[0]}-${parts[1]}', '${parts[2]}-${parts[3]}'];
    return [code.trim().toUpperCase()];
  }

  static ui.Paragraph _text(String text, double fontSize, Color color,
      {FontWeight weight = FontWeight.w400,
      double spacing = 0,
      double width = 1000,
      TextAlign align = TextAlign.left}) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: align, maxLines: 3))
      ..pushStyle(ui.TextStyle(
        fontFamily: font,
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        height: 1.25,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      ))
      ..addText(text);
    return b.build()..layout(ui.ParagraphConstraints(width: width));
  }

  /// The LinkUp rings (like assets/brand/splash_logo.png).
  static void _logo(Canvas c, Offset centre, double h) {
    final r = h / 2 - h * 0.12;
    final stroke = h * 0.24;
    final shader = ui.Gradient.linear(centre + Offset(-h, -h / 2), centre + Offset(h, h / 2), const [_blue, _cyan]);
    final p = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    c.drawCircle(centre + Offset(-r * 0.78, 0), r, p);
    c.drawCircle(centre + Offset(r * 0.78, 0), r, p);
  }

  static void paint(Canvas c, Size s, {required String code, String username = '', DateTime? made}) {
    final k = s.width / size.width;
    c.save();
    c.scale(k);
    const w = 1080.0, h = 1080.0;
    final full = Rect.fromLTWH(0, 0, w, h);
    // Background + glow.
    c.drawRect(
        full,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, const Offset(w, h), const [Color(0xFF0A1022), Color(0xFF0E1A33)]));
    void glow(Offset at, double r, Color col) => c.drawCircle(
        at, r, Paint()..shader = ui.Gradient.radial(at, r, [col.withValues(alpha: .34), col.withValues(alpha: 0)]));
    glow(const Offset(140, 120), 520, _blue);
    glow(const Offset(980, 980), 560, _cyan);
    // Fine dots, like the map background.
    final dot = Paint()..color = Colors.white.withValues(alpha: .05);
    for (var y = 36.0; y < h; y += 36) {
      for (var x = 36.0; x < w; x += 36) {
        c.drawCircle(Offset(x, y), 1.6, dot);
      }
    }

    // Brand row.
    _logo(c, const Offset(124, 120), 64);
    c.drawParagraph(_text('LinkUp', 46, Colors.white, weight: FontWeight.w700), const Offset(196, 90));

    // Title pill.
    final pillText = _text('RECOVERY CODE', 24, _cyan, weight: FontWeight.w700, spacing: 4);
    final pill =
        RRect.fromRectAndRadius(Rect.fromLTWH(80, 230, pillText.longestLine + 56, 56), const Radius.circular(28));
    c.drawRRect(pill, Paint()..color = _cyan.withValues(alpha: .12));
    c.drawRRect(
        pill,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _cyan.withValues(alpha: .45));
    c.drawParagraph(pillText, Offset(108, 230 + (56 - pillText.height) / 2));

    // Who.
    final who = username.trim().replaceFirst('@', '');
    c.drawParagraph(_text(who.isEmpty ? 'My LinkUp account' : '@$who', 52, Colors.white, weight: FontWeight.w600),
        const Offset(80, 318));

    // Code box with a gradient edge and glow.
    final box = RRect.fromRectAndRadius(const Rect.fromLTWH(80, 420, w - 160, 300), const Radius.circular(36));
    c.drawRRect(
        box.inflate(10),
        Paint()
          ..color = _blue.withValues(alpha: .20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28));
    c.drawRRect(box, Paint()..color = const Color(0xFF121E38));
    c.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..shader = ui.Gradient.linear(box.outerRect.topLeft, box.outerRect.bottomRight, const [_blue, _cyan]));
    final ls = lines(code);
    final size0 = ls.length == 1 ? (ls.first.length > 16 ? 56.0 : 80.0) : 92.0;
    final paras = [
      for (final l in ls)
        _text(l, size0, Colors.white, weight: FontWeight.w700, spacing: 6, width: w - 200, align: TextAlign.center),
    ];
    final total = paras.fold<double>(0, (a, p) => a + p.height) + (paras.length - 1) * 8;
    var y = 420 + (300 - total) / 2;
    for (final p in paras) {
      c.drawParagraph(p, Offset(100, y));
      y += p.height + 8;
    }

    // Keep private.
    const lockAt = Offset(98, 800);
    final lock = Paint()
      ..color = const Color(0xFFFBBF24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: lockAt + const Offset(0, 10), width: 34, height: 28), const Radius.circular(6)),
        lock);
    c.drawArc(
        Rect.fromCenter(center: lockAt + const Offset(0, -6), width: 22, height: 26), math.pi, math.pi, false, lock);
    c.drawParagraph(
        _text('Keep this private', 34, const Color(0xFFFDE68A), weight: FontWeight.w700), const Offset(140, 780));
    c.drawParagraph(
        _text('Anyone with this code can reset your password. LinkUp will never ask for it.', 27,
            Colors.white.withValues(alpha: .72),
            width: w - 220),
        const Offset(140, 828));

    // Footer.
    c.drawLine(
        const Offset(80, 950),
        const Offset(w - 80, 950),
        Paint()
          ..color = Colors.white.withValues(alpha: .10)
          ..strokeWidth = 2);
    c.drawParagraph(_text('Use it in LinkUp: Login > Forgot password', 25, Colors.white.withValues(alpha: .62)),
        const Offset(80, 976));
    final when = _text('Made ${day(made ?? DateTime.now())}', 25, Colors.white.withValues(alpha: .62),
        width: 400, align: TextAlign.right);
    c.drawParagraph(when, const Offset(w - 80 - 400, 976));
    c.restore();
  }

  /// The PNG bytes of the card (full 1080 x 1080).
  static Future<Uint8List> png({required String code, String username = '', DateTime? made}) async {
    final rec = ui.PictureRecorder();
    paint(Canvas(rec), size, code: code, username: username, made: made);
    final pic = rec.endRecording();
    final img = await pic.toImage(size.width.toInt(), size.height.toInt());
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      img.dispose();
      pic.dispose();
    }
  }
}

/// The card on screen (mock / tests).
class RecoveryCardView298 extends StatelessWidget {
  const RecoveryCardView298({super.key, required this.code, this.username = '', this.made});

  final String code;
  final String username;
  final DateTime? made;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(painter: _CardPainter(code, username, made)),
      );
}

class _CardPainter extends CustomPainter {
  _CardPainter(this.code, this.username, this.made);

  final String code;
  final String username;
  final DateTime? made;

  @override
  void paint(Canvas canvas, Size size) =>
      RecoveryCard298.paint(canvas, size, code: code, username: username, made: made);

  @override
  bool shouldRepaint(covariant _CardPainter old) => old.code != code || old.username != username || old.made != made;
}
