// Bundle 313 (D): get chats back from friends' phones - locked link only,
// friends only, only the chat of the two phones, only what is missing.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/messaging/data/services/chat_restore_313.dart';

class _Events implements PeerTransportContract {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements RestoreStore313 {
  _Store(this.selfId);
  @override
  final String? selfId;
  final friends = <String>{};
  final direct = <String, Map<String, dynamic>>{};
  final read = <String>{};
  final groups = <String, Map<String, String>>{}; // gid -> member -> joined
  final groupMsgs = <String, Map<String, dynamic>>{};
  final groupRead = <String>{};
  final settings = <String, String>{};

  @override
  Future<Set<String>> friendIds() async => {...friends};
  @override
  Future<bool> hasAnyMessage() async => direct.isNotEmpty || groupMsgs.isNotEmpty;
  @override
  Future<List<Map<String, dynamic>>> directChat(String peer) async => [
        for (final m in direct.values)
          if (m['sender_id'] == peer || m['recipient_id'] == peer) jsonDecode(jsonEncode(m)) as Map<String, dynamic>,
      ];
  @override
  Future<bool> hasDirect(String id) async => direct.containsKey(id);
  @override
  Future<bool> saveDirect(Map<String, dynamic> wire) async {
    final id = wire['id'] as String;
    if (direct.containsKey(id)) return false;
    direct[id] = wire;
    if (wire['sender_id'] != selfId) read.add(id);
    return true;
  }

  @override
  Future<List<String>> groupsWith(String peer) async => [
        for (final e in groups.entries)
          if (e.value.containsKey(selfId) && e.value.containsKey(peer)) e.key,
      ];
  @override
  Future<List<Map<String, dynamic>>> groupChat(String groupId) async => [
        for (final m in groupMsgs.values)
          if (m['group_id'] == groupId) Map<String, dynamic>.from(m),
      ];
  @override
  Future<String?> joinedAt(String groupId, String member) async => groups[groupId]?[member];
  @override
  Future<bool> hasGroup(String id) async => groupMsgs.containsKey(id);
  @override
  Future<bool> saveGroup(Map<String, dynamic> wire, {required bool mine}) async {
    final id = wire['id'] as String;
    if (groupMsgs.containsKey(id)) return false;
    groupMsgs[id] = wire;
    groupRead.add(id);
    return true;
  }

  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
}

/// Two (or more) phones; `locked` = which pairs can lock for each other.
class _Air {
  final phones = <String, _Phone>{};
  final unlocked = <String>{}; // phone ids nobody can lock for
  DateTime now = DateTime.utc(2026, 11, 16, 10);
}

class _Phone {
  _Phone(this.air, this.id) : store = _Store(id) {
    restore = ChatRestore313(
      transport: events,
      sendLocked: _send,
      store: store,
      sealCapable: (peer) => !air.unlocked.contains(peer) && !air.unlocked.contains(id),
      isNear: (peer) => near.contains(peer),
      allowFile: (f) async => allowed.add(f),
      pushFile: (msg, file, to) async {
        pushed.add('$msg|$file|$to');
        return true;
      },
      batteryOk: () => battery,
      nameOf: (peer) => peer.toUpperCase(),
      clock: () => air.now,
      gap: Duration.zero,
    );
    air.phones[id] = this;
  }

  final _Air air;
  final String id;
  final _Store store;
  final _Events events = _Events();
  late final ChatRestore313 restore;
  final near = <String>{};
  final allowed = <String>[];
  final pushed = <String>[];
  final sent = <Map<String, dynamic>>[];
  bool battery = true;

  Future<bool> _send(String to, Map<String, dynamic> payload) async {
    if (air.unlocked.contains(to) || air.unlocked.contains(id)) return false;
    sent.add({...payload, '_to': to});
    final other = air.phones[to];
    if (other != null) {
      other.restore.onEvent({
        'type': 'message',
        'sealed': true,
        'payload': jsonEncode({...jsonDecode(jsonEncode(payload)) as Map<String, dynamic>, 'sender_id': id}),
      });
    }
    return true;
  }

  List<String> sentTypes() => [for (final p in sent) p['type'] as String];
}

Future<void> _settle([int rounds = 40]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, dynamic> _m(String id, String from, String to, String body, {int min = 0, List<Map<String, dynamic>>? att}) => {
      'id': id,
      'sender_id': from,
      'recipient_id': to,
      'body': body,
      'created_at': DateTime.utc(2026, 11, 1, 9, min).toIso8601String(),
      'status': 'read',
      'server_seq': 0,
      'attachments': att ?? <Map<String, dynamic>>[],
    };

Map<String, dynamic> _voice(String id) => {
      'id': id,
      'original_name': '$id.m4a',
      'content_type': 'audio/mp4',
      'size': 1200,
      'local_path': '/data/user/0/com.sajjad.linkup/files/$id.m4a.enc',
    };

Map<String, dynamic> _photo(String id) => {
      'id': id,
      'original_name': '$id.jpg',
      'content_type': 'image/jpeg',
      'size': 9000,
      'local_path': '/data/user/0/com.sajjad.linkup/files/$id.jpg.enc',
    };

void main() {
  late _Air air;
  late _Phone kiran, sajjad, ayesha;

  setUp(() async {
    air = _Air();
    kiran = _Phone(air, 'kiran'); // reinstalled: lost the chats
    sajjad = _Phone(air, 'sajjad'); // the friend who still has them
    ayesha = _Phone(air, 'ayesha');
    kiran.store.friends.addAll({'sajjad', 'ayesha'});
    sajjad.store.friends.addAll({'kiran', 'ayesha'});
    ayesha.store.friends.addAll({'kiran', 'sajjad'});
    kiran.near.addAll({'sajjad', 'ayesha'});
    // Sajjad's phone: 4 messages with kiran (one is a voice note, one a
    // photo) and 1 with ayesha.
    sajjad.store.direct
      ..['k1'] = _m('k1', 'kiran', 'sajjad', 'Salam', min: 1)
      ..['k2'] = _m('k2', 'sajjad', 'kiran', 'Walaikum salam', min: 2)
      ..['k3'] = _m('k3', 'kiran', 'sajjad', '', min: 3, att: [_voice('v1')])
      ..['k4'] = _m('k4', 'sajjad', 'kiran', 'Look', min: 4, att: [_photo('p1')])
      ..['a1'] = _m('a1', 'ayesha', 'sajjad', 'private to sajjad', min: 5);
    for (final p in [kiran, sajjad, ayesha]) {
      await p.restore.start();
    }
  });

  tearDown(() async {
    for (final p in [kiran, sajjad, ayesha]) {
      await p.restore.stop();
    }
    ChatRestore313.lastDone.value = null;
  });

  group('asker gets the 1-to-1 chat back', () {
    test('only the missing messages of OUR chat travel, saved read, no paths', () async {
      kiran.store.direct['k1'] = _m('k1', 'kiran', 'sajjad', 'Salam', min: 1); // already here
      kiran.near.remove('ayesha');
      final asked = await kiran.restore.askNearbyFriends();
      expect(asked, 1);
      await _settle();
      expect(kiran.store.direct.keys.toSet(), {'k1', 'k2', 'k3', 'k4'});
      expect(kiran.store.direct.containsKey('a1'), isFalse, reason: "never someone else's chat");
      // what was asked for = only the 3 missing ids
      final want = kiran.sent.where((p) => p['type'] == ChatRestore313.wantType).single;
      expect((want['ids'] as List).toSet(), {'k2', 'k3', 'k4'});
      // no local file path ever leaves the giver
      for (final p in sajjad.sent) {
        expect(jsonEncode(p), isNot(contains('/data/user')), reason: p['type'] as String);
      }
      // sajjad's own messages are read on kiran's phone; kiran's own stay mine
      expect(kiran.store.read, containsAll(['k2', 'k4']));
      expect(kiran.store.read.contains('k3'), isFalse);
      expect(kiran.store.direct['k2']!['status'], 'delivered');
      expect(kiran.store.direct['k3']!['status'], 'read', reason: 'my own message keeps its ticks');
      expect(kiran.restore.status.value.phase, Restore313Status.finished);
      expect(ChatRestore313.lastDone.value!.count, 3);
      expect(ChatRestore313.lastDone.value!.peer, 'SAJJAD');
    });

    test('voice notes are asked one at a time; photos are not asked', () async {
      sajjad.store.direct['k5'] = _m('k5', 'sajjad', 'kiran', '', min: 6, att: [_voice('v2')]);
      kiran.near.remove('ayesha');
      await kiran.restore.askNearbyFriends();
      await _settle();
      final files = kiran.sent.where((p) => p['type'] == ChatRestore313.fileType).toList();
      expect(files.length, 1, reason: 'one at a time');
      expect(files.single['file'], 'v1');
      expect(kiran.allowed, ['v1']);
      expect(sajjad.pushed, ['k3|v1|kiran']);
      // the first file arrives -> the next one is asked
      kiran.events.controller.add({'type': 'file_received', 'file_id': 'v1', 'message_id': 'k3'});
      await _settle();
      final files2 = kiran.sent.where((p) => p['type'] == ChatRestore313.fileType).toList();
      expect([for (final f in files2) f['file']], ['v1', 'v2']);
      expect(sajjad.pushed, ['k3|v1|kiran', 'k5|v2|kiran']);
      expect(kiran.sent.any((p) => p['type'] == ChatRestore313.fileType && p['file'] == 'p1'), isFalse);
    });

    test('a giver never pushes a file of another chat or a photo', () async {
      kiran.near.remove('ayesha');
      await kiran.restore.askNearbyFriends();
      await _settle();
      final id = kiran.sent.first['id'];
      sajjad.pushed.clear();
      await sajjad.restore.handle(ChatRestore313.fileType, 'kiran', {'id': id, 'msg': 'k4', 'file': 'p1'});
      await sajjad.restore.handle(ChatRestore313.fileType, 'kiran', {'id': id, 'msg': 'a1', 'file': 'v1'});
      await sajjad.restore.handle(ChatRestore313.fileType, 'ayesha', {'id': id, 'msg': 'k3', 'file': 'v1'});
      expect(sajjad.pushed, isEmpty);
    });

    test('wrong ends, not asked for and duplicates are dropped on my side', () async {
      air.phones.remove('sajjad'); // nobody answers - I play the giver
      kiran.near.remove('ayesha');
      await kiran.restore.askNearbyFriends();
      await _settle();
      final id = kiran.sent.single['id'];
      await kiran.restore.handle(ChatRestore313.idsType, 'sajjad',
          {'id': id, 'chat': 'd', 'part': 0, 'parts': 1, 'ids': ['x1', 'x2', 'x2']});
      final want = kiran.sent.last;
      expect(want['type'], ChatRestore313.wantType);
      expect(want['ids'], ['x1', 'x2'], reason: 'a repeated id is asked once');
      await kiran.restore.handle(ChatRestore313.msgsType, 'sajjad', {
        'id': id,
        'chat': 'd',
        'items': [
          _m('x1', 'sajjad', 'ayesha', 'not our chat'),
          _m('x2', 'sajjad', 'kiran', 'ok'),
          _m('x2', 'sajjad', 'kiran', 'ok again'),
          _m('x3', 'sajjad', 'kiran', 'never asked'),
        ],
        'last': true,
      });
      expect(kiran.store.direct.keys.toSet(), {'x2'});
      expect(kiran.store.direct['x2']!['body'], 'ok');
      // a packet from another phone for this session is ignored
      await kiran.restore.handle(ChatRestore313.msgsType, 'ayesha',
          {'id': id, 'chat': 'd', 'items': [_m('x1', 'ayesha', 'kiran', 'x')], 'last': true});
      expect(kiran.store.direct.keys.toSet(), {'x2'});
    });

    test('many messages come in pages and batches (ids 300, want 50, 24 KB)', () async {
      for (var i = 0; i < 420; i++) {
        final id = 'n${i.toString().padLeft(3, '0')}';
        sajjad.store.direct[id] = _m(id, i.isEven ? 'kiran' : 'sajjad', i.isEven ? 'sajjad' : 'kiran', 'x' * 900);
      }
      kiran.near.remove('ayesha');
      await kiran.restore.askNearbyFriends();
      await _settle(3000);
      expect(kiran.store.direct.length, 424);
      expect(sajjad.sent.where((p) => p['type'] == ChatRestore313.idsType).length, 2);
      for (final p in kiran.sent.where((p) => p['type'] == ChatRestore313.wantType)) {
        expect((p['ids'] as List).length, lessThanOrEqualTo(50));
      }
      for (final p in sajjad.sent.where((p) => p['type'] == ChatRestore313.msgsType)) {
        expect(utf8.encode(jsonEncode(p['items'])).length, lessThanOrEqualTo(24 * 1024 + 2048));
      }
    });
  });

  group('giver rules', () {
    Map<String, dynamic> ask(String id) => {'type': ChatRestore313.askType, 'id': id, 'chats': ['d']};

    test('unlocked packet: nothing is given', () async {
      sajjad.restore.onEvent({
        'type': 'message',
        'sealed': false,
        'payload': jsonEncode({...ask('q1'), 'sender_id': 'kiran'}),
      });
      await _settle();
      expect(sajjad.sent, isEmpty);
    });

    test('a stranger key (not my friend\'s own saved key): nothing', () async {
      sajjad.restore.onEvent({
        'type': 'message',
        'sealed': true,
        'payload': jsonEncode({...ask('q1'), 'sender_id': 'kiran', '_locked_spk': 'abc'}),
      });
      await _settle();
      expect(sajjad.sent, isEmpty);
    });

    test('not a friend (or blocked = not in the list): nothing', () async {
      sajjad.store.friends.remove('kiran');
      await sajjad.restore.handle(ChatRestore313.askType, 'kiran', ask('q1'));
      expect(sajjad.sent, isEmpty);
    });

    test('a phone I cannot lock for gets nothing (never plain)', () async {
      air.unlocked.add('kiran');
      await sajjad.restore.handle(ChatRestore313.askType, 'kiran', ask('q1'));
      expect(sajjad.sent, isEmpty);
      expect(await kiran.restore.askNearbyFriends(), 0);
      expect(kiran.sent, isEmpty);
    });

    test('battery 10% or less: nothing', () async {
      sajjad.battery = false;
      await sajjad.restore.handle(ChatRestore313.askType, 'kiran', ask('q1'));
      expect(sajjad.sent, isEmpty);
    });

    test('one session per friend per 10 min', () async {
      air.phones.remove('kiran');
      await sajjad.restore.handle(ChatRestore313.askType, 'kiran', ask('q1'));
      final n = sajjad.sent.length;
      expect(n, greaterThan(0));
      air.now = air.now.add(const Duration(minutes: 5));
      await sajjad.restore.handle(ChatRestore313.askType, 'kiran', ask('q2'));
      expect(sajjad.sent.length, n);
      air.now = air.now.add(const Duration(minutes: 6));
      await sajjad.restore.handle(ChatRestore313.askType, 'kiran', ask('q3'));
      expect(sajjad.sent.length, greaterThan(n));
    });

    test('a group I am not in with the asker: no messages', () async {
      air.phones.remove('kiran');
      sajjad.store.groups['g2'] = {'sajjad': '2026-01-01T00:00:00Z', 'ayesha': '2026-01-01T00:00:00Z'};
      sajjad.store.groupMsgs['gm1'] = {
        'id': 'gm1',
        'group_id': 'g2',
        'sender_id': 'ayesha',
        'body': 'secret group',
        'created_at': '2026-11-01T09:00:00Z',
      };
      await sajjad.restore.handle(ChatRestore313.askType, 'kiran',
          {'type': ChatRestore313.askType, 'id': 'q1', 'chats': ['g2']});
      final ids = sajjad.sent.single;
      expect(ids['type'], ChatRestore313.idsType);
      expect(ids['ids'], isEmpty);
    });

    test('an unknown restore type is ignored (no crash)', () async {
      await sajjad.restore.handle('restore_new_999', 'kiran', {'id': 'q'});
      sajjad.restore.onEvent({
        'type': 'message',
        'sealed': true,
        'payload': jsonEncode({'type': 'restore_new_999', 'sender_id': 'kiran'}),
      });
      await _settle();
      expect(sajjad.sent, isEmpty);
    });
  });

  group('groups (both members)', () {
    test('only messages from my join date; read; nothing from a group I left', () async {
      const joined = '2026-11-01T09:30:00.000Z';
      sajjad.store.groups['g1'] = {'sajjad': '2026-10-01T00:00:00Z', 'kiran': joined, 'ayesha': joined};
      kiran.store.groups['g1'] = {'sajjad': '2026-10-01T00:00:00Z', 'kiran': joined, 'ayesha': joined};
      Map<String, dynamic> gm(String id, String from, int min) => {
            'id': id,
            'group_id': 'g1',
            'sender_id': from,
            'body': 'hi $id',
            'created_at': DateTime.utc(2026, 11, 1, 9, min).toIso8601String(),
            'attachments': <Map<String, dynamic>>[],
          };
      sajjad.store.groupMsgs
        ..['g-before'] = gm('g-before', 'sajjad', 10)
        ..['g-after1'] = gm('g-after1', 'ayesha', 40)
        ..['g-after2'] = gm('g-after2', 'kiran', 45);
      kiran.near.remove('ayesha');
      final changed = <String>[];
      final sub = GroupChangeHub.instance.changes.listen(changed.add);
      addTearDown(sub.cancel);
      await kiran.restore.askNearbyFriends();
      await _settle();
      final ask = kiran.sent.first;
      expect(ask['chats'], ['d', 'g1']);
      expect(changed, contains('g1'), reason: 'the group list reads again');
      expect(kiran.store.groupMsgs.keys.toSet(), {'g-after1', 'g-after2'});
      expect(kiran.store.groupRead, containsAll(['g-after1', 'g-after2']));
    });
  });

  group('when it runs', () {
    test('fresh install (no messages): armed for 30 days; an update is not', () async {
      final fresh = _Store('new');
      expect(await ChatRestore313.armAtLaunch(fresh, now: air.now), isTrue);
      final until = int.parse(fresh.settings[ChatRestore313.untilKey]!);
      expect(DateTime.fromMillisecondsSinceEpoch(until, isUtc: true), air.now.add(const Duration(days: 30)));
      // the next start does not arm again (even with no messages yet)
      expect(await ChatRestore313.armAtLaunch(fresh, now: air.now.add(const Duration(days: 1))), isFalse);
      expect(fresh.settings[ChatRestore313.untilKey], '$until');

      final updated = _Store('old')..direct['m'] = _m('m', 'old', 'x', 'hi');
      expect(await ChatRestore313.armAtLaunch(updated, now: air.now), isFalse);
      expect(updated.settings[ChatRestore313.untilKey], '0');
    });

    test('armed: a friend who comes near is asked once; done = never again', () async {
      await ChatRestore313.armAtLaunch(kiran.store, now: air.now);
      await kiran.restore.start();
      expect(kiran.restore.armed, isTrue);
      kiran.events.controller.add({'type': 'peer_connected', 'peer_id': 'sajjad'});
      await _settle();
      expect(kiran.store.direct.length, 4);
      final asks = kiran.sentTypes().where((t) => t == ChatRestore313.askType).length;
      expect(asks, 1);
      kiran.events.controller.add({'type': 'peer_discovered', 'peer_id': 'sajjad'});
      air.now = air.now.add(const Duration(minutes: 11));
      kiran.events.controller.add({'type': 'route_recovered', 'peer_id': 'sajjad'});
      await _settle();
      expect(kiran.sentTypes().where((t) => t == ChatRestore313.askType).length, asks);
      // a stranger who comes near is never asked
      kiran.events.controller.add({'type': 'peer_connected', 'peer_id': 'stranger'});
      await _settle();
      expect(kiran.sent.where((p) => p['_to'] == 'stranger'), isEmpty);
    });

    test('no answer (old app): not asked again at once', () async {
      await ChatRestore313.armAtLaunch(kiran.store, now: air.now);
      await kiran.restore.start();
      air.phones.remove('sajjad'); // an old app: says nothing
      kiran.events.controller.add({'type': 'peer_connected', 'peer_id': 'sajjad'});
      await _settle();
      expect(kiran.sentTypes(), [ChatRestore313.askType]);
      kiran.events.controller.add({'type': 'peer_connected', 'peer_id': 'sajjad'});
      await _settle();
      expect(kiran.sentTypes(), [ChatRestore313.askType]);
    });

    test('not armed (normal update): nobody is asked by itself', () async {
      kiran.store.direct['m'] = _m('m', 'kiran', 'x', 'hi');
      await ChatRestore313.armAtLaunch(kiran.store, now: air.now);
      await kiran.restore.start();
      expect(kiran.restore.armed, isFalse);
      kiran.events.controller.add({'type': 'peer_connected', 'peer_id': 'sajjad'});
      await _settle();
      expect(kiran.sent, isEmpty);
    });

    test('after 30 days it stops by itself', () async {
      await ChatRestore313.armAtLaunch(kiran.store, now: air.now);
      air.now = air.now.add(const Duration(days: 31));
      await kiran.restore.start();
      expect(kiran.restore.armed, isFalse);
      kiran.events.controller.add({'type': 'peer_connected', 'peer_id': 'sajjad'});
      await _settle();
      expect(kiran.sent, isEmpty);
    });

    test('Settings button with nobody near: says so, asks nobody', () async {
      kiran.near.clear();
      expect(await kiran.restore.askNearbyFriends(), 0);
      expect(kiran.restore.status.value.phase, Restore313Status.noneNear);
      expect(kiran.sent, isEmpty);
    });
  });
}
