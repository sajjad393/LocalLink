// Bundle 313 (D): the phone storage side of "get chats back" (StoreRestore313).
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/messaging/data/services/chat_restore_store_313.dart';

class _LS extends Fake implements LocalStore {
  @override
  String? deviceId = 'me';
  final devices = <Device>[];
  final blocked = <String>{};
  final messages = <String, Message>{};
  final dropped = <String>{}; // deleted / cleared on this phone
  final read = <String>[];
  final groupList = <LocalGroup>[];
  final members = <String, List<Map<String, dynamic>>>{};
  final groupRows = <String, Map<String, dynamic>>{};
  bool any = false;

  @override
  Future<List<Device>> localDevices() async => devices;
  @override
  Future<Set<String>> blockedPeerIds() async => blocked;
  @override
  Future<bool> hasAnyMessage313() async => any;
  @override
  Future<Message?> messageById(String id) async => messages[id];
  @override
  Future<void> saveMessage(Message message) async {
    if (dropped.contains(message.id)) return;
    messages[message.id] = message;
  }

  @override
  Future<void> markMessageRead(String id) async => read.add(id);
  @override
  Future<List<Message>> messagesFor(String otherId) async =>
      [for (final m in messages.values) if (m.senderId == otherId || m.recipientId == otherId) m];
  @override
  Future<List<LocalGroup>> localGroups() async => groupList;
  @override
  Future<List<Map<String, dynamic>>> groupMembers(String groupId) async => members[groupId] ?? const [];
  @override
  Future<GroupMessage?> groupMessageById(String id) async => groupRows[id] == null
      ? null
      : GroupMessage(
          id: id,
          groupId: groupRows[id]!['group_id'] as String,
          senderId: groupRows[id]!['sender_id'] as String,
          body: groupRows[id]!['body'] as String,
          createdAt: groupRows[id]!['created_at'] as String);
  @override
  Future<void> saveGroupMessage(Map<String, dynamic> m) async => groupRows[m['id'] as String] = m;
}

Device _d(String id) => Device.fromJson({'id': id, 'name': id});

Map<String, dynamic> _wire(String id, String from, String to) => {
      'id': id,
      'sender_id': from,
      'recipient_id': to,
      'body': 'hi',
      'created_at': '2026-11-01T09:00:00.000Z',
      'status': 'delivered',
      'server_seq': 0,
      'attachments': <Object>[],
    };

void main() {
  late _LS ls;
  late StoreRestore313 store;

  setUp(() {
    ls = _LS();
    store = StoreRestore313(ls);
  });

  test('friends = the lock\'s list: known phones, not blocked, not me', () async {
    ls.devices.addAll([_d('me'), _d('kiran'), _d('ayesha'), _d('bad')]);
    ls.blocked.add('bad');
    expect(await store.friendIds(), {'kiran', 'ayesha'});
  });

  test('a restored message is saved once; theirs is read, mine untouched', () async {
    expect(await store.saveDirect(_wire('m1', 'kiran', 'me')), isTrue);
    expect(await store.saveDirect(_wire('m1', 'kiran', 'me')), isFalse);
    expect(await store.saveDirect(_wire('m2', 'me', 'kiran')), isTrue);
    expect(ls.read, ['m1']);
    expect(await store.hasDirect('m1'), isTrue);
  });

  test('a message deleted / cleared on this phone does not come back', () async {
    ls.dropped.add('m3');
    expect(await store.saveDirect(_wire('m3', 'kiran', 'me')), isFalse);
    expect(ls.messages.containsKey('m3'), isFalse);
    expect(ls.read, isEmpty);
  });

  test('groups with a friend: active and both members only', () async {
    ls.groupList.addAll([
      LocalGroup.fromJson({'id': 'g1', 'state': 'active'}),
      LocalGroup.fromJson({'id': 'g2', 'state': 'active'}),
      LocalGroup.fromJson({'id': 'g3', 'state': 'left'}),
    ]);
    ls.members['g1'] = [
      {'device_id': 'me', 'joined_at': 'a'},
      {'device_id': 'kiran', 'joined_at': 'b'},
    ];
    ls.members['g2'] = [
      {'device_id': 'me'},
      {'device_id': 'ayesha'},
    ];
    ls.members['g3'] = [
      {'device_id': 'me'},
      {'device_id': 'kiran'},
    ];
    expect(await store.groupsWith('kiran'), ['g1']);
    expect(await store.joinedAt('g1', 'kiran'), 'b');
  });

  test('a restored group message is read; my own is never sent again', () async {
    final theirs = {'id': 'gm1', 'group_id': 'g1', 'sender_id': 'kiran', 'body': 'x', 'created_at': 't'};
    final mine = {'id': 'gm2', 'group_id': 'g1', 'sender_id': 'me', 'body': 'y', 'created_at': 't'};
    expect(await store.saveGroup(theirs, mine: false), isTrue);
    expect(await store.saveGroup(mine, mine: true), isTrue);
    expect(await store.saveGroup(theirs, mine: false), isFalse);
    expect(ls.groupRows['gm1']!['is_read'], 1);
    expect(ls.groupRows['gm1']!.containsKey('nearby_sent'), isFalse);
    expect(ls.groupRows['gm2']!['nearby_sent'], 1);
  });

  test('fresh install check reads the store', () async {
    expect(await store.hasAnyMessage(), isFalse);
    ls.any = true;
    expect(await store.hasAnyMessage(), isTrue);
  });
}
