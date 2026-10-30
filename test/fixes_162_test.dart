import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_bubble.dart';

class _NoopFiles implements FileTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: $invocation');
}

Message _message(String status) => Message(
      id: 'm1',
      senderId: 'me',
      recipientId: 'peer',
      body: 'Hello there',
      createdAt: DateTime.now(),
      status: status,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('4.11 no route is not an error', () {
    test('native PEER_UNAVAILABLE is recognised however it is wrapped', () {
      expect(
          DirectoryRepository.isPeerUnavailableError(
              PlatformException(code: 'PEER_UNAVAILABLE')),
          isTrue);
      expect(
          DirectoryRepository.isPeerUnavailableError(
              Exception('PlatformException(PEER_UNAVAILABLE, no route)')),
          isTrue);
    });

    test('other errors stay errors', () {
      expect(
          DirectoryRepository.isPeerUnavailableError(
              PlatformException(code: 'SEND_FAILED')),
          isFalse);
      expect(DirectoryRepository.isPeerUnavailableError(StateError('boom')),
          isFalse);
    });
  });

  group('4.6 tap a failed message', () {
    testWidgets('my failed message calls onFailedTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(MessageBubble(
        message: _message('failed'),
        isMine: true,
        files: _NoopFiles(),
        onFailedTap: () => taps++,
      )));
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      await tester.tap(find.text('Hello there'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('a sent message does not open the resend sheet',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(MessageBubble(
        message: _message('sent'),
        isMine: true,
        files: _NoopFiles(),
        onFailedTap: () => taps++,
      )));
      await tester.tap(find.text('Hello there'));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('someone else\'s message never offers resend', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(MessageBubble(
        message: _message('failed'),
        isMine: false,
        files: _NoopFiles(),
        onFailedTap: () => taps++,
      )));
      await tester.tap(find.text('Hello there'));
      await tester.pump();
      expect(taps, 0);
    });
  });
}
