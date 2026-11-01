import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';

const _min = 60 * 1000;

FriendHelloDecision _decide({
  String me = 'u-a',
  String peer = 'u-b',
  String peerDevice = 'dev-b',
  String myDevice = 'dev-a',
  bool blocked = false,
  bool chat = false,
  int now = 100 * _min,
  int? lastSent,
  int? tapped,
}) =>
    FriendHelloPolicy.decide(
      myUserId: me,
      peerUserId: peer,
      peerDeviceId: peerDevice,
      myDeviceId: myDevice,
      blocked: blocked,
      chatHasMessages: chat,
      nowMs: now,
      lastSentAtMs: lastSent,
      peerTappedAtMs: tapped,
    );

class _Harness {
  final settings = <String, String>{};
  final sent = <String>[];
  final chats = <String>{};
  final friends = <String>{};
  final blocked = <String>{};
  final opened = <String>[];

  late final FriendHelloService service = FriendHelloService(
    readSetting: (k) async => settings[k],
    writeSetting: (k, v) async => settings[k] = v,
    chatHasMessages: (d) async => chats.contains(d),
    isBlocked: (u, d) async => blocked.contains(u),
    isFriend: (u) async => friends.contains(u),
    send: (d, body) async {
      sent.add('$d|$body');
      chats.add(d);
    },
    myUserId: () => 'u-a',
    myDeviceId: () => 'dev-a',
    delay: Duration.zero,
  );
}

FriendAddedByMe _ev({String user = 'u-b', String device = 'dev-b', bool mutual = false}) =>
    FriendAddedByMe(
        userId: user,
        deviceId: device,
        displayName: 'Bee',
        source: 'nearby',
        mutual: mutual);

void main() {
  setUp(() {
    FriendAddMemory.resetForTest();
    FriendChatOpener.open = null;
    FriendChatOpener.toast = null;
  });

  group('FriendHelloPolicy.decide', () {
    test('new friend with an empty chat -> send', () {
      expect(_decide(), FriendHelloDecision.send);
    });
    test('text is exactly Hello 👋', () {
      expect(kFriendHelloText, 'Hello 👋');
    });
    test('self is skipped (user or device)', () {
      expect(_decide(peer: 'u-a'), FriendHelloDecision.skipSelf);
      expect(_decide(peerDevice: 'dev-a'), FriendHelloDecision.skipSelf);
    });
    test('no device -> skip', () {
      expect(_decide(peerDevice: ' '), FriendHelloDecision.skipNoDevice);
    });
    test('blocked -> skip', () {
      expect(_decide(blocked: true), FriendHelloDecision.skipBlocked);
    });
    test('chat already has a message -> skip (Q5)', () {
      expect(_decide(chat: true), FriendHelloDecision.skipChatHasMessages);
    });
    test('sent within 10 min -> skip, later an empty chat sends again (Q5)', () {
      expect(_decide(lastSent: 95 * _min), FriendHelloDecision.skipRecentlySent);
      expect(_decide(lastSent: 80 * _min), FriendHelloDecision.send);
      expect(_decide(lastSent: 80 * _min, chat: true),
          FriendHelloDecision.skipChatHasMessages);
    });
    test('both tapped Add: only the smaller account id sends (Q7)', () {
      // me=u-a < peer=u-b -> I send
      expect(_decide(tapped: 99 * _min), FriendHelloDecision.send);
      // me=u-c > peer=u-b -> the other phone sends
      expect(_decide(me: 'u-c', tapped: 99 * _min),
          FriendHelloDecision.skipMutualOtherSends);
      // old tap (over 2 min) is not "at the same time"
      expect(_decide(me: 'u-c', tapped: 90 * _min), FriendHelloDecision.send);
    });
  });

  group('incoming Hello + notice', () {
    test('silent only right after the notice and only for the Hello text', () {
      expect(
          FriendHelloPolicy.silenceIncoming(
              body: 'Hello 👋', nowMs: 10 * _min, noticeAtMs: 9 * _min),
          isTrue);
      expect(
          FriendHelloPolicy.silenceIncoming(
              body: 'Hello', nowMs: 10 * _min, noticeAtMs: 9 * _min),
          isFalse);
      expect(
          FriendHelloPolicy.silenceIncoming(
              body: 'Hello 👋', nowMs: 20 * _min, noticeAtMs: 9 * _min),
          isFalse);
      expect(FriendHelloPolicy.silenceIncoming(body: 'Hello 👋', nowMs: 1),
          isFalse);
    });
    test('memory: noteNotice makes the next Hello silent', () {
      var t = 1000000;
      FriendAddMemory.now = () => t;
      expect(FriendAddMemory.silenceIncomingHello('dev-b', 'Hello 👋'), isFalse);
      FriendAddMemory.noteNotice('dev-b');
      t += 5000;
      expect(FriendAddMemory.silenceIncomingHello('dev-b', 'Hello 👋'), isTrue);
      expect(FriendAddMemory.silenceIncomingHello('dev-x', 'Hello 👋'), isFalse);
    });
    test('Hello that arrived first still lets "X added you" show', () {
      expect(
          FriendHelloPolicy.treatAsNewFriend(wasContact: false, nowMs: 5),
          isTrue);
      expect(
          FriendHelloPolicy.treatAsNewFriend(wasContact: true, nowMs: 5),
          isFalse);
      expect(
          FriendHelloPolicy.treatAsNewFriend(
              wasContact: true, nowMs: 3 * _min, autoAddedAtMs: 1 * _min),
          isTrue);
      expect(
          FriendHelloPolicy.treatAsNewFriend(
              wasContact: true, nowMs: 30 * _min, autoAddedAtMs: 1 * _min),
          isFalse);
    });
  });

  group('FriendHelloService', () {
    test('sends exactly one Hello for many copies of the same add', () async {
      final h = _Harness();
      await Future.wait([
        for (var i = 0; i < 12; i++) h.service.addedByMe(_ev()),
      ]);
      // later copies (after the first finished) are stopped by the mark
      await h.service.addedByMe(_ev());
      expect(h.sent, ['dev-b|Hello 👋']);
      expect(h.settings[FriendHelloService.settingKey('u-b')], isNotNull);
    });

    test('remembered after a restart (new service, same storage)', () async {
      final h = _Harness();
      await h.service.addedByMe(_ev());
      final again = FriendHelloService(
        readSetting: (k) async => h.settings[k],
        writeSetting: (k, v) async => h.settings[k] = v,
        chatHasMessages: (d) async => false, // even if the chat looks empty
        isBlocked: (u, d) async => false,
        isFriend: (u) async => true,
        send: (d, b) async => h.sent.add('$d|$b'),
        myUserId: () => 'u-a',
        myDeviceId: () => 'dev-a',
        delay: Duration.zero,
      );
      expect(await again.addedByMe(_ev()), FriendHelloDecision.skipRecentlySent);
      expect(h.sent.length, 1);
    });

    test('chat with messages -> no Hello', () async {
      final h = _Harness()..chats.add('dev-b');
      expect(await h.service.addedByMe(_ev()),
          FriendHelloDecision.skipChatHasMessages);
      expect(h.sent, isEmpty);
    });

    test('blocked -> no Hello', () async {
      final h = _Harness()..blocked.add('u-b');
      expect(await h.service.addedByMe(_ev()), FriendHelloDecision.skipBlocked);
      expect(h.sent, isEmpty);
    });

    test('mutual: the bigger account id does not send', () async {
      final h = _Harness();
      FriendAddMemory.notePeerTapped('dev-0');
      final ev = _ev(user: 'u-0', device: 'dev-0', mutual: true); // u-a > u-0
      expect(await h.service.addedByMe(ev),
          FriendHelloDecision.skipMutualOtherSends);
      expect(h.sent, isEmpty);
    });

    test('opens the chat first; toast only when it could not open', () async {
      final h = _Harness();
      final toasts = <String>[];
      FriendChatOpener.toast = toasts.add;
      FriendChatOpener.open = (d, n) async {
        h.opened.add(d);
        return true;
      };
      await h.service.addedByMe(_ev());
      expect(h.opened, ['dev-b']);
      expect(toasts, isEmpty);

      final h2 = _Harness();
      FriendChatOpener.open = (d, n) async => false;
      await h2.service.addedByMe(_ev(user: 'u-z', device: 'dev-z'));
      expect(toasts, ['Bee added']);
    });

    test('already friend: opens the chat, no Hello, no toast', () async {
      final h = _Harness()..friends.add('u-b');
      final toasts = <String>[];
      FriendChatOpener.toast = toasts.add;
      FriendChatOpener.open = (d, n) async {
        h.opened.add(d);
        return true;
      };
      expect(await h.service.isFriend('u-b'), isTrue);
      expect(
          await h.service.openExistingChat(
              deviceId: 'dev-b', displayName: 'Bee', source: 'nearby'),
          isTrue);
      expect(h.opened, ['dev-b']);
      expect(h.sent, isEmpty);
      expect(toasts, isEmpty);
    });

    test('a failing send never throws and frees the slot', () async {
      final settings = <String, String>{};
      var calls = 0;
      final s = FriendHelloService(
        readSetting: (k) async => settings[k],
        writeSetting: (k, v) async => settings[k] = v,
        chatHasMessages: (d) async => false,
        isBlocked: (u, d) async => false,
        isFriend: (u) async => false,
        send: (d, b) async {
          calls++;
          throw Exception('offline');
        },
        myUserId: () => 'u-a',
        myDeviceId: () => 'dev-a',
        delay: Duration.zero,
      );
      expect(await s.addedByMe(_ev()), isNull);
      // mark was saved before the send: no second try / second Hello
      expect(await s.addedByMe(_ev()), FriendHelloDecision.skipRecentlySent);
      expect(calls, 1);
    });
  });
}
