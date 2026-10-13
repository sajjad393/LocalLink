import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_bubble.dart';

class _NoopFiles implements FileTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: $invocation');
}

Message _message({
  String id = 'm1',
  String senderId = 'me',
  String body = 'Hello there',
}) =>
    Message(
      id: id,
      senderId: senderId,
      recipientId: 'peer',
      body: body,
      createdAt: DateTime.now(),
      status: 'sent',
    );

final _gradientBubble = find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.decoration is BoxDecoration &&
      (widget.decoration as BoxDecoration).gradient ==
          LocalLinkBrand.linearGradient,
);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('MessageBubble', () {
    testWidgets('outgoing messages use the brand gradient with white text',
        (tester) async {
      await tester.pumpWidget(
        _host(MessageBubble(message: _message(), isMine: true, files: _NoopFiles())),
      );

      expect(_gradientBubble, findsOneWidget);
      final text = tester.widget<Text>(find.text('Hello there'));
      expect(text.style?.color, Colors.white);
      final align = tester.widget<Align>(
        find.ancestor(of: find.byType(GestureDetector), matching: find.byType(Align)).first,
      );
      expect(align.alignment, Alignment.centerRight);
    });

    testWidgets('incoming messages use the neutral surface, not the gradient',
        (tester) async {
      await tester.pumpWidget(
        _host(MessageBubble(
          message: _message(senderId: 'peer'),
          isMine: false,
          files: _NoopFiles(),
        )),
      );

      expect(_gradientBubble, findsNothing);

      final context = tester.element(find.byType(MessageBubble));
      final colors = Theme.of(context).colorScheme;
      final text = tester.widget<Text>(find.text('Hello there'));
      expect(text.style?.color, colors.onSurface);

      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text('Hello there'), matching: find.byType(Container))
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, colors.surfaceContainerHighest);
      expect(decoration.gradient, isNull);
    });

    testWidgets('renders reaction chips with counts', (tester) async {
      await tester.pumpWidget(
        _host(MessageBubble(
          message: _message(),
          isMine: true,
          files: _NoopFiles(),
          reactions: [
            MessageReaction(
              messageId: 'm1',
              reactorId: 'peer',
              emoji: '👍',
              createdAt: DateTime.now(),
            ),
          ],
        )),
      );

      expect(find.text('👍 1'), findsOneWidget);
    });

    testWidgets('long press triggers the message actions callback',
        (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        _host(MessageBubble(
          message: _message(),
          isMine: false,
          files: _NoopFiles(),
          onLongPress: () => pressed = true,
        )),
      );

      await tester.longPress(find.byType(MessageBubble));
      expect(pressed, isTrue);
    });

    testWidgets('exposes the body through semantics', (tester) async {
      await tester.pumpWidget(
        _host(MessageBubble(message: _message(body: 'Accessible text'), isMine: false, files: _NoopFiles())),
      );

      final semantics = tester.widget<Semantics>(
        find
            .descendant(of: find.byType(MessageBubble), matching: find.byType(Semantics))
            .first,
      );
      expect(semantics.properties.label, 'Accessible text');
    });
  });
}
