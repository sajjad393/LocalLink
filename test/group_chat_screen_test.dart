import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/screens/group_chat_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_bubble.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';

final _group = LocalGroup(
  id: 'g1',
  name: 'Study group',
  ownerId: 'me',
  createdAt: '2026-01-01T00:00:00Z',
);

GroupMessage _message({
  String id = 'm1',
  String senderId = 'me',
  String body = 'Seed message',
  DateTime? createdAt,
}) =>
    GroupMessage(
      id: id,
      groupId: 'g1',
      senderId: senderId,
      body: body,
      createdAt: (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
    );

class _FakeGroupMessaging implements GroupMessagingRepositoryContract {
  _FakeGroupMessaging({this.historyResult = const [], this.sendError});

  final List<GroupMessage> historyResult;
  final Object? sendError;
  final List<String> sentBodies = <String>[];
  final _incoming = StreamController<GroupMessage>.broadcast();
  final _reactions = StreamController<MessageReaction>.broadcast();

  @override
  Stream<GroupMessage> get incoming => _incoming.stream;

  @override
  Stream<MessageReaction> get reactionIncoming => _reactions.stream;

  @override
  Future<List<GroupMessage>> history(String groupId) async => historyResult;

  @override
  Future<GroupMessage> send(String groupId, String body,
      {List<PickedFile> attachments = const []}) async {
    if (sendError != null) throw sendError!;
    sentBodies.add(body);
    return _message(id: 'sent-${sentBodies.length}', body: body);
  }

  @override
  Future<void> react(String groupId, String messageId, String emoji) async {}

  @override
  Future<List<MessageReaction>> reactions(String messageId) async => const [];

  // Bundle 197a
  final _deleted = StreamController<String>.broadcast();
  @override
  Stream<String> get deletedMessageIds => _deleted.stream;
  @override
  Future<void> deleteForMe(String messageId) async {}
  @override
  Future<bool> deleteForEveryone(String groupId, String messageId) async => true;
  @override
  Future<int> clearChat(String groupId) async => 0;
}

class _FakeGroupRepository implements GroupRepositoryContract {
  _FakeGroupRepository(this.members);

  final List<GroupMember> members;

  @override
  Future<List<GroupMember>> listMembers(String groupId) async => members;

  @override
  Future<List<LocalGroup>> listGroups() async => [_group];

  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) async =>
      _group;

  @override
  Future<List<Device>> availableMemberDevices() async => const [];

  @override
  Future<void> addMember(String groupId, String deviceId) async {}

  @override
  Future<void> removeMember(String groupId, String deviceId) async {}
}

class _NoopFiles implements FileTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: $invocation');
}

GroupMember _member(String id, String name) => GroupMember(
      groupId: 'g1',
      deviceId: id,
      role: 'member',
      joinedAt: '2026-01-01T00:00:00Z',
      name: name,
    );

Widget _host(_FakeGroupMessaging messaging) => MaterialApp(
      home: GroupChatScreen(
        group: _group,
        localDeviceId: 'me',
        messaging: messaging,
        groups: _FakeGroupRepository([_member('me', 'You'), _member('d2', 'Sara')]),
        files: _NoopFiles(),
      ),
    );

/// Pumps a few frames without ``pumpAndSettle`` so infinite Lottie loops
/// cannot hang the test.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  group('GroupChatScreen', () {
    testWidgets('app bar shows the gradient group avatar and member count',
        (tester) async {
      await tester.pumpWidget(_host(_FakeGroupMessaging()));
      await _settle(tester);

      expect(find.byType(GroupAvatar), findsOneWidget);
      expect(find.text('Study group'), findsOneWidget);
      expect(find.text('2 members'), findsOneWidget);
    });

    testWidgets('empty conversation shows the animated empty state',
        (tester) async {
      await tester.pumpWidget(_host(_FakeGroupMessaging()));
      await _settle(tester);

      expect(find.byType(Lottie), findsOneWidget);
      expect(find.text('Start the group conversation'), findsOneWidget);
    });

    testWidgets('seeded messages render with a Today divider', (tester) async {
      await tester.pumpWidget(
        _host(_FakeGroupMessaging(historyResult: [
          _message(id: 'm1', senderId: 'd2', body: 'Hi everyone'),
        ])),
      );
      await _settle(tester);

      expect(find.text('Hi everyone'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.byType(Lottie), findsNothing);
    });

    testWidgets('my own messages render in the gradient bubble', (tester) async {
      await tester.pumpWidget(
        _host(_FakeGroupMessaging(historyResult: [
          _message(id: 'm1', senderId: 'me', body: 'My message'),
        ])),
      );
      await _settle(tester);

      // Scope to the bubble: the group avatar (app bar) is also gradient.
      final gradientBubble = find.descendant(
        of: find.byType(GroupMessageBubble),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).gradient ==
                  LocalLinkBrand.linearGradient,
        ),
      );
      expect(gradientBubble, findsOneWidget);
    });

    testWidgets('composing and sending shows the message and calls the repo',
        (tester) async {
      final messaging = _FakeGroupMessaging();
      await tester.pumpWidget(_host(messaging));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'Hello group');
      await tester.tap(find.byTooltip('Send message'));
      await _settle(tester);

      expect(messaging.sentBodies, ['Hello group']);
      expect(find.text('Hello group'), findsOneWidget);
    });

    testWidgets('send failures surface a friendly toast, never the raw error',
        (tester) async {
      final messaging = _FakeGroupMessaging(
        sendError: Exception('HTTP 500 internal stack trace'),
      );
      await tester.pumpWidget(_host(messaging));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'Will fail');
      await tester.tap(find.byTooltip('Send message'));
      await _settle(tester);

      // Friendly copy appears both as the toast and as the inline error;
      // the raw exception text must never surface anywhere.
      expect(
        find.text('The server is having trouble. Please try again in a moment.'),
        findsWidgets,
      );
      expect(find.textContaining('stack trace'), findsNothing);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.floating);

      await tester.pump(const Duration(seconds: 5));
    });

    // Bundle 197a (mock 19-21): hold, reply, select in a group.
    testWidgets('197a hold Sara\'s message: Reply sends a quote',
        (tester) async {
      final messaging = _FakeGroupMessaging(historyResult: [
        _message(id: 'm1', senderId: 'd2', body: 'Meeting at 5?'),
      ]);
      await tester.pumpWidget(_host(messaging));
      await _settle(tester);
      await tester.longPress(find.text('Meeting at 5?'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Message info'), findsNothing); // not mine
      expect(find.byKey(const ValueKey('held_dimmer')), findsOneWidget);
      await tester.tap(find.text('Reply'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('reply_bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('held_dimmer')), findsNothing);
      await tester.enterText(find.byType(TextField), 'Yes');
      await tester.tap(find.byTooltip('Send message'));
      await _settle(tester);
      final env = MessageEnvelope.parse(messaging.sentBodies.single);
      expect(env.text, 'Yes');
      expect(env.reply!.id, 'm1');
      expect(env.reply!.from, 'd2');
      expect(find.byKey(const ValueKey('reply_bar')), findsNothing);
    });

    testWidgets('197a Select mode shows the count bar', (tester) async {
      final messaging = _FakeGroupMessaging(historyResult: [
        _message(id: 'm1', senderId: 'me', body: 'Mine'),
        _message(id: 'm2', senderId: 'd2', body: 'Hers'),
      ]);
      await tester.pumpWidget(_host(messaging));
      await _settle(tester);
      await tester.longPress(find.text('Mine'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Message info'), findsOneWidget); // mine
      await tester.tap(find.text('Select'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('select_bar')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('Hers'));
      await _settle(tester);
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('select_bar')), findsNothing);
    });

    // Bundle 199: swipe right to reply, keyboard opens, blue flash 2 s.
    testWidgets('199 swipe Sara\'s message right: reply bar + keyboard',
        (tester) async {
      final messaging = _FakeGroupMessaging(historyResult: [
        _message(id: 'm1', senderId: 'd2', body: 'Meeting at 5?'),
      ]);
      await tester.pumpWidget(_host(messaging));
      await _settle(tester);
      await tester.drag(find.text('Meeting at 5?'), const Offset(170, 0));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('reply_bar')), findsOneWidget);
      final edit = tester.widget<EditableText>(find.byType(EditableText));
      expect(edit.focusNode.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'Yes');
      await tester.tap(find.byTooltip('Send message'));
      await _settle(tester);
      final env = MessageEnvelope.parse(messaging.sentBodies.single);
      expect(env.reply!.id, 'm1');
    });

    testWidgets('199 tap a quote: original gets the blue border for 2 s',
        (tester) async {
      final quote = MessageEnvelope.build(
          text: 'Yes',
          reply: const ReplyRef(
              id: 'm1', from: 'd2', snip: 'Meeting at 5?', kind: 'text'));
      final messaging = _FakeGroupMessaging(historyResult: [
        _message(id: 'm1', senderId: 'd2', body: 'Meeting at 5?'),
        _message(id: 'm2', senderId: 'me', body: quote),
      ]);
      await tester.pumpWidget(_host(messaging));
      await _settle(tester);
      double ringOf(String text) {
        final bubble = find.ancestor(
            of: find.text(text), matching: find.byType(GroupMessageBubble));
        final ring = find.descendant(
            of: bubble,
            matching: find.byKey(const ValueKey('bubble_flash_ring')));
        return tester
            .widget<AnimatedOpacity>(find
                .ancestor(of: ring, matching: find.byType(AnimatedOpacity))
                .first)
            .opacity;
      }

      expect(ringOf('Yes'), 0);
      await tester.tap(find.byType(QuoteBox));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      final original = find.text('Meeting at 5?').first;
      expect(
          tester
              .widget<AnimatedOpacity>(find
                  .descendant(
                      of: find.ancestor(
                          of: original,
                          matching: find.byType(GroupMessageBubble)),
                      matching: find.byType(AnimatedOpacity))
                  .first)
              .opacity,
          1);
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          tester
              .widget<AnimatedOpacity>(find
                  .descendant(
                      of: find.ancestor(
                          of: original,
                          matching: find.byType(GroupMessageBubble)),
                      matching: find.byType(AnimatedOpacity))
                  .first)
              .opacity,
          0);
    });
  });
}
