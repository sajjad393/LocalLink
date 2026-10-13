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

    testWidgets('keyboard send action triggers onSend', (tester) async {
      var sent = 0;
      await tester.pumpWidget(_host(GroupComposer(
        controller: TextEditingController(),
        pending: const [],
        isSending: false,
        onPick: () {},
        onRemove: (_) {},
        onSend: () => sent++,
      )));

      await tester.tap(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(sent, 1);
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

    testWidgets('pending attachments render as removable chips', (tester) async {
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

      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.text('b.png'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(Chip).first,
          matching: find.byTooltip('Delete'),
        ),
      );
      expect(removed, [0]);
    });
  });
}
