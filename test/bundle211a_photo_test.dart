import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/account/presentation/widgets/photo_tap_overlay.dart';

String _src(String p) => File(p).readAsStringSync();

const _profile = 'lib/features/account/presentation/screens/profile_screen.dart';
const _account = 'lib/features/account/presentation/screens/account_center_screen.dart';

void main() {
  group('211 A pure', () {
    test('inner circle leaves the lock ring clear', () {
      expect(PhotoTapOverlay.innerFor(52, locked: false), 52);
      final inner = PhotoTapOverlay.innerFor(52, locked: true);
      expect(inner, lessThan(52));
      expect(inner, greaterThan(40));
    });

    test('Profile: no camera button, tap overlay + hint, saves at once', () {
      final s = _src(_profile);
      expect(s, isNot(contains('IconButton.filled(tooltip: \'Change profile photo\'')));
      expect(s, contains('PhotoTapOverlay('));
      expect(s, contains('onCamera: _pickImage'));
      expect(s, contains("ValueKey('profile_photo_hint')"));
      expect(s, contains("'Tap photo to change'"));
      expect(s, contains("'Tap photo to add one'"));
      expect(s, contains("'Tap the camera to choose a photo'"));
      expect(s, contains('bool get _photoSavesAtOnce => _usernameLocked && !widget.onboarding;'));
      expect('if (_photoSavesAtOnce) await save();'.allMatches(s).length, 2);
      // lock rule kept (Bundle 203)
      expect(s, contains('locked: own ?? ProfilePrivacyRule.isPrivate(value)'));
    });

    test('Account: my picture gets the lock too', () {
      final s = _src(_account);
      expect(s, contains("ValueKey('account_own_avatar')"));
      expect(s, contains('ProfilePrivacyRule.ownPrivate'));
      expect(s, contains('ProfilePrivacyRule.isPrivate(profile)'));
    });
  });

  group('211 A overlay', () {
    Future<int> pump(WidgetTester tester, {bool locked = true}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PhotoTapOverlay(
              radius: 52,
              innerRadius: PhotoTapOverlay.innerFor(52, locked: locked),
              onCamera: () => opened++,
              child: const CircleAvatar(radius: 52, key: ValueKey('pic')),
            ),
          ),
        ),
      ));
      return opened;
    }

    testWidgets('nothing shows until a tap', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('profile_photo_overlay')), findsNothing);
      expect(find.byKey(const ValueKey('profile_photo_camera')), findsNothing);
    });

    testWidgets('tap → camera for 3 s, then it hides', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('pic')));
      await tester.pump();
      expect(find.byKey(const ValueKey('profile_photo_camera')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(find.byKey(const ValueKey('profile_photo_camera')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('profile_photo_camera')), findsNothing);
    });

    testWidgets('tap the camera → the photo choice opens', (tester) async {
      var opened = 0;
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final showing = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PhotoTapOverlay(
              radius: 52,
              innerRadius: 46,
              onCamera: () => opened++,
              onShowingChanged: showing.add,
              child: const CircleAvatar(radius: 52, key: ValueKey('pic')),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('pic')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('profile_photo_camera')));
      await tester.pump();
      expect(opened, 1);
      expect(find.byKey(const ValueKey('profile_photo_camera')), findsNothing);
      expect(showing, [true, false]);
      await tester.pump(const Duration(seconds: 4));
      expect(opened, 1);
    });

    testWidgets('dark circle is inside the lock ring', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('pic')));
      await tester.pump();
      final size = tester.getSize(find.byKey(const ValueKey('profile_photo_overlay')));
      expect(size.width, closeTo(2 * PhotoTapOverlay.innerFor(52, locked: true), 0.01));
      expect(size.width, lessThan(104));
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
