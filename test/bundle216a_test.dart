// Bundle 216a: crown style A (gold ring + small painted crown on top) and
// the painted crown in the "Admin · Owner" tag.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/admin_crown.dart';

void main() {
  testWidgets('decorate: gold ring + crown above the photo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: AdminCrown.decorate(
          radius: 40,
          background: Colors.white,
          child: const CircleAvatar(radius: 40),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('admin_crown_stack')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_crown_ring')), findsOneWidget);
    final crown = find.byKey(const ValueKey('admin_crown'));
    expect(crown, findsOneWidget);
    final photo = tester.getRect(find.byType(CircleAvatar));
    final c = tester.getRect(crown);
    // Sits on top, centred, 0.75·R wide.
    expect(c.center.dx, closeTo(photo.center.dx, 0.5));
    expect(c.top, lessThan(photo.top));
    expect(c.width, closeTo(AdminCrown.sizeFor(40), 0.5));
    expect(AdminCrown.sizeFor(8), 11); // 256 F1: never smaller than 11
  });

  testWidgets('role tag: painted crown + "Admin · Owner"', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: AdminRoleTag216(level: 'Owner')),
    ));
    expect(find.text('Admin · Owner'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('a216_role_tag')),
            matching: find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is CrownPainter216)),
        findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('a216_role_tag'))).height, 24);
    // No emoji crown anywhere.
    expect(find.textContaining('👑'), findsNothing);
  });

  test('crown painter repaints only when the halo changes', () {
    const a = CrownPainter216();
    expect(a.shouldRepaint(const CrownPainter216()), isFalse);
    expect(a.shouldRepaint(const CrownPainter216(halo: Colors.black)), isTrue);
    expect(CrownPainter216.heightFor(20), greaterThan(0));
  });
}
