import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart' show QrCode, QrErrorCorrectLevel, QrImage;
import 'package:locallink/features/recovery/presentation/widgets/recovery_card_298.dart';

/// Bundle 299 (Q): the picture sent when a QR code is shared (My QR code,
/// group Invite with QR). Same look as the 298 recovery card: dark navy,
/// blue / cyan glow, the LinkUp rings, a title pill, who it is, the QR big
/// on white, how to use it and a footer. Drawn by code (no asset, no
/// network) so it is the same on every phone. 1080 x 1350 (portrait, the
/// shape WhatsApp shows biggest).
enum QrCardKind299 { contact, group }

abstract final class QrShareCard299 {
  static const Size size = Size(1080, 1350);
  static const String font = RecoveryCard298.font;

  static const Color _blue = Color(0xFF2F7BF6);
  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _qrDark = Color(0xFF0E1A33);

  static String pillFor(QrCardKind299 k) => k == QrCardKind299.contact ? 'ADD ME ON LINKUP' : 'JOIN MY GROUP';

  static List<String> stepsFor(QrCardKind299 k) => k == QrCardKind299.contact
      ? const ['Open LinkUp', 'Tap Scan QR code', 'Point at this code, or pick this picture']
      : const ['Open LinkUp near a member', 'Tap Join group with QR', 'Point at this code'];

  static ui.Paragraph _text(String text, double fontSize, Color color,
      {FontWeight weight = FontWeight.w400,
      double spacing = 0,
      double width = 1000,
      TextAlign align = TextAlign.left,
      int maxLines = 1}) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: align, maxLines: maxLines, ellipsis: '…'))
      ..pushStyle(ui.TextStyle(
        fontFamily: font,
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        height: 1.25,
      ))
      ..addText(text);
    return b.build()..layout(ui.ParagraphConstraints(width: width));
  }

  static void _logo(Canvas c, Offset centre, double h) {
    final r = h / 2 - h * 0.12;
    final p = Paint()
      ..shader = ui.Gradient.linear(centre + Offset(-h, -h / 2), centre + Offset(h, h / 2), const [_blue, _cyan])
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.24;
    c.drawCircle(centre + Offset(-r * 0.78, 0), r, p);
    c.drawCircle(centre + Offset(r * 0.78, 0), r, p);
  }

  static bool _finder(int r, int c, int n) => (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);

  /// The QR: soft round squares, round finder eyes with a blue middle (the
  /// group QR look, mock 36). Quiet zone is the white box around it.
  static void _qr(Canvas c, Rect at, String data) {
    final img = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.Q));
    final n = img.moduleCount;
    final cell = at.width / n;
    final dark = Paint()..color = _qrDark;
    final white = Paint()..color = Colors.white;
    final blue = Paint()..color = _blue;
    for (var r = 0; r < n; r++) {
      for (var col = 0; col < n; col++) {
        if (_finder(r, col, n) || !img.isDark(r, col)) continue;
        c.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(at.left + col * cell, at.top + r * cell, cell + .4, cell + .4), Radius.circular(cell * .2)),
            dark);
      }
    }
    void eye(int r, int col) {
      final x = at.left + col * cell, y = at.top + r * cell;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 7 * cell, 7 * cell), Radius.circular(cell * 1.7)), dark);
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + cell, y + cell, 5 * cell, 5 * cell), Radius.circular(cell * 1.15)),
          white);
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + 2 * cell, y + 2 * cell, 3 * cell, 3 * cell), Radius.circular(cell * .8)),
          blue);
    }

    eye(0, 0);
    eye(0, n - 7);
    eye(n - 7, 0);
  }

  static void paint(
    Canvas c,
    Size s, {
    required QrCardKind299 kind,
    required String data,
    required String name,
    String sub = '',
    ui.Image? photo,
    DateTime? made,
  }) {
    final k = s.width / size.width;
    c.save();
    c.scale(k);
    const w = 1080.0, h = 1350.0;
    c.drawRect(
        const Rect.fromLTWH(0, 0, w, h),
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, const Offset(w, h), const [Color(0xFF0A1022), Color(0xFF0E1A33)]));
    void glow(Offset at, double r, Color col) => c.drawCircle(
        at, r, Paint()..shader = ui.Gradient.radial(at, r, [col.withValues(alpha: .34), col.withValues(alpha: 0)]));
    glow(const Offset(140, 120), 560, _blue);
    glow(const Offset(980, 1240), 600, _cyan);
    final dot = Paint()..color = Colors.white.withValues(alpha: .05);
    for (var y = 36.0; y < h; y += 36) {
      for (var x = 36.0; x < w; x += 36) {
        c.drawCircle(Offset(x, y), 1.6, dot);
      }
    }

    // Brand row + pill on the right.
    _logo(c, const Offset(124, 112), 64);
    c.drawParagraph(_text('LinkUp', 46, Colors.white, weight: FontWeight.w700), const Offset(196, 82));
    final pillText = _text(pillFor(kind), 23, _cyan, weight: FontWeight.w700, spacing: 3.5);
    final pw = pillText.longestLine + 52;
    final pill = RRect.fromRectAndRadius(Rect.fromLTWH(w - 80 - pw, 84, pw, 56), const Radius.circular(28));
    c.drawRRect(pill, Paint()..color = _cyan.withValues(alpha: .12));
    c.drawRRect(
        pill,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _cyan.withValues(alpha: .45));
    c.drawParagraph(pillText, Offset(w - 80 - pw + 26, 84 + (56 - pillText.height) / 2));

    // Who: round photo (or initial on the brand gradient) + name + sub.
    const av = Offset(146, 252);
    const ar = 66.0;
    if (photo != null) {
      c.save();
      c.clipPath(Path()..addOval(Rect.fromCircle(center: av, radius: ar)));
      final src = Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble());
      final side = src.shortestSide;
      c.drawImageRect(photo, Rect.fromCenter(center: src.center, width: side, height: side),
          Rect.fromCircle(center: av, radius: ar), Paint()..filterQuality = FilterQuality.high);
      c.restore();
    } else {
      c.drawCircle(
          av,
          ar,
          Paint()
            ..shader = ui.Gradient.linear(av - const Offset(ar, ar), av + const Offset(ar, ar), const [_blue, _cyan]));
      final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
      final ip = _text(initial, 60, Colors.white, weight: FontWeight.w700, width: ar * 2, align: TextAlign.center);
      c.drawParagraph(ip, Offset(av.dx - ar, av.dy - ip.height / 2));
    }
    c.drawCircle(
        av,
        ar + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Colors.white.withValues(alpha: .14));
    final np = _text(name.trim().isEmpty ? 'LinkUp' : name.trim(), 54, Colors.white, weight: FontWeight.w600, width: 760);
    final sp = _text(sub, 32, Colors.white.withValues(alpha: .66), width: 760);
    final top = av.dy - (np.height + (sub.isEmpty ? 0 : sp.height + 2)) / 2;
    c.drawParagraph(np, Offset(240, top));
    if (sub.isNotEmpty) c.drawParagraph(sp, Offset(240, top + np.height + 2));

    // The QR on white, with a soft blue glow and a gradient edge.
    const qrBox = Rect.fromLTWH(140, 372, 800, 800);
    final box = RRect.fromRectAndRadius(qrBox, const Radius.circular(44));
    c.drawRRect(
        box.inflate(12),
        Paint()
          ..color = _blue.withValues(alpha: .28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34));
    c.drawRRect(box, Paint()..color = Colors.white);
    c.drawRRect(
        box.inflate(5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..shader = ui.Gradient.linear(qrBox.topLeft, qrBox.bottomRight, const [_blue, _cyan]));
    _qr(c, qrBox.deflate(36), data);

    // Steps: 3 numbered dots in one line under the box.
    final steps = stepsFor(kind);
    var y = 1196.0;
    final num = Paint()..color = _cyan.withValues(alpha: .16);
    // 2 rows: steps 1 + 2, then step 3.
    final rows = <List<int>>[
      [0, 1],
      [2]
    ];
    for (final row in rows) {
      var x = 80.0;
      for (final i in row) {
        c.drawCircle(Offset(x + 20, y + 20), 20, num);
        final n = _text('${i + 1}', 24, _cyan, weight: FontWeight.w700, width: 40, align: TextAlign.center);
        c.drawParagraph(n, Offset(x, y + 20 - n.height / 2));
        final t = _text(steps[i], 29, Colors.white.withValues(alpha: .86), width: 520);
        c.drawParagraph(t, Offset(x + 54, y + 20 - t.height / 2));
        x += 54 + t.longestLine + 44;
      }
      y += 54;
    }

    // Footer: when it was made (contact) / it expires (group).
    final foot = kind == QrCardKind299.group ? 'Expires in 24 hours' : 'Made ${RecoveryCard298.day(made ?? DateTime.now())}';
    final fp = _text(foot, 25, kind == QrCardKind299.group ? const Color(0xFFFDE68A) : Colors.white.withValues(alpha: .62),
        width: 400, align: TextAlign.right, weight: kind == QrCardKind299.group ? FontWeight.w600 : FontWeight.w400);
    c.drawParagraph(fp, Offset(w - 80 - 400, 1196 + 54 + 20 - fp.height / 2));
    c.restore();
  }

  /// The PNG bytes of the card (full size).
  static Future<Uint8List> png({
    required QrCardKind299 kind,
    required String data,
    required String name,
    String sub = '',
    ui.Image? photo,
    DateTime? made,
  }) async {
    final rec = ui.PictureRecorder();
    paint(Canvas(rec), size, kind: kind, data: data, name: name, sub: sub, photo: photo, made: made);
    final pic = rec.endRecording();
    final img = await pic.toImage(size.width.toInt(), size.height.toInt());
    try {
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      img.dispose();
      pic.dispose();
    }
  }
}

/// The card on screen (mock / tests).
class QrShareCardView299 extends StatelessWidget {
  const QrShareCardView299(
      {super.key, required this.kind, required this.data, required this.name, this.sub = '', this.made});

  final QrCardKind299 kind;
  final String data;
  final String name;
  final String sub;
  final DateTime? made;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: QrShareCard299.size.width / QrShareCard299.size.height,
        child: CustomPaint(painter: _P(this)),
      );
}

class _P extends CustomPainter {
  _P(this.v);
  final QrShareCardView299 v;

  @override
  void paint(Canvas canvas, Size size) => QrShareCard299.paint(canvas, size,
      kind: v.kind, data: v.data, name: v.name, sub: v.sub, made: v.made);

  @override
  bool shouldRepaint(covariant _P old) => old.v != v;
}
