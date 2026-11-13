import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/screens/link_paths_full_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/link_apart_291.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

/// Bundle 291 (TODO_291 B-4): on the app maps no two people sit on top of
/// each other and no line runs under a third person's photo.
void main() {
  setUp(() {
    AdminBlockBook.instance.resetForTest();
    LinkApart291.clearCache();
  });

  const names = [
    'Ayesha', 'Bilal', 'Kiran', 'Sajjad', 'Sumaira', 'Noshad', //
    'Ibrahim', 'Alex', 'Hina', 'Zara', 'Omar', 'Usman',
  ];

  List<LinkNode> serverPhones(int n) => [
        for (var i = 0; i < n; i++) LinkNode(id: 'p$i', label: names[i], tag: LinkTag.server),
      ];

  List<LinkNode> mixed() => const [
        LinkNode(id: 'm0', label: 'Ayesha', tag: LinkTag.server),
        LinkNode(id: 'm1', label: 'Bilal', tag: LinkTag.server),
        LinkNode(id: 'm2', label: 'Kiran', tag: LinkTag.server),
        LinkNode(id: 'm3', label: 'Sajjad', tag: LinkTag.mesh),
        LinkNode(id: 'm4', label: 'Sumaira', tag: LinkTag.mesh),
        LinkNode(id: 'm5', label: 'Noshad', tag: LinkTag.wifiDirect),
        LinkNode(id: 'm6', label: 'Ibrahim', tag: LinkTag.localWifi),
        LinkNode(id: 'm7', label: 'Alex', tag: LinkTag.server, offline: true),
      ];

  // Distance in "rooms" (>= 1 = free), the same ellipse as the code.
  double room(Offset a, Offset b, double r, {bool small = false}) {
    final dx = (a.dx - b.dx) / LinkApart291.roomX(r, small: small);
    final dy = (a.dy - b.dy) / LinkApart291.roomY(r, small: small);
    return math.sqrt(dx * dx + dy * dy);
  }

  Offset self(Size s) => Offset(s.width * 0.47, s.height * 0.66);
  Offset server(Size s) => Offset(s.width * 0.15, s.height * 0.18);

  void expectApart(Map<String, Offset> place, Size size, double r, {bool small = false, String why = ''}) {
    final pts = [...place.values, self(size), server(size)];
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        expect(room(pts[i], pts[j], r, small: small), greaterThanOrEqualTo(0.97),
            reason: '$why: ${pts[i]} and ${pts[j]} overlap');
      }
    }
    for (final p in place.values) {
      expect(p.dx, inInclusiveRange(15.9, size.width - 15.9), reason: '$why: $p out of the map');
      expect(p.dy, inInclusiveRange(15.9, size.height - 33.9), reason: '$why: $p out of the map');
    }
  }

  group('full screen (r 24): people never overlap', () {
    for (final view in const [Size(320, 640), Size(411, 860)]) {
      for (final n in const [3, 6, 12]) {
        test('$n server phones, ${view.width.toInt()} dp', () {
          final nodes = serverPhones(n);
          final canvas = linkMapCanvasSize(view, linkMapUserCount(nodes));
          for (final spread in const [1.0, 1.6]) {
            final place = LinkPathsCanvas.placements(nodes, canvas, spread: spread);
            expect(place.length, n);
            expectApart(place, canvas, 24, why: 'n=$n spread=$spread');
          }
        });
      }
      test('mixed tags, ${view.width.toInt()} dp', () {
        final nodes = mixed();
        final canvas = linkMapCanvasSize(view, linkMapUserCount(nodes));
        expectApart(LinkPathsCanvas.placements(nodes, canvas), canvas, 24, why: 'mixed');
      });
    }
  });

  test('same people + size = same map (no jumping between frames)', () {
    final nodes = serverPhones(12);
    final canvas = linkMapCanvasSize(const Size(320, 640), 12);
    final a = LinkPathsCanvas.placements(nodes, canvas);
    LinkApart291.clearCache();
    final b = LinkPathsCanvas.placements(nodes, canvas);
    expect(b, a);
  });

  test('people already apart stay where 212 put them', () {
    const size = Size(600, 800);
    final start = {'a': const Offset(500, 120), 'b': const Offset(420, 600), 'c': const Offset(120, 420)};
    final out = LinkApart291.apart(start, size, r: 24, fixed: [self(size), server(size)]);
    expect(out, start);
  });

  test('a crowded small card: names may squeeze, photos never touch', () {
    const size = Size(292, 104);
    final start = {for (var i = 0; i < 12; i++) 'p$i': const Offset(200, 50)};
    final out = LinkApart291.apart(start, size, r: 14, fixed: [self(size), server(size)], small: true);
    final pts = [...out.values, self(size), server(size)];
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        expect((pts[i] - pts[j]).distance, greaterThanOrEqualTo(2 * 14.0 + 3), reason: '${pts[i]} ${pts[j]}');
      }
    }
  });

  group('lines', () {
    test('a free line keeps the 217 bow (0.60)', () {
      final route = LinkRoute291.of('t1', obstacles: const [Offset(0, 0), Offset(100, 0)], clear: 34);
      const p = Offset(0, 0), q = Offset(100, 0), c = Offset(50, 80);
      expect(route.pick(p, q, c, 0.60), LinkRoute291.control(p, q, c, 0.60));
    });

    test('a line over a third photo bows away from it', () {
      const p = Offset(0, 0), q = Offset(200, 0), c = Offset(100, 200);
      final first = LinkRoute291.control(p, q, c, 0.60);
      final third = LinkRoute291.point(p, first, q, 0.5); // right on the 217 line
      final route = LinkRoute291.of('t2', obstacles: [p, q, third], clear: 34);
      final got = route.pick(p, q, c, 0.60);
      expect(got, isNot(first));
      for (var s = 1; s < 24; s++) {
        expect((LinkRoute291.point(p, got, q, s / 24) - third).distance, greaterThanOrEqualTo(34));
      }
    });

    test('the second of two lines on top of each other moves', () {
      const p = Offset(0, 0), q = Offset(200, 0), c = Offset(100, 200);
      final route = LinkRoute291.of('t3', obstacles: const [p, q], clear: 34);
      final a = route.pick(p, q, c, 0.60);
      final b = route.pick(const Offset(1, 0), const Offset(201, 0), c, 0.60);
      final ma = LinkRoute291.point(p, a, q, 0.5);
      final mb = LinkRoute291.point(const Offset(1, 0), b, const Offset(201, 0), 0.5);
      expect((ma - mb).distance, greaterThanOrEqualTo(16));
    });
  });

  group('widgets', () {
    void view(WidgetTester tester, Size s) {
      tester.view.physicalSize = s;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Offset at(WidgetTester tester, String id, double w, double r) =>
        tester.getTopLeft(find.byKey(ValueKey('link_node_$id'))) + Offset(w / 2, r);

    for (final n in const [3, 6, 12]) {
      testWidgets('small card at 320 dp, $n server phones: photos never touch', (tester) async {
        view(tester, const Size(320, 900));
        final nodes = serverPhones(n);
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: LinkPathsMap(nodes: nodes, serverOnline: true, height: 104, title: 'Link paths')))));
        final pts = [for (final x in nodes) at(tester, x.id, 76, 14), at(tester, 'self', 76, 14)];
        for (var i = 0; i < pts.length; i++) {
          for (var j = i + 1; j < pts.length; j++) {
            expect((pts[i] - pts[j]).distance, greaterThanOrEqualTo(31), reason: 'n=$n ${pts[i]} ${pts[j]}');
          }
        }
        if (n <= 6) {
          for (var i = 0; i < pts.length; i++) {
            for (var j = i + 1; j < pts.length; j++) {
              expect(room(pts[i], pts[j], 14, small: true), greaterThanOrEqualTo(0.97));
            }
          }
        }
      });
    }

    testWidgets('full screen: the drawn photos sit on the pushed-apart spots (taps match)', (tester) async {
      view(tester, const Size(320, 700));
      final nodes = [...serverPhones(12)];
      await tester.pumpWidget(MaterialApp(
        home: LinkPathsFullScreen(nodes: nodes, serverOnline: true, targetFor: (n) => BlockTarget(userId: n.id, name: n.label)),
      ));
      await tester.pump();
      final canvasFinder = find.byType(LinkPathsCanvas);
      expect(canvasFinder, findsOneWidget);
      final canvas = tester.getSize(canvasFinder);
      final place = LinkPathsCanvas.placements(nodes, canvas, spread: (tester.widget(canvasFinder) as LinkPathsCanvas).spread);
      final origin = tester.getTopLeft(canvasFinder);
      final scale = (tester.getBottomRight(canvasFinder).dx - origin.dx) / canvas.width;
      for (final x in nodes) {
        final drawn = tester.getTopLeft(find.byKey(ValueKey('link_node_${x.id}')));
        final want = origin + (place[x.id]! - const Offset(55, 24)) * scale;
        expect((drawn - want).distance, lessThan(1.0), reason: x.id);
      }
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
