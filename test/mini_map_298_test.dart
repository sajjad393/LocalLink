import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/features/admin/presentation/widgets/link_apart_291.dart';
import 'package:locallink/features/admin/presentation/widgets/link_balance_298.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';
import 'package:locallink/features/contacts/presentation/widgets/mini_map_zoom_298.dart';

import 'support/b216_fonts.dart';

/// Bundle 298 (D): the Chats "My links" small map used only the left half
/// (every Wi-Fi Direct friend is placed left of You). Now people sit on
/// both sides over the card width; two fingers zoom 0.5x..4x; one finger
/// at normal size still scrolls the list; "Reset" only while zoomed/moved.
final String? _out = Platform.environment['UI_CHECK_OUT'];
final String _tag = Platform.environment['SHOT_TAG'] ?? 'new';

Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final f = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(f.readAsBytesSync()))));
  await loader.load();
}

const _three = [
  LinkNode(id: 'd-sumaira', label: 'sumaira', tag: LinkTag.wifiDirect, userId: 'u-sumaira'),
  LinkNode(id: 'd-kiran', label: 'kiran', tag: LinkTag.wifiDirect, userId: 'u-kiran'),
  LinkNode(id: 'd-ayesha', label: 'ayesha', tag: LinkTag.wifiDirect, userId: 'u-ayesha'),
];

const _mixed = [
  LinkNode(id: 'd-sumaira', label: 'sumaira', tag: LinkTag.wifiDirect, userId: 'u-sumaira'),
  LinkNode(id: 'd-kiran', label: 'kiran', tag: LinkTag.wifiDirect, userId: 'u-kiran'),
  LinkNode(id: 'd-ayesha', label: 'ayesha', tag: LinkTag.server, userId: 'u-ayesha'),
  LinkNode(id: 'd-ibrahim', label: 'ibrahim', tag: LinkTag.mesh, userId: 'u-ibrahim'),
  LinkNode(id: 'd-zara', label: 'zara', tag: LinkTag.mesh, userId: 'u-zara', noLine: true),
  LinkNode(id: 'd-ali', label: 'ali', tag: LinkTag.wifiDirect, userId: 'u-ali'),
];
const _mixedEdges = [LinkEdge('d-ibrahim', 'd-zara', LinkTag.mesh)];

Widget _card(List<LinkNode> nodes, List<LinkEdge> edges, TransformationController? zoom, {bool dark = false}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: LocalLinkTheme.light(),
      darkTheme: LocalLinkTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        body: ListView(key: const ValueKey('list'), children: [
          Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  child: LinkPathsMap(
                    title: 'My links',
                    subtitle: '${nodes.length} live · 0 offline',
                    height: 110,
                    nodes: nodes,
                    extraEdges: edges,
                    serverOnline: true,
                    selfId: 'd-me',
                    selfUserId: 'u-me',
                    wrapCanvas: zoom == null ? null : (c) => MiniMapZoomBox298(controller: zoom, child: c),
                    legendEnd: zoom == null ? null : MiniMapReset298(controller: zoom),
                  ),
                ),
              ),
            ),
          ),
          for (var i = 0; i < 12; i++) ListTile(title: Text('chat $i')),
        ]),
      ),
    );

Future<void> _shot(WidgetTester tester, String name) async {
  if (_out == null) return;
  final boundary = tester.firstRenderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/${_tag}_$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    await loadRoboto216();
    await _loadIcons();
  });
  setUp(LinkApart291.clearCache);

  Offset self(Size s) => Offset(s.width * 0.47, s.height * 0.66);

  test('3 Wi-Fi Direct friends: both sides of You, spread over the width', () {
    const size = Size(318, 110);
    final s = self(size);
    final place = <String, Offset>{
      'd-ayesha': Offset(s.dx - 60, s.dy + 10),
      'd-kiran': Offset(s.dx - 120, s.dy - 20),
      'd-sumaira': Offset(s.dx - 40, s.dy - 60),
    };
    final out = LinkBalance298.balance(place, size, self: s, movable: place.keys.toSet());
    final left = out.values.where((p) => p.dx < s.dx).length;
    final right = out.values.where((p) => p.dx > s.dx).length;
    expect(left, 1);
    expect(right, 2, reason: 'the cloud is on the left: the odd one goes right');
    for (final p in out.values) {
      expect(p.dx, inInclusiveRange(LinkBalance298.edge, size.width - LinkBalance298.edge));
    }
    // Same input = same map.
    expect(LinkBalance298.balance(place, size, self: s, movable: place.keys.toSet()), out);
  });

  test('a mesh chain moves as one group; server people stay by the cloud', () {
    const size = Size(318, 110);
    final s = self(size);
    final place = <String, Offset>{
      'a': Offset(s.dx - 70, s.dy), // Wi-Fi Direct
      'b': Offset(s.dx - 100, s.dy - 30), // Wi-Fi Direct
      'm1': Offset(s.dx - 50, s.dy - 50), // mesh relay
      'm2': Offset(s.dx - 90, s.dy - 60), // via m1
      'srv': const Offset(60, 30), // server: not movable
    };
    final out =
        LinkBalance298.balance(place, size, self: s, movable: {'a', 'b', 'm1', 'm2'}, links: const [('m1', 'm2')]);
    expect(out['srv'], place['srv']);
    expect((out['m1']!.dx < s.dx) == (out['m2']!.dx < s.dx), isTrue, reason: 'chain kept on one side');
    final right = out.values.where((p) => p.dx > s.dx).length;
    expect(right, greaterThanOrEqualTo(2));
  });

  testWidgets('small card: people on both sides of You (real widgets)', (tester) async {
    tester.view.physicalSize = const Size(352, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final zoom = TransformationController();
    await tester.pumpWidget(RepaintBoundary(key: const ValueKey('shot'), child: _card(_three, const [], zoom)));
    await tester.pump(const Duration(milliseconds: 300));
    final me = tester.getCenter(find.byKey(const ValueKey('link_node_self')));
    final xs = [for (final n in _three) tester.getCenter(find.byKey(ValueKey('link_node_${n.id}'))).dx];
    expect(xs.where((x) => x > me.dx).length, greaterThanOrEqualTo(1), reason: 'someone right of You');
    expect(xs.where((x) => x < me.dx).length, greaterThanOrEqualTo(1));
    expect(find.byKey(const ValueKey('mini_map_reset_298')), findsNothing, reason: 'no Reset at normal size');
    await _shot(tester, 'mini_three_light');
  });

  testWidgets('pinch zooms, Reset shows, Reset goes back and hides', (tester) async {
    tester.view.physicalSize = const Size(352, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final zoom = TransformationController();
    await tester.pumpWidget(RepaintBoundary(key: const ValueKey('shot'), child: _card(_three, const [], zoom)));
    await tester.pump(const Duration(milliseconds: 300));
    final box = tester.getRect(find.byKey(const ValueKey('mini_map_zoom_298')));
    final c = box.center;
    final g1 = await tester.startGesture(c - const Offset(20, 0), pointer: 1);
    final g2 = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
    for (var i = 1; i <= 10; i++) {
      await g1.moveTo(c - Offset(20.0 + 6 * i, 0));
      await g2.moveTo(c + Offset(20.0 + 6 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(MiniMapZoom298.scaleOf(zoom.value), greaterThan(1.5), reason: 'two fingers zoom in');
    expect(find.byKey(const ValueKey('mini_map_reset_298')), findsOneWidget);
    await _shot(tester, 'mini_zoomed_light');
    await tester.tap(find.byKey(const ValueKey('mini_map_reset_298')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(MiniMapZoom298.isDefault(zoom.value), isTrue);
    expect(find.byKey(const ValueKey('mini_map_reset_298')), findsNothing, reason: 'Reset hides again');
  });

  testWidgets('zoom limits 0.5x .. 4x', (tester) async {
    tester.view.physicalSize = const Size(352, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final zoom = TransformationController();
    await tester.pumpWidget(_card(_three, const [], zoom));
    await tester.pump(const Duration(milliseconds: 300));
    final c = tester.getRect(find.byKey(const ValueKey('mini_map_zoom_298'))).center;
    Future<void> pinch(double from, double to) async {
      final g1 = await tester.startGesture(c - Offset(from, 0), pointer: 11);
      final g2 = await tester.startGesture(c + Offset(from, 0), pointer: 12);
      for (var i = 1; i <= 12; i++) {
        final d = from + (to - from) * i / 12;
        await g1.moveTo(c - Offset(d, 0));
        await g2.moveTo(c + Offset(d, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 50));
    }

    await pinch(10, 150);
    expect(MiniMapZoom298.scaleOf(zoom.value), closeTo(MiniMapZoom298.maxScale, 0.01));
    zoom.value = Matrix4.identity();
    await tester.pump();
    await pinch(150, 8);
    expect(MiniMapZoom298.scaleOf(zoom.value), closeTo(MiniMapZoom298.minScale, 0.01));
  });

  testWidgets('normal size: one finger on the map scrolls the Chats list', (tester) async {
    tester.view.physicalSize = const Size(352, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final zoom = TransformationController();
    await tester.pumpWidget(_card(_three, const [], zoom));
    await tester.pump(const Duration(milliseconds: 300));
    final before = tester.getTopLeft(find.byKey(const ValueKey('mini_map_zoom_298'))).dy;
    await tester.dragFrom(
        tester.getRect(find.byKey(const ValueKey('mini_map_zoom_298'))).center, const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 300));
    final after = tester.getTopLeft(find.byKey(const ValueKey('mini_map_zoom_298'))).dy;
    expect(after, lessThan(before - 50), reason: 'the list scrolled');
    expect(MiniMapZoom298.isDefault(zoom.value), isTrue, reason: 'the map did not move');
  });

  testWidgets('zoomed: one finger moves the map, the list stays', (tester) async {
    tester.view.physicalSize = const Size(352, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final zoom = TransformationController(MiniMapZoom298.matrix(const Offset(-150, -50), 2));
    await tester.pumpWidget(_card(_three, const [], zoom));
    await tester.pump(const Duration(milliseconds: 300));
    final box = tester.getRect(find.byKey(const ValueKey('mini_map_zoom_298')));
    final before = box.top;
    await tester.dragFrom(box.center, const Offset(30, 40));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(find.byKey(const ValueKey('mini_map_zoom_298'))).top, before, reason: 'list did not scroll');
    final t = zoom.value.getTranslation();
    expect(t.x, closeTo(-120, 1));
    expect(t.y, closeTo(-10, 1));
    expect(find.byKey(const ValueKey('mini_map_reset_298')), findsOneWidget);
  });

  testWidgets('more people + a mesh chain: card still fits, no overflow', (tester) async {
    tester.view.physicalSize = const Size(352, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        RepaintBoundary(key: const ValueKey('shot'), child: _card(_mixed, _mixedEdges, TransformationController())));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await _shot(tester, 'mini_mixed_light');
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('shot'), child: _card(_three, const [], TransformationController(), dark: true)));
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'mini_three_dark');
  });
}
