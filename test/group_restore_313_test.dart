import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/group_event.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';

// Bundle 313 (D4): a member who reinstalled says `r:1` on its group_have;
// the other member gives OLDER messages (no 7-day signed copy) from its group
// message table: words only, from the join date, at most 2000, saved silently.
// (Fakes copied from groups_g4_test.dart.)

String _key(String who, String kind) => '$who-$kind-'.padRight(43, 'x');

// ------------------------------------------------------------ fakes ---

class _Store implements GroupNearbyStore {
  _Store(this.selfId);
  @override
  final String selfId;
  final rows = <String, Map<String, dynamic>>{};
  final members = <String, List<Map<String, dynamic>>>{};
  final messages = <String, GroupMessage>{};
  final nearbySent = <String>{};
  final friends = <String, GroupFriendKeys>{};
  final blocked = <String>{};
  final outbox = <String, Map<String, Object?>>{};
  final inviteRows = <String, Map<String, dynamic>>{};

  @override
  Future<String> selfName() async => selfId.toUpperCase();
  @override
  Future<LocalGroup?> group(String gid) async =>
      rows[gid] == null ? null : LocalGroup.fromJson(rows[gid]!);
  @override
  Future<List<LocalGroup>> groups() async =>
      [for (final g in rows.values) LocalGroup.fromJson(g)];
  @override
  Future<void> saveGroupRow(Map<String, dynamic> row) async {
    final id = row['id'].toString();
    rows[id] = {...?rows[id], ...row};
  }

  @override
  Future<void> setState(String gid, String state) async =>
      rows[gid]?['state'] = state;
  @override
  Future<void> setOrigin(String gid, String origin) async =>
      rows[gid]?['origin'] = origin;
  @override
  Future<void> saveCard(String gid, String json, int version,
      {String? origin}) async {
    rows[gid]!['card_json'] = json;
    rows[gid]!['card_version'] = version;
    if (origin != null) rows[gid]!['origin'] = origin;
  }

  @override
  Future<String> cardJson(String gid) async =>
      rows[gid]?['card_json']?.toString() ?? '';
  @override
  Future<void> replaceMembers(
          String gid, List<Map<String, dynamic>> rows) async =>
      members[gid] = rows;
  @override
  Future<Set<String>> memberIds(String gid) async =>
      {for (final r in members[gid] ?? const []) r['device_id'].toString()};
  @override
  Future<void> removeMember(String gid, String id) async =>
      members[gid]?.removeWhere((r) => r['device_id'] == id);
  @override
  Future<bool> messageExists(String id) async => messages.containsKey(id);
  @override
  Future<void> saveMessage(Map<String, dynamic> row) async {}
  @override
  Future<void> markNearbySent(String id) async => nearbySent.add(id);
  @override
  Future<GroupFriendKeys?> friend(String deviceId) async =>
      blocked.contains(deviceId) ? null : friends[deviceId];
  @override
  Future<bool> isBlocked(String deviceId) async => blocked.contains(deviceId);
  @override
  Future<void> putOutbox(Map<String, Object?> row) async =>
      outbox['${row['id']}|${row['member_id']}'] = Map.of(row);
  @override
  Future<List<Map<String, dynamic>>> dueOutbox(int nowMs) async => [
        for (final r in outbox.values)
          if ((r['next_at'] as int) <= nowMs) Map<String, dynamic>.from(r)
      ]..sort(
          (a, b) => (a['created_at'] as int).compareTo(b['created_at'] as int));
  @override
  Future<List<Map<String, dynamic>>> outboxFor(String gid) async => [
        for (final r in outbox.values)
          if (r['group_id'] == gid) Map<String, dynamic>.from(r)
      ];
  @override
  Future<void> markTry(String id, String member, int tries, int nextAt) async {
    final r = outbox['$id|$member'];
    if (r == null) return;
    r['tries'] = tries;
    r['next_at'] = nextAt;
  }

  @override
  Future<void> removeOutbox(String id, String member) async =>
      outbox.remove('$id|$member');
  @override
  Future<void> setInvite(
          String gid, String member, String state, int atMs) async =>
      inviteRows['$gid|$member'] = {
        'group_id': gid,
        'member_id': member,
        'state': state,
        'at': atMs
      };
  @override
  Future<List<Map<String, dynamic>>> invites(String gid) async => [
        for (final r in inviteRows.values)
          if (r['group_id'] == gid) r
      ];
}

class _Copies implements GroupCopyStore {
  final rows = <String, GroupCopy>{};
  @override
  Future<void> putCopy(GroupCopy copy) async =>
      rows.putIfAbsent(copy.id, () => copy);
  @override
  Future<List<GroupCopy>> copies(String gid, {int limit = 500}) async => ([
        for (final c in rows.values)
          if (c.gid == gid) c
      ]..sort((a, b) => b.keptAt.compareTo(a.keptAt)))
          .take(limit)
          .toList();
  @override
  Future<void> purgeCopies(int olderThanMs) async =>
      rows.removeWhere((_, c) => c.keptAt < olderThanMs);
}

class _Joins implements GroupJoinStore {
  final rows = <String, Map<String, dynamic>>{};
  final friends = <String>[];
  @override
  String get selfUsername => 'me';
  @override
  Future<List<String>> friendIds() async => friends;
  @override
  Future<void> putJoin(String kind, String gid, String member, String data,
          int atMs) async =>
      rows['$kind|$gid|$member'] = {
        'kind': kind,
        'group_id': gid,
        'member_id': member,
        'data': data,
        'at': atMs
      };
  @override
  Future<List<Map<String, dynamic>>> joins(String kind, {String? gid}) async =>
      [
        for (final r in rows.values)
          if (r['kind'] == kind && (gid == null || r['group_id'] == gid))
            Map.of(r)
      ];
  @override
  Future<void> removeJoin(String kind, String gid, {String? member}) async =>
      rows.removeWhere((_, r) =>
          r['kind'] == kind &&
          r['group_id'] == gid &&
          (member == null || r['member_id'] == member));
}

/// Phones near each other; [away] phones lose what is sent to them.
class _Air {
  final phones = <String, _Phone>{};
  final away = <String>{};
  int now = 1000000;
  final _queue = <Future<void> Function()>[];

  Future<void> pump() async {
    for (var round = 0; round < 50 && _queue.isNotEmpty; round++) {
      final work = List.of(_queue);
      _queue.clear();
      for (final w in work) {
        await w();
      }
    }
  }
}

class _Phone {
  _Phone(this.air, this.id) : store = _Store(id) {
    service = GroupNearbyService(
      store: store,
      keys: GroupCardKeys(
        sign: (text) async => 'S:${_key(id, 'sign')}:${text.hashCode}',
        verify: (text, sig, key) async => sig == 'S:$key:${text.hashCode}',
        ownSignKey: () async => _key(id, 'sign'),
        ownSealKey: () async => _key(id, 'seal'),
      ),
      send: _send,
      events: const Stream<Map<String, dynamic>>.empty(),
      onMessage: (m) async {
        store.messages[m.id] = m;
        got.add(m);
      },
      onSentNearby: (id) async => sentNearby.add(id),
      postToServer: (gid, body) async => serverPosts.add(body),
      copies: copyStore,
      catchUpAllowed: () => batteryOk,
      joins: joinStore,
      nowMs: () => air.now,
    );
    air.phones[id] = this;
  }

  final _Air air;
  final String id;
  final _Store store;
  final _Copies copyStore = _Copies();
  final _Joins joinStore = _Joins();
  bool batteryOk = true;
  late final GroupNearbyService service;
  final got = <GroupMessage>[];
  final sentNearby = <String>[];
  final sentTo = <String>[];
  final serverPosts = <String>[];

  void befriend(_Phone other) {
    store.friends[other.id] = GroupFriendKeys(
        id: other.id,
        name: other.id.toUpperCase(),
        seal: _key(other.id, 'seal'),
        sign: _key(other.id, 'sign'));
  }

  Future<bool> _send({
    required String recipientId,
    required String theirIdentityKey,
    required Map<String, dynamic> payload,
  }) async {
    sentTo.add('$recipientId:${payload['type']}');
    expect(theirIdentityKey, _key(recipientId, 'seal'),
        reason: 'locked with the member key');
    final to = air.phones[recipientId];
    if (to == null || air.away.contains(recipientId)) return true;
    final stranger = !to.store.friends.containsKey(id);
    air._queue.add(() => to.service.handlePacket({
          ...jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
          'sender_id': id,
          'recipient_id': recipientId,
          if (stranger) '_locked_spk': _key(id, 'seal'),
        }));
    return true;
  }
}

Future<void> _settle(_Air air) async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
    await air.pump();
  }
}

// 2026-11-03 10:00 UTC
const _t0 = 1793700000000;

void main() {
  late _Air air;
  late _Phone sajjad, ali, sara;
  final restored = <GroupMessage>[];
  var saraRestoring = true;

  String at(int minutes) =>
      DateTime.fromMillisecondsSinceEpoch(_t0 + minutes * 60000, isUtc: true).toIso8601String();

  List<Map<String, dynamic>> table(_Phone p, String gid) => [
        for (final m in p.store.messages.values)
          if (m.groupId == gid)
            {
              'id': m.id,
              'group_id': m.groupId,
              'sender_id': m.senderId,
              'body': m.body,
              'created_at': m.createdAt,
              'attachments': [for (final a in m.attachments) a.toJson()],
            },
      ]..sort((a, b) => (a['created_at'] as String).compareTo(b['created_at'] as String));

  setUp(() async {
    restored.clear();
    saraRestoring = true;
    air = _Air()..now = _t0;
    sajjad = _Phone(air, 'sajjad');
    ali = _Phone(air, 'ali');
    sara = _Phone(air, 'sara');
    sajjad.befriend(ali);
    sajjad.befriend(sara);
    ali.befriend(sajjad);
    sara.befriend(sajjad);
    ali.service.olderMessages313 = (gid) async => table(ali, gid);
    ali.service.restoreGap313 = Duration.zero;
    sara.service.restoring313 = () => saraRestoring;
    sara.service.saveRestored313 = (m) async {
      sara.store.messages[m.id] = m;
      restored.add(m);
      return true;
    };
    await sajjad.service.createGroup(gid: 'g-1', name: 'Office', memberIds: ['ali', 'sara'], origin: 'nearby');
    await _settle(air);
  });

  /// Messages 8+ days old (their signed copies are gone), then Sara
  /// reinstalls: her messages are wiped.
  Future<void> oldChatThenReinstall() async {
    await sajjad.service.fanOut('g-1', 'm1', 'Lunch?', at(1));
    await sara.service.fanOut('g-1', 'm2', 'Yes, 1 pm', at(2));
    await _settle(air);
    expect(ali.store.messages.keys, containsAll(['m1', 'm2']));
    air.now += const Duration(days: 8).inMilliseconds;
    await ali.service.catchUpWith('sajjad'); // purges the old copies
    ali.copyStore.rows.clear();
    sara.copyStore.rows.clear();
    sara.store.messages.clear();
    sara.got.clear();
    sara.sentTo.clear();
    ali.sentTo.clear();
    air.away.add('sajjad');
  }

  test('r:1 on group_have only while getting chats back', () async {
    saraRestoring = false;
    await sara.service.catchUpWith('ali');
    await _settle(air);
    expect(restored, isEmpty);
    expect(ali.sentTo.where((s) => s == 'sara:group_give'), isEmpty);
  });

  test('older messages come back (mine too), read and silent, no ack, no copy', () async {
    await oldChatThenReinstall();
    final changed = <String>[];
    final sub = GroupChangeHub.instance.changes.listen(changed.add);
    addTearDown(sub.cancel);
    await sara.service.catchUpWith('ali');
    await _settle(air);
    expect(restored.map((m) => m.id).toSet(), {'m1', 'm2'});
    expect(changed, contains('g-1'), reason: 'the group list reads again');
    expect(restored.firstWhere((m) => m.id == 'm2').senderId, 'sara', reason: 'my own old message');
    expect(restored.firstWhere((m) => m.id == 'm1').body, 'Lunch?');
    expect(sara.got, isEmpty, reason: 'not a new message (no notification path)');
    expect(sara.sentTo.where((s) => s.endsWith(':group_ack')), isEmpty);
    expect(sara.copyStore.rows, isEmpty, reason: 'no signature = never passed on');
    expect(ali.sentTo, contains('sara:group_give'));
  });

  test('not getting chats back: r:1 items are refused', () async {
    await oldChatThenReinstall();
    saraRestoring = false;
    await sara.service.handlePacket({
      'type': 'group_give',
      'gid': 'g-1',
      'sender_id': 'ali',
      '_locked_spk': _key('ali', 'seal'),
      'items': [
        {'id': 'm1', 'w': 'sajjad', 'c': at(1), 'b': 'Lunch?', 'r': 1},
      ],
    });
    expect(restored, isEmpty);
    expect(sara.store.messages, isEmpty);
  });

  test('a stranger key that is not the member key: refused', () async {
    await oldChatThenReinstall();
    await sara.service.handlePacket({
      'type': 'group_give',
      'gid': 'g-1',
      'sender_id': 'ali',
      '_locked_spk': _key('zzz', 'seal'),
      'items': [
        {'id': 'm1', 'w': 'sajjad', 'c': at(1), 'b': 'Lunch?', 'r': 1},
      ],
    });
    expect(restored, isEmpty);
  });

  test('a writer who is not a member, files and system lines: refused', () async {
    await oldChatThenReinstall();
    await sara.service.handlePacket({
      'type': 'group_give',
      'gid': 'g-1',
      'sender_id': 'ali',
      '_locked_spk': _key('ali', 'seal'),
      'items': [
        {'id': 'x1', 'w': 'nobody', 'c': at(3), 'b': 'fake', 'r': 1},
        {'id': 'x2', 'w': 'ali', 'c': at(3), 'b': 'photo', 'r': 1, 'a': [<String, Object>{'id': 'f'}]},
        {'id': 'x3', 'w': 'ali', 'c': at(3), 'b': 'llev:v1:{}', 'r': 1},
        {'id': 'x4', 'w': 'ali', 'c': at(3), 'b': 'llgc:v1:abc', 'r': 1},
        {'id': 'x5', 'w': 'ali', 'c': at(3), 'b': 'ok', 'r': 1},
      ],
    });
    expect(restored.map((m) => m.id), ['x5']);
  });

  test('the giver sends nothing older than the member joined; no files or lines', () async {
    final zara = _Phone(air, 'zara');
    sajjad.befriend(zara);
    zara.befriend(sajjad);
    final zaraGot = <GroupMessage>[];
    zara.service.restoring313 = () => true;
    zara.service.saveRestored313 = (m) async {
      zaraGot.add(m);
      return true;
    };
    await sajjad.service.fanOut('g-1', 'old', 'Before Zara', at(1));
    await _settle(air);
    air.now = _t0 + 10 * 60000;
    await sajjad.service.addMember('g-1', 'zara');
    await _settle(air);
    await sajjad.service.fanOut('g-1', 'new', 'After Zara', at(11));
    await _settle(air);
    // Ali's table also has a system line and a file message.
    ali.store.messages['line'] = GroupMessage(
        id: 'line', groupId: 'g-1', senderId: 'sajjad', body: const GroupEvent(kind: 'leave', by: 'x').encode(), createdAt: at(12));
    air.now += const Duration(days: 8).inMilliseconds;
    ali.copyStore.rows.clear();
    zara.copyStore.rows.clear();
    zara.store.messages.clear(); // Zara reinstalled
    air.away.add('sajjad');
    await zara.service.catchUpWith('ali');
    await _settle(air);
    final ids = zaraGot.map((m) => m.id).toSet();
    expect(ids, contains('new'));
    expect(ids, isNot(contains('old')));
    expect(ids, isNot(contains('line')));
  });

  test('at most 2000 older messages per group and ask (the newest)', () async {
    for (var i = 0; i < 2100; i++) {
      final id = 'b${i.toString().padLeft(4, '0')}';
      ali.store.messages[id] = GroupMessage(
          id: id,
          groupId: 'g-1',
          senderId: 'sajjad',
          body: 'n$i',
          createdAt: DateTime.fromMillisecondsSinceEpoch(_t0 + 60000 + i * 1000, isUtc: true).toIso8601String());
    }
    air.now += const Duration(days: 8).inMilliseconds;
    air.away.add('sajjad');
    await sara.service.catchUpWith('ali');
    await _settle(air);
    expect(restored.length, GroupNearbyService.restoreMax313);
    expect(restored.any((m) => m.id == 'b0000'), isFalse);
    expect(restored.any((m) => m.id == 'b2099'), isTrue);
  });

  test('battery 10% or less on the giver: nothing older is given', () async {
    await oldChatThenReinstall();
    ali.batteryOk = false;
    await sara.service.catchUpWith('ali');
    await _settle(air);
    expect(restored, isEmpty);
  });
}
