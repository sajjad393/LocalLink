import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/core/widgets/movable_fab.dart';

/// Bundle 289: one toast look everywhere (TODO_289 T-1..T-5).
Widget _host(void Function(BuildContext) onTap, {Brightness b = Brightness.dark, bool fab = false}) =>
    MaterialApp(
      theme: ThemeData(brightness: b),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final button = Center(
              child: ElevatedButton(
                key: const ValueKey('go'),
                onPressed: () => onTap(context),
                child: const Text('go'),
              ),
            );
            if (!fab) return button;
            return MovableFabArea(
              place: FabPlace(),
              fab: const SizedBox(key: ValueKey('the_fab'), width: 56, height: 56),
              child: button,
            );
          },
        ),
      ),
    );

SnackBar _bar(WidgetTester t) => t.widget<SnackBar>(find.byType(SnackBar));

Icon _icon(WidgetTester t) =>
    t.widget<Icon>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Icon)));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LinkToastHub.reset();
  });

  group('T-1 look', () {
    for (final b in Brightness.values) {
      testWidgets('card colour, shape and text style ($b)', (t) async {
        await t.pumpWidget(_host((c) => LinkToast.show(c, 'Profile saved', kind: LinkToastKind.done), b: b));
        await t.tap(find.byKey(const ValueKey('go')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        final s = _bar(t);
        expect(s.behavior, SnackBarBehavior.floating);
        expect(s.backgroundColor,
            b == Brightness.dark ? const Color(0xFF2A2D38) : const Color(0xFF1F2937));
        expect((s.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(14));
        expect(s.margin, const EdgeInsets.fromLTRB(16, 0, 16, 16));
        expect(s.padding, const EdgeInsets.fromLTRB(14, 12, 14, 12));
        expect(s.duration, const Duration(seconds: 3));
        final text = t.widget<Text>(find.text('Profile saved'));
        expect(text.style!.fontSize, 14);
        expect(text.style!.height, 1.35);
        expect(text.maxLines, 2);
        expect(text.style!.color,
            b == Brightness.dark ? const Color(0xFFECEBF2) : Colors.white);
      });
    }

    final kinds = {
      LinkToastKind.done: (Icons.check_rounded, const Color(0xFF86EFAC)),
      LinkToastKind.error: (Icons.warning_rounded, const Color(0xFFF87171)),
      LinkToastKind.info: (Icons.info_rounded, const Color(0xFF8EA6FF)),
    };
    kinds.forEach((kind, want) {
      testWidgets('icon for ${kind.name}', (t) async {
        await t.pumpWidget(_host((c) => LinkToast.show(c, 'Hello', kind: kind)));
        await t.tap(find.byKey(const ValueKey('go')));
        await t.pump();
        final icon = _icon(t);
        expect(icon.icon, want.$1);
        expect(icon.color, want.$2);
      });
    });

    testWidgets('action on the right, tap runs it and closes the toast', (t) async {
      var undone = 0;
      await t.pumpWidget(_host((c) => LinkToast.show(c, 'Message deleted',
          kind: LinkToastKind.done, actionLabel: 'Undo', onAction: () => undone++)));
      await t.tap(find.byKey(const ValueKey('go')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final undo = t.widget<Text>(find.text('Undo'));
      expect(undo.style!.color, const Color(0xFF8EA6FF));
      expect(undo.style!.fontWeight, FontWeight.w700);
      await t.tap(find.text('Undo'));
      await t.pump();
      expect(undone, 1);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Message deleted'), findsNothing);
    });

    testWidgets('a new toast replaces the old one; it goes after 3 s', (t) async {
      var n = 0;
      await t.pumpWidget(_host((c) => LinkToast.show(c, 'Toast ${++n}')));
      await t.tap(find.byKey(const ValueKey('go')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('go')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 800));
      expect(find.text('Toast 1'), findsNothing);
      expect(find.text('Toast 2'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Toast 2'), findsNothing);
    });

    testWidgets('showErrorToast uses the same card with the red sign', (t) async {
      await t.pumpWidget(_host((c) => showErrorToast(c, error: Exception('boom'))));
      await t.tap(find.byKey(const ValueKey('go')));
      await t.pump();
      expect(_bar(t).backgroundColor, const Color(0xFF2A2D38));
      expect(_icon(t).color, const Color(0xFFF87171));
    });

    test('maybeOn with no messenger does nothing', () {
      expect(LinkToast.maybeOn(null, 'x'), isNull);
    });
  });

  group('kind from words', () {
    test('failures are errors, done words are done, others info', () {
      expect(LinkToast.guess('Could not share logs'), LinkToastKind.error);
      expect(LinkToast.guess('Call is no longer available'), LinkToastKind.error);
      expect(LinkToast.guess('Link copied'), LinkToastKind.done);
      expect(LinkToast.guess('Contact added'), LinkToastKind.done);
      expect(LinkToast.guess('LinkUp updated to 3.0.90'), LinkToastKind.done);
      expect(LinkToast.guess('Press back again to exit'), LinkToastKind.info);
    });
  });

  group('T-5 FAB moves up while a toast shows', () {
    testWidgets('up while shown, back after', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_host((c) => LinkToast.show(c, 'Contact added', kind: LinkToastKind.done), fab: true));
      await t.pump();
      final before = t.getTopLeft(find.byKey(const ValueKey('the_fab'))).dy;
      await t.tap(find.byKey(const ValueKey('go')));
      await t.pump();
      expect(LinkToastHub.lift.value, greaterThan(0));
      await t.pump(const Duration(milliseconds: 500));
      final up = t.getTopLeft(find.byKey(const ValueKey('the_fab'))).dy;
      expect(up, lessThan(before));
      // the button's bottom sits above the toast card
      final toastTop = t.getTopLeft(find.byType(SnackBar)).dy;
      expect(up + 56, lessThanOrEqualTo(toastTop + 1));
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(SnackBar), findsNothing);
      expect(LinkToastHub.lift.value, 0);
      await t.pump(const Duration(milliseconds: 500));
      expect(t.getTopLeft(find.byKey(const ValueKey('the_fab'))).dy, before);
    });
  });

  group('T-4 every toast uses LinkToast (code check)', () {
    test('no raw showSnackBar left in lib/ except inside link_toast.dart', () {
      final left = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('link_toast.dart')) continue;
        if (f.readAsStringSync().contains('showSnackBar(')) left.add(f.path);
      }
      expect(left, isEmpty);
    });

    test('back-to-exit toast stays 2 s', () {
      final s = File('lib/features/home/presentation/screens/home_screen.dart').readAsStringSync();
      final i = s.indexOf("'Press back again to exit'");
      expect(i, greaterThan(0));
      expect(s.substring(i, i + 120), contains('Duration(seconds: 2)'));
    });

    test('admin keys kept', () {
      final s = File('lib/features/admin/presentation/screens/admin_panel_screen.dart').readAsStringSync();
      expect(s, contains("ValueKey('admin_no_longer')"));
      expect(s, contains("ValueKey('admin_not_available')"));
    });
  });
}
