// Bundle 237: a friend on a new phone keeps ONE chat with the old and the
// new messages.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/message_delete_book.dart';
import 'package:locallink/core/services/person_phones_237.dart';
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';
import 'package:locallink/features/messaging/data/message_delete_actions.dart';

class _Settings {
  final Map<String, String> rows = {};
  Future<String?> read(String k) async => rows[k];
  Future<void> write(String k, String v) async => rows[k] = v;
}

Device _device(String id, {bool online = false, String lastSeen = '2026-01-01T00:00:00Z'}) => Device(
      id: id,
      name: 'Device $id',
      platform: 'android',
      createdAt: '2026-01-01T00:00:00Z',
      lastSeenAt: lastSeen,
      serverConnected: online,
    );

final class _Repo implements HomeRepositoryContract {
  _Repo(this.deviceList, this.userByDevice);
  final List<Device> deviceList;
  final Map<String, String> userByDevice;
  @override
  String? get localDeviceId => 'me';
  @override
  Stream<Map<String, dynamic>> get presenceEvents => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get directPresenceEvents => const Stream.empty();
  @override
  Future<List<Device>> devices() async => deviceList;
  @override
  Future<List<LocalGroup>> groups() async => const <LocalGroup>[];
  @override
  Future<List<Device>> localDevices() async => deviceList;
  @override
  Future<List<LocalGroup>> localGroups() async => const <LocalGroup>[];
  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) => throw UnimplementedError();
  @override
  Future<void> cacheDevice(Device device) async {}
  @override
  Future<void> markDeviceSeen(String deviceId) async {}
  @override
  Future<String?> userIdForDevice(String deviceId) async => userByDevice[deviceId];
  @override
  Future<String?> labelForDevice(String deviceId) async => null;
}

/// Only what MessageDeleteActions.clearChat touches.
class _Store implements LocalStore {
  final Map<String, Message> direct = {};
  final Map<String, Set<String>> person = {};

  @override
  String? get deviceId => 'me';

  @override
  Future<Set<String>> phonesOfPerson237(String deviceId) async => person[deviceId] ?? {deviceId};

  @override
  Future<List<String>> clearableDirectMessageIds(String peerId) async {
    final phones = await phonesOfPerson237(peerId);
    return [
      for (final m in direct.values)
        if (phones.contains(m.senderId) || phones.contains(m.recipientId)) m.id,
    ];
  }

  @override
  Future<List<String>> deleteMessageLocal(String id) async {
    direct.remove(id);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Message _msg(String id, String from, String to, DateTime at) =>
    Message(id: id, senderId: from, recipientId: to, body: 'hi $id', createdAt: at, status: 'sent');

void main() {
  late _Settings settings;
  final book = PersonPhones237.instance;

  setUp(() async {
    settings = _Settings();
    await book.load(read: settings.read, write: settings.write);
  });
  tearDown(() => book.clearForTest());

  group('237 PersonPhones237 book', () {
    test('remembers an old phone, newest first, saved and loaded back', () async {
      expect(await book.remember('u-ali', 'phone-1', currentDeviceId: 'phone-2'), isTrue);
      expect(await book.remember('u-ali', 'phone-2', currentDeviceId: 'phone-3'), isTrue);
      expect(book.pastOf('u-ali'), ['phone-2', 'phone-1']);
      expect(book.ownerOf('phone-1'), 'u-ali');
      final again = PersonPhones237();
      await again.load(read: settings.read, write: settings.write);
      expect(again.pastOf('u-ali'), ['phone-2', 'phone-1']);
      expect(jsonDecode(settings.rows[PersonPhones237.settingKey]!), isA<Map>());
    });

    test('the current phone is never kept as old; repeats change nothing', () async {
      expect(await book.remember('u-ali', 'phone-2', currentDeviceId: 'phone-2'), isFalse);
      expect(await book.remember('u-ali', 'phone-1', currentDeviceId: 'phone-2'), isTrue);
      expect(await book.remember('u-ali', 'phone-1', currentDeviceId: 'phone-2'), isFalse);
      expect(book.pastOf('u-ali'), ['phone-1']);
    });

    test('at most 10 old phones per person', () async {
      for (var i = 0; i < 14; i++) {
        await book.remember('u-ali', 'p$i', currentDeviceId: 'now');
      }
      expect(book.pastOf('u-ali'), hasLength(PersonPhones237.maxPerPerson));
      expect(book.pastOf('u-ali').first, 'p13');
    });

    test('server list (newest first) keeps its order', () async {
      expect(await book.rememberAll('u-ali', ['p-new', 'p-mid', 'p-old'], currentDeviceId: 'now'), isTrue);
      expect(book.pastOf('u-ali'), ['p-new', 'p-mid', 'p-old']);
      expect(await book.rememberAll('u-ali', ['p-new', 'p-old'], currentDeviceId: 'now'), isFalse);
    });

    test('a phone that becomes someone\'s current phone leaves every list (235 New owner)', () async {
      await book.remember('u-ali', 'phone-1', currentDeviceId: 'phone-2');
      expect(await book.forgetForOthers('phone-1', userId: 'u-sara'), isTrue);
      expect(book.ownerOf('phone-1'), isNull);
      expect(book.isEmpty, isTrue);
    });

    test('a card for another person never adds phones to Ali', () async {
      await book.remember('u-ali', 'phone-1', currentDeviceId: 'phone-2');
      await book.remember('u-sara', 'phone-9', currentDeviceId: 'phone-8');
      expect(book.pastOf('u-ali'), ['phone-1']);
      expect(book.ownerOf('phone-9'), 'u-sara');
    });

    test('bad JSON in settings = empty book, no crash', () async {
      settings.rows[PersonPhones237.settingKey] = '{not json';
      await book.load(read: settings.read, write: settings.write);
      expect(book.isEmpty, isTrue);
    });
  });

  group('237 one chat query', () {
    test('where clause covers all phones, both directions, only with me', () {
      final w = LocalStore.phonesWhere237('me', {'phone-2', 'phone-1'});
      expect(w.where, '((sender_id=? AND recipient_id IN (?,?)) OR (sender_id IN (?,?) AND recipient_id=?))');
      expect(w.args, ['me', 'phone-2', 'phone-1', 'phone-2', 'phone-1', 'me']);
    });

    test('one phone = the same rows as before', () {
      final w = LocalStore.phonesWhere237('me', {'phone-1'});
      expect(w.args, ['me', 'phone-1', 'phone-1', 'me']);
    });
  });

  group('237 server contacts', () {
    test('past_device_ids is read (max 10); missing = empty', () {
      final c = AccountContact.fromJson({
        'user_id': 'u-ali',
        'device_id': 'now',
        'added_at': '',
        'past_device_ids': [for (var i = 0; i < 12; i++) 'p$i', ''],
      });
      expect(c.pastDeviceIds, hasLength(10));
      expect(c.pastDeviceIds.first, 'p0');
      expect(AccountContact.fromJson({'user_id': 'u', 'device_id': 'd', 'added_at': ''}).pastDeviceIds, isEmpty);
    });
  });

  group('237 Chats list', () {
    test('one row per person; the current phone wins even when the old one was seen later', () async {
      await book.remember('u-ali', 'ali-old', currentDeviceId: 'ali-new');
      final repo = _Repo([
        _device('ali-old', lastSeen: '2026-05-01T00:00:00Z'),
        _device('ali-new', lastSeen: '2026-01-01T00:00:00Z'),
      ], {'ali-old': 'u-ali', 'ali-new': 'u-ali'});
      final bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      await bloc.load();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(bloc.state.devices.map((d) => d.id), ['ali-new']);
    });
  });

  group('237 Clear / Delete chat', () {
    test('clears the messages of all his phones and they never come back', () async {
      final s = _Settings();
      await MessageDeleteBook.instance.load(read: s.read, write: s.write);
      await book.remember('u-ali', 'ali-old', currentDeviceId: 'ali-new');
      final store = _Store()
        ..person['ali-new'] = {'ali-new', 'ali-old'}
        ..person['ali-old'] = {'ali-new', 'ali-old'};
      final t = DateTime.utc(2026, 1, 1);
      store.direct['m1'] = _msg('m1', 'ali-old', 'me', t);
      store.direct['m2'] = _msg('m2', 'me', 'ali-new', t.add(const Duration(hours: 1)));
      store.direct['m3'] = _msg('m3', 'sara', 'me', t);
      final actions = MessageDeleteActions(store: store, deleteFile: (_) async {});
      final n = await actions.clearChat(chatId: 'ali-new', group: false, keepRow: true);
      expect(n, 2);
      expect(store.direct.keys, ['m3']);
      // An old copy from the old phone id is dropped (never brought back).
      expect(
          MessageDeleteBook.instance.dropsMessage(
              id: 'm1',
              chatKey: MessageDeleteBook.directKey('ali-old'),
              createdAt: t,
              senderId: 'ali-old'),
          isTrue);
    });
  });
}
