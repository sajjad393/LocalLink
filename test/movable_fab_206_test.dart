import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locallink/core/widgets/brand_gradient_fab.dart';
import 'package:locallink/core/widgets/movable_fab.dart';

const _area = Size(360, 600);

Widget _app(FabPlace place, {VoidCallback? onTap, int items = 0}) =>
    MaterialApp(
      home: Scaffold(
        body: MovableFabArea(
          place: place,
          fab: BrandGradientFab(
            heroTag: 'test_fab',
            tooltip: 'New conversation',
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: onTap ?? () {},
          ),
          child: ListView(
            key: const ValueKey('list'),
            children: [
              for (var i = 0; i < items; i++)
                SizedBox(height: 80, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );

Offset _fabTopLeft(WidgetTester tester) =>
    tester.getTopLeft(find.byType(BrandGradientFab)) -
    tester.getTopLeft(find.byType(MovableFabArea));

Future<void> _holdAndDrag(WidgetTester tester, Offset by) async {
  final g = await tester
      .startGesture(tester.getCenter(find.byType(BrandGradientFab)));
  await tester.pump(const Duration(milliseconds: 600));
  await g.moveBy(by / 2);
  await tester.pump();
  await g.moveBy(by / 2);
  await tester.pump();
  await g.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('206 rules', () {
    test('today\'s place is bottom-right, 16 from the edges', () {
      final o = FabPlaceRules.offsetFor(FabPosition.home, _area, 56);
      expect(o, const Offset(360 - 56 - 16, 600 - 56 - 16));
      final l = FabPlaceRules.offsetFor(
          const FabPosition(left: true, y: 0), _area, 56);
      expect(l, const Offset(16, 16));
    });

    test('let go: the nearest side, the same height', () {
      final left = FabPlaceRules.dropAt(const Offset(100, 272), _area, 56);
      expect(left.left, isTrue);
      expect(left.y, closeTo(0.5, 0.001));
      final right = FabPlaceRules.dropAt(const Offset(200, 16), _area, 56);
      expect(right.left, isFalse);
      expect(right.y, 0);
      // Below the area: kept at the bottom.
      expect(FabPlaceRules.dropAt(const Offset(10, 900), _area, 56).y, 1);
    });

    test(
        'the height is a share of the area, so a smaller area (keyboard) '
        'keeps it inside', () {
      const pos = FabPosition(left: true, y: 1);
      final small = FabPlaceRules.offsetFor(pos, const Size(360, 300), 56);
      expect(small.dy, 300 - 56 - 16);
      final tiny = FabPlaceRules.offsetFor(pos, const Size(360, 60), 56);
      expect(tiny.dy, 16);
    });

    test('dragging is kept inside the area', () {
      expect(FabPlaceRules.clampDrag(const Offset(-50, -50), _area, 56),
          const Offset(16, 16));
      expect(FabPlaceRules.clampDrag(const Offset(999, 999), _area, 56),
          const Offset(360 - 56 - 16, 600 - 56 - 16));
    });

    test('values', () {
      expect(FabPlaceRules.margin, 16);
      expect(FabPlaceRules.liftScale, 1.15);
      expect(FabPlaceRules.slide, const Duration(milliseconds: 200));
      expect(FabPlaceRules.hintTimes, 2);
    });
  });

  group('206 place store', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('saved and read back', () async {
      final a = FabPlace();
      await a.load();
      expect(a.value, FabPosition.home);
      await a.move(const FabPosition(left: true, y: 0.4));
      final b = FabPlace();
      await b.load();
      expect(b.value, const FabPosition(left: true, y: 0.4));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FabPlace.sideKey), 'left');
      expect(prefs.getDouble(FabPlace.yKey), 0.4);
    });

    test('a bad saved value falls back inside', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{FabPlace.sideKey: 'right', FabPlace.yKey: 7.0});
      final a = FabPlace();
      await a.load();
      expect(a.value, const FabPosition(left: false, y: 1));
    });
  });

  group('206 moving the button', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    testWidgets('a quick tap opens it and nothing moves', (tester) async {
      final place = FabPlace();
      var taps = 0;
      await tester.pumpWidget(_app(place, onTap: () => taps++));
      await tester.pump();
      final before = _fabTopLeft(tester);
      await tester.tap(find.byType(BrandGradientFab));
      await tester.pump(const Duration(milliseconds: 300));
      expect(taps, 1);
      expect(_fabTopLeft(tester), before);
      expect(place.value, FabPosition.home);
    });

    testWidgets('hold, drag left, let go: it slides to the left edge',
        (tester) async {
      final place = FabPlace();
      var taps = 0;
      await tester.pumpWidget(_app(place, onTap: () => taps++));
      await tester.pump();
      await _holdAndDrag(tester, const Offset(-600, -150));
      expect(taps, 0);
      expect(place.value.left, isTrue);
      expect(place.value.y, lessThan(1));
      expect(_fabTopLeft(tester).dx, 16);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FabPlace.sideKey), 'left');
    });

    testWidgets('a small drag right of the middle goes back to the right edge',
        (tester) async {
      final place = FabPlace();
      await tester.pumpWidget(_app(place));
      await tester.pump();
      await _holdAndDrag(tester, const Offset(-60, -200));
      expect(place.value.left, isFalse);
      final area = tester.getSize(find.byType(MovableFabArea));
      expect(_fabTopLeft(tester).dx, area.width - 56 - 16);
    });

    testWidgets('holding shows "Drag to move" only the first 2 times',
        (tester) async {
      final place = FabPlace();
      await tester.pumpWidget(_app(place));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        final g = await tester
            .startGesture(tester.getCenter(find.byType(BrandGradientFab)));
        await tester.pump(const Duration(milliseconds: 600));
        expect(
            find.text('Drag to move'), i < 2 ? findsOneWidget : findsNothing);
        await g.up();
        await tester.pump(const Duration(milliseconds: 400));
      }
    });

    testWidgets('one place: another tab follows at once', (tester) async {
      final place = FabPlace();
      await tester.pumpWidget(_app(place));
      await tester.pump();
      await place.move(const FabPosition(left: true, y: 0.5));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MovableFabArea(
            place: place,
            fab: BrandGradientFab(
                heroTag: 'other',
                tooltip: 'New call',
                icon: Icons.add_ic_call_rounded,
                onPressed: () {}),
            child: const SizedBox.expand(),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_fabTopLeft(tester).dx, 16);
    });

    testWidgets('scrolling the list never moves it', (tester) async {
      final place = FabPlace();
      await tester.pumpWidget(_app(place, items: 30));
      await tester.pump();
      final before = _fabTopLeft(tester);
      await tester.fling(
          find.byKey(const ValueKey('list')), const Offset(0, -500), 2000);
      await tester.pumpAndSettle();
      expect(_fabTopLeft(tester), before);
      expect(place.value, FabPosition.home);
    });

    testWidgets('the saved place is used at start', (tester) async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{FabPlace.sideKey: 'left', FabPlace.yKey: 0.0});
      final place = FabPlace();
      await tester.pumpWidget(_app(place));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_fabTopLeft(tester), const Offset(16, 16));
    });
  });

  group('206 the 3 tabs use it', () {
    test('Chats, Calls and People', () {
      String read(String p) => File(p).readAsStringSync();
      final chats =
          read('lib/features/home/presentation/screens/home_screen.dart');
      final calls =
          read('lib/features/calls/presentation/screens/calls_screen.dart');
      final people =
          read('lib/features/directory/presentation/contacts_screen.dart');
      for (final s in [chats, calls, people]) {
        expect(s, contains('MovableFabArea('), reason: 'tab body');
      }
      expect(chats, contains("heroTag: 'home_fab'"));
      expect(calls, contains("heroTag: 'calls_fab'"));
      expect(people, contains("heroTag: 'add_contact_fab'"));
      for (final s in [chats, calls, people]) {
        expect(s, isNot(contains('floatingActionButton:')));
      }
    });
  });
}
