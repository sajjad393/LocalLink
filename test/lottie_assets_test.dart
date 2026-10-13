// Validity guard for the hand-authored Lottie animations shipped in
// assets/animations/. If any JSON is malformed the lottie package throws
// during composition parsing — this test fails instead of the production UI.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assets = <String>[
    'assets/animations/chat_hero.json',
    'assets/animations/radar_pulse.json',
    'assets/animations/empty_inbox.json',
  ];

  for (final asset in assets) {
    testWidgets('parses and renders $asset', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(child: Lottie.asset(asset, width: 120, height: 120)),
      ));
      // pumpFrame lets the composition load asynchronously; an invalid file
      // surfaces an exception during this pump.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(Lottie), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
