import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/services/message_delete_book.dart';
import 'package:locallink/features/groups/bloc/group_chat_bloc.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';

class _Repo implements MessagingRepositoryContract {
  List<Message> rows = [];
  final incomingCtl = StreamController<Message>.broadcast();
  final deletedCtl = StreamController<String>.broadcast();
  final sent = <String>[];
  final forMe = <String>[];
  final forAll = <String>[];
  bool allowEveryone = true;
  int clears = 0;
  bool? lastKeepRow;

  @override
  String get localDeviceId => 'me';
  @override
  bool get isServerConnected => true;
  @override
  Future<Device?> peer(String deviceId) async => null;
  @override
  Future<List<Message>> cachedHistory(String peerId) async => rows;
  @override
  Stream<Message> get incoming => incomingCtl.stream;
  @override
  Future<List<Message>> history(String otherDeviceId) async => rows;
  @override
  Future<Set<String>> chatPeerIds() async => {'ali'};
  @override
  Future<void> send(String recipientId, String body,
      {List<PickedFile> attachments = const []}) async {
    sent.add(body);
  }

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
  Stream<String> get deletedMessageIds => deletedCtl.stream;
  @override
  Future<void> deleteForMe(String messageId) async => forMe.add(messageId);
  @override
  Future<bool> deleteForEveryone(String recipientId, String messageId) async {
    if (!allowEveryone) return false;
    forAll.add(messageId);
    return true;
  }

  @override
  Future<int> clearChat(String peerId, {bool keepRow = true}) async {
    clears++;
    lastKeepRow = keepRow;
    return 0;
  }
}

class _GroupRepo implements GroupMessagingRepositoryContract {
  List<GroupMessage> rows = [];
  final deletedCtl = StreamController<String>.broadcast();
  final sent = <String>[];
  int clears = 0;
  @override
  Stream<GroupMessage> get incoming => const Stream.empty();
  @override
  Stream<MessageReaction> get reactionIncoming => const Stream.empty();
  @override
  Future<List<GroupMessage>> history(String groupId) async => rows;
  @override
  Future<GroupMessage> send(String groupId, String body,
      {List<PickedFile> attachments = const []}) async {
    sent.add(body);
    return GroupMessage(
        id: 'n${sent.length}',
        groupId: groupId,
        senderId: 'me',
        body: body,
        createdAt: DateTime.now().toUtc().toIso8601String());
  }

  @override
  Future<void> react(String groupId, String messageId, String emoji) async {}
  @override
  Future<List<MessageReaction>> reactions(String messageId) async => const [];
  @override
  Stream<String> get deletedMessageIds => deletedCtl.stream;
  @override
  Future<void> deleteForMe(String messageId) async {}
  @override
  Future<bool> deleteForEveryone(String groupId, String messageId) async =>
      true;
  @override
  Future<int> clearChat(String groupId) async {
    clears++;
    return 0;
  }
}

Message _m(String id, String from, {String status = 'sent'}) => Message(
    id: id,
    senderId: from,
    recipientId: from == 'me' ? 'ali' : 'me',
    body: 'text $id',
    createdAt: DateTime(2026, 11, 3, 20, int.parse(id.substring(1))),
    status: status);

const _ali = Device(id: 'ali', name: 'Ali', platform: 'android', createdAt: '', lastSeenAt: '');

void main() {
  setUp(() => MessageDeleteBook.instance.resetMemory());

  group('197a ChatBloc', () {
    late _Repo repo;
    late ChatBloc bloc;
    setUp(() async {
      repo = _Repo()
        ..rows = [
          _m('m1', 'ali'),
          _m('m2', 'me'),
          _m('m3', 'me', status: 'queued'),
        ];
      bloc = ChatBloc(repository: repo, device: _ali);
      await bloc.load();
    });
    tearDown(() => bloc.close());

    test('reply is sent inside the envelope', () async {
      await bloc.send('Yes, leaving now',
          reply: const ReplyRef(id: 'm1', from: 'ali', snip: 'text m1'));
      final env = MessageEnvelope.parse(repo.sent.single);
      expect(env.text, 'Yes, leaving now');
      expect(env.reply!.id, 'm1');
      await bloc.send('plain');
      expect(repo.sent.last, 'plain');
    });

    test('Delete for me removes the bubbles at once', () async {
      await bloc.deleteForMe(['m1', 'm2']);
      expect(repo.forMe, ['m1', 'm2']);
      expect(bloc.messages.map((m) => m.id), ['m3']);
    });

    test('Delete for everyone too late changes nothing', () async {
      repo.allowEveryone = false;
      final ok = await bloc.deleteForEveryone(['m2']);
      expect(ok, isFalse);
      expect(bloc.messages.map((m) => m.id), contains('m2'));
      repo.allowEveryone = true;
      expect(await bloc.deleteForEveryone(['m2']), isTrue);
      expect(bloc.messages.map((m) => m.id), isNot(contains('m2')));
    });

    test('a deleted id from anywhere drops the bubble', () async {
      repo.deletedCtl.add('m1');
      await Future<void>.delayed(Duration.zero);
      expect(bloc.messages.map((m) => m.id), isNot(contains('m1')));
    });

    test('Clear chat keeps my unsent message only', () async {
      await bloc.clearChat();
      expect(repo.clears, 1);
      expect(repo.lastKeepRow, isTrue);
      expect(bloc.messages.map((m) => m.id), ['m3']);
    });

    test('a deleted message arriving late is ignored', () async {
      await MessageDeleteBook.instance
          .markDeleted('m9', kind: MessageDeleteBook.kindMe);
      repo.incomingCtl.add(_m('m9', 'ali'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.messages.map((m) => m.id), isNot(contains('m9')));
      repo.incomingCtl.add(_m('m8', 'ali'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.messages.map((m) => m.id), contains('m8'));
    });
  });

  group('197a GroupChatBloc', () {
    const family = LocalGroup(id: 'fam', name: 'Family', ownerId: 'me', createdAt: '');
    test('reply, deleted stream, clear', () async {
      final repo = _GroupRepo()
        ..rows = [
          GroupMessage(
              id: 'g1',
              groupId: 'fam',
              senderId: 'bilal',
              body: 'Meeting at 5?',
              createdAt: '2026-11-03T15:30:00Z',
              serverSeq: 1),
          const GroupMessage(
              id: 'g2',
              groupId: 'fam',
              senderId: 'me',
              body: 'waiting',
              createdAt: '2026-11-03T15:31:00Z'),
        ];
      final bloc =
          GroupChatBloc(repository: repo, group: family, localDeviceId: 'me');
      await bloc.load();
      await bloc.send('Yes',
          reply: const ReplyRef(id: 'g1', from: 'bilal', snip: 'Meeting at 5?'));
      expect(MessageEnvelope.parse(repo.sent.single).reply!.id, 'g1');
      repo.deletedCtl.add('g1');
      await Future<void>.delayed(Duration.zero);
      expect(bloc.messages.map((m) => m.id), isNot(contains('g1')));
      await bloc.clearChat();
      expect(repo.clears, 1);
      // My unsent message (serverSeq 0) stays.
      expect(bloc.messages.map((m) => m.id), contains('g2'));
      await bloc.close();
    });
  });
}
