import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/groups/data/group_invite_link.dart';
import 'package:locallink/features/groups/presentation/screens/group_link_screens.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_bubble.dart';
import 'package:locallink/features/messaging/presentation/widgets/bubble_media.dart';

import 'support/phase5_fakes.dart';

/// Bundle G6 (mock L1-L5): group invite link.
class _Api implements LocalLinkApi {
  final log = <String>[];
  Map<String, dynamic> preview = {
    'group_id': 'g1',
    'name': 'Family',
    'members': 4,
    'member_names': ['Sara', 'Bilal', ' '],
    'invited_by': 'Sajjad',
    'approve': false,
    'status': 'none',
  };
  String joinStatus = 'joined';

  @override
  String get baseUrl => 'https://server.example/';

  @override
  Future<String> groupInviteToken(String groupId,
      {bool approve = false, bool reset = false}) async {
    log.add('token:$groupId:approve=$approve:reset=$reset');
    return reset ? 'NEWtoken23' : 'ABCdef234';
  }

  @override
  Future<Map<String, dynamic>> groupJoinPreview(String token) async {
    log.add('preview:$token');
    return preview;
  }

  @override
  Future<Map<String, dynamic>> joinGroupByLink(String token,
      {String seal = '', String sign = ''}) async {
    log.add('join:$token');
    return {'status': joinStatus, 'group_id': 'g1'};
  }

  @override
  Future<List<Map<String, dynamic>>> groupLinkRequests(String groupId) async {
    log.add('requests:$groupId');
    return [
      {'device_id': 'dev-z', 'name': ' ', 'created_at': '2026-11-04T10:00:00Z'},
    ];
  }

  @override
  Future<void> declineGroupLinkRequest(String groupId, String deviceId) async {
    log.add('decline:$groupId:$deviceId');
  }

  @override
  Future<bool> addGroupMember(String groupId, String deviceId) async {
    log.add('add:$groupId:$deviceId');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

LocalGroup _group({String origin = 'server', int cardVersion = 0}) => LocalGroup(
    id: 'g1',
    name: 'Family',
    ownerId: 'me',
    createdAt: '2026-11-04T10:00:00Z',
    origin: origin,
    cardVersion: cardVersion);

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  late _Api api;
  final refreshed = <String>[];
  final opened = <String>[];

  setUp(() {
    api = _Api();
    refreshed.clear();
    opened.clear();
    GroupInviteService.instance = GroupInviteService(
        api: api, refreshGroup: (gid) async => refreshed.add(gid));
    GroupInviteService.openGroup = (gid) async => opened.add(gid);
  });

  tearDown(() {
    GroupInviteService.instance = null;
    GroupInviteService.openGroup = null;
  });

  group('link words', () {
    test('token found in app link and web link; bad letters refused', () {
      expect(GroupInviteLink.tokenIn('come linkup://join/ABCdef234 now'),
          'ABCdef234');
      expect(GroupInviteLink.tokenIn('https://s.example/join/XyZ23456'),
          'XyZ23456');
      expect(GroupInviteLink.tokenIn('hello'), isNull);
      // 0 / 1 / O / I / l are never in a token.
      expect(GroupInviteLink.tokenIn('linkup://join/ABCDEF10'), isNull);
      expect(GroupInviteLink.tokenIn('linkup://join/short'), isNull);
    });

    test('share text: web link first, app link after', () {
      final t = GroupInviteLink.shareText(
          'Family', 'ABCdef234', 'https://server.example/');
      expect(t.split('\n'), [
        'Join my LinkUp group "Family":',
        'https://server.example/join/ABCdef234',
        '',
        'In LinkUp: linkup://join/ABCdef234',
      ]);
      expect(GroupInviteLink.shareText('Family', 'ABCdef234', ''),
          'Join my LinkUp group "Family":\nlinkup://join/ABCdef234');
    });

    test('preview words (mock L3)', () {
      final p = GroupJoinPreview.fromJson(api.preview);
      expect(p.memberNames, ['Sara', 'Bilal']);
      expect(p.line, 'Group · 4 members · invite link from Sajjad');
      expect(
          const GroupJoinPreview(groupId: 'g', name: 'A', members: 1).line,
          'Group · 1 member');
    });
  });

  group('service', () {
    test('admin token: card groups always ask first; reset = new', () async {
      final s = GroupInviteService.instance!;
      expect(await s.token(_group()), 'ABCdef234');
      expect(await s.token(_group(origin: 'both', cardVersion: 2), reset: true),
          'NEWtoken23');
      expect(api.log, [
        'token:g1:approve=false:reset=false',
        'token:g1:approve=true:reset=true',
      ]);
    });

    test('join -> group refreshed, preview turns "member"', () async {
      final s = GroupInviteService.instance!;
      await s.preview('ABCdef234');
      expect(await s.join('ABCdef234'), 'joined');
      expect(refreshed, ['g1']);
      expect(s.cached('ABCdef234')!.status, 'member');
    });

    test('requests: nameless -> "LinkUp user"; nearby-only -> none', () async {
      final s = GroupInviteService.instance!;
      final r = await s.requests(_group());
      expect(r.single.name, 'LinkUp user');
      expect(r.single.via, 'link');
      expect(await s.requests(_group(origin: 'nearby', cardVersion: 1)),
          isEmpty);
      await s.approve(_group(), r.single);
      await s.decline('g1', 'dev-z');
      expect(api.log, contains('add:g1:dev-z'));
      expect(api.log, contains('decline:g1:dev-z'));
    });
  });

  group('screens', () {
    testWidgets('Join group -> joins and opens the chat', (tester) async {
      await tester.pumpWidget(_app(const JoinGroupByLinkScreen(token: 'ABCdef234')));
      await tester.pump();
      expect(find.text('Family'), findsOneWidget);
      expect(find.byKey(const ValueKey('join_link_line')), findsOneWidget);
      expect(find.text('Join group'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('join_link_join')));
      await tester.pump();
      await tester.pump();
      expect(api.log, contains('join:ABCdef234'));
      expect(opened, ['g1']);
    });

    testWidgets('Approve ON -> "Ask to join" -> "Requested ✓"', (tester) async {
      api.preview = {...api.preview, 'approve': true};
      api.joinStatus = 'requested';
      await tester.pumpWidget(_app(const JoinGroupByLinkScreen(token: 'ABCdef234')));
      await tester.pump();
      expect(find.text('Ask to join'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('join_link_join')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('join_link_requested')), findsOneWidget);
      expect(find.textContaining('An admin must say yes'), findsOneWidget);
      expect(opened, isEmpty);
    });

    testWidgets('already a member -> "Open group"', (tester) async {
      api.preview = {...api.preview, 'status': 'member'};
      await tester.pumpWidget(_app(const JoinGroupByLinkScreen(token: 'ABCdef234')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('join_link_open')));
      await tester.pump();
      expect(opened, ['g1']);
    });

    testWidgets('signed out -> the screen says so', (tester) async {
      GroupInviteService.instance = null;
      await tester.pumpWidget(_app(const JoinGroupByLinkScreen(token: 'ABCdef234')));
      await tester.pump();
      expect(find.byKey(const ValueKey('join_link_error')), findsOneWidget);
    });

    testWidgets('admin link page: link, copy, share, reset (L1/L2)',
        (tester) async {
      await tester.pumpWidget(_app(GroupInviteLinkScreen(group: _group())));
      await tester.pump();
      expect(find.byKey(const ValueKey('link_box')), findsOneWidget);
      expect(find.textContaining('ABCdef234'), findsWidgets);
      for (final k in ['link_copy', 'link_share', 'link_reset']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      await tester.tap(find.byKey(const ValueKey('link_reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('link_reset_yes')));
      await tester.pump();
      await tester.pump();
      expect(api.log.last, 'token:g1:approve=false:reset=true');
      expect(find.textContaining('NEWtoken23'), findsWidgets);
    });

    testWidgets('Nearby-only group: no link, use QR (L5)', (tester) async {
      await tester.pumpWidget(
          _app(GroupInviteLinkScreen(group: _group(origin: 'nearby', cardVersion: 1))));
      await tester.pump();
      expect(find.byKey(const ValueKey('link_nearby_only')), findsOneWidget);
      expect(find.byKey(const ValueKey('link_box')), findsNothing);
      expect(api.log, isEmpty);
    });
  });

  group('in the chat (with Bundle 202 bubbles)', () {
    testWidgets('a link message -> card in the group bubble; tap -> Join',
        (tester) async {
      const m = GroupMessage(
          id: 'm1',
          groupId: 'g2',
          senderId: 'sara',
          body: 'Join us linkup://join/ABCdef234',
          createdAt: '2026-11-04T16:41:00Z',
          serverSeq: 3);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: GroupMessageBubble(
                      message: m,
                      isMine: false,
                      files: FakeFilesRepository(),
                      senderName: 'Sara',
                      avatarColumn: false)))));
      await tester.pump();
      final card = find.byKey(const ValueKey('invite_card_ABCdef234'));
      expect(card, findsOneWidget);
      expect(find.text('Group invite · 4 members'), findsOneWidget);
      // A text message: normal padding, no 202 picture grid.
      expect(BubbleMedia.of(m.attachments, hasCaption: true).tight, isFalse);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(JoinGroupByLinkScreen), findsOneWidget);
    });

    test('both bubbles carry the card; the 202 grid stays', () {
      for (final p in [
        'lib/features/messaging/presentation/widgets/message_bubble.dart',
        'lib/features/groups/presentation/widgets/group_message_bubble.dart',
      ]) {
        final s = File(p).readAsStringSync();
        expect(s, contains('GroupInviteCard('), reason: p);
        expect(s, contains('...media.build('), reason: p);
        expect(s, contains('BubbleMedia.padding('), reason: p);
      }
    });
  });

  group('opening links from other apps', () {
    test('Android: linkup://join intent + channel', () {
      final man = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(man, contains('android:scheme="linkup"'));
      expect(man, contains('android:host="join"'));
      final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt')
          .readAsStringSync();
      expect(kt, contains('"locallink/join_link"'));
    });

    test('app shell sets and clears the open-group hook', () {
      final s = File('lib/app/local_link_app.dart').readAsStringSync();
      expect(s, contains('GroupInviteService.openGroup = _openGroupChat;'));
      expect(s, contains('if (GroupInviteService.openGroup == _openGroupChat)'));
      expect(s, contains('_checkJoinLink()'));
    });
  });
}
