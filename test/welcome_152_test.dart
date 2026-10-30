import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/locallink_logo_mark.dart';
import 'package:locallink/features/authentication/presentation/screens/welcome_screen.dart';
import 'package:locallink/features/authentication/presentation/widgets/welcome_mesh_background.dart';

Widget _host({
  required VoidCallback onCreateAccount,
  required VoidCallback onLogIn,
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 844),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: reduceMotion),
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: WelcomeView(onCreateAccount: onCreateAccount, onLogIn: onLogIn),
    ),
  );
}

WelcomeMeshPainter _meshPainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.descendant(
    of: find.byType(WelcomeMeshBackground),
    matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is WelcomeMeshPainter),
  ));
  return paint.painter! as WelcomeMeshPainter;
}

void _phone(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  group('WelcomeView (bundle 152)', () {
    testWidgets('shows the new texts and the 3 cards', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(onCreateAccount: () {}, onLogIn: () {}));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('LocalLink'), findsOneWidget);
      expect(find.text(WelcomeView.tagline), findsOneWidget);
      expect(find.text('Messages, photos, videos'), findsOneWidget);
      expect(find.text('Nearby, Online or Offline'), findsOneWidget);
      expect(find.text('Voice calls'), findsOneWidget);
      expect(find.text('Private and secure'), findsOneWidget);
      expect(find.text('Your account, your chats'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(
          find.textContaining('I already have an account', findRichText: true),
          findsOneWidget);
      expect(find.text('Messages that work anywhere'), findsNothing);
      expect(find.byType(LocalLinkLogoMark), findsOneWidget);
      expect(find.byType(WelcomeMeshBackground), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('Create account is the main button, Log in is the link',
        (tester) async {
      _phone(tester);
      var created = 0;
      var loggedIn = 0;
      await tester.pumpWidget(_host(
        onCreateAccount: () => created++,
        onLogIn: () => loggedIn++,
      ));
      await tester.pump();

      await tester.tap(find.text('Create account'));
      await tester.pump();
      expect(created, 1);
      expect(loggedIn, 0);

      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(loggedIn, 1);
      expect(created, 1);
      await _dispose(tester);
    });

    testWidgets('animation keeps running while the screen is open',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(onCreateAccount: () {}, onLogIn: () {}));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isTrue);
      final first = _meshPainter(tester).seconds;
      await tester.pump(const Duration(milliseconds: 700));
      final second = _meshPainter(tester).seconds;
      expect(second, isNot(first));
      expect(_meshPainter(tester).showPackets, isTrue);
      await _dispose(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('"Remove animations" shows a still picture', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
          _host(onCreateAccount: () {}, onLogIn: () {}, reduceMotion: true));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      final painter = _meshPainter(tester);
      expect(painter.showPackets, isFalse);
      expect(painter.seconds, WelcomeMeshPainter.stillFrameSeconds);
      await _dispose(tester);
    });

    testWidgets('small phone: no overflow, buttons still reachable',
        (tester) async {
      tester.view.physicalSize = const Size(320, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
        onCreateAccount: () {},
        onLogIn: () {},
        size: const Size(320, 540),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(find.text('Create account'),
          find.byType(SingleChildScrollView), const Offset(0, -80));
      expect(find.text('Create account').hitTestable(), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('dark theme builds without errors', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(
          onCreateAccount: () {}, onLogIn: () {}, brightness: Brightness.dark));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(_meshPainter(tester).dark, isTrue);
      await _dispose(tester);
    });
  });

  group('WelcomeMeshPainter', () {
    test('mesh has lines and every packet route uses a real line', () {
      expect(WelcomeMeshPainter.edges, isNotEmpty);
      for (var k = 0; k < 200; k++) {
        final (a, b) = WelcomeMeshPainter.packetRoute(k);
        expect(a, isNot(b));
        final ok = WelcomeMeshPainter.edges
            .any((e) => (e.$1 == a && e.$2 == b) || (e.$1 == b && e.$2 == a));
        expect(ok, isTrue, reason: 'packet $k uses edge $a-$b');
      }
    });

    test('about two or three messages move at a time', () {
      for (var t = 2.0; t < 60; t += 0.37) {
        final n = WelcomeMeshPainter.activePackets(t).length;
        expect(n, inInclusiveRange(2, 3), reason: 't=$t');
        for (final (_, p) in WelcomeMeshPainter.activePackets(t)) {
          expect(p, inInclusiveRange(0, 1));
        }
      }
    });

    test('the receiving phone pulses right after a message arrives', () {
      const k = 10;
      const arrive =
          k * WelcomeMeshPainter.packetEvery + WelcomeMeshPainter.packetTravel;
      final to = WelcomeMeshPainter.packetRoute(k).$2;
      final pulses = WelcomeMeshPainter.pulsesAt(arrive + 0.05);
      expect(pulses[to], greaterThan(0.8));
    });

    test('loop is seamless (drift at 0 s and 60 s match)', () {
      const size = Size(390, 230);
      final a = WelcomeMeshPainter.nodesAt(0, size);
      final b = WelcomeMeshPainter.nodesAt(
          WelcomeMeshPainter.loopSeconds.toDouble(), size);
      for (var i = 0; i < a.length; i++) {
        expect((a[i] - b[i]).distance, lessThan(0.001));
      }
    });

    test('paints at many times without throwing', () {
      for (final dark in [false, true]) {
        for (var t = 0.0; t < 61; t += 0.9) {
          final recorder = PictureRecorder();
          WelcomeMeshPainter(seconds: t, dark: dark)
              .paint(Canvas(recorder), const Size(390, 230));
          recorder.endRecording().dispose();
        }
      }
    });
  });

  test('logo mark path has two holes and fits its box', () {
    const size = Size(237, 146);
    final path = LocalLinkLogoPainter.markPath(size);
    final bounds = path.getBounds();
    expect(bounds.left, closeTo(0, 0.5));
    expect(bounds.right, closeTo(237, 0.5));
    expect(bounds.height, closeTo(146, 0.5));
    // ring band is filled, hole centres are empty, the middle overlap is filled
    expect(path.contains(const Offset(20, 73)), isTrue);
    expect(path.contains(const Offset(73, 73)), isFalse);
    expect(path.contains(const Offset(164, 73)), isFalse);
    expect(path.contains(const Offset(118, 73)), isTrue);
  });
}
