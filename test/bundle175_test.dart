import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/home/presentation/widgets/background_status_card.dart';

/// Bundle 175 (10): STATUS card on "Keep LocalLink running".
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool running,
    required bool notifications,
    bool starting = false,
    VoidCallback? onStart,
    VoidCallback? onAllow,
  }) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BackgroundStatusCard(
          running: running,
          notifications: notifications,
          starting: starting,
          onStart: onStart ?? () {},
          onAllowNotifications: onAllow ?? () {},
        ),
      ),
    ));
  }

  Color edgeColor(WidgetTester tester) {
    final box = tester
        .widget<Container>(find.byKey(const ValueKey('background-status-card')))
        .decoration! as BoxDecoration;
    return (box.border! as Border).top.color;
  }

  testWidgets('running + notifications on: green, no Start button',
      (tester) async {
    await pump(tester, running: true, notifications: true);
    expect(find.text('Running now'), findsOneWidget);
    expect(find.text('Messages arrive when the app is closed'), findsOneWidget);
    expect(find.text('Notifications on'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    expect(edgeColor(tester), BackgroundStatusCard.green);
  });

  testWidgets('stopped: red with Start, tap starts', (tester) async {
    var started = 0;
    await pump(tester,
        running: false, notifications: true, onStart: () => started++);
    expect(find.text('Stopped by your phone'), findsOneWidget);
    expect(find.text('Messages wait until it runs again'), findsOneWidget);
    expect(edgeColor(tester), BackgroundStatusCard.red);
    await tester.tap(find.text('Start'));
    expect(started, 1);
  });

  testWidgets('starting shows a spinner instead of Start', (tester) async {
    await pump(tester, running: false, notifications: true, starting: true);
    expect(find.text('Start'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('notifications off: red row, tap opens settings',
      (tester) async {
    var asked = 0;
    await pump(tester,
        running: true, notifications: false, onAllow: () => asked++);
    expect(find.text('Notifications off - tap to allow'), findsOneWidget);
    expect(edgeColor(tester), BackgroundStatusCard.red);
    await tester.tap(find.text('Notifications off - tap to allow'));
    expect(asked, 1);
  });

  testWidgets('notifications on: the row does nothing on tap', (tester) async {
    var asked = 0;
    await pump(tester,
        running: true, notifications: true, onAllow: () => asked++);
    await tester.tap(find.text('Notifications on'));
    expect(asked, 0);
  });

  testWidgets('fits a small phone (320 wide) without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, running: false, notifications: false);
    expect(tester.takeException(), isNull);
  });
}
