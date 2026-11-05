// Bundle 196: contact sheets, own Private profile, Blocked everywhere,
// block state, Nearby friend requests (TODO_196 Part 14).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/notifications/notification_action.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/widgets/blocked_pill.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/calls/presentation/widgets/call_history_tile.dart';
import 'package:locallink/features/directory/data/block_state.dart';
import 'package:locallink/features/directory/data/friend_requests.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart';
import 'package:locallink/features/directory/presentation/blocked_people_screen.dart';
import 'package:locallink/features/directory/presentation/contact_sheets.dart';

String _src(String path) => File(path).readAsStringSync();

final _ali = BlockedPerson(
  userId: 'u-ali',
  deviceId: 'd-ali',
  name: 'Ali',
  username: 'ali',
  blockedAt: DateTime(2026, 11, 2, 20, 49),
);

Future<void> _host(WidgetTester tester, Widget child,
    {double width = 1080}) async {
  tester.view.physicalSize = Size(width, 2280);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: LocalLinkTheme.light(),
    home: Scaffold(body: child),
  ));
  await tester.pump();
}

/// A button that opens a sheet and keeps what it returned.
class _Opener extends StatefulWidget {
  const _Opener(this.open);
  final Future<Object?> Function(BuildContext context) open;
  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  Object? result = 'none';
  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          onPressed: () async {
            final r = await widget.open(context);
            setState(() => result = r);
          },
          child: Text('open:$result'),
        ),
      );
}

Future<void> _openSheet(WidgetTester tester,
    Future<Object?> Function(BuildContext context) open) async {
  await _host(tester, _Opener(open));
  await tester.tap(find.textContaining('open:'));
  await tester.pumpAndSettle();
}

class _Dir extends Fake implements DirectoryRepositoryContract {
  final List<String> blocked = <String>[];
  final List<String> unblocked = <String>[];
  @override
  Future<List<DirectoryProfile>> contacts() async => const [];
  @override
  Future<void> blockUser(String userId) async => blocked.add(userId);
  @override
  Future<void> unblockUser(String userId) async => unblocked.add(userId);
}

void main() {
  setUp(() {
    BlockHub.resetForTest();
    FriendRequestBook.resetForTest();
    PresenceHub.instance.resetForTest();
  });

  group('block state (Part 12)', () {
    const s = BlockState(
      fromUserId: 'u-sajjad',
      fromDeviceId: 'd-sajjad',
      toUserId: 'u-ali',
      state: BlockState.blocked,
      ts: 1000,
    );

    test('wire round trip + fixed signed text', () {
      final back = BlockState.fromWire(s.toMap())!;
      expect(back.canonical(), s.canonical());
      expect(s.canonical(),
          'block-state|v1|u-sajjad|d-sajjad|u-ali|blocked|1000');
      expect(BlockState.fromWire({...s.toMap(), 'state': 'maybe'}), isNull);
      expect(BlockState.fromWire({...s.toMap(), 'to_user_id': 'u-sajjad'}),
          isNull, reason: 'not to myself');
    });

    test('newest ts wins; blocked-me lists follow the latest state', () {
      final all = <String, Map<String, dynamic>>{};
      expect(BlockedByStates.apply(all, s), isTrue);
      expect(BlockedByStates.blockedMeDevices(all), {'d-sajjad'});
      expect(BlockedByStates.blockedMeUsers(all), {'u-sajjad'});
      const older = BlockState(
          fromUserId: 'u-sajjad',
          fromDeviceId: 'd-sajjad',
          toUserId: 'u-ali',
          state: BlockState.unblocked,
          ts: 900);
      expect(BlockedByStates.apply(all, older), isFalse);
      expect(BlockedByStates.blockedMeUsers(all), {'u-sajjad'});
      const newer = BlockState(
          fromUserId: 'u-sajjad',
          fromDeviceId: 'd-sajjad',
          toUserId: 'u-ali',
          state: BlockState.unblocked,
          ts: 2000);
      expect(BlockedByStates.apply(all, newer), isTrue);
      expect(BlockedByStates.blockedMeUsers(all), isEmpty);
      final again = BlockedByStates.decode(BlockedByStates.encode(all));
      expect(again['u-sajjad']?['state'], 'unblocked', reason: 'saved');
    });

    test('resend: 2 min gap, 50 tries, 7 days', () {
      const w = WaitingBlockState(
          userId: 'u-ali', state: 'blocked', ts: 0, tries: 1, lastTryMs: 0);
      expect(BlockStateResendPolicy.step(w, nowMs: 1), BlockStateStep.send);
      const recent = WaitingBlockState(
          userId: 'u-ali', state: 'blocked', ts: 0, tries: 1, lastTryMs: 1000);
      expect(BlockStateResendPolicy.step(recent, nowMs: 60 * 1000),
          BlockStateStep.wait);
      const many = WaitingBlockState(
          userId: 'u-ali', state: 'blocked', ts: 0, tries: 50, lastTryMs: 0);
      expect(BlockStateResendPolicy.step(many, nowMs: 5),
          BlockStateStep.stopMaxTries);
      expect(
          BlockStateResendPolicy.step(w,
              nowMs: BlockStateResendPolicy.lifetimeMs),
          BlockStateStep.stopTimeout);
    });

    test('lock layer lets the two new types through strangers', () {
      final seal = _src(
          'lib/features/connectivity/data/services/sealing_peer_transport.dart');
      expect(seal, contains('CONTACT_BLOCK_STATE'));
      expect(seal, contains('CONTACT_BLOCK_STATE_ACK'));
    });
  });

  group('friend requests book (12b)', () {
    FriendRequest req(String d, int at) => FriendRequest(
        deviceId: d, userId: 'u-$d', name: 'N$d', username: 'n$d', atMs: at, body: '{}');

    test('new / repeat / decline / 24 h', () async {
      final book = FriendRequestBook.instance;
      var now = 1000;
      book.now = () => now;
      expect(await book.addIncoming(req('a', now)), isTrue);
      expect(await book.addIncoming(req('a', now)), isFalse);
      expect(book.visible.map((r) => r.deviceId), ['a']);
      await book.decline('a');
      expect(book.visible, isEmpty);
      expect(await book.addIncoming(req('a', now)), isFalse,
          reason: 'declined stays quiet');
      now += FriendRequestRules.lifetimeMs + 1;
      expect(book.incoming('a'), isNull, reason: 'gone after 24 h');
    });

    test('Requested for 24 h, then Add friend again', () async {
      final book = FriendRequestBook.instance;
      var now = 5;
      book.now = () => now;
      await book.markSent('d-sum', 'u-sum');
      expect(book.isSent('d-sum'), isTrue);
      expect(book.isSentUser('u-sum'), isTrue);
      now += FriendRequestRules.lifetimeMs;
      expect(book.isSent('d-sum'), isFalse);
    });

    test('saved and read back (restart)', () async {
      final settings = <String, String>{};
      final book = FriendRequestBook.instance;
      book.now = () => 10;
      await book.attach(
          read: (k) async => settings[k],
          write: (k, v) async => settings[k] = v);
      await book.addIncoming(req('b', 10));
      await book.markSent('d-x', 'u-x');
      FriendRequestBook.resetForTest();
      final again = FriendRequestBook.instance..now = () => 20;
      await again.attach(
          read: (k) async => settings[k],
          write: (k, v) async => settings[k] = v);
      expect(again.visible.single.deviceId, 'b');
      expect(again.isSent('d-x'), isTrue);
    });

    test('age words', () {
      expect(FriendRequestRules.age(0, 30 * 1000), '<1 min');
      expect(FriendRequestRules.age(0, 5 * 60000), '5 min');
      expect(FriendRequestRules.age(0, 3 * 3600000), '3 h');
    });

    test('notification Accept / Decline actions parse', () {
      Map<String, String> m(String a) => {
            'action': a,
            'conversation_type': 'friend',
            'notification_id': '1',
            'conversation_id': 'u-ali',
            'message_id': 'friend',
            'sender_id': 'd-ali',
            'recipient_id': 'me',
          };
      expect(LocalLinkNotificationAction.fromMap(m('friend_request_accept')).action,
          NotificationActionType.friendRequestAccept);
      expect(
          LocalLinkNotificationAction.fromMap(m('friend_request_decline')).action,
          NotificationActionType.friendRequestDecline);
    });
  });

  group('BlockHub', () {
    test('lists, devices, users, blocked-me', () async {
      final hub = BlockHub.instance;
      hub.setForTest(
          people: [_ali, const BlockedPerson(userId: 'dev-only')],
          blockedMeDevices: {'d-sajjad'});
      expect(hub.people.map((p) => p.userId), ['u-ali'],
          reason: 'device-only rows are not people');
      expect(hub.isBlockedDevice('d-ali'), isTrue);
      expect(hub.isBlockedUser('u-ali'), isTrue);
      expect(hub.personForDevice('d-ali')?.name, 'Ali');
      expect(hub.hasBlockedMe('d-sajjad'), isTrue);
      expect(hub.hasBlockedMe('d-ali'), isFalse);
    });

    test('attach loads and follows changes', () async {
      var list = <BlockedPerson>[];
      final hub = BlockHub.instance;
      await hub.attach(
        loadPeople: () async => list,
        loadPeerIds: () async => {for (final p in list) p.deviceId},
        loadBlockedMe: () async => (<String>{}, <String>{}),
      );
      expect(hub.people, isEmpty);
      list = [_ali];
      await hub.reload();
      expect(hub.isBlockedDevice('d-ali'), isTrue);
    });

    test('date / time words (no intl)', () {
      expect(blockDateLabel(DateTime(2026, 11, 2)), '2 Nov 2026');
      expect(blockTimeLabel(DateTime(2026, 11, 2, 20, 49)), '8:49 PM');
      expect(blockTimeLabel(DateTime(2026, 11, 2, 0, 5)), '12:05 AM');
    });
  });

  group('sheets (screens 2-6, 14b/c)', () {
    testWidgets('actions sheet: 4 rows, red Block, no share/privacy',
        (tester) async {
      await _openSheet(
          tester, (c) => showContactActionsSheet(c, name: 'Ali', username: 'ali'));
      expect(find.byKey(const Key('contact_actions_sheet')), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Voice call'), findsOneWidget);
      expect(find.text('Remove contact'), findsOneWidget);
      expect(find.text('Block Ali'), findsOneWidget);
      expect(find.text('@ali'), findsOneWidget);
      expect(find.textContaining('privacy'), findsNothing);
      expect(find.textContaining('Share'), findsNothing);
      final block = tester.widget<Text>(find.text('Block Ali'));
      expect(block.style?.color, LocalLinkTheme.light().colorScheme.error);
      await tester.tap(find.text('Block Ali'));
      await tester.pumpAndSettle();
      expect(find.text('open:ContactSheetChoice.block'), findsOneWidget);
    });

    testWidgets('Block sheet: exact words; Cancel = false, Block = true',
        (tester) async {
      await _openSheet(tester, (c) => showBlockSheet(c, name: 'Ali'));
      expect(find.text('Block Ali?'), findsOneWidget);
      expect(find.textContaining("can't message or call", findRichText: true),
          findsOneWidget);
      expect(find.textContaining('removed from your contacts', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('You can unblock them any time.',
              findRichText: true),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('block_sheet_cancel')));
      await tester.pumpAndSettle();
      expect(find.text('open:false'), findsOneWidget);
      await tester.tap(find.textContaining('open:'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block_sheet_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('open:true'), findsOneWidget);
    });

    testWidgets('Remove sheet words', (tester) async {
      await _openSheet(tester, (c) => showRemoveSheet(c, name: 'Ali'));
      expect(find.text('Remove Ali from your contacts?'), findsOneWidget);
      expect(find.textContaining('stays', findRichText: true), findsOneWidget);
      expect(find.textContaining('You can add them again later.',
              findRichText: true),
          findsOneWidget);
    });

    testWidgets('Unblock sheet: date, both buttons', (tester) async {
      await _openSheet(tester, (c) => showUnblockSheet(c, _ali));
      expect(find.text('Ali is blocked'), findsOneWidget);
      expect(find.textContaining('Blocked on 2 Nov 2026.', findRichText: true),
          findsOneWidget);
      expect(find.byType(BlockedPill), findsOneWidget);
      await tester.tap(find.byKey(const Key('unblock_sheet_only')));
      await tester.pumpAndSettle();
      expect(find.text('open:UnblockChoice.only'), findsOneWidget);
    });

    testWidgets('Private profile sheet: 4 points, Make private',
        (tester) async {
      await _openSheet(tester, showPrivateProfileSheet);
      expect(find.text('Make your profile private?'), findsOneWidget);
      expect(find.textContaining('QR code', findRichText: true), findsOneWidget);
      expect(find.textContaining('Only you can change this', findRichText: true),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('private_profile_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('open:true'), findsOneWidget);
    });

    testWidgets('Conversation info: normal vs blocked', (tester) async {
      await _openSheet(
          tester,
          (c) => showChatInfoSheet(c,
              name: 'sumaira',
              subtitle: '@sumaira · Nearby',
              blocked: false,
              showCall: true));
      expect(find.byKey(const Key('chat_info_call')), findsOneWidget);
      expect(find.byKey(const Key('chat_info_search')), findsOneWidget);
      expect(find.text('Block sumaira'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat_info_close')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await _openSheet(
          tester,
          (c) => showChatInfoSheet(c,
              name: 'Ali',
              subtitle: '',
              username: '@ali',
              blocked: true,
              showCall: true));
      expect(find.byKey(const Key('chat_info_call')), findsNothing);
      expect(find.text('Unblock Ali'), findsOneWidget);
      expect(find.byType(BlockedPill), findsOneWidget);
    });
  });

  group('Blocked label on every screen', () {
    testWidgets('Chats row: pill, no call button', (tester) async {
      var calls = 0;
      await _host(
          tester,
          MessengerConversationTile(
            title: 'Ali',
            subtitle: 'Ok, call me later',
            time: 'Yesterday',
            blocked: true,
            onCall: () => calls++,
          ));
      expect(find.byType(BlockedPill), findsOneWidget);
      expect(find.byType(MutedAvatar), findsOneWidget);
      expect(find.byType(MessengerCallButton), findsNothing);
      expect(find.text('Yesterday'), findsOneWidget);
    });

    testWidgets('Calls row: pill, no call back, tap opens Unblock',
        (tester) async {
      BlockHub.instance.setForTest(people: [_ali]);
      var calls = 0;
      await _host(
          tester,
          CallHistoryTile(
            call: CallRecord(
              id: 'c1',
              callerId: 'd-ali',
              calleeId: 'me',
              status: 'missed',
              startedAt: DateTime(2026, 11, 1, 20, 5),
              peerName: 'Ali',
            ),
            title: 'Ali',
            status: 'Missed',
            date: '8:05 PM',
            duration: null,
            selfId: 'me',
            missed: true,
            onCall: () => calls++,
          ));
      expect(find.byType(BlockedPill), findsOneWidget);
      expect(find.byType(MessengerCallButton), findsNothing);
      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byKey(const Key('unblock_sheet')), findsOneWidget);
    });

    testWidgets('Calls row: they blocked me = no call back, no label',
        (tester) async {
      BlockHub.instance.setForTest(blockedMeDevices: {'d-sajjad'});
      await _host(
          tester,
          CallHistoryTile(
            call: CallRecord(
              id: 'c2',
              callerId: 'me',
              calleeId: 'd-sajjad',
              status: 'completed',
              startedAt: DateTime(2026, 11, 1),
              peerName: 'Sajjad',
            ),
            title: 'Sajjad',
            status: 'Completed',
            date: '8:05 PM',
            duration: null,
            selfId: 'me',
            onCall: () {},
          ));
      expect(find.byType(MessengerCallButton), findsNothing);
      expect(find.byType(BlockedPill), findsNothing);
    });

    testWidgets('Profile page: blocked view with both Unblock buttons',
        (tester) async {
      BlockHub.instance.setForTest(people: [_ali]);
      final dir = _Dir();
      BlockHub.instance.unblock = dir.unblockUser;
      await _host(
          tester,
          DirectoryProfileView(
            profile: const DirectoryProfile(
                userId: 'u-ali', deviceId: 'd-ali', username: 'ali', displayName: 'Ali'),
            repository: dir,
          ));
      await tester.pump();
      expect(find.byKey(const ValueKey('profile_blocked_chip')), findsOneWidget);
      expect(
          find.text(
              "You blocked Ali on 2 Nov 2026. They can't message or call you."),
          findsOneWidget);
      expect(find.text('Unblock and add back'), findsOneWidget);
      expect(find.text('Unblock only'), findsOneWidget);
      expect(find.text('Block user'), findsNothing);
      expect(find.text('Add Contact'), findsNothing);
      expect(find.text('Searchable by others'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('profile_unblock_only')));
      await tester.pump();
      expect(dir.unblocked, ['u-ali']);
    });

    testWidgets('Profile page: no privacy switch for a contact',
        (tester) async {
      expect(
          _src('lib/features/directory/presentation/add_contact_screen.dart'),
          isNot(contains('_privacySwitch')));
      expect(_src('lib/features/directory/presentation/contacts_screen.dart'),
          isNot(contains('_editPrivacy')));
    });

    testWidgets('Blocked people screen: rows + empty text', (tester) async {
      BlockHub.instance.setForTest(people: [_ali]);
      // (The test font draws every letter 1 em wide, so the row is
      // checked on a wider screen; a real 360 dp phone has room.)
      await _host(tester, const BlockedPeopleScreen(), width: 1500);
      expect(find.text('1 PERSON'), findsOneWidget);
      expect(find.text('Ali'), findsOneWidget);
      expect(find.byType(BlockedPill), findsOneWidget);
      expect(find.text('Tap a person to see more.'), findsOneWidget);
      BlockHub.instance.setForTest();
      await tester.pump();
      expect(find.text("You haven't blocked anyone."), findsOneWidget);
    });

    testWidgets('search result card for a blocked match', (tester) async {
      var taps = 0;
      await _host(
          tester, BlockedResultCard(person: _ali, onUnblock: () => taps++));
      expect(find.text('Unblock'), findsOneWidget);
      expect(find.byType(BlockedPill), findsOneWidget);
      await tester.tap(find.byKey(const Key('search_result_unblock')));
      expect(taps, 1);
    });

    testWidgets('group label can be red', (tester) async {
      await _host(tester,
          const MessengerGroupLabel('Blocked', color: Color(0xFFB3261E)));
      final t = tester.widget<Text>(find.text('BLOCKED'));
      expect(t.style?.color, const Color(0xFFB3261E));
    });
  });

  group('source checks', () {
    test('chat: bar on both sides, no call icon, info is a sheet', () {
      final chat =
          _src('lib/features/messaging/presentation/screens/chat_screen.dart');
      expect(chat, contains("'You blocked \${_peerName(device)}.'"));
      expect(chat, contains("\"You can't message \${_peerName(device)}.\""));
      expect(chat, contains('!iBlocked && !blockedMe'));
      expect(chat, contains('showChatInfoSheet('));
      expect(chat, isNot(contains('AlertDialog(\n        title: Text(device.name')));
    });

    test('People: requests on top, blocked at the bottom, Private label', () {
      final people =
          _src('lib/features/directory/presentation/contacts_screen.dart');
      expect(people, contains("MessengerGroupLabel('Requests'"));
      expect(people, contains("MessengerGroupLabel('Blocked'"));
      expect(people, contains('PrivatePill('));
      expect(people, contains('showContactActionsSheet('));
      expect(people, isNot(contains('PopupMenuItem(value: \'block\'')));
    });

    test('Settings: PRIVACY group with Blocked people (Bundle 202: Private profile moved to Profile)', () {
      final s = _src(
          'lib/features/home/presentation/screens/messenger_settings_screen.dart');
      expect(s, contains("MessengerGroupLabel('Privacy'"));
      expect(s, isNot(contains("'Private profile'")));
      expect(s, contains("'Blocked people'"));
      final card = _src(
          'lib/features/account/presentation/widgets/private_profile_card.dart');
      expect(card, contains("'Private profile'"));
      expect(card, contains('discoverableByName: !makePrivate'));
      expect(s.indexOf("MessengerGroupLabel('This phone')"),
          lessThan(s.indexOf("MessengerGroupLabel('Privacy'")));
      // Bundle 214: the Admin section is removed.
      expect(s, isNot(contains("MessengerGroupLabel('Admin')")));
    });

    test('profile save keeps my Private choice', () {
      final p = _src(
          'lib/features/account/presentation/screens/profile_screen.dart');
      expect(p, contains('discoverableByName: profile?.discoverableByName ?? true'));
    });

    test('Nearby: Requested button + wait note + on-screen count', () {
      final n = _src(
          'lib/features/directory/presentation/nearby_people_section.dart');
      expect(n, contains("ValueKey('nearby_requested_\${mesh.nodeId}')"));
      expect(n, contains("'Request sent. \$who needs to accept.'"));
      expect(n, contains('nearbyOnScreen++'));
      expect(n, contains('nearbyOnScreen--'));
    });

    test('Kotlin: Accept first, then Decline on the request notice', () {
      final k = _src(
          'android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkNotificationManager.kt');
      expect(k.indexOf('ACTION_FRIEND_REQUEST_ACCEPT, 4, "Accept"'),
          lessThan(k.indexOf('ACTION_FRIEND_REQUEST_DECLINE, 3, "Decline"')));
    });
  });
}
