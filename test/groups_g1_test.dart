import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/features/groups/data/group_mute_book.dart';
import 'package:locallink/features/groups/presentation/screens/new_group_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_sheets.dart';
import 'package:locallink/features/messaging/presentation/widgets/pinch_text_zoom.dart';

/// Bundle G1: the group screens must match the approved mock G0
/// (texts, order, icons). One test block per mock screen.

const _ali = GroupFriend(deviceId: 'd-ali', name: 'Ali');
const _sara = GroupFriend(deviceId: 'd-sara', name: 'Sara');
const _bilal = GroupFriend(deviceId: 'd-bilal', name: 'Bilal');

final _group = LocalGroup(
  id: 'g1',
  name: 'Office',
  ownerId: 'me',
  createdAt: '2026-11-03T00:00:00Z',
);

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Opens [open] from a button so the sheet has a route below it.
Widget _launcher(Future<Object?> Function(BuildContext) open,
        {void Function(Object?)? onResult}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await open(context);
                onResult?.call(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void _expectOrder(WidgetTester t, List<String> texts) {
  var lastY = -1.0;
  for (final x in texts) {
    expect(find.text(x), findsOneWidget, reason: x);
    final y = t.getTopLeft(find.text(x)).dy;
    expect(y, greaterThan(lastY), reason: 'order: $x');
    lastY = y;
  }
}

void main() {
  group('mock 2: Start sheet', () {
    testWidgets('title, rows with small lines, Join with QR, Close', (t) async {
      Object? result;
      await t.pumpWidget(
          _launcher((c) => showStartSheet(c), onResult: (r) => result = r));
      await t.tap(find.text('open'));
      await _frames(t);
      _expectOrder(t, [
        'Start',
        'New chat',
        'Message one friend',
        'New group',
        'Up to 32 people Nearby, 100 Online',
        'Join group with QR',
        'Scan a group code',
        'Close',
      ]);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.group_outlined), findsOneWidget);
      // G4: "Join group with QR" (mock 2).
      expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
      await t.tap(find.text('New group'));
      await _frames(t);
      expect(result, StartChoice.newGroup);
    });
  });

  group('mock 3 / 3b / 4: New group', () {
    Widget host({
      List<GroupFriend> friends = const [_ali, _bilal, _sara],
      GroupCreateCallback? onCreate,
      VoidCallback? onPeople,
    }) =>
        MaterialApp(
          home: NewGroupScreen(
            loadFriends: () async => friends,
            onCreate: onCreate ??
                (name, people, options) async => GroupCreateResult(_group),
            onGoToPeople: onPeople ?? () {},
          ),
        );

    testWidgets('3: friends list, check, chips, "N of 32", arrow button',
        (t) async {
      await t.pumpWidget(host());
      await _frames(t);
      expect(find.text('New group'), findsOneWidget);
      expect(find.text('Add people'), findsOneWidget);
      expect(find.text('YOUR FRIENDS'), findsOneWidget);
      _expectOrder(t, ['Ali', 'Bilal', 'Sara']);
      expect(find.text('Offline'), findsNWidgets(3));
      expect(find.byKey(const ValueKey('pick_off')), findsNWidgets(3));
      expect(find.byIcon(Icons.search), findsOneWidget);
      // Arrow is grey and does nothing while nobody is picked.
      final fab = t.widget<SquareGradientFab>(
          find.byKey(const ValueKey('new_group_next')));
      expect(fab.onPressed, isNull);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('pick_d-ali')));
      await t.tap(find.byKey(const ValueKey('pick_d-sara')));
      await t.pump();
      expect(find.text('Add people · 2 of 32'), findsOneWidget);
      expect(find.byKey(const ValueKey('new_group_chips')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip_d-ali')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick_on')), findsNWidgets(2));
      expect(
          t
              .widget<SquareGradientFab>(
                  find.byKey(const ValueKey('new_group_next')))
              .onPressed,
          isNotNull);
      // Tap a chip = take the person out.
      await t.tap(find.byKey(const ValueKey('chip_d-ali')));
      await t.pump();
      expect(find.text('Add people · 1 of 32'), findsOneWidget);
    });

    testWidgets('3: search filters the friends', (t) async {
      await t.pumpWidget(host());
      await _frames(t);
      await t.tap(find.byKey(const ValueKey('new_group_search_button')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('new_group_search')), 'sa');
      await t.pump();
      expect(find.byKey(const ValueKey('pick_d-sara')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick_d-ali')), findsNothing);
    });

    testWidgets('3b: no friends - text and Go to People', (t) async {
      var people = 0;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.push(
                c,
                MaterialPageRoute(
                  builder: (_) => NewGroupScreen(
                    loadFriends: () async => const [],
                    onCreate: (n, p, o) async => GroupCreateResult(_group),
                    onGoToPeople: () => people++,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await _frames(t);
      expect(find.text('Add people'), findsOneWidget);
      expect(find.text('No friends yet'), findsOneWidget);
      expect(
          find.textContaining('Groups are made from your friends. Add friends in',
              findRichText: true),
          findsOneWidget);
      expect(find.text('Go to People'), findsOneWidget);
      expect(
          t
              .widget<SquareGradientFab>(
                  find.byKey(const ValueKey('new_group_next')))
              .onPressed,
          isNull);
      await t.tap(find.text('Go to People'));
      await _frames(t);
      expect(people, 1);
      expect(find.text('No friends yet'), findsNothing);
    });

    testWidgets('4: name, counter, "2 PEOPLE + YOU", check = Create',
        (t) async {
      String? madeName;
      List<GroupFriend>? madePeople;
      await t.pumpWidget(host(onCreate: (name, people, options) async {
        madeName = name;
        madePeople = people;
        return GroupCreateResult(_group);
      }));
      await _frames(t);
      await t.tap(find.byKey(const ValueKey('pick_d-ali')));
      await t.tap(find.byKey(const ValueKey('pick_d-sara')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('new_group_next')));
      await _frames(t);
      // G2: subtitle "Name and photo" + the "Group name" hint (mock 4).
      expect(find.text('Name and photo'), findsOneWidget);
      expect(find.text('Group name'), findsOneWidget);
      expect(find.text('2 PEOPLE + YOU'), findsOneWidget);
      expect(find.text('0/80'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(
          t
              .widget<SquareGradientFab>(
                  find.byKey(const ValueKey('new_group_create')))
              .onPressed,
          isNull);
      await t.enterText(find.byKey(const ValueKey('new_group_name')), 'Office');
      await t.pump();
      expect(find.text('6/80'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('new_group_create')));
      await _frames(t);
      expect(madeName, 'Office');
      expect(madePeople!.map((p) => p.name), ['Ali', 'Sara']);
      // Both screens closed.
      expect(find.byType(NewGroupNameScreen), findsNothing);
    });

    testWidgets('4: a clear reason when it cannot be made', (t) async {
      await t.pumpWidget(host(
          onCreate: (n, p, o) async => throw const GroupCreateError(
              'Making a group needs Online for now. Try again when Online.')));
      await _frames(t);
      await t.tap(find.byKey(const ValueKey('pick_d-ali')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('new_group_next')));
      await _frames(t);
      await t.enterText(find.byKey(const ValueKey('new_group_name')), 'Office');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('new_group_create')));
      await _frames(t);
      expect(
          find.text('Making a group needs Online for now. Try again when Online.'),
          findsOneWidget);
      expect(find.byType(NewGroupNameScreen), findsOneWidget);
    });
  });

  group('mock 10: Chats group row', () {
    Widget row({required bool muted, int unread = 3}) => MaterialApp(
          home: Scaffold(
            body: MessengerConversationTile(
              title: 'Family',
              subtitle: 'Mum: Voice message',
              time: '9:02 PM',
              group: _group,
              unreadCount: unread,
              muted: muted,
            ),
          ),
        );

    testWidgets('muted: bell, grey count, grey time', (t) async {
      await t.pumpWidget(row(muted: true, unread: 12));
      expect(find.byKey(const ValueKey('row_muted_bell')), findsOneWidget);
      final badge = t.widget<Container>(find
          .ancestor(of: find.text('12'), matching: find.byType(Container))
          .first);
      expect((badge.decoration as BoxDecoration).color, const Color(0xFFB9BAC2));
      final time = t.widget<Text>(find.text('9:02 PM'));
      expect(time.style?.fontWeight, FontWeight.w400);
    });

    testWidgets('not muted: blue count, no bell', (t) async {
      await t.pumpWidget(row(muted: false));
      expect(find.byKey(const ValueKey('row_muted_bell')), findsNothing);
      final time = t.widget<Text>(find.text('9:02 PM'));
      expect(time.style?.fontWeight, FontWeight.w700);
    });
  });

  group('mock 11: hold a group row', () {
    testWidgets('header, rows in order, Exit group (G2), Close', (t) async {
      await t.pumpWidget(_launcher((c) =>
          showGroupRowSheet(c, name: 'Office', memberCount: 4, muted: false)));
      await t.tap(find.text('open'));
      await _frames(t);
      _expectOrder(t, [
        'Office',
        'Group · 4 members',
        'Mark as read',
        'Mute notifications',
        'Group info',
        'Clear chat',
        'Exit group',
        'Close',
      ]);
      expect(find.text('Delete group'), findsNothing);
      expect(find.byIcon(Icons.mark_chat_read_outlined), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.clear_all_rounded), findsOneWidget);
    });

    testWidgets('muted group offers Unmute', (t) async {
      Object? result;
      await t.pumpWidget(_launcher(
          (c) => showGroupRowSheet(c, name: 'Office', memberCount: 4, muted: true),
          onResult: (r) => result = r));
      await t.tap(find.text('open'));
      await _frames(t);
      expect(find.text('Mute notifications'), findsNothing);
      await t.tap(find.text('Unmute notifications'));
      await _frames(t);
      expect(result, GroupRowChoice.unmute);
    });
  });

  group('mock 34: mute sheet', () {
    testWidgets('texts, 1 week picked first, Cancel / Mute', (t) async {
      Object? result;
      await t.pumpWidget(_launcher((c) => showGroupMuteSheet(c),
          onResult: (r) => result = r));
      await t.tap(find.text('open'));
      await _frames(t);
      _expectOrder(t, [
        'Mute notifications',
        'You still get messages. A mention of you (@) still notifies you.',
        '8 hours',
        '1 week',
        'Always',
      ]);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
      await t.tap(find.text('Mute'));
      await _frames(t);
      expect((result! as GroupMuteChoice).length, const Duration(days: 7));
    });

    testWidgets('Always = no end', (t) async {
      Object? result;
      await t.pumpWidget(_launcher((c) => showGroupMuteSheet(c),
          onResult: (r) => result = r));
      await t.tap(find.text('open'));
      await _frames(t);
      await t.tap(find.text('Always'));
      await t.pump();
      await t.tap(find.text('Mute'));
      await _frames(t);
      expect((result! as GroupMuteChoice).length, isNull);
    });
  });

  group('GroupMuteBook', () {
    setUp(GroupMuteBook.instance.debugReset);
    tearDown(GroupMuteBook.instance.debugReset);

    test('8 hours ends, Always stays, saved and loaded', () async {
      final saved = <String, String>{};
      final book = GroupMuteBook.instance;
      var now = 1000000;
      book.now = () => now;
      await book.load(read: (k) async => saved[k], write: (k, v) async => saved[k] = v);
      await book.mute('a', const Duration(hours: 8));
      await book.mute('b', null);
      expect(book.isMuted('a'), isTrue);
      expect(book.isMuted('b'), isTrue);
      expect(book.isMuted('c'), isFalse);
      now += const Duration(hours: 8, seconds: 1).inMilliseconds;
      expect(book.isMuted('a'), isFalse);
      expect(book.isMuted('b'), isTrue);
      expect(saved[GroupMuteBook.key], contains('"b":-1'));
      // A fresh start reads the same list.
      book.debugReset();
      book.now = () => now;
      await book.load(read: (k) async => saved[k], write: (k, v) async => saved[k] = v);
      expect(book.isMuted('b'), isTrue);
      await book.unmute('b');
      expect(book.isMuted('b'), isFalse);
    });
  });

  group('mock 24: search mark', () {
    test('every match gets the yellow mark, any case', () {
      final spans = ChatBodyText.markSpans('Lunch at 1? lunch!', 'LUNCH')!;
      expect(spans.map((s) => s.text), ['Lunch', ' at 1? ', 'lunch', '!']);
      expect(spans[0].style?.backgroundColor, const Color(0xFFFFE58A));
      expect(spans[1].style, isNull);
      expect(ChatBodyText.markSpans('Hello', 'x'), isNull);
      expect(ChatBodyText.markSpans('Hello', ''), isNull);
    });
  });

  group('wiring (source)', () {
    String src(String p) => File(p).readAsStringSync();

    test('Chats + opens the Start sheet; New chat still goes to People', () {
      final home = src('lib/features/home/presentation/screens/home_screen.dart');
      expect(home, contains('onPressed: _openStartSheet'));
      expect(home, contains('case StartChoice.newChat:\n        setState(() => _index = 2);'));
      expect(home, contains('NewGroupScreen('));
      expect(home, contains('muted: GroupMuteBook.instance.isMuted(group.id)'));
      expect(home, contains('showGroupRowSheet('));
      // Friends only, blocked people left out.
      expect(home, contains('widget.store.contacts()'));
      expect(home, contains('BlockHub.instance.isBlockedDevice(id)'));
    });

    test('muted group: no notification; title = group, "Sara: ..." text', () {
      final n = src('lib/core/notifications/local_link_notification_service.dart');
      // G5: a mention still rings in a muted group.
      expect(n, contains('if (GroupMuteBook.instance.isMuted(message.groupId) && !mentioned) return;'));
      expect(n, contains("return who.isEmpty ? body : '\$who: \$body';"));
      expect(n, isNot(contains("isGroup ? '\$title • \${senderName ?? 'Message'}'")));
    });

    test('mutes load at start', () {
      final d = src('lib/app/app_dependencies.dart');
      expect(d, contains('GroupMuteBook.instance\n          .load('));
    });

    test('take a reaction back: empty emoji note, row deleted both sides', () {
      final s = src('lib/features/groups/data/services/group_messaging_service.dart');
      expect(s, contains('await _removeReaction(groupId, messageId);'));
      expect(s, contains("'emoji': ''"));
      expect(RegExp('deleteGroupMessageReaction').allMatches(s).length, 2);
      final b = src('lib/features/groups/bloc/group_chat_bloc.dart');
      expect(b, contains("repository.react(state.group.id, messageId, '')"));
      expect(b, contains('if(r.emoji.isEmpty){if(i>=0)list.removeAt(i);}'));
    });

    test('group chat: ⋮ text rows (mock 14), voice notes, search', () {
      final g = src('lib/features/groups/presentation/screens/group_chat_screen.dart');
      expect(g, contains("const PopupMenuItem(value: 'info', child: Text('Group info'))"));
      expect(g, contains('ChatComposer('));
      expect(g, contains('voice: _voice'));
      expect(g, contains("VoiceDraftStore.put(key, draft)"));
      expect(g, isNot(contains('GroupComposer(')));
      expect(g, contains("'\${at + 1} of \${matches.length}'"));
    });
  });
}
