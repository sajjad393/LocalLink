// Bundle 217d: the new crown everywhere (TODO_217 §2.3).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/admin_crown.dart';

void main() {
  test('sizes: 1.1 x radius, never under 13; height 0.88 x width', () {
    expect(AdminCrown.sizeFor(40), closeTo(44, 1e-9));
    expect(AdminCrown.sizeFor(5), 13);
    expect(CrownPainter216.heightFor(50), closeTo(44, 1e-9));
  });

  testWidgets('decorate: crown centred, band on the ring, bottom touches the photo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AdminCrown.decorate(
            radius: 24,
            background: Colors.white,
            child: const CircleAvatar(radius: 24),
          ),
        ),
      ),
    ));
    final photo = tester.getRect(find.byType(CircleAvatar));
    final crown = tester.getRect(find.byKey(const ValueKey('admin_crown')));
    final ringTop = photo.top - 2.6;
    expect(crown.center.dx, closeTo(photo.center.dx, 0.5));
    expect(crown.width, closeTo(AdminCrown.sizeFor(24), 0.01));
    expect(crown.height, closeTo(CrownPainter216.heightFor(AdminCrown.sizeFor(24)), 0.01));
    expect(crown.bottom - ringTop, closeTo(3.0, 0.5));
    expect(crown.bottom, greaterThan(photo.top));
    expect(crown.top, lessThan(ringTop));
  });

  test('paintCrown217 draws at 13, 26 and 40 px (with and without halo)', () async {
    for (final w in [13.0, 26.0, 40.0]) {
      for (final halo in [null, Colors.white]) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        paintCrown217(canvas, Offset(w, 4), w, halo: halo);
        final image = await rec.endRecording().toImage((w * 2).ceil(), (w * 1.2).ceil());
        final bytes = await image.toByteData();
        expect(bytes, isNotNull);
        image.dispose();
      }
    }
  });

  testWidgets('mark() keeps the admin_crown key and the 216 colours', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Center(child: AdminCrown.mark(20))));
    expect(find.byKey(const ValueKey('admin_crown')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('admin_crown'))).height,
        closeTo(17.6, 0.01));
    expect(kCrownFill216, const Color(0xFFFFC727));
    expect(kCrownBand216, const Color(0xFFEFA300));
    expect(kCrownLine216, const Color(0xFFA87400));
    expect(kCrownGem216, const Color(0xFFE5484D));
    expect(kCrownTop217, const Color(0xFFFFE985));
    expect(kCrownBlue217, const Color(0xFF3B82F6));
  });
}
