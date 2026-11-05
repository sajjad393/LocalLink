import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/presentation/screens/link_paths_full_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

/// Bundle 222 (mock M-2): zoom out until the whole map fits; lines unchanged.
void main() {
  setUp(AdminBlockBook.instance.resetForTest);

  const nodes = [
    LinkNode(id: 'a', label: 'Bilal', tag: LinkTag.wifiDirect),
    LinkNode(id: 'b', label: 'Ali Raza', tag: LinkTag.mesh, blocked: true),
    LinkNode(id: 'c', label: 'Sana', tag: LinkTag.localWifi),
  ];

  Future<TransformationController> openFull(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: LinkPathsFullScreen(
        nodes: nodes,
        serverOnline: true,
        targetFor: (n) => BlockTarget(userId: n.id, name: n.label),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return tester.widget<InteractiveViewer>(find.byKey(const ValueKey('link_map_viewer'))).transformationController!;
  }

  double scale(TransformationController c) => c.value.getMaxScaleOnAxis();

  test('fit = whole canvas on the screen, never above 1x', () {
    const view = Size(400, 700);
    final canvas = linkMapCanvasSize(view, 5);
    final fit = linkMapFitScale(view, canvas);
    expect(canvas.width * fit, lessThanOrEqualTo(view.width + 0.01));
    expect(canvas.height * fit, lessThanOrEqualTo(view.height + 0.01));
    expect(fit, lessThan(1));
    expect(linkMapFitScale(const Size(2000, 2000), const Size(100, 100)), 1);
    expect(linkMapFitScale(Size.zero, canvas), 1);
  });

  testWidgets('"-" goes down to the whole map, then turns grey; tag shows 1.5 s', (tester) async {
    final ctrl = await openFull(tester);
    final viewer = tester.widget<InteractiveViewer>(find.byKey(const ValueKey('link_map_viewer')));
    expect(viewer.minScale, lessThan(1), reason: 'pinch can also go below 1x');
    final fit = viewer.minScale;
    expect(scale(ctrl), closeTo(1, 0.01), reason: 'opens at 1x as before');
    for (var i = 0; i < 6; i++) {
      final btn = tester.widget<IconButton>(find.byKey(const ValueKey('link_map_zoom_out')));
      if (btn.onPressed == null) break;
      await tester.tap(find.byKey(const ValueKey('link_map_zoom_out')));
      await tester.pump();
    }
    expect(scale(ctrl), closeTo(fit, 0.01));
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('link_map_zoom_out'))).onPressed, isNull);
    expect(find.byKey(const ValueKey('link_map_whole_tag')), findsOneWidget);
    expect(find.text('Whole map'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byKey(const ValueKey('link_map_whole_tag')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('link_map_zoom_in')));
    await tester.pump();
    expect(scale(ctrl), greaterThan(fit + 0.05));
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('link_map_zoom_out'))).onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('double tap: whole map <-> 2x', (tester) async {
    final ctrl = await openFull(tester);
    final fit = tester.widget<InteractiveViewer>(find.byKey(const ValueKey('link_map_viewer'))).minScale;
    final map = find.byKey(const ValueKey('link_map_viewer'));
    Future<void> doubleTap() async {
      await tester.tap(map, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(map, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
    }

    await doubleTap();
    expect(scale(ctrl), closeTo(fit, 0.01));
    await doubleTap();
    expect(scale(ctrl), closeTo(2, 0.01));
    await doubleTap();
    expect(scale(ctrl), closeTo(fit, 0.01));
    await tester.pump(const Duration(seconds: 2));
  });

  test('map lines, colours and motion are exactly the 217 code', () {
    final src = File('lib/features/admin/presentation/widgets/link_paths_map.dart').readAsStringSync();
    final part = src.substring(src.indexOf('/// Bundle 217: when the map lines may move')).replaceAll('\r\n', '\n');
    expect(sha256.convert(utf8.encode(part)).toString(),
        '798158082d36f3183093544595c93ca6b4d75a24c5c3ed333f428b41ea5159ad');
  });
}
