// Bundle 207 (L1 + L2): Chats tab search, 1:1 search like groups.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group_extras.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_search_hit.dart';
import 'package:locallink/core/widgets/chat_search_bar.dart';
import 'package:locallink/features/home/presentation/widgets/chats_search.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';

const me = 'me-1';

Map<String, Object?> direct(String id, String body,
        {String from = 'ali', String to = me, String at = '2026-11-04T09:06:00Z', String? file}) =>
    {
      'id': id,
      'sender_id': from,
      'recipient_id': to,
      'body': body,
      'created_at': at,
      'status': 'delivered',
      'server_seq': 0,
      'file': file,
    };

Map<String, Object?> grp(String id, String body,
        {String from = 'zara', String at = '2026-11-05T00:32:00Z'}) =>
    {
      'id': id,
      'group_id': 'g-office',
      'sender_id': from,
      'body': body,
      'created_at': at,
      'server_seq': 1,
    };

MessageSearchHit hit(String id, String text,
        {bool group = false, String chat = 'ali', String file = '', String from = 'ali'}) =>
    MessageSearchHit(
        messageId: id,
        chatId: chat,
        group: group,
        senderId: from,
        text: text,
        createdAt: DateTime(2026, 11, 4, 9, 6),
        fileName: file);

Message msg(String id, String text, {List<Attachment> atts = const []}) => Message(
    id: id,
    senderId: 'ali',
    recipientId: me,
    body: text,
    createdAt: DateTime(2026, 11, 4),
    status: 'delivered',
    attachments: atts);

void main() {
  group('207 L1 MessageSearchHit', () {
    test('1:1 row: the chat is the other person; mine too', () {
      final h = MessageSearchHit.fromDirect(direct('m1', 'I will reach the office at 10'),
          self: me, query: 'Office')!;
      expect(h.chatId, 'ali');
      expect(h.group, isFalse);
      expect(h.line, 'I will reach the office at 10');
      final mine = MessageSearchHit.fromDirect(
          direct('m2', 'Left my charger in the office', from: me, to: 'sara'),
          self: me,
          query: 'office')!;
      expect(mine.chatId, 'sara');
    });

    test('a match only in the hidden wire part is not a hit', () {
      expect(
          MessageSearchHit.fromDirect(direct('m3', 'llmsg:v1:{"text":"hello","office":1}'),
              self: me, query: 'office'),
          isNull);
    });

    test('deleted messages are left out', () {
      expect(
          MessageSearchHit.fromDirect(direct('m4', 'office'),
              self: me, query: 'office', deleted: (id) => id == 'm4'),
          isNull);
    });

    test('a file name match is a media hit', () {
      final h = MessageSearchHit.fromDirect(direct('m5', '', file: 'office_plan.pdf'),
          self: me, query: 'office')!;
      expect(h.isMedia, isTrue);
      expect(h.line, 'office_plan.pdf');
    });

    test('group: text yes; system notes and locked messages no; polls by question', () {
      final h = MessageSearchHit.fromGroup(grp('g1', 'Tomorrow office or work from home?'),
          query: 'office')!;
      expect(h.group, isTrue);
      expect(h.chatId, 'g-office');
      expect(MessageSearchHit.fromGroup(grp('g2', 'llev:v1:{"k":"office"}'), query: 'office'),
          isNull);
      expect(MessageSearchHit.fromGroup(grp('g3', 'llsk:v1:office'), query: 'office'), isNull);
      final poll = const GroupPoll(question: 'Office party day?', options: ['Fri', 'Sat']).encode();
      expect(MessageSearchHit.fromGroup(grp('g4', poll), query: 'office'), isNotNull);
    });

    test('LocalStore.searchMessages exists (read only, both tables, limit 50)', () {
      final src = File('lib/core/services/local_store.dart').readAsStringSync();
      expect(src, contains('Future<List<MessageSearchHit>> searchMessages(String query,'));
      expect(src, contains('{int limit = 50}'));
      expect(src, contains('FROM group_messages gm'));
      expect(src, contains("ESCAPE '\\'"));
    });
  });

  group('207 L1 Chats tab search view', () {
    late List<String> opened;
    late TextEditingController text;

    Widget view({Duration delay = Duration.zero, ThemeData? theme}) => MaterialApp(
          theme: theme,
          home: Scaffold(
            appBar: ChatsSearchBar(controller: text, onClose: () => opened.add('close')),
            body: ChatsSearchView(
              controller: text,
              delay: delay,
              chats: const [
                ChatsSearchChat(
                    id: 'g-office',
                    group: true,
                    title: 'Office',
                    subtitle: 'sumaira: Home',
                    time: '12:52 AM',
                    avatar: CircleAvatar()),
                ChatsSearchChat(
                    id: 'ali',
                    group: false,
                    title: 'Ali',
                    subtitle: 'Ok',
                    time: 'Mon',
                    avatar: CircleAvatar()),
              ],
              search: (q) async => q.toLowerCase().contains('office')
                  ? [
                      hit('m1', 'I will reach the office at 10', chat: 'sumaira'),
                      hit('g1', 'Tomorrow office or work from home',
                          group: true, chat: 'g-office', from: me),
                      hit('m5', '', file: 'office.pdf', chat: 'ali'),
                    ]
                  : <MessageSearchHit>[],
              titleOf: (h) => h.group ? 'Office' : h.chatId,
              avatarOf: (h) => const CircleAvatar(),
              prefixOf: (h) => h.senderId == me ? 'You: ' : '',
              timeOf: (_) => 'Yesterday',
              onOpenChat: (c) => opened.add('chat:${c.id}'),
              onOpenHit: (h) => opened.add('hit:${h.chatId}:${h.messageId}'),
            ),
          ),
        );

    setUp(() {
      opened = [];
      text = TextEditingController();
    });

    testWidgets('finds the group by name and the messages; tap opens at the message', (t) async {
      await t.pumpWidget(view());
      expect(find.byKey(const ValueKey('chats_search_empty')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('chats_search_field')), 'office');
      await t.pump();
      await t.pump();
      await t.pump();
      expect(find.text('CHATS'), findsOneWidget);
      expect(find.byKey(const ValueKey('chats_search_chat_g-office')), findsOneWidget);
      expect(find.byKey(const ValueKey('chats_search_chat_ali')), findsNothing);
      expect(find.text('MESSAGES · 3'), findsOneWidget);
      expect(find.textContaining('You: Tomorrow', findRichText: true), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('chats_search_hit_m1')));
      await t.tap(find.byKey(const ValueKey('chats_search_chat_g-office')));
      expect(opened, ['hit:sumaira:m1', 'chat:g-office']);
    });

    testWidgets('filters: Chats / Messages / Media', (t) async {
      await t.pumpWidget(view());
      await t.enterText(find.byKey(const ValueKey('chats_search_field')), 'office');
      await t.pump();
      await t.pump();
      await t.pump();
      await t.tap(find.byKey(const ValueKey('chats_search_filter_chats')));
      await t.pump();
      expect(find.byKey(const ValueKey('chats_search_hit_m1')), findsNothing);
      expect(find.byKey(const ValueKey('chats_search_chat_g-office')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('chats_search_filter_messages')));
      await t.pump();
      expect(find.text('MESSAGES · 2'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('chats_search_filter_media')));
      await t.pump();
      expect(find.text('MESSAGES · 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('chats_search_hit_m5')), findsOneWidget);
    });

    testWidgets('no results text; X clears; back closes', (t) async {
      await t.pumpWidget(view(theme: ThemeData.dark()));
      await t.enterText(find.byKey(const ValueKey('chats_search_field')), 'xyz');
      await t.pump();
      await t.pump();
      await t.pump();
      expect(find.text("No results for 'xyz'"), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('chats_search_clear')));
      await t.pump();
      expect(text.text, isEmpty);
      await t.tap(find.byKey(const ValueKey('chats_search_close')));
      expect(opened, ['close']);
    });

    testWidgets('waits 250 ms after typing before searching', (t) async {
      var calls = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatsSearchView(
            controller: text,
            chats: const [],
            search: (q) async {
              calls++;
              return <MessageSearchHit>[];
            },
            titleOf: (_) => '',
            avatarOf: (_) => const SizedBox(),
            prefixOf: (_) => '',
            timeOf: (_) => '',
            onOpenChat: (_) {},
            onOpenHit: (_) {},
          ),
        ),
      ));
      text.text = 'o';
      await t.pump(const Duration(milliseconds: 100));
      text.text = 'of';
      await t.pump(const Duration(milliseconds: 100));
      text.text = 'off';
      await t.pump(const Duration(milliseconds: 300));
      expect(calls, 1);
    });

    test('around(): the word stays visible in one line', () {
      final s = ChatsSearchView.around(
          'This is a very long sentence before we talk about the office plan', 'office');
      expect(s.startsWith('…'), isTrue);
      expect(s, contains('office plan'));
      expect(ChatsSearchView.around('short office', 'office'), 'short office');
    });

    test('home: search icon on the Chats bar, opens at the message', () {
      final src = File('lib/features/home/presentation/screens/home_screen.dart').readAsStringSync();
      expect(src, contains("ValueKey('chats_search_open')"));
      expect(src, contains('widget.store.searchMessages(q)'));
      expect(src, contains('_chatRoute(d, jumpTo: messageId)'));
      expect(src, contains('_groupRoute(g, jumpTo: messageId)'));
      expect(src, contains('if (_index == 0 && _chatsSearching) {'));
    });
  });

  group('207 L2 1:1 search like groups', () {
    test('nothing is hidden; matches newest first incl. file names', () {
      final list = [
        msg('a', 'Are you coming to the office today?'),
        msg('b', 'Yes, a bit late'),
        msg('c', 'I will reach the office at 10'),
        msg('d', 'see file',
            atts: [
              const Attachment(
                  id: 'f',
                  originalName: 'Office.pdf',
                  contentType: 'application/pdf',
                  size: 1,
                  sha256: 'x')
            ]),
      ];
      expect(ChatScreen.searchMatches(list, 'office'), ['d', 'c', 'a']);
      expect(ChatScreen.searchMatches(list, ''), isEmpty);
    });

    testWidgets('shared bar: "2 of 3", up = older, down = newer', (t) async {
      final c = TextEditingController(text: 'office');
      var at = 0;
      final went = <int>[];
      Widget bar() => MaterialApp(
            home: Scaffold(
              appBar: ChatSearchBar(
                keyPrefix: 'chat',
                controller: c,
                count: 3,
                at: at,
                onClose: () {},
                onChanged: (_) {},
                onGo: went.add,
              ),
            ),
          );
      at = 1;
      await t.pumpWidget(bar());
      expect(find.text('2 of 3'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('chat_search_older')));
      await t.tap(find.byKey(const ValueKey('chat_search_newer')));
      expect(went, [2, 0]);
      expect(ChatSearchBar.countText(0, 0), '0 of 0');
    });

    test('chat screen uses the shared bar, marks words, no hiding filter', () {
      final src = File('lib/features/messaging/presentation/screens/chat_screen.dart')
          .readAsStringSync();
      expect(src, contains('ChatSearchBar('));
      expect(src, contains('highlight: searchQuery'));
      expect(src, contains('final visibleMessages = state.messages;'));
      expect(src, contains('widget.jumpToMessageId'));
      final g = File('lib/features/groups/presentation/screens/group_chat_screen.dart')
          .readAsStringSync();
      expect(g, contains('ChatSearchBar('));
      expect(g, contains('widget.jumpToMessageId'));
    });
  });
}
