import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';

// Bundle 215 (A + §8.2): no "Adding…" strip on the group chat page; a
// signed group message from a pending member clears her "Pending".
// (Phones-in-the-air fakes copied from groups_g3_test.)

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
  Future<void> saveCard(String gid, String json, int version, {String? origin}) async {
    rows[gid]!['card_json'] = json;
    rows[gid]!['card_version'] = version;
    if (origin != null) rows[gid]!['origin'] = origin;
  }

  @override
  Future<String> cardJson(String gid) async =>
      rows[gid]?['card_json']?.toString() ?? '';
  @override
  Future<void> replaceMembers(String gid, List<Map<String, dynamic>> rows) async =>
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
      ]..sort((a, b) => (a['created_at'] as int).compareTo(b['created_at'] as int));
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
  Future<void> setInvite(String gid, String member, String state, int atMs) async =>
      inviteRows['$gid|$member'] = {'group_id': gid, 'member_id': member, 'state': state, 'at': atMs};
  @override
  Future<List<Map<String, dynamic>>> invites(String gid) async =>
      [for (final r in inviteRows.values) if (r['group_id'] == gid) r];
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
      nowMs: () => air.now,
    );
    air.phones[id] = this;
  }

  final _Air air;
  final String id;
  final _Store store;
  late final GroupNearbyService service;
  final got = <GroupMessage>[];
  final sentNearby = <String>[];
  final sentTo = <String>[];
  final serverPosts = <String>[];

  void befriend(_Phone other) {
    store.friends[other.id] = GroupFriendKeys(
        id: other.id, name: other.id.toUpperCase(), seal: _key(other.id, 'seal'), sign: _key(other.id, 'sign'));
  }

  Future<bool> _send({
    required String recipientId,
    required String theirIdentityKey,
    required Map<String, dynamic> payload,
  }) async {
    sentTo.add('$recipientId:${payload['type']}');
    expect(theirIdentityKey, _key(recipientId, 'seal'), reason: 'locked with the member key');
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

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('pending clears when her message arrives', () {
    late _Air air;
    late _Phone sajjad, ali, sara;

    setUp(() {
      air = _Air();
      sajjad = _Phone(air, 'sajjad');
      ali = _Phone(air, 'ali');
      sara = _Phone(air, 'sara');
      sajjad.befriend(ali);
      sajjad.befriend(sara);
      ali.befriend(sajjad);
      sara.befriend(sajjad);
    });

    Future<void> make() async {
      air.away.add('sara');
      await sajjad.service.createGroup(
          gid: 'g-1', name: 'Family', memberIds: ['ali', 'sara'], origin: 'nearby');
      await _settle(air);
    }

    Future<String> state(String who) async =>
        (await sajjad.service.invites('g-1')).firstWhere((i) => i.memberId == who).state;

    Map<String, dynamic> msg(String id, {bool goodSig = true}) {
      const at = '2026-11-05T10:00:00Z';
      final text = GroupNearbyService.messageText('g-1', id, 'sara', at, 'Salam');
      return {
        'type': GroupNearbyService.typeMessage,
        'gid': 'g-1',
        'id': id,
        'body': 'Salam',
        'created_at': at,
        'sig': goodSig ? 'S:${_key('sara', 'sign')}:${text.hashCode}' : 'S:bad:1',
        'sender_id': 'sara',
        'recipient_id': 'sajjad',
      };
    }

    test('waiting → her signed message → added (+ change), once', () async {
      await make();
      expect(await state('sara'), 'waiting');
      expect(await state('ali'), 'added');
      await sajjad.service.handlePacket(msg('m1'));
      expect(await state('sara'), 'added');
      expect(sajjad.got.any((m) => m.id == 'm1'), isTrue);
      final at = sajjad.store.inviteRows['g-1|sara']!['at'];
      air.now += 5000;
      await sajjad.service.handlePacket(msg('m2'));
      expect(sajjad.store.inviteRows['g-1|sara']!['at'], at, reason: 'set once');
    });

    test('a bad signature does not clear it', () async {
      await make();
      await sajjad.service.handlePacket(msg('m1', goodSig: false));
      expect(await state('sara'), 'waiting');
    });

    test('not reached in 7 days (failed) also clears on her message', () async {
      await make();
      air.now += const Duration(days: 8).inMilliseconds;
      await sajjad.service.flush();
      expect(await state('sara'), 'failed');
      await sajjad.service.handlePacket(msg('m1'));
      expect(await state('sara'), 'added');
    });

    test('the card still reaches her later as before', () async {
      await make();
      await sajjad.service.handlePacket(msg('m1'));
      air.away.remove('sara');
      await sajjad.service.flush(peerId: 'sara');
      await _settle(air);
      expect((await sara.store.group('g-1'))!.isActive, isTrue);
      expect(await state('sara'), 'added');
    });
  });

  test('sources: chat page has no strip; widgets kept; receive hook', () {
    final chat = _src('lib/features/groups/presentation/screens/group_chat_screen.dart');
    expect(chat, isNot(contains('GroupAddingBanner(')));
    expect(chat, isNot(contains('_adding')));
    expect(chat, isNot(contains('_openAdding')));
    expect(chat, isNot(contains('showAddingPeopleSheet')));
    final w = _src('lib/features/groups/presentation/widgets/group_nearby_widgets.dart');
    expect(w, contains('class GroupAddingBanner extends StatelessWidget'));
    expect(w, contains('Future<void> showAddingPeopleSheet('));
    expect(w, contains('class GroupPendingTag extends StatelessWidget'));
    final svc = _src('lib/features/groups/data/services/group_nearby_service.dart');
    expect(svc, contains('await _inviteDoneBy(gid, from);'));
    expect(_src('lib/core/models/group_event.dart'), contains("'You added \${list(targets)}'"));
  });
}
