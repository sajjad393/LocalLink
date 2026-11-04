// ignore_for_file: prefer_const_constructors
import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/chat_preview.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/groups/data/group_extras_book.dart';
import 'package:locallink/features/groups/data/group_receipts.dart';
import 'package:locallink/features/groups/data/group_sender_keys.dart';
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';

import 'support/phase5_fakes.dart';

// Bundle G6: end-to-end sender keys for group messages on the server road.

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
  Future<void> saveGroupMessageReaction(
      {required String messageId,
      required String reactorId,
      required String emoji,
      required String createdAt}) async {}
  @override
  Future<List<Map<String, dynamic>>> groups() async =>
      groupsById.values.toList();
  @override
  Future<List<String>> deleteGroupMessageLocal(String id) async {
    for (final rows in groupMessageRows.values) {
      rows.removeWhere((r) => r['id']?.toString() == id);
    }
    return const [];
  }

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
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// One phone: id, X25519 identity, settings.
class _Phone {
  _Phone(this.id, this.pair, this.public);
  final String id;
  final SimpleKeyPair pair;
  final List<int> public;
  final Map<String, String> settings = {};

  static Future<_Phone> make(String id) async {
    final pair = await X25519().newKeyPair();
    return _Phone(id, pair, (await pair.extractPublicKey()).bytes);
  }

  GroupSenderKeys keys(Map<String, _Phone> book, {Map<String, String>? store}) {
    final s = store ?? settings;
    return GroupSenderKeys(
      selfId: () => id,
      read: (k) async => s[k],
      write: (k, v) async => s[k] = v,
      ownKeys: () async => [await SealKeyPair.from(pair)],
      publicKeyOf: (gid, who) async => book[who]?.public,
    );
  }
}

void main() {
  late _Phone ali, me, sara, bilal;
  late Map<String, _Phone> book;

  setUpAll(() async {
    ali = await _Phone.make('ali');
    me = await _Phone.make('self-device');
    sara = await _Phone.make('sara');
    bilal = await _Phone.make('bilal');
    book = {'ali': ali, 'self-device': me, 'sara': sara, 'bilal': bilal};
  });

  setUp(() {
    for (final p in [ali, me, sara, bilal]) {
      p.settings.clear();
    }
    GroupExtrasBook.instance = GroupExtrasBook();
  });

  group('keys', () {
    test('one lock, every member opens; the server sees no text', () async {
      final a = ali.keys(book);
      final key = await a.current('g1', ['sara', 'self-device', 'ali']);
      expect(key.members, ['sara', 'self-device'], reason: 'me left out, sorted');
      final note = (await a.keysNote('g1', key.kid, key.key, key.members))!;
      expect(note, startsWith('llskd:v1:'));
      final locked = await a.lock('g1', 'm1', 'Lunch at 1? 🍛', key);
      expect(locked, startsWith('llsk:v1:${key.kid}.'));
      expect(locked.contains('Lunch'), isFalse);
      for (final p in [sara, me]) {
        final k = p.keys(book);
        expect(await k.open('g1', 'ali', 'm1', locked), isNull, reason: 'no key yet');
        expect(await k.acceptKeys('g1', 'ali', note), key.kid);
        expect(await k.open('g1', 'ali', 'm1', locked), 'Lunch at 1? 🍛');
      }
      // Bilal was not in the list: nothing for him
      expect(await bilal.keys(book).acceptKeys('g1', 'ali', note), isNull);
      // my own copy from the server opens with my own key
      expect(await a.open('g1', 'ali', 'm1', locked), 'Lunch at 1? 🍛');
    });

    test('the server can\'t move it (other id / group / writer) or change it', () async {
      final a = ali.keys(book);
      final key = await a.current('g1', ['sara']);
      final s = sara.keys(book);
      await s.acceptKeys('g1', 'ali', (await a.keysNote('g1', key.kid, key.key, key.members))!);
      final locked = await a.lock('g1', 'm1', 'secret', key);
      expect(await s.open('g1', 'ali', 'm2', locked), isNull);
      expect(await s.open('g2', 'ali', 'm1', locked), isNull);
      expect(await s.open('g1', 'bilal', 'm1', locked), isNull);
      final bad = '${locked.substring(0, locked.length - 3)}AAA';
      expect(await s.open('g1', 'ali', 'm1', bad), isNull);
      // a key note can't be passed off as someone else's
      final note2 = (await a.keysNote('g1', key.kid, key.key, ['sara']))!;
      expect(await sara.keys(book, store: {}).acceptKeys('g1', 'bilal', note2), isNull);
    });

    test('a new member list = a new key; old keys stay for old messages', () async {
      final a = ali.keys(book);
      final k1 = await a.current('g1', ['sara']);
      expect((await a.current('g1', ['sara'])).kid, k1.kid);
      final k2 = await a.current('g1', ['sara', 'bilal']);
      expect(k2.kid, isNot(k1.kid));
      final k3 = await a.current('g1', ['bilal']);
      expect(k3.kid, isNot(k2.kid), reason: 'Sara left: she can\'t read new ones');
      expect(await a.ownKey('g1', k1.kid), k1.key);
      expect(await a.ownKeyWasFor('g1', k1.kid, 'sara'), isTrue);
      expect(await a.ownKeyWasFor('g1', k1.kid, 'bilal'), isFalse,
          reason: 'new members never get an older key');
    });

    test('a missing public key = no note (message goes as before)', () async {
      final a = ali.keys({'ali': ali});
      final key = await a.current('g1', ['sara']);
      expect(await a.keysNote('g1', key.kid, key.key, key.members), isNull);
    });

    test('ask note + kid + key text forms', () {
      final ask = GroupSenderKeys.askNote('ali', 'ab12');
      expect(GroupSenderKeys.parseAsk(ask), ('ali', 'ab12'));
      expect(GroupSenderKeys.kidOf('llsk:v1:ab12.x.y'), 'ab12');
      expect(GroupSenderKeys.kidOf('hello'), '');
      final b = List<int>.generate(32, (i) => i);
      expect(GroupSenderKeys.decodePublicKey('AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'), b);
      expect(GroupSenderKeys.decodePublicKey('AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8='), b);
      expect(GroupSenderKeys.decodePublicKey('short'), isNull);
    });

    test('member keys: card / friend first, then directory, then server', () async {
      var serverCalls = 0;
      final k = GroupMemberKeys(
        cardOrFriend: (g, id) async => id == 'ali' ? 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8' : '',
        directory: (id) async => id == 'sara'
            ? {'identity_public_key': 'AQECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'}
            : null,
        server: () async {
          serverCalls++;
          return {'bilal': 'AgECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'};
        },
      );
      expect((await k.lookup('g', 'ali'))![0], 0);
      expect((await k.lookup('g', 'sara'))![0], 1);
      expect(serverCalls, 0);
      expect((await k.lookup('g', 'bilal'))![0], 2);
      expect(await k.lookup('g', 'bilal'), isNotNull);
      expect(serverCalls, 1, reason: 'cached');
    });

    test('locked text reads "🔒 Waiting…" in the chat and Chats list', () {
      const body = 'llsk:v1:ab12.xx.yy';
      final m = GroupMessage(id: 'x', groupId: 'g', senderId: 'ali', body: body, createdAt: '');
      expect(m.text, GroupSenderKeys.waitingText);
      expect(
          chatPreviewText(
              ChatPreview(messageId: 'x', senderId: 'ali', body: body, createdAt: DateTime(2026)),
              localDeviceId: 'me', senderName: 'Ali'),
          'Ali: ${GroupSenderKeys.waitingText}');
    });
  });

  group('service', () {
    late _Store store;
    late FakeSocket socket;
    late GroupMessagingService service;

    setUp(() async {
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
      service.senderKeys = me.keys(book, store: store.settings);
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
          'created_at': '2026-11-04T16:40:00Z',
          'server_seq': seq,
        };

    test('send: key note first, then only locked text; my row stays open', () async {
      await socket.goOnline();
      await _pump();
      final m = await service.send('g1', 'Office closed on Friday');
      await _pump();
      final sends = socket.sentFrames.where((f) => f['type'] == 'send_group_message').toList();
      expect(sends, hasLength(2));
      expect(sends[0]['body'].toString(), startsWith('llskd:v1:'));
      expect(sends[1]['id'], m.id);
      final wire = sends[1]['body'].toString();
      expect(wire, startsWith('llsk:v1:'));
      expect(wire.contains('Friday'), isFalse);
      expect(store.groupOutboxItems.single['body'], 'Office closed on Friday');
      // Ali and Sara can open it with the note
      for (final p in [ali, sara]) {
        final k = p.keys(book, store: {});
        expect(await k.acceptKeys('g1', 'self-device', sends[0]['body'].toString()), isNotNull);
        expect(await k.open('g1', 'self-device', m.id, wire), 'Office closed on Friday');
      }
      // the server took the note: the next message has no note
      socket.emitFrame({...frame(sends[0]['id'].toString(), 'self-device', sends[0]['body'].toString()), 'type': 'group_message_ack'});
      await _pump();
      socket.sentFrames.clear();
      await service.send('g1', 'Second');
      await _pump();
      final again = socket.sentFrames.where((f) => f['type'] == 'send_group_message').toList();
      expect(again.where((f) => f['body'].toString().startsWith('llskd:')), isEmpty);
      // my own message echoed back (ack) keeps the open text
      socket.emitFrame({...frame(m.id, 'self-device', wire, seq: 9), 'type': 'group_message_ack'});
      await _pump();
      expect((await store.groupMessageById(m.id))!.body, 'Office closed on Friday');
    });

    test('a member list change makes a new key note', () async {
      await socket.goOnline();
      await service.send('g1', 'one');
      await _pump();
      final first = socket.sentFrames.firstWhere((f) => f['body'].toString().startsWith('llskd:'));
      socket.emitFrame({...frame(first['id'].toString(), 'self-device', first['body'].toString()), 'type': 'group_message_ack'});
      await _pump();
      store.members['g1']!.removeWhere((r) => r['device_id'] == 'sara');
      socket.sentFrames.clear();
      await service.send('g1', 'two');
      await _pump();
      final note = socket.sentFrames.firstWhere((f) => f['body'].toString().startsWith('llskd:'));
      expect(await sara.keys(book, store: {}).acceptKeys('g1', 'self-device', note['body'].toString()), isNull,
          reason: 'Sara left: no key for her');
    });

    test('no public key for a member: sent as before (no lock)', () async {
      store.members['g1']!.add({'device_id': 'stranger', 'role': 'member'});
      await socket.goOnline();
      await service.send('g1', 'plain one');
      await _pump();
      final sends = socket.sentFrames.where((f) => f['type'] == 'send_group_message').toList();
      expect(sends.single['body'], 'plain one');
    });

    test('receive: note then locked message -> open bubble', () async {
      final a = ali.keys(book);
      final key = await a.current('g1', ['self-device', 'sara']);
      socket.emitFrame(frame('k1', 'ali', (await a.keysNote('g1', key.kid, key.key, key.members))!));
      await _pump();
      final got = <GroupMessage>[];
      final sub = service.incoming.listen(got.add);
      socket.emitFrame(frame('m1', 'ali', await a.lock('g1', 'm1', 'Lunch?', key)));
      await _pump();
      expect((await store.groupMessageById('m1'))!.body, 'Lunch?');
      expect(got.single.text, 'Lunch?');
      expect(await store.groupMessageById('k1'), isNull, reason: 'notes are never lines');
      // a locked reaction is applied, never a bubble
      final r = await a.lock('g1', 'r1',
          'llrx:v1:{"message_id":"m1","emoji":"👍","reactor_id":"ali","created_at":"2026-11-04T16:41:00Z"}', key);
      final rx = <MessageReaction>[];
      final rsub = service.reactionIncoming.listen(rx.add);
      socket.emitFrame(frame('r1', 'ali', r));
      await _pump();
      expect(rx.single.emoji, '👍');
      expect(await store.groupMessageById('r1'), isNull);
      await sub.cancel();
      await rsub.cancel();
    });

    test('locked before the key: "Waiting", ask once; opens when the key comes', () async {
      await socket.goOnline();
      await _pump();
      final a = ali.keys(book);
      final key = await a.current('g1', ['self-device', 'sara']);
      socket.emitFrame(frame('m1', 'ali', await a.lock('g1', 'm1', 'Hello team', key)));
      socket.emitFrame(frame('m2', 'ali', await a.lock('g1', 'm2', 'Second', key)));
      await _pump();
      expect((await store.groupMessageById('m1'))!.text, GroupSenderKeys.waitingText);
      final asks = socket.sentFrames
          .where((f) => f['body'].toString().startsWith('llskq:'))
          .toList();
      expect(asks, hasLength(1), reason: 'one ask per writer + key');
      expect(GroupSenderKeys.parseAsk(asks.single['body'].toString()), ('ali', key.kid));
      final got = <GroupMessage>[];
      final sub = service.incoming.listen(got.add);
      socket.emitFrame(frame('k1', 'ali', (await a.keysNote('g1', key.kid, key.key, key.members))!));
      await _pump();
      expect((await store.groupMessageById('m1'))!.body, 'Hello team');
      expect((await store.groupMessageById('m2'))!.body, 'Second');
      expect(got.map((m) => m.text), containsAll(['Hello team', 'Second']));
      await sub.cancel();
    });

    test('Ali asks for my key: I send it again (new note id)', () async {
      await socket.goOnline();
      await service.send('g1', 'x');
      await _pump();
      final first = socket.sentFrames.firstWhere((f) => f['body'].toString().startsWith('llskd:'));
      socket.emitFrame({...frame(first['id'].toString(), 'self-device', first['body'].toString()), 'type': 'group_message_ack'});
      await _pump();
      final kid = GroupSenderKeys.kidOf(socket.sentFrames
          .firstWhere((f) => f['body'].toString().startsWith('llsk:'))['body']
          .toString());
      socket.sentFrames.clear();
      socket.emitFrame(frame('q1', 'ali', GroupSenderKeys.askNote('self-device', kid)));
      await _pump();
      final note = socket.sentFrames.singleWhere((f) => f['body'].toString().startsWith('llskd:'));
      expect(note['id'], isNot(first['id']));
      expect(await ali.keys(book, store: {}).acceptKeys('g1', 'self-device', note['body'].toString()), kid);
      // an ask for someone else is ignored
      socket.sentFrames.clear();
      socket.emitFrame(frame('q2', 'ali', GroupSenderKeys.askNote('sara', kid)));
      await _pump();
      expect(socket.sentFrames, isEmpty);
    });

    test('rows saved locked by sync open on the next connect', () async {
      final a = ali.keys(book);
      final key = await a.current('g1', ['self-device', 'sara']);
      await service.senderKeys!.acceptKeys('g1', 'ali', (await a.keysNote('g1', key.kid, key.key, key.members))!);
      store.groupMessageRows['g1'] = [
        {'id': 's1', 'group_id': 'g1', 'sender_id': 'ali', 'body': await a.lock('g1', 's1', 'From sync', key), 'created_at': '2026-11-04T10:00:00Z', 'server_seq': 3},
      ];
      expect(await service.openLockedRows(), 1);
      expect((await store.groupMessageById('s1'))!.body, 'From sync');
    });
  });
}
