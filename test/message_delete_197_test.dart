import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/message_delete_book.dart';
import 'package:locallink/features/messaging/data/message_delete_actions.dart';

/// Settings table in memory.
class _Settings {
  final Map<String, String> rows = {};
  Future<String?> read(String k) async => rows[k];
  Future<void> write(String k, String v) async => rows[k] = v;
}

/// Only what MessageDeleteActions touches.
class _Store implements LocalStore {
  final Map<String, Message> direct = {};
  final Map<String, GroupMessage> groupRows = {};
  final Map<String, List<String>> paths = {};
  final List<String> emitted = [];
  final _deleted = StreamController<String>.broadcast();

  @override
  String? get deviceId => 'me';

  @override
  Stream<String> get deletedMessageIds => _deleted.stream;

  @override
  Future<Message?> messageById(String id) async => direct[id];

  @override
  Future<GroupMessage?> groupMessageById(String id) async => groupRows[id];

  @override
  Future<List<String>> deleteMessageLocal(String id) async {
    direct.remove(id);
    emitted.add(id);
    return paths.remove(id) ?? const [];
  }

  @override
  Future<List<String>> deleteGroupMessageLocal(String id) async {
    groupRows.remove(id);
    emitted.add(id);
    return paths.remove(id) ?? const [];
  }

  @override
  Future<List<String>> clearableDirectMessageIds(String peerId) async => [
        for (final m in direct.values)
          if ((m.senderId == peerId || m.recipientId == peerId) &&
              !(m.senderId == 'me' && m.status == 'queued'))
            m.id,
      ];

  @override
  Future<List<String>> clearableGroupMessageIds(String groupId) async => [
        for (final g in groupRows.values)
          if (g.groupId == groupId && !(g.senderId == 'me' && g.serverSeq == 0))
            g.id,
      ];

  @override
  bool dropsDirectMessage(Message message) {
    final self = deviceId ?? '';
    final peer =
        message.senderId == self ? message.recipientId : message.senderId;
    if (message.senderId == self) {
      return MessageDeleteBook.instance.isDeleted(message.id);
    }
    return MessageDeleteBook.instance.dropsMessage(
        id: message.id,
        chatKey: MessageDeleteBook.directKey(peer),
        createdAt: message.createdAt,
        senderId: message.senderId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Message _msg(String id, String from, String to, DateTime at,
        {String status = 'sent'}) =>
    Message(
        id: id,
        senderId: from,
        recipientId: to,
        body: 'hi $id',
        createdAt: at,
        status: status);

void main() {
  late _Settings settings;
  late _Store store;
  late List<String> removedFiles;
  late MessageDeleteActions actions;
  final book = MessageDeleteBook.instance;

  setUp(() async {
    settings = _Settings();
    await book.load(read: settings.read, write: settings.write);
    store = _Store();
    removedFiles = [];
    actions = MessageDeleteActions(
        store: store, deleteFile: (p) async => removedFiles.add(p));
  });

  group('197a MessageDeleteBook', () {
    test('saved in settings and loaded back', () async {
      await book.markDeleted('m1', kind: MessageDeleteBook.kindMe);
      await book.clearChat(MessageDeleteBook.directKey('ali'), keepRow: true);
      expect(settings.rows.keys,
          containsAll([MessageDeleteBook.deletedKey, MessageDeleteBook.clearsKey]));
      final again = MessageDeleteBook();
      await again.load(read: settings.read, write: settings.write);
      expect(again.isDeleted('m1'), isTrue);
      expect(again.keptEmptyDirectPeers(), {'ali'});
    });

    test('early delete is forgotten after 7 days', () async {
      final now = DateTime.utc(2026, 11, 3);
      await book.markDeleted('m9',
          kind: MessageDeleteBook.kindEarly, by: 'ali', at: now, now: now);
      final later = MessageDeleteBook();
      await later.load(
          read: settings.read,
          write: settings.write,
          now: now.add(const Duration(days: 8)));
      expect(later.markFor('m9'), isNull);
      final sooner = MessageDeleteBook();
      await sooner.load(
          read: settings.read,
          write: settings.write,
          now: now.add(const Duration(days: 6)));
      expect(sooner.markFor('m9'), isNotNull);
    });

    test('keeps only the newest ids', () async {
      final small = MessageDeleteBook();
      await small.load(read: settings.read, write: settings.write);
      for (var i = 0; i < MessageDeleteBook.maxDeleted + 5; i++) {
        await small.markDeleted('id$i', kind: MessageDeleteBook.kindMe);
      }
      expect(small.deletedCount, MessageDeleteBook.maxDeleted);
      expect(small.isDeleted('id0'), isFalse);
      expect(small.isDeleted('id${MessageDeleteBook.maxDeleted + 4}'), isTrue);
    });

    test('clear drops older messages only; Delete chat hides the row',
        () async {
      final at = DateTime.utc(2026, 11, 3, 20);
      await book.clearChat(MessageDeleteBook.directKey('ali'),
          keepRow: false, at: at);
      bool drops(DateTime t) => book.dropsMessage(
          id: 'x', chatKey: MessageDeleteBook.directKey('ali'), createdAt: t);
      expect(drops(at.subtract(const Duration(minutes: 1))), isTrue);
      expect(drops(at.add(const Duration(seconds: 1))), isFalse);
      expect(book.keptEmptyDirectPeers(), isEmpty);
    });

    test('an applied delete never goes back to early', () async {
      await book.markDeleted('m1', kind: MessageDeleteBook.kindAll, by: 'me');
      await book.markDeleted('m1', kind: MessageDeleteBook.kindEarly, by: 'x');
      expect(book.markFor('m1')!.kind, MessageDeleteBook.kindAll);
    });
  });

  group('197a delete actions', () {
    final t0 = DateTime.now().toUtc();

    test('Delete for me: row, files, never comes back', () async {
      store.direct['m1'] = _msg('m1', 'ali', 'me', t0);
      store.paths['m1'] = ['/data/attachments/m1.jpg.enc'];
      await actions.deleteForMe('m1', group: false);
      expect(store.direct, isEmpty);
      expect(removedFiles, ['/data/attachments/m1.jpg.enc']);
      expect(store.emitted, ['m1']);
      expect(book.isDeleted('m1'), isTrue);
      // A copy from Online history / a late Nearby copy is dropped.
      expect(store.dropsDirectMessage(_msg('m1', 'ali', 'me', t0)), isTrue);
    });

    test('Delete for everyone received from the sender in time', () async {
      store.direct['m2'] = _msg('m2', 'ali', 'me', t0);
      final cmd = DeleteCommand(
          messageId: 'm2', by: 'ali', at: t0.add(const Duration(minutes: 3)));
      await actions.applyRemote(
          body: cmd.encode(), envelopeSender: 'ali', group: false);
      expect(store.direct.containsKey('m2'), isFalse);
      expect(book.isDeleted('m2'), isTrue);
    });

    test('wrong sender is refused', () async {
      store.direct['m3'] = _msg('m3', 'ali', 'me', t0);
      final forged = DeleteCommand(messageId: 'm3', by: 'eve', at: t0);
      await actions.applyRemote(
          body: forged.encode(), envelopeSender: 'eve', group: false);
      expect(store.direct.containsKey('m3'), isTrue);
      // "by" says ali, but the envelope came from eve.
      final relabeled = DeleteCommand(messageId: 'm3', by: 'ali', at: t0);
      await actions.applyRemote(
          body: relabeled.encode(), envelopeSender: 'eve', group: false);
      expect(store.direct.containsKey('m3'), isTrue);
    });

    test('too old is refused (over 5 min + 2 min slack)', () async {
      store.direct['m4'] = _msg('m4', 'ali', 'me', t0);
      final late = DeleteCommand(
          messageId: 'm4', by: 'ali', at: t0.add(const Duration(minutes: 8)));
      await actions.applyRemote(
          body: late.encode(), envelopeSender: 'ali', group: false);
      expect(store.direct.containsKey('m4'), isTrue);
      expect(book.isDeleted('m4'), isFalse);
    });

    test('delete before the message: the message is dropped later', () async {
      final cmd = DeleteCommand(
          messageId: 'm5', by: 'ali', at: t0.add(const Duration(minutes: 1)));
      await actions.applyRemote(
          body: cmd.encode(), envelopeSender: 'ali', group: false);
      expect(book.markFor('m5')!.kind, MessageDeleteBook.kindEarly);
      expect(store.dropsDirectMessage(_msg('m5', 'ali', 'me', t0)), isTrue);
      // Someone else's message with that id is not hidden.
      expect(store.dropsDirectMessage(_msg('m5', 'bob', 'me', t0)), isFalse);
    });

    test('same delete twice: nothing happens', () async {
      store.direct['m6'] = _msg('m6', 'ali', 'me', t0);
      final cmd = DeleteCommand(messageId: 'm6', by: 'ali', at: t0);
      await actions.applyRemote(
          body: cmd.encode(), envelopeSender: 'ali', group: false);
      await actions.applyRemote(
          body: cmd.encode(), envelopeSender: 'ali', group: false);
      expect(store.emitted, ['m6']);
    });

    test('bad delete body is ignored', () async {
      await actions.applyRemote(
          body: 'lldel:v1:{bad', envelopeSender: 'ali', group: false);
      expect(store.emitted, isEmpty);
    });

    test('my side of Delete for everyone', () async {
      store.direct['m7'] = _msg('m7', 'me', 'ali', t0);
      await actions.deleteForEveryoneLocal('m7', group: false, at: t0);
      expect(store.direct, isEmpty);
      expect(book.markFor('m7')!.kind, MessageDeleteBook.kindAll);
      expect(book.markFor('m7')!.by, 'me');
    });

    test('groups: only the sender of that group message', () async {
      store.groupRows['g1'] = GroupMessage(
          id: 'g1',
          groupId: 'fam',
          senderId: 'bilal',
          body: 'Meeting at 5?',
          createdAt: t0.toIso8601String(),
          serverSeq: 4);
      await actions.applyRemote(
          body: DeleteCommand(messageId: 'g1', by: 'sumaira', at: t0).encode(),
          envelopeSender: 'sumaira',
          group: true);
      expect(store.groupRows.containsKey('g1'), isTrue);
      await actions.applyRemote(
          body: DeleteCommand(messageId: 'g1', by: 'bilal', at: t0).encode(),
          envelopeSender: 'bilal',
          group: true);
      expect(store.groupRows.containsKey('g1'), isFalse);
    });

    test('Clear chat keeps my unsent messages and marks the chat', () async {
      store.direct['a'] = _msg('a', 'ali', 'me', t0);
      store.direct['b'] = _msg('b', 'me', 'ali', t0);
      store.direct['c'] = _msg('c', 'me', 'ali', t0, status: 'queued');
      store.direct['d'] = _msg('d', 'bob', 'me', t0);
      store.paths['a'] = ['/x/a.enc'];
      final n =
          await actions.clearChat(chatId: 'ali', group: false, keepRow: true);
      expect(n, 2);
      expect(store.direct.keys, unorderedEquals(['c', 'd']));
      expect(removedFiles, ['/x/a.enc']);
      expect(book.keptEmptyDirectPeers(), {'ali'});
      // History can't bring back older messages.
      expect(
          store.dropsDirectMessage(
              _msg('a', 'ali', 'me', t0.subtract(const Duration(seconds: 1)))),
          isTrue);
    });
  });

  group('197a wiring (source checks)', () {
    String src(String p) => File(p).readAsStringSync();

    test('delete rides every receive path that consumes reactions', () {
      final s = src(
          'lib/features/messaging/data/services/reliable_messaging_service.dart');
      final body = s.substring(s.indexOf('Future<bool> _consumeReaction('));
      expect(body.indexOf('DeleteCommand.isDelete'),
          lessThan(body.indexOf('_reactionPrefix')));
      expect('await _consumeReaction('.allMatches(s).length,
          greaterThanOrEqualTo(4));
      expect(s, contains('_incoming.stream.where((m) => !store.dropsDirectMessage(m))'));
      final g =
          src('lib/features/groups/data/services/group_messaging_service.dart');
      expect(g, contains('DeleteCommand.isDelete(message.body)'));
      expect(g, contains('!store.dropsGroupMessage(m)'));
    });

    test('save paths skip control bodies and deleted / cleared ids', () {
      final s = src('lib/core/services/local_store.dart');
      expect(s, contains('MessageEnvelope.isControl(message.body)'));
      expect(s, contains('existing.isEmpty && _dropsDirect(message)'));
      expect(s, contains("MessageEnvelope.isControl(gm['body']"));
      expect(s, contains('MessageDeleteBook.instance.load('));
      expect(s, contains('MessageDeleteBook.instance.resetMemory()'));
    });

    test('no database version change in 197a', () {
      // Bundle 197b added v27 = only the media_state side table; the
      // 197a message tables stay as they were.
      final s = src('lib/core/services/local_store.dart');
      // Bundle 198: v28 only adds messages.played_at (read receipts).
      final i = s.indexOf('Future<void> _upgradeTo28(');
      final up28 = s.substring(i, s.indexOf('\n  }\n', i));
      expect(RegExp('ALTER TABLE').allMatches(up28).length, 1);
      expect(up28, contains('ADD COLUMN played_at TEXT'));
      // Bundle G2: v29 only adds group columns (no message table change).
      final j = s.indexOf('Future<void> _upgradeTo29(');
      final up29 = s.substring(j, s.indexOf('\n  }\n', j));
      expect(up29, isNot(contains("'messages'")));
      expect(up29, isNot(contains('_upgradeTo30')));
      // Bundle G3: v30 only adds group tables / columns (no 'messages').
      final k = s.indexOf('Future<void> _upgradeTo30(');
      final up30 = s.substring(k, s.indexOf('\n  }\n', k));
      expect(up30, isNot(contains("'messages'")));
      expect(up30, isNot(contains('TABLE messages')));
      // Bundle G4: v31 only adds group_copies (no 'messages').
      final l = s.indexOf('Future<void> _upgradeTo31(');
      final up31 = s.substring(l, s.indexOf('\n  }\n', l));
      expect(up31, isNot(contains('TABLE messages')));
      // Bundle G5: v32 only adds group_receipts.
      final m32 = s.indexOf('Future<void> _upgradeTo32(');
      final up32 = s.substring(m32, s.indexOf('\n  }\n', m32));
      expect(up32, isNot(contains('TABLE messages')));
      // Bundle G7: v33 only adds group_file_sends + group_copies columns.
      final m33 = s.indexOf('Future<void> _upgradeTo33(');
      final up33 = s.substring(m33, s.indexOf('\n  }\n', m33));
      expect(up33, isNot(contains('TABLE messages')));
      expect(up33, isNot(contains("'messages'")));
      expect(s, isNot(contains('_upgradeTo34')));
      expect(s, contains('CREATE TABLE IF NOT EXISTS media_state ('));
    });
  });
}
