// Bundle 298 (A + B) regression: the big map full screen (bars hidden,
// Exit pill, Back leaves full screen first, bars back on dispose) and the
// one search pill (no inner border from the theme, 2 dp ring only while
// typing, typing works).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/widgets/search_pill_298.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/screens/link_paths_full_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

void main() {
  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('298-A full screen map', () {
    const nodes = [
      LinkNode(id: 'a', label: 'Bilal', tag: LinkTag.wifiDirect),
      LinkNode(id: 'b', label: 'Sana', tag: LinkTag.mesh),
    ];

    testWidgets('open hides bars + top bar, Exit and Back come back, dispose restores', (tester) async {
      bigView(tester);
      final modes = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') modes.add('${call.arguments}');
        // Manual mode (bars shown) goes as the overlay list.
        if (call.method == 'SystemChrome.setEnabledSystemUIOverlays') modes.add('manual ${call.arguments}');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('HOME'))));
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => LinkPathsFullScreen(
              nodes: nodes, serverOnline: true, targetFor: (n) => BlockTarget(userId: n.id, name: n.label))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link_map_full_298_open')), findsOneWidget);
      expect(find.byKey(const ValueKey('link_map_full_298')), findsNothing);
      expect(find.byKey(const ValueKey('link_map_search')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('link_map_full_298_open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link_map_full_298')), findsOneWidget);
      expect(find.byKey(const ValueKey('link_map_full_298_exit')), findsOneWidget);
      expect(find.byKey(const ValueKey('link_map_search')), findsNothing, reason: 'only the map + zoom + Exit');
      expect(find.byTooltip('Small map'), findsNothing);
      expect(modes.last, contains('immersiveSticky'));
      expect(find.text('Bilal'), findsWidgets, reason: 'people still on the map');

      await tester.tap(find.byKey(const ValueKey('link_map_full_298_exit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link_map_full_298')), findsNothing);
      expect(find.byKey(const ValueKey('link_map_search')), findsOneWidget);
      expect(modes.last, contains('manual'));

      // Back: first leaves full screen, the page stays.
      await tester.tap(find.byKey(const ValueKey('link_map_full_298_open')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link_map_full_298')), findsNothing);
      expect(find.byType(LinkPathsFullScreen), findsOneWidget);

      // Leaving the page while full: bars come back.
      await tester.tap(find.byKey(const ValueKey('link_map_full_298_open')));
      await tester.pumpAndSettle();
      modes.clear();
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('HOME'))));
      await tester.pumpAndSettle();
      expect(modes, isNotEmpty);
      expect(modes.last, contains('manual'));
    });
  });

  group('298-B search pill', () {
    Future<TextEditingController> pump(WidgetTester tester, ThemeData theme) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: SearchPill298(controller: c, hint: 'Search', fieldKey: const ValueKey('f298')))),
      ));
      return c;
    }

    BoxDecoration deco(WidgetTester tester) => tester
        .widget<AnimatedContainer>(find.byKey(const ValueKey('search_pill_298')))
        .decoration! as BoxDecoration;

    for (final dark in [false, true]) {
      testWidgets('no inner box, ring only while typing, typing works (${dark ? 'dark' : 'light'})', (tester) async {
        final c = await pump(tester, dark ? LocalLinkTheme.dark() : LocalLinkTheme.light());
        final field = tester.widget<TextField>(find.byKey(const ValueKey('f298')));
        for (final b in [
          field.decoration!.border,
          field.decoration!.enabledBorder,
          field.decoration!.focusedBorder,
        ]) {
          expect(b, InputBorder.none);
        }
        expect((deco(tester).border! as Border).top.color, Colors.transparent);
        await tester.tap(find.byKey(const ValueKey('f298')));
        await tester.pumpAndSettle();
        final ring = (deco(tester).border! as Border).top;
        expect(ring.color, isNot(Colors.transparent));
        expect(ring.width, 2);
        await tester.enterText(find.byKey(const ValueKey('f298')), 'sana');
        await tester.pump();
        expect(c.text, 'sana');
        // The real decorator draws no outline inside the pill.
        final dec = tester.widget<InputDecorator>(find.descendant(
            of: find.byKey(const ValueKey('f298')), matching: find.byType(InputDecorator)));
        expect(dec.decoration.focusedBorder, InputBorder.none);
      });
    }

    test('every listed search uses the pill (source)', () {
      for (final f in [
        'lib/core/widgets/chat_search_bar.dart',
        'lib/features/home/presentation/widgets/chats_search.dart',
        'lib/features/groups/presentation/screens/new_group_screen.dart',
        'lib/features/groups/presentation/screens/group_info_screen.dart',
        'lib/features/messaging/presentation/screens/forward_screen.dart',
        'lib/features/directory/presentation/contacts_screen.dart',
        'lib/features/admin/presentation/widgets/admin_list_page.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('SearchPill298('), reason: f);
      }
    });
  });
}
