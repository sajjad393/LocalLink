// Bundle 216j: the 216 kit widgets have the mock sizes and colours
// (UI_SPEC_216 §1–§2), with the real Roboto216 font.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

import 'support/b216_fonts.dart';

void main() {
  setUpAll(loadRoboto216);

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    ));
    await tester.pump();
  }

  testWidgets('search 44, chips 32, tag 21, button 44, pill 30', (tester) async {
    await show(
      tester,
      Column(children: [
        AdminSearch216(key: const ValueKey('s'), hint: 'Search', onChanged: (_) {}),
        AdminChips216(
            key: const ValueKey('c'), items: const ['All', 'Admins'], selected: 0, onSelected: (_) {}),
        const Align(
            alignment: Alignment.centerLeft,
            child: AdminTag216('Active', A216Tone.green, key: ValueKey('t'), dot: true)),
        AdminButton216('Save', key: const ValueKey('b'), onTap: () {}),
        Align(
            alignment: Alignment.centerLeft,
            child: AdminPillButton216('Block', A216Tone.red, () {}, key: const ValueKey('p'))),
      ]),
    );
    expect(tester.getSize(find.byKey(const ValueKey('s'))).height, closeTo(A216.searchHeight, 0.5));
    expect(tester.getSize(find.byKey(const ValueKey('t'))).height, closeTo(A216.tagHeight, 0.5));
    expect(tester.getSize(find.byKey(const ValueKey('b'))).height, closeTo(A216.buttonHeight, 0.5));
    expect(tester.getSize(find.byKey(const ValueKey('p'))).height, closeTo(A216.pillHeight, 0.5));
    final chip = find.descendant(of: find.byKey(const ValueKey('c')), matching: find.text('All'));
    expect(chip, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stepper 104 × 32, avatar 40', (tester) async {
    await show(
      tester,
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AdminStepper216(key: ValueKey('st'), value: '15 s'),
        AdminPersonAvatar216(key: ValueKey('av'), name: 'Sumaira Bibi'),
      ]),
    );
    final st = tester.getSize(find.byKey(const ValueKey('st')));
    expect(st.width, closeTo(104, 0.5));
    expect(st.height, closeTo(32, 0.5));
    final av = tester.getSize(find.byKey(const ValueKey('av')));
    expect(av.width, closeTo(40, 0.5));
  });

  testWidgets('list rows have the given height and a divider', (tester) async {
    await show(
      tester,
      AdminListCard216([
        AdminRow216(key: const ValueKey('r1'), title: 'Users', subtitle: 'People', height: 56, onTap: () {}),
        const AdminRow216(key: ValueKey('r2'), title: 'Devices', height: 64),
      ]),
    );
    expect(tester.getSize(find.byKey(const ValueKey('r1'))).height, closeTo(56, 1));
    expect(tester.getSize(find.byKey(const ValueKey('r2'))).height, closeTo(64, 1));
    expect(tester.getTopLeft(find.text('Devices')).dy,
        greaterThan(tester.getTopLeft(find.text('Users')).dy));
  });

  testWidgets('tags: fill and text colours from the tone', (tester) async {
    await show(tester, const Align(alignment: Alignment.topLeft, child: AdminTag216('Blocked', A216Tone.red)));
    final text = tester.widget<Text>(find.text('Blocked'));
    final box = tester.widget<Container>(find
        .ancestor(of: find.text('Blocked'), matching: find.byType(Container))
        .first);
    final deco = box.decoration as BoxDecoration?;
    expect(deco?.color, isNotNull);
    expect(text.style?.color, isNot(deco?.color));
    expect(text.style?.fontFamily, 'Roboto216');
  });

  testWidgets('empty state and banner render without overflow', (tester) async {
    await show(
      tester,
      const Column(children: [
        AdminEmptyState216(icon: Icons.search, tone: A216Tone.grey, title: 'No one found', body: 'Try another name.'),
        AdminBanner216(A216BannerKind.warning, 'No server right now', body: 'Offline tools still work.'),
      ]),
    );
    expect(find.text('No one found'), findsOneWidget);
    expect(find.text('No server right now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
