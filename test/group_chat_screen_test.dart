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
  });
}
