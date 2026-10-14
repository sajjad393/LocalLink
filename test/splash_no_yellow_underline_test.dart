import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/widgets/local_link_splash.dart';

void main() {
  testWidgets('splash text never falls back to the yellow-underline engine style',
      (tester) async {
    // Mount the splash EXACTLY the way startup does — bare, with no Scaffold.
    // Mount exactly like startup: MaterialApp(home: splash) — note no Scaffold.
    await tester.pumpWidget(const MaterialApp(home: LocalLinkSplashScreen()));
    for (final text in ['LocalLink', 'Secure, local-first messaging']) {
      // a Material ancestor must sit between the text and the root
      expect(
        find.ancestor(of: find.text(text), matching: find.byType(Material)),
        findsOneWidget,
      );
      final widget = tester.widget<Text>(find.text(text));
      expect(widget.style?.decoration, isNot(TextDecoration.underline));
    }
  });
}
