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
import 'package:locallink/features/groups/data/group_mute_book.dart';
import 'package:locallink/features/messaging/presentation/widgets/pinch_text_zoom.dart';
import 'package:locallink/features/messaging/presentation/widgets/chat_composer.dart';

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
  _FakeGroupMessaging(
      {this.historyResult = const [],
      this.sendError,
      this.reactionMap = const {}});

  final List<GroupMessage> historyResult;
  final Object? sendError;
  final Map<String, List<MessageReaction>> reactionMap;
  final List<String> reacted = <String>[];
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
  Future<void> react(String groupId, String messageId, String emoji) async {
    reacted.add('$messageId:$emoji');
  }

  @override
  Future<List<MessageReaction>> reactions(String messageId) async =>
      reactionMap[messageId] ?? const [];

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
  _FakeGroupRepository(this.members, {LocalGroup? group})
      : group = group ?? _group;

  final List<GroupMember> members;
  final LocalGroup group;
  final List<String> calls = <String>[];

  @override
  Future<List<GroupMember>> listMembers(String groupId) async => members;

  @override
  Future<List<LocalGroup>> listGroups() async => [_group];

  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds,
          {String description = '',
          String editInfo = 'admins',
          String sendMessages = 'all',
          String addMembers = 'admins',
          List<int>? photoJpeg}) async =>
      _group;

  // Bundle G2.
  @override
  Future<LocalGroup?> localGroup(String groupId) async => group;
  @override
  Future<LocalGroup?> refreshGroup(String groupId) async => group;
  @override
  Future<LocalGroup> updateGroup(String groupId,
          {String? name,
          String? description,
          String? editInfo,
          String? sendMessages,
          String? addMembers}) async =>
      _group;
  @override
  Future<void> setPhoto(String groupId, List<int>? jpeg) async {}
  @override
  Future<void> setAdmin(String groupId, String deviceId,
      {required bool admin}) async {}
  @override
  Future<void> leave(String groupId) async => calls.add('leave');
  @override
  Future<void> deleteLocal(String groupId) async => calls.add('delete');

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

Widget _host(_FakeGroupMessaging messaging,
        {List<GroupMember>? members,
        LocalGroup? group,
        _FakeGroupRepository? repo}) =>
    MaterialApp(
      home: GroupChatScreen(
        group: group ?? _group,
        localDeviceId: 'me',
        messaging: messaging,
        groups: repo ??
            _FakeGroupRepository(
                members ?? [_member('me', 'You'), _member('d2', 'Sara')],
                group: group),
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

/// G1: a few frames for menus / sheets (the empty-chat Lottie never
/// settles, so no pumpAndSettle).
Future<void> _anim(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('GroupChatScreen', () {
    testWidgets('G1 app bar: group photo, name, "You, Sara" (mock 13)',
        (tester) async {
      await tester.pumpWidget(_host(_FakeGroupMessaging()));
      await _settle(tester);

      expect(find.byType(GroupAvatar), findsOneWidget);
      expect(find.text('Study group'), findsOneWidget);
      expect(find.text('You, Sara'), findsOneWidget);
      expect(find.text('2 members'), findsNothing);
      // Mock 13: only the ⋮ on the right (no (i) button any more).
      expect(find.byTooltip('Group info'), findsNothing);
      expect(find.byKey(const ValueKey('group_more_menu')), findsOneWidget);
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

    testWidgets('G1 my own messages: neutral bubble like 1:1, clock tick',
        (tester) async {
      await tester.pumpWidget(
        _host(_FakeGroupMessaging(historyResult: [
          _message(id: 'm1', senderId: 'me', body: 'My message'),
        ])),
      );
      await _settle(tester);

      // Mock 13: no blue gradient on my bubble any more.
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
      expect(gradientBubble, findsNothing);
      // serverSeq 0 = not on the server yet = clock.
      expect(find.byKey(const ValueKey('group_tick_pending')), findsOneWidget);
    });

    testWidgets('composing and sending shows the message and calls the repo',
        (tester) async {
      final messaging = _FakeGroupMessaging();
      await tester.pumpWidget(_host(messaging));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'Hello group');
      await tester.pump();
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
      await tester.pump();
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
      await tester.pump();
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
      await tester.pump();
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

    // ---------------- Bundle G1 (mock 13, 14, 21, 24, 34) ----------------

    testWidgets('G1 mock 13: name + photo on the first bubble of a run only',
        (tester) async {
      final t0 = DateTime.now();
      await tester.pumpWidget(_host(
        _FakeGroupMessaging(historyResult: [
          _message(id: 'a', senderId: 'd2', body: 'Lunch at 1?', createdAt: t0),
          _message(id: 'b', senderId: 'd2', body: 'Same place', createdAt: t0),
          _message(id: 'c', senderId: 'me', body: 'Yes', createdAt: t0),
          _message(id: 'd', senderId: 'd2', body: 'Great', createdAt: t0),
        ]),
        members: [
          _member('me', 'You'),
          GroupMember(
              groupId: 'g1',
              deviceId: 'd2',
              role: 'admin',
              joinedAt: '2026-01-01T00:00:00Z',
              name: 'Sara'),
        ],
      ));
      await _settle(tester);
      // Run 1 (a, b) + run 2 (d) = 2 names, 2 photos.
      expect(find.byKey(const ValueKey('group_sender_name')), findsNWidgets(2));
      expect(find.byKey(const ValueKey('group_sender_photo')), findsNWidgets(2));
      // Role label next to the name.
      expect(find.text('Admin'), findsNWidgets(2));
      final name = tester.widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('group_sender_name')).first,
          matching: find.text('Sara')));
      expect(name.style?.color, GroupMessageBubble.nameColor('Sara'));
      expect(name.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('G1 mock 13: 1:1 message box with the voice mic',
        (tester) async {
      await tester.pumpWidget(_host(_FakeGroupMessaging()));
      await _settle(tester);
      expect(find.byType(ChatComposer), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_mic')), findsOneWidget);
    });

    testWidgets('G1 mock 14: the ⋮ menu rows and order', (tester) async {
      await tester.pumpWidget(_host(_FakeGroupMessaging()));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('group_more_menu')));
      await _anim(tester);
      // G2: Exit group (red) is the last row.
      const rows = [
        'Group info',
        'Search',
        'Media, links and docs',
        'New poll',
        'Mute notifications',
        'Clear chat',
        'Exit group'
      ];
      var lastY = -1.0;
      for (final r in rows) {
        expect(find.text(r), findsOneWidget, reason: r);
        final y = tester.getTopLeft(find.text(r)).dy;
        expect(y, greaterThan(lastY), reason: r);
        lastY = y;
      }
    });

    testWidgets('G1 mock 34: mute from ⋮ - sheet, Mute, bell in the bar',
        (tester) async {
      GroupMuteBook.instance.debugReset();
      addTearDown(GroupMuteBook.instance.debugReset);
      await tester.pumpWidget(_host(_FakeGroupMessaging()));
      await _settle(tester);
      expect(find.byKey(const ValueKey('group_bar_muted')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('group_more_menu')));
      await _anim(tester);
      await tester.tap(find.text('Mute notifications'));
      await _anim(tester);
      expect(find.text('8 hours'), findsOneWidget);
      expect(find.text('1 week'), findsOneWidget);
      expect(find.text('Always'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mute_confirm')));
      await _anim(tester);
      expect(GroupMuteBook.instance.isMuted('g1'), isTrue);
      expect(find.byKey(const ValueKey('group_bar_muted')), findsOneWidget);
      // The menu now offers Unmute.
      await tester.tap(find.byKey(const ValueKey('group_more_menu')));
      await _anim(tester);
      await tester.tap(find.text('Unmute notifications'));
      await _anim(tester);
      expect(GroupMuteBook.instance.isMuted('g1'), isFalse);
    });

    testWidgets('G1 mock 24: search - pill, "1 of 2", arrows, yellow mark',
        (tester) async {
      final t0 = DateTime.now();
      await tester.pumpWidget(_host(_FakeGroupMessaging(historyResult: [
        _message(id: 'a', senderId: 'd2', body: 'Lunch at 1?', createdAt: t0),
        _message(id: 'b', senderId: 'd2', body: 'Hello', createdAt: t0),
        _message(id: 'c', senderId: 'me', body: 'lunch place?', createdAt: t0),
      ])));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('group_more_menu')));
      await _anim(tester);
      await tester.tap(find.text('Search'));
      await _anim(tester);
      expect(find.byKey(const ValueKey('group_search_bar')), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('group_search_field')), 'lunch');
      await tester.pump();
      expect(find.text('1 of 2'), findsOneWidget);
      // Matches are marked yellow inside the bubbles.
      final marked = find.byWidgetPredicate((w) =>
          w is Text &&
          w.textSpan != null &&
          (w.textSpan! as TextSpan).children?.any((c) =>
                  c is TextSpan &&
                  c.style?.backgroundColor == ChatBodyText.markColor) ==
              true);
      expect(marked, findsNWidgets(2));
      await tester.tap(find.byTooltip('Older'));
      await tester.pump();
      expect(find.text('2 of 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Newer'));
      await tester.pump();
      expect(find.text('1 of 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('group_search_bar')), findsNothing);
      expect(marked, findsNothing);
    });

    testWidgets('G1 mock 21: tap the emoji chip - who reacted, remove mine',
        (tester) async {
      final now = DateTime.now();
      final messaging = _FakeGroupMessaging(
        historyResult: [_message(id: 'm1', senderId: 'd2', body: 'Lunch?')],
        reactionMap: {
          'm1': [
            MessageReaction(
                messageId: 'm1', reactorId: 'd2', emoji: '👍', createdAt: now),
            MessageReaction(
                messageId: 'm1', reactorId: 'me', emoji: '👍', createdAt: now),
          ],
        },
      );
      await tester.pumpWidget(_host(messaging));
      await _settle(tester);
      expect(find.text('👍 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group_reaction_chip_👍')));
      await _anim(tester);
      expect(find.text('Reactions'), findsOneWidget);
      expect(find.text('All 2'), findsOneWidget);
      expect(find.text('You'), findsWidgets);
      expect(find.text('Tap to remove'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reaction_remove_mine')));
      await _anim(tester);
      expect(messaging.reacted, ['m1:']);
    });
    group('G2 group chat', () {
    testWidgets('mock 26: announcement group - a member sees no message box',
        (tester) async {
      final g = LocalGroup(
          id: 'g1',
          name: 'Study group',
          ownerId: 'd2',
          createdAt: '2026-01-01T00:00:00Z',
          sendMessages: 'admins');
      await tester.pumpWidget(_host(_FakeGroupMessaging(historyResult: [
        _message(id: 'm1', senderId: 'd2', body: 'News'),
      ]), group: g));
      await _settle(tester);
      expect(find.byKey(const ValueKey('group_admins_only')), findsOneWidget);
      expect(find.byType(ChatComposer), findsNothing);
    });

    testWidgets('mock 25: removed - read only + Delete group asks first',
        (tester) async {
      final g = LocalGroup(
          id: 'g1',
          name: 'Study group',
          ownerId: 'd2',
          createdAt: '2026-01-01T00:00:00Z',
          state: 'removed');
      final repo = _FakeGroupRepository(
          [_member('me', 'You'), _member('d2', 'Sara')],
          group: g);
      await tester.pumpWidget(_host(
          _FakeGroupMessaging(historyResult: [
            _message(id: 'm1', senderId: 'd2', body: 'Bye'),
          ]),
          group: g,
          repo: repo));
      await _settle(tester);
      expect(find.text("You're no longer a participant in this group."),
          findsOneWidget);
      expect(find.byType(ChatComposer), findsNothing);
      await tester.tap(find.byKey(const ValueKey('group_delete_button')));
      await _anim(tester);
      expect(find.text('Delete "Study group"?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete_group_confirm')));
      await _anim(tester);
      expect(repo.calls, contains('delete'));
    });

    testWidgets('system lines show as grey chips (not bubbles)',
        (tester) async {
      await tester.pumpWidget(_host(_FakeGroupMessaging(historyResult: [
        _message(
            id: 'ev-1',
            senderId: 'd2',
            body: 'llev:v1:{"k":"add","by":"d2","t":["me"],"nm":{"d2":"Sara"}}'),
        _message(id: 'm2', senderId: 'd2', body: 'Welcome'),
      ])));
      await _settle(tester);
      expect(find.text('Sara added you'), findsOneWidget);
      expect(find.byKey(const ValueKey('group_system_line_ev-1')),
          findsOneWidget);
      expect(find.textContaining('llev'), findsNothing);
      expect(find.text('Welcome'), findsOneWidget);
    });

    testWidgets('⋮ has Exit group; it asks first and leaves', (tester) async {
      final repo = _FakeGroupRepository(
          [_member('me', 'You'), _member('d2', 'Sara')]);
      await tester.pumpWidget(_host(
          _FakeGroupMessaging(historyResult: [
            _message(id: 'm1', senderId: 'd2', body: 'Hi'),
          ]),
          repo: repo));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('group_more_menu')));
      await _anim(tester);
      expect(find.text('Exit group'), findsOneWidget);
      await tester.tap(find.text('Exit group'));
      await _anim(tester);
      expect(find.text('Exit "Study group"?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('exit_group_confirm')));
      await _anim(tester);
      expect(repo.calls, contains('leave'));
    });
  });
});
}
