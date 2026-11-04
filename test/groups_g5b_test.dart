// ignore_for_file: unused_element_parameter, prefer_const_constructors
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/chat_preview.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/group_event.dart';
import 'package:locallink/core/models/group_extras.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/data/group_extras_book.dart';
import 'package:locallink/features/groups/data/group_receipts.dart';
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/screens/group_chat_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_extras_widgets.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';

import 'support/phase5_fakes.dart';

// Bundle G5b (mock G5b P + Q): pin a message, polls.

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


class _Store extends FakeStore {
  final Map<String, String> settings = {};
  final Map<String, List<Map<String, dynamic>>> members = {};

  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
  @override
  Future<List<Map<String, dynamic>>> groupMembers(String groupId) async =>
      members[groupId] ?? const [];
  @override
  Future<GroupMessage?> groupMessageById(String id) async {
    for (final rows in groupMessageRows.values) {
      for (final r in rows) {
        if (r['id']?.toString() == id) return GroupMessage.fromJson(r);
      }
    }
    return null;
  }
}

Future<void> _pump() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

String _iso(DateTime d) => d.toUtc().toIso8601String();

void main() {
  setUp(() {
    GroupExtrasBook.instance = GroupExtrasBook();
    GroupExtrasHub.debugReset();
  });

  group('207 K one answer, 3-minute change', () {
    final t0 = DateTime.utc(2026, 11, 5, 10);
    String at(Duration d) => _iso(t0.add(d));

    test('a change at 2:59 counts, at 3:01 is ignored (every phone)', () async {
      final book = GroupExtrasBook();
      expect(await book.applyVote(GroupVote(
          pollId: 'p', choices: [0], at: at(Duration.zero), voter: 'ali', first: at(Duration.zero))), isTrue);
      expect(await book.applyVote(GroupVote(
          pollId: 'p', choices: [1], at: at(const Duration(minutes: 2, seconds: 59)),
          voter: 'ali', first: at(Duration.zero))), isTrue);
      expect(await book.applyVote(GroupVote(
          pollId: 'p', choices: [0], at: at(const Duration(minutes: 3, seconds: 1)),
          voter: 'ali', first: at(Duration.zero))), isFalse);
      expect(book.votesOf('p')['ali']!.choices, [1]);
      // a note that claims a later first time: the earliest seen is kept
      expect(await book.applyVote(GroupVote(
          pollId: 'p', choices: [0], at: at(const Duration(minutes: 5)),
          voter: 'ali', first: at(const Duration(minutes: 4)))), isFalse);
      expect(book.votesOf('p')['ali']!.first, at(Duration.zero));
    });

    test('an older app (no f) / a many-answers poll: no time rule', () async {
      final book = GroupExtrasBook();
      await book.applyVote(GroupVote(pollId: 'p', choices: [0], at: at(Duration.zero), voter: 'sara'));
      expect(await book.applyVote(GroupVote(
          pollId: 'p', choices: [0, 1], at: at(const Duration(hours: 2)), voter: 'sara')), isTrue);
    });

    test('f goes on the wire and back; old notes parse', () {
      final v = GroupVote(pollId: 'p', choices: [1], at: at(Duration.zero), first: at(Duration.zero));
      expect(v.encode(), contains('"f"'));
      expect(GroupVote.parse(v.encode())!.first, at(Duration.zero));
      final old = GroupVote(pollId: 'p', choices: [1], at: at(Duration.zero));
      expect(old.encode(), isNot(contains('"f"')));
      expect(GroupVote.parse(old.encode())!.first, '');
    });

    test('change time left (countdown) and final', () {
      final poll = GroupPoll.build('Q', ['A', 'B'])!;
      final t = GroupPollTally(poll, {
        'me': GroupVote(pollId: 'p', choices: [0], at: at(Duration.zero), first: at(Duration.zero)),
      });
      expect(t.changeLeft('me', t0.add(const Duration(seconds: 19))), const Duration(minutes: 2, seconds: 41));
      expect(t.changeLeft('me', t0.add(const Duration(minutes: 4)))! <= Duration.zero, isTrue);
      expect(t.changeLeft('ali', t0), isNull);
      final many = GroupPoll.build('Q', ['A', 'B'], multi: true)!;
      expect(GroupPollTally(many, {
        'me': GroupVote(pollId: 'p', choices: [0], at: at(Duration.zero), first: at(Duration.zero)),
      }).changeLeft('me', t0), isNull);
    });

    testWidgets('poll card: countdown, then "Your vote is final"; radio; N of M voted', (tester) async {
      final poll = GroupPoll.build('Tomorrow?', ['Office', 'Home'])!;
      final t = GroupPollTally(poll, {
        'me': GroupVote(pollId: 'p', choices: [0], at: at(Duration.zero), first: at(Duration.zero)),
        'sara': GroupVote(pollId: 'p', choices: [1], at: at(Duration.zero)),
      });
      var now = t0.add(const Duration(seconds: 19));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: GroupPollView(
                  poll: poll, tally: t, self: 'me', nameOf: (id) => id, members: 3, now: () => now))));
      expect(find.text('You can change your vote for 2:41'), findsOneWidget);
      expect(find.text('2 of 3 voted'), findsOneWidget);
      expect(find.byKey(const ValueKey('poll_opt_on_0')), findsOneWidget);
      now = t0.add(const Duration(minutes: 3, seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Your vote is final'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('dark mode: counts and track are readable', (tester) async {
      final poll = GroupPoll.build('Q', ['A', 'B'])!;
      final t = GroupPollTally(poll, {});
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(body: GroupPollView(poll: poll, tally: t, self: 'me', nameOf: (id) => id))));
      final count = tester.widget<Text>(find.byKey(const ValueKey('poll_count_0')));
      expect(count.style!.color, isNot(const Color(0xFF44454C)));
      final track = tester.widget<Container>(find.byKey(const ValueKey('poll_track_0')));
      expect(track.color, const Color(0xFF3A3D48));
    });
  });

  group('models', () {
    test('pin note: encode / parse / unpin / bad text', () {
      final at = DateTime.utc(2026, 11, 4, 16);
      final n = GroupPinNote(
          messageId: 'm1', at: _iso(at), until: _iso(at.add(const Duration(days: 7))));
      expect(n.encode(), startsWith('llpin:v1:'));
      final back = GroupPinNote.parse(n.encode(), by: 'ali')!;
      expect(back.messageId, 'm1');
      expect(back.by, 'ali');
      expect(back.activeAt(at.add(const Duration(days: 6))), isTrue);
      expect(back.activeAt(at.add(const Duration(days: 8))), isFalse);
      final un = GroupPinNote.parse(GroupPinNote(messageId: '', at: _iso(at)).encode())!;
      expect(un.isUnpin, isTrue);
      expect(un.activeAt(at), isFalse);
      expect(GroupPinNote.parse('llpin:v1:{bad'), isNull);
      expect(GroupPinNote.parse('llpin:v1:{"m":"x","at":"2026-11-04T00:00:00Z"}'), isNull,
          reason: 'a pin needs an end');
    });

    test('pin: newest note wins; ties pick the same on every phone', () {
      final a = GroupPinNote(messageId: 'm1', at: '2026-11-04T10:00:00Z', until: 'x');
      final b = GroupPinNote(messageId: 'm2', at: '2026-11-04T11:00:00Z', until: 'x');
      expect(a.olderThan(b), isTrue);
      expect(b.olderThan(a), isFalse);
      final c = GroupPinNote(messageId: 'm3', at: '2026-11-04T11:00:00Z', until: 'x');
      expect(b.olderThan(c) != c.olderThan(b), isTrue);
    });

    test('pin: lengths + time left', () {
      expect(GroupPinNote.lengths.map(GroupPinNote.lengthLabel).toList(),
          ['24 hours', '7 days', '30 days']);
      final now = DateTime.utc(2026, 11, 4, 12);
      expect(GroupPinNote.leftLabel(now.add(const Duration(days: 7)), now), '7 days');
      expect(GroupPinNote.leftLabel(now.add(const Duration(hours: 30)), now), '2 days');
      expect(GroupPinNote.leftLabel(now.add(const Duration(hours: 24)), now), '1 day');
      expect(GroupPinNote.leftLabel(now.add(const Duration(hours: 5)), now), '5 h');
      expect(GroupPinNote.leftLabel(now.add(const Duration(minutes: 20)), now), '20 min');
    });

    test('poll: build checks (2-12 options, no doubles, question)', () {
      expect(GroupPoll.build('Q?', ['A']), isNull);
      expect(GroupPoll.build('', ['A', 'B']), isNull);
      expect(GroupPoll.build('Q?', ['A', ' a ', '']), isNull, reason: 'same option twice');
      expect(GroupPoll.build('Q?', [for (var i = 0; i < 13; i++) 'o$i']), isNull);
      final p = GroupPoll.build(' Where? ', ['Biryani', 'Pizza', ''], multi: true)!;
      expect(p.question, 'Where?');
      expect(p.options, ['Biryani', 'Pizza']);
      final back = GroupPoll.parse(p.encode())!;
      expect(back.multi, isTrue);
      expect(back.options, ['Biryani', 'Pizza']);
      expect(back.preview, '📊 Poll: Where?');
    });

    test('poll message reads as "📊 Poll: …" (text, Chats row)', () {
      final body = GroupPoll.build('Lunch?', ['Yes', 'No'])!.encode();
      final m = GroupMessage(id: 'p', groupId: 'g', senderId: 'ali', body: body, createdAt: '2026-11-04T00:00:00Z');
      expect(m.text, '📊 Poll: Lunch?');
      expect(m.poll, isNotNull);
      final line = chatPreviewText(
          ChatPreview(
              messageId: 'p', senderId: 'ali', body: body,
              createdAt: DateTime.utc(2026, 11, 4)),
          localDeviceId: 'me', senderName: 'Ali');
      expect(line, 'Ali: 📊 Poll: Lunch?');
    });

    test('vote: parse + tally (one / many / take back)', () {
      final one = GroupPoll.build('Q', ['A', 'B', 'C'])!;
      final v = GroupVote.parse(
          GroupVote(pollId: 'p', choices: [2, 0], at: '2026-11-04T10:00:00Z').encode(),
          voter: 'ali')!;
      expect(v.choices, [0, 2]);
      var t = GroupPollTally(one, {'ali': v});
      expect(t.picksOf('ali'), [0], reason: 'select one keeps the first');
      expect(t.voters, 1);
      expect(t.tap('me', 1), [1]);
      t = GroupPollTally(one, {
        'ali': v,
        'me': GroupVote(pollId: 'p', choices: [1], at: '2026-11-04T10:01:00Z'),
        'sara': GroupVote(pollId: 'p', choices: [0], at: '2026-11-04T09:00:00Z'),
        'bilal': GroupVote(pollId: 'p', choices: [9], at: '2026-11-04T09:00:00Z'),
      });
      expect(t.voters, 3, reason: 'out of range does not count');
      expect(t.votersOf(0), ['sara', 'ali'], reason: 'oldest vote first');
      expect(t.shareOf(0), closeTo(2 / 3, .001));
      expect(t.tap('me', 1), isEmpty, reason: 'tap again = take back');
      expect(t.tap('me', 2), [2], reason: 'select one moves the vote');
      final many = GroupPoll.build('Q', ['A', 'B', 'C'], multi: true)!;
      final t2 = GroupPollTally(many, {'me': GroupVote(pollId: 'p', choices: [0], at: 'x')});
      expect(t2.tap('me', 2), [0, 2]);
    });

    test('"Ali pinned a message" line, never unread', () {
      final e = GroupEvent.parse(const GroupEvent(kind: 'pin', by: 'ali', names: {'ali': 'Ali'}).encode())!;
      expect(e.lines('me'), ['Ali pinned a message']);
      expect(GroupEvent.parse(const GroupEvent(kind: 'pin', by: 'me').encode())!.lines('me'),
          ['You pinned a message']);
      expect(e.countsAsUnread('me'), isFalse);
    });
  });

  group('book', () {
    test('pin: newest wins, kept in settings, read back', () async {
      final saved = <String, String>{};
      final book = GroupExtrasBook()
        ..read = ((k) async => saved[k])
        ..write = ((k, v) async => saved[k] = v);
      final now = DateTime.now().toUtc();
      final newer = GroupPinNote(messageId: 'm2', at: _iso(now), until: _iso(now.add(const Duration(days: 1))), by: 'ali');
      final older = GroupPinNote(messageId: 'm1', at: _iso(now.subtract(const Duration(minutes: 1))), until: _iso(now.add(const Duration(days: 1))), by: 'ali');
      expect(await book.applyPin('g1', newer), isTrue);
      expect(await book.applyPin('g1', older), isFalse);
      expect(book.activePin('g1')!.messageId, 'm2');
      final again = GroupExtrasBook()..read = ((k) async => saved[k]);
      await again.loadPin('g1');
      expect(again.activePin('g1')!.messageId, 'm2');
      expect(await book.applyPin('g1', GroupPinNote(messageId: '', at: _iso(now.add(const Duration(seconds: 1))), by: 'ali')), isTrue);
      expect(book.activePin('g1'), isNull);
    });

    test('votes: per voter the newest note wins; kept in settings', () async {
      final saved = <String, String>{};
      final book = GroupExtrasBook()
        ..read = ((k) async => saved[k])
        ..write = ((k, v) async => saved[k] = v);
      expect(await book.applyVote(const GroupVote(pollId: 'p', choices: [1], at: '2026-11-04T10:00:00Z', voter: 'ali')), isTrue);
      expect(await book.applyVote(const GroupVote(pollId: 'p', choices: [0], at: '2026-11-04T09:00:00Z', voter: 'ali')), isFalse);
      expect(await book.applyVote(const GroupVote(pollId: 'p', choices: [], at: '2026-11-04T11:00:00Z', voter: 'sara')), isTrue);
      expect(book.votesOf('p')['ali']!.choices, [1]);
      expect(jsonDecode(saved['group_poll_p']!)['ali']['c'], [1]);
      final again = GroupExtrasBook()..read = ((k) async => saved[k]);
      await again.loadPolls(['p']);
      expect(again.tally('p', GroupPoll.build('Q', ['A', 'B'])!).voters, 1);
    });
  });

  group('service', () {
    late _Store store;
    late FakeSocket socket;
    late GroupMessagingService service;

    setUp(() {
      store = _Store();
      socket = FakeSocket();
      store.groupsById['g1'] = <String, dynamic>{
        'id': 'g1',
        'name': 'Office',
        'owner_id': 'self-device',
        'created_at': '2026-01-01T00:00:00Z',
      };
      store.members['g1'] = [
        {'device_id': 'self-device', 'role': 'owner'},
        {'device_id': 'ali', 'role': 'admin'},
        {'device_id': 'sara', 'role': 'member'},
      ];
      service = GroupMessagingService(
          store, LocalLinkApi(store, socket), socket, FakeFilesRepository());
      service.start();
    });

    tearDown(() async {
      GroupReceiptHub.reset();
      await service.dispose();
      await socket.shutdown();
    });

    Map<String, dynamic> frame(String id, String sender, String body, {int seq = 5}) => {
          'type': 'group_message',
          'id': id,
          'group_id': 'g1',
          'sender_id': sender,
          'body': body,
          'created_at': _iso(DateTime.now()),
          'server_seq': seq,
        };

    test('an admin\'s pin: bar for everyone + grey line; a member\'s pin is refused', () async {
      final now = DateTime.now().toUtc();
      final pin = GroupPinNote(messageId: 'm1', at: _iso(now), until: _iso(now.add(const Duration(days: 7))));
      socket.emitFrame(frame('n1', 'sara', pin.encode()));
      await _pump();
      expect(GroupExtrasBook.instance.activePin('g1'), isNull);
      expect(await store.groupMessages('g1'), isEmpty, reason: 'never a bubble');
      socket.emitFrame(frame('n2', 'ali', pin.encode()));
      await _pump();
      expect(GroupExtrasBook.instance.activePin('g1')!.messageId, 'm1');
      expect(GroupExtrasBook.instance.activePin('g1')!.by, 'ali');
      final rows = await store.groupMessages('g1');
      expect(rows, hasLength(1));
      expect(GroupEvent.parse(rows.single['body'].toString())!.kind, 'pin');
      expect(store.settings.keys, contains('group_pin_g1'));
      // unpin from the admin: bar gone, no new line
      socket.emitFrame(frame('n3', 'ali',
          GroupPinNote(messageId: '', at: _iso(now.add(const Duration(seconds: 2)))).encode()));
      await _pump();
      expect(GroupExtrasBook.instance.activePin('g1'), isNull);
      expect(await store.groupMessages('g1'), hasLength(1));
    });

    test('I pin (owner): line + note in the outbox; the hub does the same', () async {
      expect(await GroupExtrasHub.pin!('g1', 'm7', const Duration(days: 7)), isTrue);
      final note = store.groupOutboxItems.single;
      expect(note['body'].toString(), startsWith('llpin:v1:'));
      expect(GroupExtrasBook.instance.activePin('g1')!.messageId, 'm7');
      final rows = await store.groupMessages('g1');
      expect(rows.single['id'], note['id'], reason: 'line has the note id (ack keeps it)');
      expect(await GroupExtrasHub.unpin!('g1'), isTrue);
      expect(GroupExtrasBook.instance.activePin('g1'), isNull);
      expect(store.groupOutboxItems, hasLength(2));
    });

    test('a member can\'t pin', () async {
      store.members['g1'] = [
        {'device_id': 'self-device', 'role': 'member'},
      ];
      expect(await service.pinMessage('g1', 'm1', const Duration(days: 1)), isFalse);
      expect(store.groupOutboxItems, isEmpty);
    });

    test('poll goes as a message; votes are notes, newest wins per voter', () async {
      final poll = GroupPoll.build('Lunch?', ['Biryani', 'Pizza'])!;
      expect(await GroupExtrasHub.sendPoll!('g1', poll), isTrue);
      final sent = (await store.groupMessages('g1')).single;
      expect(GroupPoll.isPoll(sent['body'].toString()), isTrue);
      final pid = sent['id'].toString();
      final oldDelay = GroupMessagingService.voteDelay;
      GroupMessagingService.voteDelay = Duration.zero;
      addTearDown(() => GroupMessagingService.voteDelay = oldDelay);
      expect(await GroupExtrasHub.vote!('g1', pid, [1]), isTrue);
      expect(store.groupOutboxItems.last['body'].toString(), startsWith('llvote:v1:'));
      socket.emitFrame(frame('v1', 'sara',
          GroupVote(pollId: pid, choices: [0], at: _iso(DateTime.now())).encode()));
      await _pump();
      socket.emitFrame(frame('v0', 'sara',
          const GroupVote(pollId: 'x', choices: [1], at: '2020-01-01T00:00:00Z').encode()));
      await _pump();
      final t = GroupExtrasBook.instance.tally(pid, poll);
      expect(t.picksOf('self-device'), [1]);
      expect(t.picksOf('sara'), [0]);
      expect((await store.groupMessages('g1')).length, 1, reason: 'votes are never bubbles');
    });

    test('207 K5: 10 fast taps -> 1 vote note (the last one)', () async {
      final poll = GroupPoll.build('Lunch?', ['Biryani', 'Pizza'])!;
      await GroupExtrasHub.sendPoll!('g1', poll);
      final pid = (await store.groupMessages('g1')).single['id'].toString();
      final before = store.groupOutboxItems.length;
      final oldDelay = GroupMessagingService.voteDelay;
      GroupMessagingService.voteDelay = const Duration(milliseconds: 60);
      addTearDown(() => GroupMessagingService.voteDelay = oldDelay);
      for (var i = 0; i < 10; i++) {
        await service.vote('g1', pid, [i % 2]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final notes = store.groupOutboxItems.skip(before).toList();
      expect(notes, hasLength(1));
      final v = GroupVote.parse(notes.single['body'].toString())!;
      expect(v.choices, [1]);
      expect(v.first, isNotEmpty, reason: 'one-answer vote carries the first time');
    });

    test('207 K3: my vote is final 3 minutes after my first vote', () async {
      final poll = GroupPoll.build('Lunch?', ['Biryani', 'Pizza'])!;
      await GroupExtrasHub.sendPoll!('g1', poll);
      final pid = (await store.groupMessages('g1')).single['id'].toString();
      final old = DateTime.now().toUtc().subtract(const Duration(minutes: 4));
      await GroupExtrasBook.instance.applyVote(GroupVote(
          pollId: pid, choices: [0], at: _iso(old), voter: 'self-device', first: _iso(old)));
      GroupMessagingService.voteDelay = Duration.zero;
      addTearDown(() => GroupMessagingService.voteDelay = const Duration(milliseconds: 1500));
      final before = store.groupOutboxItems.length;
      expect(await service.vote('g1', pid, [1]), isFalse);
      expect(store.groupOutboxItems.length, before);
      expect(GroupExtrasBook.instance.tally(pid, poll).picksOf('self-device'), [0]);
    });

    test('Nearby notes are read the same way', () async {
      await service.receiveNearby(GroupMessage(
          id: 'v9', groupId: 'g1', senderId: 'sara',
          body: const GroupVote(pollId: 'pp', choices: [0], at: '2026-11-04T10:00:00Z').encode(),
          createdAt: '2026-11-04T10:00:00Z'));
      expect(GroupExtrasBook.instance.votesOf('pp').keys, ['sara']);
      expect(await store.groupMessages('g1'), isEmpty);
    });
  });

  group('screens', () {
    testWidgets('P2: pin sheet - 7 days picked, Pin returns it', (tester) async {
      Duration? got;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (c) => Scaffold(
                  body: TextButton(
                      onPressed: () async => got = await showPinLengthSheet(c),
                      child: const Text('go'))))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Pin for how long?'), findsOneWidget);
      expect(find.text('24 hours'), findsOneWidget);
      expect(find.text('30 days'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pin_confirm')));
      await tester.pumpAndSettle();
      expect(got, const Duration(days: 7));
    });

    testWidgets('P1/P4: hold sheet shows Pin or Unpin only when asked', (tester) async {
      Future<void> open(PinRow row) async {
        await tester.pumpWidget(MaterialApp(
            key: UniqueKey(),
            home: Builder(
                builder: (c) => Scaffold(
                    body: TextButton(
                        onPressed: () => showMessageActionsSheet(c,
                            mine: false, hasText: true, pinRow: row),
                        child: const Text('go'))))));
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
      }

      await open(PinRow.none);
      expect(find.text('Pin'), findsNothing);
      expect(find.text('Unpin'), findsNothing);
      await open(PinRow.pin);
      expect(find.byKey(const ValueKey('msg_action_pin')), findsOneWidget);
      final pinY = tester.getTopLeft(find.text('Pin')).dy;
      expect(pinY, greaterThan(tester.getTopLeft(find.text('Forward')).dy));
      expect(pinY, lessThan(tester.getTopLeft(find.text('Select')).dy));
      await open(PinRow.unpin);
      expect(find.byKey(const ValueKey('msg_action_unpin')), findsOneWidget);
    });

    testWidgets('Q2: New poll - Send only when valid; add / remove options', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      GroupPoll? got;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (c) => Scaffold(
                  body: TextButton(
                      onPressed: () async => got = await Navigator.of(c).push<GroupPoll>(
                          MaterialPageRoute(builder: (_) => const NewPollScreen())),
                      child: const Text('go'))))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      FilledButton send() => tester.widget<FilledButton>(find.byKey(const ValueKey('poll_send')));
      expect(send().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('poll_question')), 'Where should we eat on Friday?');
      await tester.enterText(find.byKey(const ValueKey('poll_option_0')), 'Biryani House');
      await tester.pump();
      expect(send().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('poll_option_1')), 'Pizza Point');
      await tester.tap(find.byKey(const ValueKey('poll_add_option')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('poll_option_2')), 'Chinese Corner');
      await tester.pump();
      // Bundle 207 (K1): no "many answers" switch; the 3-minute rule note.
      expect(find.byKey(const ValueKey('poll_multi')), findsNothing);
      expect(find.byKey(const ValueKey('poll_rule_note')), findsOneWidget);
      expect(send().onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('poll_send')));
      await tester.pumpAndSettle();
      expect(got!.options, ['Biryani House', 'Pizza Point', 'Chinese Corner']);
      expect(got!.multi, isFalse);
    });

    testWidgets('Q3/Q4: poll view counts, my tick, tap + View votes', (tester) async {
      final poll = GroupPoll.build('Where?', ['Biryani', 'Pizza', 'Chinese'])!;
      final tally = GroupPollTally(poll, {
        'me': const GroupVote(pollId: 'p', choices: [0], at: '2026-11-04T16:45:00Z'),
        'ali': const GroupVote(pollId: 'p', choices: [0], at: '2026-11-04T16:46:00Z'),
        'bilal': const GroupVote(pollId: 'p', choices: [1], at: '2026-11-04T16:48:00Z'),
      });
      final taps = <int>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (c) => GroupPollView(
                        poll: poll,
                        tally: tally,
                        self: 'me',
                        nameOf: (id) => id,
                        onTapOption: taps.add,
                        onViewVotes: () => showPollVotesSheet(c,
                            poll: poll, tally: tally, members: 4, self: 'me', nameOf: (id) => id,
                            memberIds: const ['me', 'ali', 'bilal', 'zara']),
                      )))));
      expect(find.text('POLL · CHOOSE ONE'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('poll_count_0'))).data, '2');
      expect(tester.widget<Text>(find.byKey(const ValueKey('poll_count_2'))).data, '0');
      expect(find.byKey(const ValueKey('poll_opt_on_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('poll_opt_on_1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('poll_opt_1')));
      expect(taps, [1]);
      await tester.tap(find.byKey(const ValueKey('poll_view_votes')));
      await tester.pumpAndSettle();
      expect(find.text('Where? · 3 of 4 voted'), findsOneWidget);
      expect(find.text('2 votes · 67%'), findsOneWidget);
      expect(find.text('0 votes · 0%'), findsOneWidget);
      expect(find.byKey(const ValueKey('poll_votes_row_0_me')), findsOneWidget);
      expect(find.byKey(const ValueKey('poll_votes_wait_zara')), findsOneWidget);
      expect(find.text('Not voted yet'), findsOneWidget);
      expect(find.textContaining('You · '), findsNothing);
    });

    testWidgets('chat: pinned bar on top (tap = jump), poll bubble, ⋮ New poll', (tester) async {
      final now = DateTime.now().toUtc();
      await GroupExtrasBook.instance.applyPin(
          'g1',
          GroupPinNote(
              messageId: 'm1', at: _iso(now), until: _iso(now.add(const Duration(days: 7))), by: 'me'));
      final poll = GroupPoll.build('Lunch?', ['Yes', 'No'])!;
      final votes = <String>[];
      GroupExtrasHub.vote = (gid, pid, c) async {
        votes.add('$pid:${c.join(',')}');
        return true;
      };
      await tester.pumpWidget(_host(_FakeGroupMessaging(historyResult: [
        _message(id: 'm1', senderId: 'd2', body: 'Office closed on Friday'),
        _message(id: 'p1', senderId: 'd2', body: poll.encode()),
      ])));
      await _settle(tester);
      await _settle(tester);
      expect(find.byKey(const ValueKey('group_pinned_bar')), findsOneWidget);
      expect(find.text('Sara: Office closed on Friday'), findsOneWidget);
      expect(find.text('7 days'), findsOneWidget);
      expect(find.byKey(const ValueKey('poll_view_p1')), findsOneWidget);
      expect(find.text('Lunch?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('poll_opt_0')));
      await tester.pump();
      expect(votes, ['p1:0']);
      await tester.tap(find.byKey(const ValueKey('group_more_menu')));
      await _anim(tester);
      expect(find.text('New poll'), findsOneWidget);
    });

    testWidgets('chat: owner holds a message -> Pin; the pinned one -> Unpin', (tester) async {
      final now = DateTime.now().toUtc();
      await GroupExtrasBook.instance.applyPin(
          'g1',
          GroupPinNote(
              messageId: 'm1', at: _iso(now), until: _iso(now.add(const Duration(days: 1))), by: 'me'));
      String? unpinned;
      GroupExtrasHub.unpin = (gid) async {
        unpinned = gid;
        return true;
      };
      await tester.pumpWidget(_host(_FakeGroupMessaging(historyResult: [
        _message(id: 'm1', senderId: 'd2', body: 'Pinned one'),
        _message(id: 'm2', senderId: 'd2', body: 'Other one'),
      ]), members: [
        const GroupMember(groupId: 'g1', deviceId: 'me', role: 'owner', joinedAt: '', name: 'You'),
        _member('d2', 'Sara'),
      ]));
      await _settle(tester);
      // a plain member sees no Pin (checked in the service too)
      await tester.longPress(find.text('Other one'));
      await _anim(tester);
      expect(find.byKey(const ValueKey('msg_action_pin')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await _anim(tester);
      await tester.longPress(find.text('Pinned one').last);
      await _anim(tester);
      await tester.tap(find.byKey(const ValueKey('msg_action_unpin')));
      await _anim(tester);
      expect(unpinned, 'g1');
    });
  });
}
