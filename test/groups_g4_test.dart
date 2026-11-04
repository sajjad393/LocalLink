import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/group_event.dart';
import 'package:locallink/core/models/group_card.dart';
import 'package:locallink/core/models/group_join_code.dart';
import 'package:locallink/core/services/locallink_api.dart'
    show GroupActionException;
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';

// Bundle G4: catch-up between members (signed copies, 7 days), card
// catch-up, new members only from their join, battery stop.

String _key(String who, String kind) => '$who-$kind-'.padRight(43, 'x');

GroupCardMember _m(String id, String role) => GroupCardMember(
    id: id,
    name: id.toUpperCase(),
    role: role,
    seal: _key(id, 'seal'),
    sign: _key(id, 'sign'));

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
  group('catch-up between members (G4)', () {
    late _Air air;
    late _Phone sajjad, ali, sara;

    setUp(() {
      air = _Air()..now = _t0;
      sajjad = _Phone(air, 'sajjad');
      ali = _Phone(air, 'ali');
      sara = _Phone(air, 'sara');
      sajjad.befriend(ali);
      sajjad.befriend(sara);
      ali.befriend(sajjad);
      sara.befriend(sajjad);
    });

    Future<void> make() async {
      await sajjad.service.createGroup(
          gid: 'g-1',
          name: 'Office',
          memberIds: ['ali', 'sara'],
          origin: 'nearby');
      await _settle(air);
    }

    String at(int minutes) =>
        DateTime.fromMillisecondsSinceEpoch(_t0 + minutes * 60000, isUtc: true)
            .toIso8601String();

    test('messages are signed by the writer and kept as copies', () async {
      await make();
      await sajjad.service.fanOut('g-1', 'm1', 'Lunch?', at(1));
      await _settle(air);
      expect(ali.got.last.body, 'Lunch?');
      expect(sajjad.copyStore.rows.keys, contains('m1'));
      expect(ali.copyStore.rows['m1']!.writer, 'sajjad');
      expect(ali.copyStore.rows['m1']!.sig, isNotEmpty);
    });

    test('Sara missed a message: Ali gives it when they meet', () async {
      await make();
      air.away.add('sara');
      await sajjad.service.fanOut('g-1', 'm1', 'Lunch?', at(1));
      await _settle(air);
      expect(sara.got.where((m) => m.id == 'm1'), isEmpty);
      // Sajjad is gone for good; Sara meets Ali.
      air.away
        ..remove('sara')
        ..add('sajjad');
      await ali.service.catchUpWith('sara');
      await _settle(air);
      final got = sara.got.where((m) => m.id == 'm1').single;
      expect(got.senderId, 'sajjad', reason: 'shown as the writer');
      expect(got.body, 'Lunch?');
      expect(ali.sentTo, contains('sara:group_give'));
      // and Sajjad gets "got it" from Sara when he is back
      expect(sara.sentTo, contains('sajjad:group_ack'));
    });

    test('a changed copy is refused (bad signature)', () async {
      await make();
      await sajjad.service.fanOut('g-1', 'm1', 'Lunch?', at(1));
      await _settle(air);
      await sara.service.handlePacket({
        'type': 'group_give',
        'gid': 'g-1',
        'sender_id': 'ali',
        '_locked_spk': _key('ali', 'seal'),
        'items': [
          {
            'id': 'm2',
            'w': 'sajjad',
            'c': at(2),
            'b': 'Changed text',
            's': ali.copyStore.rows['m1']!.sig,
          }
        ],
      });
      expect(sara.got.where((m) => m.id == 'm2'), isEmpty);
    });

    test('a plain message must come from its writer', () async {
      await make();
      await sara.service.handlePacket({
        'type': 'group_msg',
        'gid': 'g-1',
        'id': 'mx',
        'body': 'fake',
        'created_at': at(3),
        'w': 'sajjad',
        'sig': 'x',
        'sender_id': 'ali',
        '_locked_spk': _key('ali', 'seal'),
      });
      expect(sara.got.where((m) => m.id == 'mx'), isEmpty);
    });

    test('nothing to give when both have the same', () async {
      await make();
      await sajjad.service.fanOut('g-1', 'm1', 'Lunch?', at(1));
      await _settle(air);
      ali.sentTo.clear();
      sara.sentTo.clear();
      await ali.service.catchUpWith('sara');
      await _settle(air);
      expect(ali.sentTo, contains('sara:group_have'));
      expect(ali.sentTo, isNot(contains('sara:group_give')));
      expect(sara.sentTo, isNot(contains('ali:group_give')));
    });

    test('at most once per 2 min per member and group', () async {
      await make();
      ali.sentTo.clear();
      await ali.service.catchUpWith('sara');
      await ali.service.catchUpWith('sara');
      await _settle(air);
      expect(ali.sentTo.where((s) => s == 'sara:group_have').length, 1);
      air.now += 121000;
      await ali.service.catchUpWith('sara');
      await _settle(air);
      expect(ali.sentTo.where((s) => s == 'sara:group_have').length, 2);
    });

    test('battery 10% or less: no catch-up', () async {
      await make();
      ali.batteryOk = false;
      ali.sentTo.clear();
      await ali.service.catchUpWith('sara');
      await _settle(air);
      expect(ali.sentTo, isEmpty);
    });

    test('Sara missed "Sajjad added you": she gets the card from Ali',
        () async {
      air.away.add('sara');
      await make();
      expect(await sara.store.group('g-1'), isNull);
      air.away
        ..remove('sara')
        ..add('sajjad');
      // Sajjad's queue is not delivering (he is gone); Ali meets Sara.
      await ali.service.catchUpWith('sara');
      await _settle(air);
      expect(sara.sentTo, contains('ali:group_need'));
      expect((await sara.store.group('g-1'))!.isActive, isTrue);
    });

    test('a new member gets only messages from when they joined', () async {
      final zara = _Phone(air, 'zara');
      sajjad.befriend(zara);
      zara.befriend(sajjad);
      await make();
      await sajjad.service.fanOut('g-1', 'old', 'Before Zara', at(1));
      await _settle(air);
      air.now = _t0 + 10 * 60000;
      await sajjad.service.addMember('g-1', 'zara');
      await _settle(air);
      expect((await zara.store.group('g-1'))!.isActive, isTrue);
      await sajjad.service.fanOut('g-1', 'new', 'After Zara', at(11));
      air.away.add('zara');
      await _settle(air);
      air.away
        ..remove('zara')
        ..add('sajjad');
      air.now += 200000;
      await ali.service.catchUpWith('zara');
      await _settle(air);
      final ids = zara.got.map((m) => m.id).toSet();
      expect(ids, contains('new'));
      expect(ids, isNot(contains('old')));
    });

    test('copies older than 7 days are dropped', () async {
      await make();
      await sajjad.service.fanOut('g-1', 'm1', 'Lunch?', at(1));
      await _settle(air);
      air.now += const Duration(days: 8).inMilliseconds;
      await ali.service.catchUpWith('sara');
      expect(ali.copyStore.rows, isEmpty);
    });
  });

  group('Join with QR (G4)', () {
    late _Air air;
    late _Phone sajjad, ali, usman;

    setUp(() async {
      air = _Air()..now = _t0;
      sajjad = _Phone(air, 'sajjad');
      ali = _Phone(air, 'ali');
      usman = _Phone(air, 'usman');
      sajjad.befriend(ali);
      ali.befriend(sajjad);
      ali.befriend(usman);
      usman.befriend(ali);
      usman.joinStore.friends.add('ali');
      await sajjad.service.createGroup(
          gid: 'g-1', name: 'Office', memberIds: ['ali'], origin: 'nearby');
      await _settle(air);
    });

    test('the code: llgq1:, 24 hours, admin key, reused, Reset makes a new one',
        () async {
      final code = await sajjad.service.inviteCode('g-1');
      final text = code.encode();
      expect(text, startsWith('llgq1:'));
      final back = GroupJoinCode.parse(text)!;
      expect(back.gid, 'g-1');
      expect(back.name, 'Office');
      expect(back.count, 2);
      expect(back.issuer, 'sajjad');
      expect(back.seal, _key('sajjad', 'seal'));
      expect(back.until - _t0, const Duration(hours: 24).inMilliseconds);
      await _settle(air);
      // the members got the card with the code
      expect((await ali.service.card('g-1'))!.qrToken, code.token);
      final again = await sajjad.service.inviteCode('g-1');
      expect(again.token, code.token,
          reason: 'same code inside the first hour');
      final reset = await sajjad.service.inviteCode('g-1', reset: true);
      expect(reset.token, isNot(code.token));
      expect(GroupJoinCode.parse('hello'), isNull);
      expect(GroupJoinCode.parse('llgq1:@@@'), isNull);
    });

    test('only admins make the code', () async {
      expect(() => ali.service.inviteCode('g-1'),
          throwsA(isA<GroupActionException>()));
    });

    test('approve off: a stranger scans and is added at once, without internet',
        () async {
      final code = await sajjad.service.inviteCode('g-1');
      await usman.service.askToJoin(GroupJoinCode.parse(code.encode())!);
      expect(await usman.service.joinState('g-1'), 'asked');
      await _settle(air);
      final c = (await sajjad.service.card('g-1'))!;
      expect(c.has('usman'), isTrue);
      expect(c.member('usman')!.seal, _key('usman', 'seal'));
      final local = await usman.store.group('g-1');
      expect(local!.isActive, isTrue,
          reason: 'Usman took the card from Sajjad (not his friend)');
      expect(GroupEvent.parse(usman.got.last.body)!.lines('usman').last,
          'SAJJAD added you');
      expect(await usman.service.joinState('g-1'), 'none');
      expect((await ali.service.card('g-1'))!.has('usman'), isTrue);
    });

    test('approve on: request waits; Add puts him in; Ignore says nothing',
        () async {
      await sajjad.service.update('g-1', approve: true);
      await _settle(air);
      final code = await sajjad.service.inviteCode('g-1');
      await usman.service.askToJoin(code);
      await _settle(air);
      expect((await sajjad.service.card('g-1'))!.has('usman'), isFalse);
      final reqs = await sajjad.service.joinRequests('g-1');
      expect(reqs.single.name, 'USMAN');
      expect(reqs.single.username, 'me');
      expect(reqs.single.friend, isFalse);
      expect(reqs.single.viaNames, ['ALI'],
          reason: 'Ali (member) is his friend');
      expect(await usman.service.joinState('g-1'), 'asked');
      await sajjad.service.addJoiner('g-1', 'usman');
      await _settle(air);
      expect((await usman.store.group('g-1'))!.isActive, isTrue);
      expect(await sajjad.service.joinRequests('g-1'), isEmpty);
    });

    test('Ignore removes the request silently', () async {
      await sajjad.service.update('g-1', approve: true);
      final code = await sajjad.service.inviteCode('g-1');
      await usman.service.askToJoin(code);
      await _settle(air);
      usman.sentTo.clear();
      sajjad.sentTo.clear();
      await sajjad.service.ignoreJoiner('g-1', 'usman');
      await _settle(air);
      expect(await sajjad.service.joinRequests('g-1'), isEmpty);
      expect(sajjad.sentTo.where((s) => s.startsWith('usman:')), isEmpty);
      expect(await usman.store.group('g-1'), isNull);
    });

    test('expired code: refused on the scanner phone', () async {
      final code = await sajjad.service.inviteCode('g-1');
      air.now += const Duration(hours: 25).inMilliseconds;
      await expectLater(
          usman.service.askToJoin(code),
          throwsA(isA<GroupActionException>().having((e) => e.message, 'text',
              'This group code has expired. Ask for a new one.')));
    });

    test('reset code: the old one is refused by the admin phone', () async {
      final old = await sajjad.service.inviteCode('g-1');
      await sajjad.service.inviteCode('g-1', reset: true);
      await usman.service.askToJoin(old);
      await _settle(air);
      expect((await sajjad.service.card('g-1'))!.has('usman'), isFalse);
      expect(await usman.service.joinState('g-1'), 'expired');
    });

    test('a forged request (wrong signature) is refused', () async {
      final code = await sajjad.service.inviteCode('g-1');
      await sajjad.service.handlePacket({
        'type': 'group_join',
        'gid': 'g-1',
        't': code.token,
        'n': 'Usman',
        'k': _key('usman', 'seal'),
        's': _key('usman', 'sign'),
        'sig': 'bad',
        'sender_id': 'usman',
        '_locked_spk': _key('usman', 'seal'),
      });
      await _settle(air);
      expect((await sajjad.service.card('g-1'))!.has('usman'), isFalse);
    });

    test('a card from someone else is not taken because I scanned a code',
        () async {
      final code = await sajjad.service.inviteCode('g-1');
      await sajjad.service.update('g-1', approve: true);
      await usman.service.askToJoin(code);
      final fake = GroupCard(
        gid: 'g-1',
        version: 9,
        name: 'Office',
        owner: 'zara',
        by: 'zara',
        at: 1,
        members: [
          _m('zara', 'owner'),
          _m('usman', 'member'),
          _m('sajjad', 'member')
        ],
        signature: 'S:${_key('zara', 'sign')}:x',
      );
      expect(
          GroupCardRules.joinSigner(fake,
              self: 'usman',
              issuer: 'sajjad',
              issuerSign: _key('sajjad', 'sign')),
          isNull);
    });

    test('approve change makes one settings line', () async {
      await sajjad.service.update('g-1', approve: true);
      await _settle(air);
      expect(GroupEvent.parse(ali.got.last.body)!.lines('ali').last,
          'SAJJAD changed the group settings');
      expect((await ali.service.card('g-1'))!.approve, isTrue);
    });
  });

  test('signed text and short ids', () {
    expect(GroupNearbyService.messageText('g', 'i', 'w', 'c', 'b'),
        'llgm1\ng\ni\nw\nc\nb');
    expect(GroupNearbyService.shortId('abc'), hasLength(12));
    expect(
        GroupNearbyService.shortId('abc'), GroupNearbyService.shortId('abc'));
  });

  // Bundle G5: receipts per member over Nearby.
  group('receipts over Nearby (G5)', () {
    late _Air air;
    late _Phone sajjad, ali, sara;
    final receipts = <String>[];

    setUp(() async {
      receipts.clear();
      air = _Air()..now = _t0;
      sajjad = _Phone(air, 'sajjad');
      ali = _Phone(air, 'ali');
      sara = _Phone(air, 'sara');
      sajjad.befriend(ali);
      sajjad.befriend(sara);
      ali.befriend(sajjad);
      sara.befriend(sajjad);
      sajjad.service.onReceipt =
          (gid, id, member, status) async => receipts.add('$gid|$id|$member|$status');
      await sajjad.service.createGroup(
          gid: 'g-5', name: 'Office', memberIds: ['ali', 'sara'], origin: 'nearby');
      await _settle(air);
    });

    test('each member that got it = one "delivered"', () async {
      final at = DateTime.fromMillisecondsSinceEpoch(_t0 + 60000, isUtc: true)
          .toIso8601String();
      await sajjad.service.fanOut('g-5', 'm1', 'Lunch?', at);
      await _settle(air);
      expect(receipts, containsAll(['g-5|m1|ali|delivered', 'g-5|m1|sara|delivered']));
    });

    test('group_read from a member = "read"; strangers are ignored', () async {
      expect(await ali.service.sendRead('g-5', 'sajjad', ['m1', 'm2']), isTrue);
      await _settle(air);
      expect(receipts, ['g-5|m1|ali|read', 'g-5|m2|ali|read']);
      expect(ali.sentTo.last, 'sajjad:group_read');
      receipts.clear();
      await sajjad.service.handlePacket({
        'type': 'group_read',
        'gid': 'g-5',
        'ids': ['m1'],
        'sender_id': 'zed',
      });
      expect(receipts, isEmpty);
      // nothing to myself / empty lists
      expect(await ali.service.sendRead('g-5', 'ali', ['m1']), isFalse);
      expect(await ali.service.sendRead('g-5', 'sajjad', const []), isFalse);
    });
  });
}
