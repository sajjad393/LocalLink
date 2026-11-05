// Bundle 217c: aerial moving map lines (TODO_217 §2.1, §2.2).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

/// Records the circles a painter draws (radius + colour).
class _Rec implements Canvas {
  final circles = <({double r, Color color, PaintingStyle style})>[];
  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add((r: radius, color: paint.color, style: paint.style));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _three = [
  LinkNode(id: 'd-sum', label: 'Sumaira', tag: LinkTag.wifiDirect, userId: 'u-sum'),
  LinkNode(id: 'd-ali', label: 'Ali', tag: LinkTag.mesh, userId: 'u-ali'),
  LinkNode(id: 'd-zia', label: 'Zia', tag: LinkTag.server, userId: 'u-zia'),
];

Widget _host(List<LinkNode> nodes,
        {bool serverOnline = true, bool dark = false, bool noAnim = false}) =>
    MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: noAnim),
          child: Scaffold(
            body: SizedBox(
              width: 360,
              height: 400,
              child: LinkPathsCanvas(
                serverOnline: serverOnline,
                selfId: 'd-saj',
                nodes: nodes,
              ),
            ),
          ),
        ),
      ),
    );

LinkPathsCanvasState _state(WidgetTester t) =>
    t.state<LinkPathsCanvasState>(find.byType(LinkPathsCanvas));

CustomPainter _painter(WidgetTester t) => t
    .widgetList<CustomPaint>(find.descendant(
        of: find.byType(LinkPathsCanvas), matching: find.byType(CustomPaint)))
    .map((w) => w.painter)
    .firstWhere((p) => p != null && p.runtimeType.toString() == '_LinkPathsPainter')!;

_Rec _record(WidgetTester t) {
  final rec = _Rec();
  _painter(t).paint(rec, const Size(360, 400));
  return rec;
}

bool _isDot(({double r, Color color, PaintingStyle style}) c) =>
    c.r == 2.6 && c.color == Colors.white && c.style == PaintingStyle.fill;

void main() {
  setUp(() {
    AdminBadgeBook.instance.resetForTest();
  });
  tearDown(LinkMotion217.resetForTest);

  test('aerial control point bows away from the centre', () {
    final c = LinkPathsCanvas.aerialControl(
        Offset.zero, const Offset(100, 0), const Offset(50, 50));
    expect(c.dx, closeTo(50, 1e-9));
    expect(c.dy, closeTo(-60, 1e-9));
    final s = LinkPathsCanvas.aerialControl(
        Offset.zero, const Offset(100, 0), const Offset(50, 50),
        small: true);
    expect(s.dy, closeTo(-36, 1e-9));
    // Centre on the line itself: bow upwards.
    final up = LinkPathsCanvas.aerialControl(
        Offset.zero, const Offset(100, 0), const Offset(50, 0));
    expect(up.dy, lessThan(0));
  });

  testWidgets('motion on: animates and draws a moving dot', (tester) async {
    LinkMotion217.debugForce = true;
    await tester.pumpWidget(_host(_three));
    await tester.pump();
    expect(_state(tester).debugAnimating, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(_record(tester).circles.where(_isDot), isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('motion off by "Remove animations"', (tester) async {
    LinkMotion217.motionInTests = true;
    await tester.pumpWidget(_host(_three, noAnim: true));
    await tester.pump();
    expect(_state(tester).debugAnimating, isFalse);
    expect(_record(tester).circles.where(_isDot), isEmpty);
  });

  testWidgets('motion off by battery saver, back on when it ends', (tester) async {
    LinkMotion217.motionInTests = true;
    await tester.pumpWidget(_host(_three));
    await tester.pump();
    expect(_state(tester).debugAnimating, isTrue);
    LinkMotion217.powerSave.value = true;
    await tester.pump();
    expect(_state(tester).debugAnimating, isFalse);
    LinkMotion217.powerSave.value = false;
    await tester.pump();
    expect(_state(tester).debugAnimating, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('motion off while the app is paused', (tester) async {
    LinkMotion217.motionInTests = true;
    await tester.pumpWidget(_host(_three));
    await tester.pump();
    expect(_state(tester).debugAnimating, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(_state(tester).debugAnimating, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_state(tester).debugAnimating, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('old tests stay quiet: no motion under flutter test by default', (tester) async {
    await tester.pumpWidget(_host(_three));
    await tester.pumpAndSettle();
    expect(_state(tester).debugAnimating, isFalse);
  });

  testWidgets('blocked only: grey dashes, no dot', (tester) async {
    LinkMotion217.debugForce = true;
    await tester.pumpWidget(_host(const [
      LinkNode(id: 'd-ali', label: 'Ali', tag: LinkTag.wifiDirect, userId: 'u-ali', blocked: true),
    ], serverOnline: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_record(tester).circles.where(_isDot), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dark map: dark server circle', (tester) async {
    await tester.pumpWidget(_host(_three, dark: true));
    await tester.pump();
    // Paint keeps float colours: compare as ARGB ints.
    final colors = _record(tester).circles.map((c) => c.color.toARGB32()).toList();
    expect(colors, contains(0xFF161B22));
    expect(colors, contains(0xFF2F6BFF));
  });

  testWidgets('shouldRepaint on theme / motion change; old literals kept', (tester) async {
    await tester.pumpWidget(_host(_three));
    await tester.pump();
    final light = _painter(tester);
    await tester.pumpWidget(_host(_three, dark: true));
    await tester.pump(const Duration(milliseconds: 400)); // theme change animates
    final dark = _painter(tester);
    expect(dark.shouldRepaint(light), isTrue);
    LinkMotion217.motionInTests = true;
    LinkMotion217.powerSave.value = true;
    await tester.pumpWidget(_host(_three, dark: true));
    await tester.pump();
    final still = _painter(tester);
    LinkMotion217.powerSave.value = false;
    await tester.pump();
    final moving = _painter(tester);
    expect(moving.shouldRepaint(still), isTrue);
    expect(still.shouldRepaint(dark), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  test('sources keep the old literals and the native branch', () {
    final src = _read('lib/features/admin/presentation/widgets/link_paths_map.dart');
    expect(src, contains('old.crownKey != crownKey'));
    expect(src, contains('_crown(canvas'));
    expect(src, contains('paintCrown217('));
    expect(src, isNot(contains('\\u{1F451}')));
    expect(_read('android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt'),
        contains('call.method == "powerSave"'));
  });
}

String _read(String path) => File(path).readAsStringSync();
