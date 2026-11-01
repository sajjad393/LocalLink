import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';

Future<void> _open(WidgetTester tester, Future<void> Function(BuildContext) open) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (c) => Scaffold(
        body: Center(
            child: ElevatedButton(
                onPressed: () => open(c), child: const Text('open'))),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  final now = DateTime.now();

  testWidgets('read: Sent, Delivered, Read rows', (tester) async {
    await _open(
        tester,
        (c) => showMessageInfoSheet(c,
            preview: const Text('Salam!'),
            sentAt: now,
            deliveredAt: now,
            readAt: now,
            peerName: 'Ali'));
    expect(find.byKey(const ValueKey('info_read')), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.byKey(const ValueKey('info_played')), findsNothing);
    expect(find.byKey(const ValueKey('info_receipts_off')), findsNothing);
  });

  testWidgets('not read yet: no Read row', (tester) async {
    await _open(
        tester,
        (c) => showMessageInfoSheet(c,
            preview: const Text('Salam!'), sentAt: now, deliveredAt: now));
    expect(find.byKey(const ValueKey('info_delivered')), findsOneWidget);
    expect(find.byKey(const ValueKey('info_read')), findsNothing);
  });

  testWidgets('switch OFF: Read hidden, note shown', (tester) async {
    await _open(
        tester,
        (c) => showMessageInfoSheet(c,
            preview: const Text('Salam!'),
            sentAt: now,
            deliveredAt: now,
            readAt: now,
            receiptsOff: true));
    expect(find.byKey(const ValueKey('info_read')), findsNothing);
    expect(find.byKey(const ValueKey('info_receipts_off')), findsOneWidget);
    expect(find.textContaining('Read receipts are off'), findsOneWidget);
  });

  testWidgets('voice note: Played row (also when OFF)', (tester) async {
    await _open(
        tester,
        (c) => showMessageInfoSheet(c,
            preview: const Text('0:14'),
            sentAt: now,
            deliveredAt: now,
            readAt: now,
            playedAt: now,
            receiptsOff: true));
    expect(find.byKey(const ValueKey('info_played')), findsOneWidget);
    expect(find.text('Played'), findsOneWidget);
  });

  testWidgets('groups: no Read / Played', (tester) async {
    await _open(
        tester,
        (c) => showMessageInfoSheet(c,
            preview: const Text('x'), sentAt: now, group: true));
    expect(find.byKey(const ValueKey('info_read')), findsNothing);
    expect(find.byKey(const ValueKey('info_played')), findsNothing);
  });
}
