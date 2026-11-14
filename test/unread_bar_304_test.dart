import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/widgets/unread_bar_304.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' hide CallState;
import 'package:locallink/features/calls/domain/call_gateway.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';

import 'support/phase5_fakes.dart';

/// 304 (H2): "N unread messages" bar (like WhatsApp) in 1:1 and group chats.

class _NoopFiles implements FileTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('not used: $invocation');
}

class _Messaging extends Fake implements MessagingRepositoryContract {}

class _Groups extends Fake implements GroupMessagingRepositoryContract {}

class _Gateway extends Fake implements CallGateway {}

class _Repo implements MessagingRepositoryContract {
  List<Message> rows = [];
  final sent = <String>[];
  @override
  String get localDeviceId => 'me';
  @override
  bool get isServerConnected => true;
  @override
  Future<Device?> peer(String deviceId) async => null;
  @override
  Future<List<Message>> cachedHistory(String peerId) async => rows;
  @override
  Stream<Message> get incoming => const Stream.empty();
  @override
  Future<List<Message>> history(String otherDeviceId) async => rows;
  @override
  Future<Set<String>> chatPeerIds() async => {'d-ali'};
  @override
  Future<void> send(String recipientId, String body, {List<PickedFile> attachments = const []}) async =>
      sent.add(body);
  @override
  Stream<MessageReaction> get reactionIncoming => const Stream.empty();
  @override
  Future<void> react(String recipientId, String messageId, String emoji) async {}
  @override
  Future<List<MessageReaction>> reactions(String messageId) async => const [];
  @override
  Future<bool> resendFailed(String messageId) async => false;
  @override
  Future<void> deleteFailed(String messageId) async {}
  @override
  Stream<String> get deletedMessageIds => const Stream.empty();
  @override
  Future<void> deleteForMe(String messageId) async {}
  @override
  Future<bool> deleteForEveryone(String recipientId, String messageId) async => false;
  @override
  Future<int> clearChat(String peerId, {bool keepRow = true}) async => 0;
}

/// Unread = the friend's messages not marked read yet (like the real store).
class _Store extends FakeStore {
  final List<Message> unread = <Message>[];
  @override
  Future<List<Message>> unreadMessagesForConversation(String otherId) async => List.of(unread);
  @override
  // (all at once: keeps the notification summary refresh off the fake db)
  Future<void> markMessageRead(String id) async => unread.clear();
  @override
  Future<void> removeNotificationStateForMessage(String messageId) async {}
}

const _ali = Device(id: 'd-ali', name: 'Ali', platform: 'android', createdAt: '', lastSeenAt: '');

List<Message> _chat(int total) => [
      for (var i = 0; i < total; i++)
        Message(
            id: 'm$i',
            senderId: i.isEven ? 'd-ali' : 'me',
            recipientId: i.isEven ? 'me' : 'd-ali',
            body: 'message number $i',
            createdAt: DateTime(2026, 11, 15, 10, i),
            status: 'read'),
    ];

String _src(String p) => File(p).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the bar', () {
    test('1 / many', () {
      expect(UnreadBar304.label(1), '1 unread message');
      expect(UnreadBar304.label(5), '5 unread messages');
    });

    for (final dark in [false, true]) {
      testWidgets('full-width soft band + pill in the primary colour (${dark ? 'dark' : 'light'})', (t) async {
        final theme = dark ? LocalLinkTheme.dark() : LocalLinkTheme.light();
        await t.pumpWidget(MaterialApp(
            theme: theme,
            home: const Scaffold(
                body: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Column(children: [UnreadBar304(count: 3, bleed: 12)])))));
        expect(find.text('3 unread messages'), findsOneWidget);
        final text = t.widget<Text>(find.text('3 unread messages'));
        expect(text.style?.color?.toARGB32(), theme.colorScheme.primary.toARGB32());
        expect(text.style?.fontWeight, FontWeight.w600);
        final band = find.byWidgetPredicate((w) =>
            w is ColoredBox && w.color.toARGB32() == theme.colorScheme.primary.withValues(alpha: .10).toARGB32());
        expect(band, findsOneWidget);
        // The band reaches both screen edges (over the list's side padding).
        final r = t.getRect(band);
        expect(r.left, 0);
        expect(r.right, 800);
      });
    }
  });

  group('1:1 chat (real screen)', () {
    late _Store store;
    late LocalLinkNotificationService service;

    setUp(() {
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(const MethodChannel('locallink/notifications'), (_) async => null);
      m.setMockMethodCallHandler(const MethodChannel('locallink/notification_actions'), (_) async => null);
      store = _Store();
      service = LocalLinkNotificationService(
        store: store,
        messaging: _Messaging(),
        groups: _Groups(),
        calls: CallBloc(service: _Gateway(), repository: FakeCallRepository()),
      );
    });

    Future<_Repo> open(WidgetTester t, {required int total, required int unreadFrom, bool dark = false}) async {
      t.view.physicalSize = const Size(360, 780);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repo = _Repo()..rows = _chat(total);
      store.unread
        ..clear()
        ..addAll(repo.rows.where((m) => m.senderId == 'd-ali' && int.parse(m.id.substring(1)) >= unreadFrom));
      final chat = ChatBloc(repository: repo, device: _ali);
      await t.runAsync(chat.load);
      await t.pumpWidget(MaterialApp(
        theme: LocalLinkTheme.light(),
        darkTheme: LocalLinkTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: ChatScreen(controller: chat, files: _NoopFiles(), notifications: service),
      ));
      for (var i = 0; i < 8; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.pump(const Duration(milliseconds: 150));
      }
      return repo;
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    }

    bool onScreen(WidgetTester t, Finder f) {
      if (f.evaluate().isEmpty) return false;
      final r = t.getRect(f);
      return r.bottom > 0 && r.top < 780;
    }

    testWidgets('a few unread: bar above the first unread, right count, opens at the bottom', (t) async {
      await open(t, total: 30, unreadFrom: 24); // m24 m26 m28
      final bar = find.byKey(const ValueKey('unread_bar_304'));
      expect(bar, findsOneWidget);
      expect(find.text('3 unread messages'), findsOneWidget);
      // Right above the first unread message and below the one before it.
      expect(t.getRect(bar).bottom, lessThanOrEqualTo(t.getRect(find.text('message number 24')).top));
      expect(t.getRect(bar).top, greaterThanOrEqualTo(t.getRect(find.text('message number 23')).bottom));
      expect(onScreen(t, find.text('message number 29')), isTrue, reason: 'still at the bottom');
      // Marked read on open (ticks / badges unchanged).
      expect(store.unread, isEmpty);
      await close(t);
    });

    testWidgets('1 unread: "1 unread message"', (t) async {
      await open(t, total: 30, unreadFrom: 28);
      expect(find.text('1 unread message'), findsOneWidget);
      await close(t);
    });

    testWidgets('long unread part: the chat opens at the bar (dark)', (t) async {
      await open(t, total: 40, unreadFrom: 6, dark: true); // 17 unread, longer than the screen
      final bar = find.byKey(const ValueKey('unread_bar_304'));
      expect(find.text('17 unread messages'), findsOneWidget);
      expect(onScreen(t, bar), isTrue);
      expect(t.getRect(bar).top, lessThan(200), reason: 'bar near the top');
      expect(onScreen(t, find.text('message number 39')), isFalse, reason: 'not at the bottom');
      await close(t);
    });

    testWidgets('nothing unread: no bar', (t) async {
      await open(t, total: 30, unreadFrom: 99);
      expect(find.byKey(const ValueKey('unread_bar_304')), findsNothing);
      await close(t);
    });

    testWidgets('sending a message removes the bar; the next open has none', (t) async {
      final repo = await open(t, total: 30, unreadFrom: 24);
      expect(find.byKey(const ValueKey('unread_bar_304')), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'hi');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(repo.sent, contains('hi'));
      expect(find.byKey(const ValueKey('unread_bar_304')), findsNothing);
      await close(t);
      // Leave + open again: everything was read -> no bar.
      final again = _Repo()..rows = _chat(30);
      final chat = ChatBloc(repository: again, device: _ali);
      await t.runAsync(chat.load);
      await t.pumpWidget(MaterialApp(
          theme: LocalLinkTheme.light(),
          home: ChatScreen(controller: chat, files: _NoopFiles(), notifications: service)));
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.byKey(const ValueKey('unread_bar_304')), findsNothing);
      await close(t);
    });
  });

  group('source rules', () {
    test('1:1: unread taken BEFORE marking read; a jump target wins; send clears', () {
      final s = _src('lib/features/messaging/presentation/screens/chat_screen.dart');
      final a = s.indexOf('unreadDirectIds304(widget.controller.device.id)');
      final b = s.indexOf('markDirectConversationRead(widget.controller.device.id)', a);
      expect(a, greaterThan(0));
      expect(b, greaterThan(a));
      // jump (search / notification) returns before the bar scroll
      final init = s.substring(s.indexOf('void _scrollToInitial()'), s.indexOf('void _scrollToBottom('));
      expect(init.indexOf('_jumpTo(jump'), lessThan(init.indexOf('showUnreadBar304')));
      final send = s.substring(s.indexOf('Future<void> _send() async'), s.indexOf('Future<void> _send() async') + 400);
      expect(send, contains('_clearUnread304()'));
      final voice = s.substring(s.indexOf('Future<void> _sendVoiceNote('), s.indexOf('Future<void> _sendVoiceNote(') + 200);
      expect(voice, contains('_clearUnread304()'));
    });

    test('group: same bar, unread taken before marking read, send clears, jump wins', () {
      final s = _src('lib/features/groups/presentation/screens/group_chat_screen.dart');
      final a = s.indexOf('unreadGroupIds304(widget.group.id)');
      expect(a, greaterThan(0));
      expect(s.indexOf('markGroupConversationRead(widget.group.id)', a), greaterThan(a));
      expect(s, contains('UnreadBar304('));
      expect(s.indexOf('if (showDate) MessengerDateDivider(date: parsed),'),
          lessThan(s.indexOf(' UnreadBar304(')), reason: 'bar under the date line');
      final load = s.substring(s.indexOf('Future<void> _load() async'), s.indexOf('Future<void> _loadMemberNames('));
      expect(load.indexOf('_jumpTo(jump)'), lessThan(load.indexOf('showUnreadBar304')));
      final send = s.substring(s.indexOf('Future<void> _send() async'), s.indexOf('Future<void> _send() async') + 500);
      expect(send, contains('_clearUnread304()'));
      final voice = s.substring(s.indexOf('Future<void> _sendVoiceNote('), s.indexOf('Future<void> _sendVoiceNote(') + 200);
      expect(voice, contains('_clearUnread304()'));
    });
  });
}
