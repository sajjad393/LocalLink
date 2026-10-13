import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/local_link_splash.dart';

void main() {
  testWidgets('splash renders brand logo, wordmark and progress bar',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LocalLinkSplashScreen()));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(LocalLinkSplashScreen), findsOneWidget);
    expect(find.text('LocalLink'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      LocalLinkSplashScreen.logoAsset,
    );

    // Entrance animation completes without errors.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('skips the entrance animation when animations are disabled',
      (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(const MaterialApp(home: LocalLinkSplashScreen()));
    await tester.pump();

    expect(find.text('LocalLink'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
