import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/groups/presentation/widgets/group_composer.dart';

final _gradientCircle = find.byWidgetPredicate(
  (widget) =>
      widget is Ink &&
      widget.decoration is BoxDecoration &&
      (widget.decoration as BoxDecoration).gradient ==
          LocalLinkBrand.linearGradient &&
      (widget.decoration as BoxDecoration).shape == BoxShape.circle,
);

Widget _host(GroupComposer composer) =>
    MaterialApp(home: Scaffold(body: composer));

void main() {
  group('GroupComposer', () {
    testWidgets('send button is the brand gradient circle (reference design)',
        (tester) async {
      await tester.pumpWidget(_host(GroupComposer(
        controller: TextEditingController(),
        pending: const [],
        isSending: false,
        onPick: () {},
        onRemove: (_) {},
        onSend: () {},
      )));

      expect(_gradientCircle, findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('tapping send invokes onSend', (tester) async {
      var sent = 0;
      await tester.pumpWidget(_host(GroupComposer(
        controller: TextEditingController(),
        pending: const [],
        isSending: false,
        onPick: () {},
        onRemove: (_) {},
        onSend: () => sent++,
      )));

      await tester.tap(find.byTooltip('Send message'));
      expect(sent, 1);
    });

    testWidgets('207 J: Enter is a new line, it never sends', (tester) async {
      var sent = 0;
      await tester.pumpWidget(_host(GroupComposer(
        controller: TextEditingController(),
        pending: const [],
        isSending: false,
        onPick: () {},
        onRemove: (_) {},
        onSend: () => sent++,
      )));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textInputAction, TextInputAction.newline);
      expect(field.keyboardType, TextInputType.multiline);
      expect(field.onSubmitted, isNull);
      await tester.tap(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      expect(sent, 0);
    });

    testWidgets('while sending shows a white progress indicator and blocks taps',
        (tester) async {
      var sent = 0;
      var picked = 0;
      await tester.pumpWidget(_host(GroupComposer(
        controller: TextEditingController(),
        pending: const [],
        isSending: true,
        onPick: () => picked++,
        onRemove: (_) {},
        onSend: () => sent++,
      )));

      final progress = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progress.color, Colors.white);

      await tester.tap(find.byTooltip('Send message'), warnIfMissed: false);
      await tester.tap(find.byTooltip('Attach'), warnIfMissed: false);
      expect(sent, 0);
      expect(picked, 0);
    });

    testWidgets('pending attachments render in the review strip (Bundle 202)', (tester) async {
      final removed = <int>[];
      await tester.pumpWidget(_host(GroupComposer(
        controller: TextEditingController(),
        pending: const [
          PickedFile(path: '/tmp/a.pdf', name: 'a.pdf', contentType: 'application/pdf', size: 10),
          PickedFile(path: '/tmp/b.png', name: 'b.png', contentType: 'image/png', size: 20),
        ],
        isSending: false,
        onPick: () {},
        onRemove: removed.add,
        onSend: () {},
      )));

      // Bundle 202: document = icon + short name, photo = small picture.
      expect(find.text('a'), findsOneWidget);
      expect(find.byKey(const ValueKey('pending_file:0')), findsOneWidget);
      expect(find.byKey(const ValueKey('pending_thumb:1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pending_remove:0')));
      expect(removed, [0]);
    });
  });

  test('207 J: the 1:1 box is the same (new line, no keyboard send)', () {
    final src = File('lib/features/messaging/presentation/widgets/chat_composer.dart')
        .readAsStringSync();
    expect(src, contains('TextInputAction.newline'));
    expect(src, contains('TextInputType.multiline'));
    expect(src, isNot(contains('TextInputAction.send')));
    expect(src, isNot(contains('onSubmitted: (_) => onSend()')));
  });
}
