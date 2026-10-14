import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';

Widget _host(Widget child, [ThemeData? theme]) => MaterialApp(
      theme: theme ?? LocalLinkTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  group('brand theme v2', () {
    test('light theme is anchored in the blue→cyan brand family', () {
      final scheme = LocalLinkTheme.light().colorScheme;
      expect(scheme.primary, LocalLinkBrand.gradientStart);
      expect(scheme.secondary, isNot(scheme.primary));
    });

    test('app bars stay flat and use the bolder brand title', () {
      final appBar = LocalLinkTheme.light().appBarTheme;
      expect(appBar.scrolledUnderElevation, 0);
      expect(appBar.titleTextStyle?.fontWeight, FontWeight.w800);
    });

    test('motion assets are declared by the token set', () {
      expect(LocalLinkAssets.lottieLoadingRadar, contains('radar_pulse'));
      expect(LocalLinkAssets.lottieEmptyInbox, contains('empty_inbox'));
    });
  });

  group('shared state views', () {
    testWidgets('loading view is Lottie-first and shows the message', (tester) async {
      await tester.pumpWidget(_host(
          const LocalLinkLoadingView(message: 'Loading your conversations…')));
      expect(find.byType(Lottie), findsOneWidget);
      expect(find.text('Loading your conversations…'), findsOneWidget);
    });

    testWidgets('invalid lottie asset falls back to the plain spinner', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(
        child: LocalLinkEmptyView(
          icon: Icons.forum_outlined,
          lottieAsset: 'assets/animations/does_not_exist.json',
          title: 'Nothing here',
          message: 'No items yet.',
        ),
      )));
      await tester.pump();
      // Fallback must kick in: no crash, the icon circle is drawn instead.
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('empty view keeps title, message and action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(LocalLinkEmptyView(
        icon: Icons.people_outline,
        title: 'No contacts yet',
        message: 'Add a contact to get started.',
        actionLabel: 'Add contact',
        onAction: () => tapped = true,
      )));
      await tester.tap(find.text('Add contact'));
      expect(tapped, isTrue);
    });
  });
}
