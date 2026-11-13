// Bundle 283: Add Contact cleanup (mock `mocks/add_contact_improved_283.html`
// + `_light.html`): no Bluetooth / Wi-Fi Direct words, new search look, same
// look on every phone (Roboto, text cap 1.3x, fixed colours, light version),
// QR buttons with one job each.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
import 'package:locallink/features/directory/data/people_to_add_267.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart';
import 'package:locallink/features/directory/presentation/add_contact_ui283.dart';

String _read(String path) => File(path).readAsStringSync();

const _ui = [
  'lib/features/directory/presentation/add_contact_screen.dart',
  'lib/features/directory/presentation/nearby_people_section.dart',
  'lib/features/directory/presentation/my_qr_screen.dart',
  'lib/features/directory/presentation/add_contact_ui283.dart',
];

/// Only the quoted words (comments may still explain the radios).
List<String> _literals(String src) {
  final code = src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
  return [
    for (final m in RegExp(r"'([^'\\\n]|\\.)*'|" r'"([^"\\\n]|\\.)*"').allMatches(code)) m.group(0)!,
  ];
}

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  bool dark = true,
  double width = 360,
  double textScale = 1,
  bool calm = false,
}) async {
  tester.view.physicalSize = Size(width * 2, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: LocalLinkTheme.light(),
    darkTheme: LocalLinkTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Builder(
      builder: (context) => MediaQuery(
        data: LocalLinkLook.clampScaler(MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: calm,
        )),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 900));
}

const _sara = DirectoryProfile(
  userId: 'u-sara',
  username: 'sara',
  displayName: 'Sara Khan',
  deviceId: '',
);

void main() {
  group('283 words and buttons (source)', () {
    test('1. no Bluetooth / Wi-Fi Direct words on the Add Contact screens', () {
      for (final path in _ui) {
        for (final lit in _literals(_read(path))) {
          expect(lit.contains('Bluetooth'), isFalse, reason: '$path $lit');
          expect(lit.contains('Wi-Fi Direct'), isFalse, reason: '$path $lit');
        }
      }
      final nearby = _read(_ui[1]);
      expect(nearby, isNot(contains('NearbyChips256')));
      expect(nearby, contains("'NEARBY_LIST'"), reason: 'the NEARBY_LIST log stays');
    });

    test('2. QR: Scan = camera, My QR code = my code, From photo, Paste code stays', () {
      final qr = _read(_ui[2]);
      expect(qr, contains('pushReplacement('));
      expect(qr, contains('scanner.analyzeImage(path)'));
      expect(qr, contains('linkUpQrScannerController()'));
      expect(qr, contains("'No QR code found in this picture'"));
      expect(qr, contains("ValueKey('scan_my_qr_283')"));
      expect(qr, contains("ValueKey('scan_from_photo_283')"));
      expect(qr, contains("ValueKey('scan_paste_283')"));
      expect(qr, contains("\"Point at your friend's QR code\""));
      expect(qr, contains("'Share my QR'"));
      expect(qr, contains("'Scan instead'"));
      expect(qr, contains('size: 208'));
      final add = _read(_ui[0]);
      expect(add, contains('myProfile: widget.pairing?.ownQrProfile242,'));
    });

    test('3. same look on every phone: Roboto, text cap 1.3x, fixed colours', () {
      expect(LocalLinkTheme.dark().textTheme.bodyMedium?.fontFamily, LocalLinkLook.fontFamily);
      expect(LocalLinkTheme.light().textTheme.bodyMedium?.fontFamily, LocalLinkLook.fontFamily);
      const big = MediaQueryData(textScaler: TextScaler.linear(2));
      expect(LocalLinkLook.clampScaler(big).textScaler.scale(10), 13);
      expect(_read('lib/app/local_link_app.dart'), contains('builder: _look290'));
      expect(LinkPalette.dark.card, const Color(0xFF1A1B22));
      expect(LinkPalette.light.card, Colors.white);
    });

    test('4. scene height by width (S-3): 320 -> 184, 360+ -> 212', () {
      expect(AddUi283.sceneHeight(320), 184);
      expect(AddUi283.sceneHeight(300), 184);
      expect(AddUi283.sceneHeight(360), 212);
      expect(AddUi283.sceneHeight(412), 212);
      expect(AddUi283.sceneHeight(340), closeTo(198, .01));
    });

    test('5. empty screen words', () {
      expect(PeopleToAdd267.emptyServerTitle, "You've added everyone");
      expect(PeopleToAdd267.emptyServer,
          'Everyone on LinkUp is already in your contacts. To add someone new, search their name or use a QR code.');
    });
  });

  group('283 widgets', () {
    testWidgets('6. a contact: green Contact pill + @user', (tester) async {
      await _show(
          tester,
          SearchResultCard(
            profile: _sara,
            initial: 'S',
            isContact: true,
            onOpen: () {},
            onAdd: () {},
          ));
      expect(find.byKey(const Key('search_result_added')), findsOneWidget);
      expect(find.text('Contact'), findsOneWidget);
      expect(find.text('@sara'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('7. not a contact: gradient Add + "@user · Offline"', (tester) async {
      var added = 0;
      await _show(
          tester,
          SearchResultCard(
            profile: _sara,
            initial: 'S',
            isContact: false,
            onOpen: () {},
            onAdd: () => added++,
          ));
      expect(find.text('@sara · Offline'), findsOneWidget);
      await tester.tap(find.byKey(const Key('search_result_add')));
      expect(added, 1);
    });

    testWidgets('8. not found card + QR hint', (tester) async {
      await _show(tester, const Column(children: [NotFoundCard283(query: 'qqq'), QrHint283()]));
      expect(find.text('No one called "qqq" on LinkUp'), findsOneWidget);
      expect(find.text(QrHint283.text), findsOneWidget);
    });

    testWidgets('9. empty screen: title, words, two actions', (tester) async {
      var qr = 0, near = 0;
      await _show(
          tester,
          EmptyAdd283(
            title: PeopleToAdd267.emptyServerTitle,
            text: PeopleToAdd267.emptyServer,
            textKey: const ValueKey('people267_empty'),
            onMyQr: () => qr++,
            onNearby: () => near++,
          ));
      expect(find.text("You've added everyone"), findsOneWidget);
      expect(find.byKey(const ValueKey('people267_empty')), findsOneWidget);
      expect(find.text('Show my QR code'), findsOneWidget);
      expect(find.text('Let a friend scan you'), findsOneWidget);
      expect(find.text('Find people nearby'), findsOneWidget);
      expect(find.text('Phones around you with LinkUp'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add283_opt_qr')));
      await tester.tap(find.byKey(const ValueKey('add283_opt_nearby')));
      expect((qr, near), (1, 1));
    });

    testWidgets('10. no Nearby on this phone -> only the QR action', (tester) async {
      await _show(
          tester,
          EmptyAdd283(
            title: PeopleToAdd267.emptyNearbyTitle,
            text: PeopleToAdd267.emptyNearby,
            onMyQr: () {},
          ));
      expect(find.text('Show my QR code'), findsOneWidget);
      expect(find.text('Find people nearby'), findsNothing);
    });

    testWidgets('11. Wi-Fi card: words + the button only calls back', (tester) async {
      var taps = 0;
      await _show(
          tester,
          WarnCard283(
            kind: WarnKind283.wifi,
            title: 'Wi-Fi is off',
            text: 'Turn it on to find phones near you',
            action: 'Turn on',
            onPressed: () => taps++,
          ));
      expect(find.text('Wi-Fi is off'), findsOneWidget);
      expect(find.text('Turn it on to find phones near you'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      expect(taps, 1);
    });

    testWidgets('12. section title = small capitals + live "Searching"', (tester) async {
      await _show(tester, const SectionTitle283('People nearby', live: true));
      expect(find.text('PEOPLE NEARBY'), findsOneWidget);
      expect(find.text('Searching'), findsOneWidget);
      final t = tester.widget<Text>(find.text('PEOPLE NEARBY'));
      expect(t.style?.fontSize, 12);
      expect(t.style?.letterSpacing, 1);
    });

    testWidgets('13. search scene on a small phone (320 dp) is 184 high', (tester) async {
      await _show(tester, const NearbyScene283(meInitial: 'S'), width: 320);
      expect(tester.getSize(find.byType(NearbyScene283)).height, 184);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('14. "Remove animations" = still frame (nothing keeps ticking)', (tester) async {
      await _show(
          tester,
          const Column(children: [
            NearbyScene283(),
            LookingText283('Looking for phones near you'),
            SectionTitle283('People nearby', live: true),
          ]),
          calm: true);
      await tester.pumpAndSettle();
      expect(find.text('Looking for phones near you'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('15. light version + big text (1.3x) on 320 dp: no overflow', (tester) async {
      await _show(
          tester,
          Column(children: [
            SearchResultCard(
              profile: _sara,
              initial: 'S',
              isContact: false,
              onOpen: () {},
              onAdd: () {},
            ),
            const WarnCard283(
              kind: WarnKind283.nearby,
              title: 'Find phones near you',
              text: 'LinkUp needs your OK once',
              action: 'Allow',
            ),
            const ScanButton283(),
          ]),
          dark: false,
          width: 320,
          textScale: 2);
      expect(tester.takeException(), isNull);
      final card = tester.widget<Container>(find
          .ancestor(of: find.text('Sara Khan'), matching: find.byType(Container))
          .last);
      expect((card.decoration! as BoxDecoration).color, Colors.white);
      expect(find.text('Scan QR code'), findsOneWidget);
    });
  });
}
