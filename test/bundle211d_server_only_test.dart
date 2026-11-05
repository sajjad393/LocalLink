import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/home/presentation/screens/messenger_settings_screen.dart';

void main() {
  group('211 D Admin section only with the server', () {
    Future<AppViewModeCubit> pump(WidgetTester tester, {required bool online}) async {
      final view = AppViewModeCubit()..setServerConnected(online);
      addTearDown(view.close);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ServerOnlySection(
            viewMode: view,
            child: const Text('Admin panel'),
          ),
        ),
      ));
      return view;
    }

    testWidgets('offline from the start: hidden', (tester) async {
      await pump(tester, online: false);
      expect(find.text('Admin panel'), findsNothing);
    });

    testWidgets('server connects: shows', (tester) async {
      final view = await pump(tester, online: false);
      view.setServerConnected(true);
      await tester.pump();
      expect(find.text('Admin panel'), findsOneWidget);
    });

    testWidgets('server drops: stays 5 s, then hides', (tester) async {
      final view = await pump(tester, online: true);
      expect(find.text('Admin panel'), findsOneWidget);
      view.setServerConnected(false);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Admin panel'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('Admin panel'), findsNothing);
    });

    testWidgets('short drop (back within 5 s): never hides', (tester) async {
      final view = await pump(tester, online: true);
      view.setServerConnected(false);
      await tester.pump(const Duration(seconds: 2));
      view.setServerConnected(true);
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Admin panel'), findsOneWidget);
    });

    testWidgets('closed while waiting: no error', (tester) async {
      final view = await pump(tester, online: true);
      view.setServerConnected(false);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
