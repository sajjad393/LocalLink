import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/chat_preview.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/group_mentions.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/features/groups/data/group_mention_book.dart';
import 'package:locallink/features/groups/data/group_receipts.dart';
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';
import 'package:locallink/features/groups/presentation/widgets/group_mention_widgets.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_bubble.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_info_sheet.dart';
import 'package:locallink/features/groups/presentation/widgets/group_media_strip.dart';
import 'package:locallink/features/storage/domain/media_clean_policy.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';
import 'package:locallink/features/messaging/presentation/widgets/pinch_text_zoom.dart';

import 'support/phase5_fakes.dart';

// Bundle G5: receipts per member, Message info, typing, @mentions.

GroupReceipt _r(String id, String who, {DateTime? d, DateTime? r}) =>
    GroupReceipt(messageId: id, deviceId: who, deliveredAt: d ?? r, readAt: r);

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('mentions', () {
    test('picked names become tokens; screens show "@Ali"', () {
      final body = GroupMentions.encode('Please check @Ali and @all',
          {'Ali': 'dev-ali', 'all': GroupMentions.allId});
      expect(body, 'Please check @[Ali](dev-ali) and @[all](all)');
      expect(GroupMentions.plain(body), 'Please check @Ali and @all');
      expect(GroupMentions.ids(body), {'dev-ali', 'all'});
      // an email or a name not picked stays plain text
      expect(GroupMentions.encode('mail a@Ali.com @Sara', {'Ali': 'x'}),
          'mail a@Ali.com @Sara');
    });

    test('longest name first ("Ali Khan" before "Ali")', () {
      final body = GroupMentions.encode(
          '@Ali Khan and @Ali', {'Ali': 'a1', 'Ali Khan': 'a2'});
      expect(body, '@[Ali Khan](a2) and @[Ali](a1)');
    });

    test('@all counts only from an admin', () {
      const body = 'Meeting @[all](all)';
      expect(GroupMentions.mentionsMe(body, 'me'), isFalse);
      expect(GroupMentions.mentionsMe(body, 'me', writerIsAdmin: true), isTrue);
      expect(GroupMentions.mentionsMe('@[Me](me) hi', 'me'), isTrue);
      expect(GroupMentions.mentionsMe('@[Bo](bo) hi', 'me'), isFalse);
    });

    test('the "@" list follows the word at the cursor', () {
      expect(GroupMentions.queryAt('Please check @A', 15), 'A');
      expect(GroupMentions.queryAt('@', 1), '');
      expect(GroupMentions.queryAt('mail a@b', 8), isNull);
      expect(GroupMentions.queryAt('@Ali done', 9), isNull);
      final (text, at) = GroupMentions.insert('Please check @A', 15, 'Ali');
      expect(text, 'Please check @Ali ');
      expect(at, text.length);
    });

    test('Chats preview never shows the token', () {
      final p = ChatPreview(
          messageId: 'm',
          senderId: 'b',
          body: '@[Sajjad](s) can you book?',
          createdAt: DateTime(2026, 11, 4));
      expect(chatPreviewText(p, localDeviceId: 's', senderName: 'Bilal'),
          'Bilal: @Sajjad can you book?');
    });

    testWidgets('bubble text: blue "@Ali" (mock 17)', (tester) async {
      await tester.pumpWidget(_app(const ChatBodyText('Please check @[Ali](a)',
          color: Colors.black, mentions: true)));
      expect(find.byKey(const ValueKey('chat_body_mentions')), findsOneWidget);
      final rich = tester.widget<Text>(find.byKey(const ValueKey('chat_body_mentions')));
      expect(rich.textSpan!.toPlainText(), 'Please check @Ali');
      // 1:1 chats (mentions off) keep the text as it is
      await tester.pumpWidget(_app(
          const ChatBodyText('Please check @[Ali](a)', color: Colors.black)));
      expect(find.text('Please check @[Ali](a)'), findsOneWidget);
    });

    testWidgets('"@" list: members with role + @all for admins (mock 16)',
        (tester) async {
      GroupMentionChoice? picked;
      await tester.pumpWidget(_app(SizedBox(
          width: 360,
          child: GroupMentionList(choices: const [
            GroupMentionChoice(id: 'a', name: 'Ali', sub: 'Admin'),
            GroupMentionChoice(
                id: 'all',
                name: 'all',
                sub: 'Admins only: notify everyone',
                everyone: true),
          ], onPick: (c) => picked = c))));
      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('@all'), findsOneWidget);
      expect(find.text('Admins only: notify everyone'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mention_a')));
      expect(picked?.id, 'a');
    });

    test('blue @ book: add, clear, saved', () async {
      final saved = <String, String>{};
      GroupMentionBook.instance.debugReset();
      await GroupMentionBook.instance
          .load(read: (k) async => saved[k], write: (k, v) async => saved[k] = v);
      GroupMentionBook.instance.add('g1');
      expect(GroupMentionBook.instance.has('g1'), isTrue);
      await _pump();
      expect(saved[GroupMentionBook.key], 'g1');
      GroupMentionBook.instance.clear('g1');
      expect(GroupMentionBook.instance.has('g1'), isFalse);
      GroupMentionBook.instance.debugReset();
    });
  });

  group('ticks + Message info', () {
    final t = DateTime(2026, 11, 4, 21, 41);
    final others = {'ali', 'sara', 'bilal'};

    test('✓ until all got it; grey ✓✓ all got it; blue ✓✓ all read', () {
      expect(groupTickFor(sent: false, others: others), GroupTick.pending);
      expect(groupTickFor(sent: true, others: others), GroupTick.sent);
      final two = {'ali': _r('m', 'ali', d: t), 'sara': _r('m', 'sara', d: t)};
      expect(groupTickFor(sent: true, others: others, receipts: two), GroupTick.sent);
      final all = {...two, 'bilal': _r('m', 'bilal', r: t)};
      expect(groupTickFor(sent: true, others: others, receipts: all),
          GroupTick.delivered);
      final read = {for (final o in others) o: _r('m', o, r: t)};
      expect(groupTickFor(sent: true, others: others, receipts: read), GroupTick.read);
      expect(
          groupTickFor(sent: true, others: others, receipts: read, readsOn: false),
          GroupTick.delivered,
          reason: 'my read receipts off = no blue (same as 1-to-1)');
      // a member who left no longer counts
      expect(groupTickFor(sent: true, others: {'ali'}, receipts: two),
          GroupTick.delivered);
    });

    test('mock 19 lists: Read by 2 of 3, Delivered to 1', () {
      final info = GroupMessageInfo.build(others: {
        'ali': 'Ali',
        'sara': 'Sara',
        'bilal': 'Bilal'
      }, receipts: {
        'ali': _r('m', 'ali', r: t.add(const Duration(minutes: 1))),
        'sara': _r('m', 'sara', r: t.add(const Duration(minutes: 2))),
        'bilal': _r('m', 'bilal', d: t),
      });
      expect(info.total, 3);
      expect(info.read.map((p) => p.name), ['Ali', 'Sara']);
      expect(info.delivered.map((p) => p.name), ['Bilal']);
      expect(info.waiting, isEmpty);
    });

    testWidgets('sheet (mock 19)', (tester) async {
      final info = GroupMessageInfo.build(others: {
        'ali': 'Ali',
        'sara': 'Sara',
        'bilal': 'Bilal'
      }, receipts: {
        'ali': _r('m', 'ali', r: DateTime.now()),
        'sara': _r('m', 'sara', r: DateTime.now()),
        'bilal': _r('m', 'bilal', d: DateTime.now()),
      });
      await tester.pumpWidget(_app(
          GroupMessageInfoBody(preview: const Text('Yes, I will come'), info: info)));
      expect(find.text('Message info'), findsOneWidget);
      expect(find.text('Read by 2 of 3'), findsOneWidget);
      expect(find.text('Delivered to 1'), findsOneWidget);
      expect(find.textContaining('Today, '), findsNWidgets(3));
      expect(
          find.text('Blue ✓✓ in the chat only when all 3 have read it. '
              'People with read receipts off show under Delivered.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('ginfo_waiting')), findsNothing);
    });

    testWidgets('sheet (mock 20): Delivered to 2 of 3 + Waiting', (tester) async {
      final info = GroupMessageInfo.build(others: {
        'ali': 'Ali',
        'sara': 'Sara',
        'bilal': 'Bilal'
      }, receipts: {
        'ali': _r('m', 'ali', d: DateTime.now()),
        'sara': _r('m', 'sara', d: DateTime.now()),
      });
      await tester.pumpWidget(_app(
          GroupMessageInfoBody(preview: const Text('Yes, I will come'), info: info)));
      expect(find.text('Delivered to 2 of 3'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('gets it when Nearby or Online'), findsOneWidget);
      expect(find.text('✓ = sent. ✓✓ only when all members got it.'), findsOneWidget);
      expect(find.byKey(const ValueKey('ginfo_read')), findsNothing);
    });

    testWidgets('not sent yet keeps the old line', (tester) async {
      await tester.pumpWidget(_app(GroupMessageInfoBody(
          preview: const Text('x'),
          info: GroupMessageInfo.build(others: const {'a': 'A'}),
          notSentYet: true)));
      expect(find.text('Not sent yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('ginfo_hint')), findsNothing);
    });

    testWidgets('bubble ticks', (tester) async {
      final m = GroupMessage(
          id: 'm1',
          groupId: 'g',
          senderId: 'me',
          body: 'Yes',
          createdAt: '2026-11-04T16:41:00Z',
          serverSeq: 3);
      for (final (tick, key) in [
        (null, 'group_tick_sent'),
        (GroupTick.sent, 'group_tick_sent'),
        (GroupTick.delivered, 'group_tick_delivered'),
        (GroupTick.read, 'group_tick_read'),
      ]) {
        await tester.pumpWidget(_app(GroupMessageBubble(
            message: m,
            isMine: true,
            files: FakeFilesRepository(),
            senderName: 'You',
            avatarColumn: false,
            tick: tick)));
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: '$tick');
      }
    });
  });

  group('typing', () {
    test('words (mock 15 / 15b)', () {
      expect(groupTypingText(['Sara']), 'Sara is typing…');
      expect(groupTypingText(['Sara', 'Bilal']), 'Sara and Bilal are typing…');
      expect(groupTypingText(['A', 'B', 'C']), '3 people are typing…');
      expect(groupTypingText(const []), '');
    });

    test('a note lasts 6 s; "stopped" ends it', () async {
      var now = DateTime(2026, 11, 4, 10);
      final book = GroupTypingBook(clock: () => now);
      final changes = <String>[];
      final sub = book.changes.listen(changes.add);
      book.note('g', 'sara', true);
      book.note('g', 'bilal', true);
      expect(book.typing('g'), ['sara', 'bilal']);
      book.note('g', 'bilal', false);
      expect(book.typing('g'), ['sara']);
      now = now.add(const Duration(seconds: 7));
      expect(book.typing('g'), isEmpty);
      await _pump();
      expect(changes, isNotEmpty);
      await sub.cancel();
      book.dispose();
    });

    test('sender: one "on" per 3 s, "off" when cleared', () {
      var now = DateTime(2026, 11, 4, 10);
      final sent = <bool>[];
      final s = GroupTypingSender(sent.add, clock: () => now);
      s.changed('H');
      s.changed('He');
      expect(sent, [true]);
      now = now.add(const Duration(seconds: 3));
      s.changed('Hel');
      expect(sent, [true, true]);
      s.changed('');
      expect(sent, [true, true, false]);
      s.stop();
      expect(sent, [true, true, false], reason: 'no second off');
      s.dispose();
    });
  });

  group('Chats row (mock 10)', () {
    testWidgets('blue typing line + blue @', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MessengerConversationTile(
                  title: 'Office',
                  subtitle: 'Sara is typing…',
                  subtitleBlue: true,
                  mentioned: true,
                  unreadCount: 4))));
      expect(find.byKey(const ValueKey('row_mention_at')), findsOneWidget);
      expect(find.text('@'), findsOneWidget);
      final line = tester.widget<Text>(find.text('Sara is typing…'));
      expect(line.style?.fontWeight, FontWeight.w500);
    });
  });

  group('service (server road)', () {
    late FakeStore store;
    late FakeSocket socket;
    late GroupMessagingService service;

    setUp(() {
      ReadReceiptsSetting.instance.debugSet(true);
      store = FakeStore();
      socket = FakeSocket();
      store.groupsById['g1'] = <String, dynamic>{
        'id': 'g1',
        'name': 'Office',
        'owner_id': 'ali',
        'created_at': '2026-01-01T00:00:00Z',
      };
      service = GroupMessagingService(
          store, LocalLinkApi(store, socket), socket, FakeFilesRepository());
      service.start();
    });

    tearDown(() async {
      GroupReceiptHub.reset();
      ReadReceiptsSetting.instance.debugSet(true);
      await service.dispose();
      await socket.shutdown();
    });

    test('a member\'s receipt is kept and shown', () async {
      final changed = <String>[];
      final sub = service.receiptChanges.listen(changed.add);
      socket.emitFrame({
        'type': 'group_receipt',
        'group_id': 'g1',
        'id': 'm1',
        'device_id': 'ali',
        'status': 'read',
        'created_at': '2026-11-04T16:42:00Z',
      });
      await _pump();
      final rows = groupReceiptsByMessage(await store.groupReceipts('g1'));
      expect(rows['m1']!['ali']!.readAt, isNotNull);
      expect(rows['m1']!['ali']!.deliveredAt, isNotNull);
      expect(changed, ['g1']);
      // hub gives the chat screen the same rows
      final viaHub = await GroupReceiptHub.load!('g1');
      expect(viaHub['m1']!.keys, ['ali']);
      await sub.cancel();
    });

    test('a new message from a member: "got it" goes back', () async {
      await socket.goOnline();
      await _pump();
      socket.sentFrames.clear();
      socket.emitFrame({
        'type': 'group_message',
        'id': 'm9',
        'group_id': 'g1',
        'sender_id': 'ali',
        'body': 'Lunch?',
        'created_at': '2026-11-04T16:40:00Z',
        'server_seq': 7,
      });
      await _pump();
      final frame = socket.sentFrames.singleWhere((f) => f['type'] == 'group_receipt');
      expect(frame['status'], 'delivered');
      expect(frame['message_ids'], ['m9']);
      expect(frame['durable'], isFalse);
    });

    test('open chat = "read" for server messages; switch off = none', () async {
      store.groupMessageRows['g1'] = [
        {'id': 'a1', 'group_id': 'g1', 'sender_id': 'ali', 'body': 'Hi', 'created_at': '2026-11-04T16:40:00Z', 'server_seq': 1},
        {'id': 'me1', 'group_id': 'g1', 'sender_id': 'self-device', 'body': 'Yo', 'created_at': '2026-11-04T16:41:00Z', 'server_seq': 2},
      ];
      // offline: nothing sent, nothing marked (it waits for the next open)
      await service.markRead('g1');
      expect(socket.sentFrames, isEmpty);
      expect(await store.groupReceipts('g1'), isEmpty);
      await socket.goOnline();
      await _pump();
      socket.sentFrames.clear();
      await service.markRead('g1');
      final frame = socket.sentFrames.single;
      expect(frame['type'], 'group_receipt');
      expect(frame['status'], 'read');
      expect(frame['message_ids'], ['a1']);
      // only once
      await service.markRead('g1');
      expect(socket.sentFrames, hasLength(1));
      // switch off: a new message is marked but no "read" goes out
      ReadReceiptsSetting.instance.debugSet(false);
      store.groupMessageRows['g1']!.add({'id': 'a2', 'group_id': 'g1', 'sender_id': 'ali', 'body': 'x', 'created_at': '2026-11-04T16:45:00Z', 'server_seq': 3});
      await service.markRead('g1');
      expect(socket.sentFrames, hasLength(1));
      final rows = groupReceiptsByMessage(await store.groupReceipts('g1'));
      expect(rows['a2']!['self-device']!.readAt, isNotNull);
    });

    test('typing: sent on the server road; others shown, 6 s', () async {
      service.sendTyping('g1', true);
      expect(socket.sentFrames, isEmpty, reason: 'offline = nothing');
      await socket.goOnline();
      service.sendTyping('g1', true);
      expect(socket.sentFrames.last['type'], 'group_typing');
      expect(socket.sentFrames.last['enabled'], isTrue);
      socket.emitFrame({'type': 'group_typing', 'group_id': 'g1', 'sender_id': 'sara', 'enabled': true});
      await _pump();
      expect(GroupReceiptHub.typing!('g1'), ['sara']);
      // her message ends "typing"
      socket.emitFrame({
        'type': 'group_message', 'id': 's1', 'group_id': 'g1', 'sender_id': 'sara',
        'body': 'Me too', 'created_at': '2026-11-04T16:46:00Z', 'server_seq': 9,
      });
      await _pump();
      expect(GroupReceiptHub.typing!('g1'), isEmpty);
    });
  });

  group('media strip (mock d1)', () {
    MediaFile f(int i, MediaKind kind, {String chat = 'g1', bool group = true}) =>
        MediaFile(
            fileId: 'f$i',
            messageId: 'm$i',
            chatId: chat,
            isGroup: group,
            mine: false,
            sent: true,
            kind: kind,
            name: 'n$i',
            contentType: '',
            rowPath: '',
            diskPath: null,
            bytes: 10,
            messageAt: DateTime(2026, 11, 1).add(Duration(minutes: i)));

    testWidgets('label with count, 3 newest pictures, "+21"', (tester) async {
      final files = [
        for (var i = 0; i < 21; i++) f(i, MediaKind.document),
        f(30, MediaKind.photo),
        f(31, MediaKind.video),
        f(32, MediaKind.photo),
        f(40, MediaKind.photo, chat: 'other'),
        f(41, MediaKind.photo, chat: 'g1', group: false),
      ];
      List<MediaFile>? all;
      await tester.pumpWidget(_app(SizedBox(
          width: 400,
          child: GroupMediaStrip(
              groupId: 'g1',
              load: () async => files,
              thumb: (_) async => null,
              onOpenAll: (list) => all = list,
              onOpenFile: (_, __) {}))));
      await tester.pump();
      await tester.pump();
      expect(find.text('MEDIA, LINKS AND DOCS · 24'), findsOneWidget);
      expect(find.byKey(const ValueKey('group_media_f32')), findsOneWidget);
      expect(find.byKey(const ValueKey('group_media_f31')), findsOneWidget);
      expect(find.byKey(const ValueKey('group_media_f30')), findsOneWidget);
      expect(find.text('+21'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group_media_more')));
      expect(all, hasLength(24));
    });

    testWidgets('nothing in the group = no strip', (tester) async {
      await tester.pumpWidget(_app(GroupMediaStrip(
          groupId: 'g1',
          load: () async => const <MediaFile>[],
          onOpenAll: (_) {},
          onOpenFile: (_, __) {})));
      await tester.pump();
      expect(find.byKey(const ValueKey('group_media_strip')), findsNothing);
    });
  });

  test('source: chat screen uses the new parts', () {
    final s = File('lib/features/groups/presentation/screens/group_chat_screen.dart')
        .readAsStringSync();
    expect(s, contains('showGroupMessageInfoSheet('));
    expect(s, contains('GroupMentions.encode('));
    expect(s, contains("ValueKey('group_bar_typing')"));
    expect(s, contains('GroupTypingBubble('));
    expect(s, contains('tick: _tickFor(message)'));
    expect(s, contains("Text('Media, links and docs')"));
    final info = File('lib/features/groups/presentation/screens/group_info_screen.dart')
        .readAsStringSync();
    expect(info, contains('GroupMediaStrip('));
    final svc = File('lib/features/groups/data/services/group_messaging_service.dart')
        .readAsStringSync();
    expect(svc, contains("'type': 'group_receipt'"));
    expect(svc, contains("'type': 'group_typing'"));
  });
}
