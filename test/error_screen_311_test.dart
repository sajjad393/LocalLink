// Bundle 311: a screen that breaks shows what broke (not a plain grey box).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/widgets/error_screen_311.dart';

class _Boom311 extends StatelessWidget {
  const _Boom311();
  @override
  Widget build(BuildContext context) => throw StateError('boom 311');
}

FlutterErrorDetails _details() {
  final stack = StackTrace.fromString(List.generate(30, (i) => '#$i      frame$i (package:locallink/x.dart)').join('\n'));
  return FlutterErrorDetails(
    exception: StateError('Bad thing'),
    stack: stack,
    library: 'widgets library',
    context: ErrorDescription('building HomeScreen(dirty)'),
  );
}

void main() {
  test('describe: version, error, what was built, top 14 stack lines', () {
    final s = ErrorScreen311.describe(_details());
    final lines = s.split('\n');
    expect(lines.first, 'App: ${AppBuild.stamp}');
    expect(s, contains('Error: Bad state: Bad thing'));
    expect(s, contains('While: building HomeScreen(dirty)'));
    expect(s, contains('Part: widgets library'));
    expect(s, contains('#0      frame0'));
    expect(s, contains('#13      frame13'));
    expect(s, isNot(contains('frame14')));
  });

  test('describe: no stack / no context still works; long errors are cut', () {
    final s = ErrorScreen311.describe(FlutterErrorDetails(exception: 'x' * 900));
    expect(s, contains('Error: '));
    expect(s, isNot(contains('While:')));
    expect(s, isNot(contains('Stack:')));
    expect(s.length, lessThan(800));
  });

  testWidgets('works as the whole app (no MaterialApp, no Directionality) + Copy', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(ErrorScreen311.builder(_details()));
    expect(tester.takeException(), isNull);
    expect(find.text('LinkUp could not draw this screen'), findsOneWidget);
    expect(find.textContaining('While: building HomeScreen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('error311_copy')));
    await tester.pump();
    expect(copied, contains('Error: Bad state: Bad thing'));
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('inside a list it stays a card (no endless grey wall)', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ListView(children: [ErrorScreen311.builder(_details()), const Text('after')]))));
    expect(tester.takeException(), isNull);
    final h = tester.getSize(find.byType(ErrorScreen311)).height;
    expect(h, lessThanOrEqualTo(640));
    expect(find.text('after'), findsOneWidget);
  });

  testWidgets('a widget that throws while building shows the error screen', (tester) async {
    final old = ErrorWidget.builder;
    ErrorWidget.builder = ErrorScreen311.builder;
    try {
      await tester.pumpWidget(const MaterialApp(home: _Boom311()));
      expect(tester.takeException(), isA<StateError>());
      expect(find.byType(ErrorScreen311), findsOneWidget);
      expect(find.textContaining('boom 311'), findsOneWidget);
      expect(find.textContaining('_Boom311'), findsWidgets);
    } finally {
      ErrorWidget.builder = old; // the test binding checks it is back
    }
  });

  test('main.dart: release builds use it; the error log stays', () {
    final src = File('lib/main.dart').readAsStringSync();
    expect(src, contains('ErrorWidget.builder = ErrorScreen311.builder;'));
    expect(src, contains("'flutter_framework_error'"));
    expect(src, contains('runApp(const LocalLinkApp());'));
  });
}
