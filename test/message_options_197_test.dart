import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';
import 'package:locallink/features/messaging/presentation/screens/forward_screen.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_bubble.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';

class _NoFiles implements FileTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

/// A button that opens [open] and stores what it returned.
class _Host extends StatefulWidget {
  final Future<Object?> Function(BuildContext) open;
  const _Host(this.open);
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Object? result = 'none';
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final r = await widget.open(context);
              setState(() => result = r);
            },
            child: const Text('open'),
          ),
        ),
      );
}

Future<_HostState> _pump(
    WidgetTester tester, Future<Object?> Function(BuildContext) open) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: _Host(open)));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return tester.state<_HostState>(find.byType(_Host, skipOffstage: false));
}

void main() {
  group('197a hold sheet', () {
    testWidgets("friend's message: no Message info", (tester) async {
      final host = await _pump(tester,
          (c) => showMessageActionsSheet(c, mine: false, hasText: true));
      for (final t in ['Reply', 'Copy', 'Forward', 'Select', 'Delete']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Message info'), findsNothing);
      expect(find.text('👍'), findsOneWidget);
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect((host.result as MessageActionResult).action, MessageAction.reply);
    });

    testWidgets('own message: + Message info; emoji returns the emoji',
        (tester) async {
      final host = await _pump(tester,
          (c) => showMessageActionsSheet(c, mine: true, hasText: true));
      expect(find.text('Message info'), findsOneWidget);
      await tester.tap(find.text('❤️'));
      await tester.pumpAndSettle();
      final r = host.result as MessageActionResult;
      expect(r.action, MessageAction.react);
      expect(r.emoji, '❤️');
    });

    testWidgets('photo only: no Copy; blocked: no Reply; unsent: no Forward',
        (tester) async {
      await _pump(
          tester,
          (c) => showMessageActionsSheet(c,
              mine: true, hasText: false, canReply: false, canForward: false));
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Reply'), findsNothing);
      expect(find.text('Forward'), findsNothing);
      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('197a delete sheet', () {
    testWidgets('own and new: both buttons', (tester) async {
      final host = await _pump(
          tester,
          (c) => showDeleteMessagesSheet(c,
              count: 1, allowEveryone: true, peerName: 'Ali'));
      expect(find.text('Delete message?'), findsOneWidget);
      expect(find.text('Delete for everyone'), findsOneWidget);
      expect(find.text('Delete for me'), findsOneWidget);
      await tester.tap(find.text('Delete for everyone'));
      await tester.pumpAndSettle();
      expect(host.result, DeleteChoice.forEveryone);
    });

    testWidgets("Ali's / old: Delete for me only + hint", (tester) async {
      await _pump(
          tester,
          (c) => showDeleteMessagesSheet(c,
              count: 3, allowEveryone: false, peerName: 'Ali'));
      expect(find.text('Delete 3 messages?'), findsOneWidget);
      expect(find.text('Delete for everyone'), findsNothing);
      expect(find.text('Delete for me'), findsOneWidget);
      expect(find.textContaining('Ali still has it'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  testWidgets('Message info: Sent + Delivered / Waiting', (tester) async {
    final now = DateTime.now();
    await _pump(
        tester,
        (c) => showMessageInfoSheet(c,
            preview: const Text('Yes, 10 minutes'),
            sentAt: now,
            deliveredAt: now,
            peerName: 'Ali'));
    expect(find.text('Message info'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.textContaining('Today, '), findsNWidgets(2));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  });

  testWidgets('Message info waiting + group not sent', (tester) async {
    await _pump(
        tester,
        (c) => showMessageInfoSheet(c,
            preview: const Text('x'), sentAt: DateTime.now(), peerName: 'Ali'));
    expect(find.textContaining('Waiting. Ali gets it'), findsOneWidget);
    expect(find.text('Delivered'), findsNothing);
  });

  testWidgets('Clear chat / Delete chat sheets', (tester) async {
    final host =
        await _pump(tester, (c) => showClearChatSheet(c, name: 'Ali'));
    expect(find.text('Clear chat with Ali?'), findsOneWidget);
    expect(find.textContaining('The chat stays in your Chats list'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm_clear_chat')));
    await tester.pumpAndSettle();
    expect(host.result, isTrue);
  });

  testWidgets('Chats-list hold: group has no Delete chat', (tester) async {
    await _pump(
        tester,
        (c) => showChatRowSheet(c,
            name: 'Family',
            subtitle: 'Group',
            avatar: const CircleAvatar(),
            allowDelete: false));
    expect(find.text('Clear chat'), findsOneWidget);
    expect(find.text('Delete chat'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  group('197a bubble', () {
    Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 400, child: child)));

    testWidgets('quote + Forwarded show, the envelope never does',
        (tester) async {
      final body = MessageEnvelope.build(
          text: 'Yes, leaving now',
          reply: const ReplyRef(id: 'm1', from: 'ali', snip: 'Are you coming?'),
          forwarded: true);
      await tester.pumpWidget(host(MessageBubble(
        message: Message(
            id: 'm2',
            senderId: 'me',
            recipientId: 'ali',
            body: body,
            createdAt: DateTime(2026, 11, 3, 20, 43)),
        isMine: true,
        files: _NoFiles(),
        quoteName: 'Ali',
      )));
      expect(find.text('Yes, leaving now'), findsOneWidget);
      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('Are you coming?'), findsOneWidget);
      expect(find.text('Forwarded'), findsOneWidget);
      expect(find.textContaining('llmsg'), findsNothing);
    });

    testWidgets('quote of a deleted message: not available', (tester) async {
      await tester.pumpWidget(host(const QuoteBox(
          name: 'Ali', line: 'x', isYou: false, notAvailable: true)));
      expect(find.text('Message not available'), findsOneWidget);
    });

    testWidgets('reply bar closes', (tester) async {
      var closed = false;
      await tester.pumpWidget(host(ReplyBar(
          name: 'Ali',
          line: 'Are you coming?',
          isYou: false,
          onClose: () => closed = true)));
      await tester.tap(find.byKey(const ValueKey('reply_bar_close')));
      expect(closed, isTrue);
    });

    testWidgets('highlight = bubble grey + ring only', (tester) async {
      const base = BoxDecoration(color: Colors.white);
      final scheme = ThemeData.light().colorScheme;
      final on = highlightBubble(base, scheme, on: true);
      expect(on.border, isNotNull);
      expect(on.color, isNot(Colors.white));
      expect(highlightBubble(base, scheme, on: false), same(base));
      final blue = highlightBubble(
          const BoxDecoration(gradient: LinearGradient(colors: [Colors.blue, Colors.cyan])),
          scheme,
          on: true,
          gradient: true);
      expect(blue.gradient, isNotNull);
      expect(blue.border, isNotNull);
    });
  });

  testWidgets('Forward to: pick many, bottom bar, send returns picks',
      (tester) async {
    final host = await _pump(
      tester,
      (c) => Navigator.push<List<ForwardTarget>>(
        c,
        MaterialPageRoute(
          builder: (_) => ForwardScreen(
            loadTargets: () async => const [
              ForwardTarget(id: 's', name: 'sumaira', subtitle: 'Hello 👋'),
              ForwardTarget(id: 'b', name: 'Bilal'),
              ForwardTarget(id: 'f', name: 'Family', isGroup: true),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Forward to'), findsOneWidget);
    expect(find.text('RECENT CHATS'), findsOneWidget);
    expect(find.byKey(const ValueKey('forward_bottom_bar')), findsNothing);
    await tester.tap(find.text('sumaira'));
    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    expect(find.text('sumaira, Family'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('forward_search')), 'bil');
    await tester.pumpAndSettle();
    expect(find.text('sumaira'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('forward_send')));
    await tester.pumpAndSettle();
    final picks = host.result as List<ForwardTarget>;
    expect(picks.map((t) => t.key), ['d:s', 'g:f']);
  });

  test('forward sends "Forwarded" envelopes to every pick', () async {
    final sent = <String>[];
    final hub = ForwardHub(
      targets: () async => const [],
      files: _NoFiles(),
      send: (t, body, files) async => sent.add('${t.key}|$body'),
    );
    final n = await hub.forward(
      const [ForwardItem(text: 'Yes, 10 minutes')],
      const [
        ForwardTarget(id: 's', name: 'sumaira'),
        ForwardTarget(id: 'f', name: 'Family', isGroup: true),
      ],
    );
    expect(n, 2);
    expect(sent.length, 2);
    final env = MessageEnvelope.parse(sent.first.split('|').last);
    expect(env.forwarded, isTrue);
    expect(env.text, 'Yes, 10 minutes');
  });

  test('chat ⋮ pop-up is the tidy 15A one', () {
    final s = File(
            'lib/features/messaging/presentation/screens/chat_screen.dart')
        .readAsStringSync();
    expect(s, contains('position: PopupMenuPosition.under'));
    expect(s, contains('PopupMenuDivider()'));
    expect(s, contains("title: Text('Clear chat')"));
    expect(s, contains("leading: Icon(Icons.info_outline)"));
    // The failed-message sheet (162) stays.
    expect(s, contains("Text('Message not sent'"));
  });
}
