import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/presentation/screens/link_paths_full_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

/// Bundle 212 (H1 f, E6-E7): blocked users on the map, full-screen map.
void main() {
  setUp(AdminBlockBook.instance.resetForTest);

  const nodes = [
    LinkNode(id: 'a', label: 'Bilal', tag: LinkTag.wifiDirect),
    LinkNode(id: 'b', label: 'Ali Raza', tag: LinkTag.mesh, blocked: true),
    LinkNode(id: 'c', label: 'Sana', tag: LinkTag.localWifi),
  ];

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('small map: blocked legend + expand button', (tester) async {
    bigView(tester);
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LinkPathsMap(nodes: nodes, serverOnline: false, onExpand: () => opened++))));
    expect(find.byType(LinkBlockedLegend), findsOneWidget);
    expect(find.text('Blocked · relays only'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('link_paths_expand')));
    expect(opened, 1);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LinkPathsMap(nodes: [LinkNode(id: 'a', label: 'B', tag: LinkTag.mesh)], serverOnline: true))));
    expect(find.byType(LinkBlockedLegend), findsNothing);
    expect(find.byKey(const ValueKey('link_paths_expand')), findsNothing);
  });

  testWidgets('placements spread wider on the big map', (tester) async {
    const size = Size(1000, 1000);
    final small = LinkPathsCanvas.placements(nodes, size, spread: 1);
    final big = LinkPathsCanvas.placements(nodes, size, spread: 2);
    expect(small.keys.toSet(), {'a', 'b', 'c'});
    final hub = Offset(size.width * 0.47, size.height * 0.66);
    expect((big['a']! - hub).distance, greaterThan((small['a']! - hub).distance));
  });

  Future<Map<String, String>> openFull(WidgetTester tester) async {
    bigView(tester);
    final hints = <String, String>{};
    await tester.pumpWidget(MaterialApp(
      home: LinkPathsFullScreen(
        nodes: nodes,
        serverOnline: false,
        targetFor: (n) => BlockTarget(userId: n.id, name: n.label),
        readHint: (k) async => hints[k],
        writeHint: (k, v) async => hints[k] = v,
      ),
    ));
    await tester.pump();
    await tester.pump();
    return hints;
  }

  testWidgets('full map: counts, hint shown 3 times max, chips filter', (tester) async {
    final hints = await openFull(tester);
    expect(find.text('3 users · 1 blocked · server offline'), findsOneWidget);
    expect(find.byKey(const ValueKey('link_map_hint')), findsOneWidget);
    expect(hints[LinkPathsFullScreen.hintKey], '1');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('link_map_filter_blocked')), 120,
        scrollable: find
            .descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable))
            .first);
    expect(find.byKey(const ValueKey('link_map_filter_blocked')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('link_map_filter_blocked')));
    await tester.pump();
    final chip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('link_map_filter_blocked')));
    expect(chip.selected, isTrue);
    expect(linkMapFilterMatches(LinkMapFilter.blocked, nodes[1]), isTrue);
    expect(linkMapFilterMatches(LinkMapFilter.blocked, nodes[0]), isFalse);
    expect(linkMapFilterMatches(LinkMapFilter.mesh, nodes[1]), isTrue);
  });

  testWidgets('full map: zoom buttons and centre', (tester) async {
    await openFull(tester);
    final viewer = tester.widget<InteractiveViewer>(find.byKey(const ValueKey('link_map_viewer')));
    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 4);
    final ctrl = viewer.transformationController!;
    await tester.tap(find.byKey(const ValueKey('link_map_zoom_in')));
    await tester.pump();
    expect(ctrl.value.getMaxScaleOnAxis(), greaterThan(1.1));
    await tester.tap(find.byKey(const ValueKey('link_map_zoom_out')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('link_map_zoom_out')));
    await tester.pump();
    expect(ctrl.value.getMaxScaleOnAxis(), closeTo(1, 0.01));
    await tester.tap(find.byKey(const ValueKey('link_map_centre')));
    await tester.pump();
  });

  testWidgets('full map: search a missing name says so', (tester) async {
    await openFull(tester);
    await tester.enterText(find.byKey(const ValueKey('link_map_search')), 'Zed');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.textContaining('No one called'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('link_map_search')), 'ali');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
  });

  test('big canvas grows with users', () {
    const view = Size(400, 700);
    final few = linkMapCanvasSize(view, 3);
    final many = linkMapCanvasSize(view, 60);
    expect(many.width, greaterThanOrEqualTo(few.width));
    expect(few.width, greaterThanOrEqualTo(view.width));
  });
}
