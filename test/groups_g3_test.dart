import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/group_card.dart';
import 'package:locallink/core/models/group_event.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';
import 'package:locallink/features/groups/presentation/widgets/group_nearby_widgets.dart';

// Bundle G3: Nearby groups - signed card, locked packets to each member,
// per-member queue, bridge to the server.

String _key(String who, String kind) => '$who-$kind-'.padRight(43, 'x');

GroupCardMember _m(String id, String role) => GroupCardMember(
    id: id, name: id.toUpperCase(), role: role, seal: _key(id, 'seal'), sign: _key(id, 'sign'));

GroupCard _card({int v = 1, String by = 'sajjad', List<GroupCardMember>? members, String sig = 'sig'}) =>
    GroupCard(
      gid: 'g-1',
      version: v,
      name: 'Office',
      owner: 'sajjad',
      members: members ?? [_m('sajjad', 'owner'), _m('ali', 'member'), _m('sara', 'member')],
      by: by,
      at: 1000 + v,
      createdAt: '2026-11-03T10:00:00Z',
      signature: sig,
    );

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

void main() {
  group('group card (pure)', () {
    test('signed text is the same whatever the member order', () {
      final a = _card();
      final b = _card(members: a.members.reversed.toList());
      expect(a.canonical(), b.canonical());
      expect(a.canonical().contains('"sig"'), isFalse);
      final back = GroupCard.decode(a.encode())!;
      expect(back.canonical(), a.canonical());
      expect(back.signature, 'sig');
      expect(back.member('ali')!.seal, _key('ali', 'seal'));
    });

    test('shape: owner, signer, size, keys, signature', () {
      expect(GroupCardRules.shape(_card()), isNull);
      expect(GroupCardRules.shape(_card(by: 'ali')), 'signer');
      expect(GroupCardRules.shape(_card(sig: '')), 'unsigned');
      expect(
          GroupCardRules.shape(_card(members: [
            for (var i = 0; i < 33; i++) _m(i == 0 ? 'sajjad' : 'p$i', i == 0 ? 'owner' : 'member')
          ])),
          'size');
      expect(
          GroupCardRules.shape(_card(members: [
            _m('sajjad', 'owner'),
            const GroupCardMember(id: 'ali', name: 'Ali', role: 'member', seal: 'short', sign: 'short'),
          ])),
          'keys');
    });

    test('only a friend can add me (signer key = friend profile key)', () {
      final c = _card();
      expect(GroupCardRules.firstSigner(c, self: 'ali', signerFriendSignKey: _key('sajjad', 'sign')),
          _key('sajjad', 'sign'));
      expect(GroupCardRules.firstSigner(c, self: 'ali', signerFriendSignKey: null), isNull);
      expect(GroupCardRules.firstSigner(c, self: 'ali', signerFriendSignKey: 'other'), isNull);
      expect(GroupCardRules.firstSigner(c, self: 'zara', signerFriendSignKey: _key('sajjad', 'sign')),
          isNull, reason: 'not on the card');
    });

    test('a newer card must be signed by an admin of my card', () {
      final old = _card();
      expect(GroupCardRules.updateSigner(old, _card(v: 2)), _key('sajjad', 'sign'));
      expect(GroupCardRules.updateSigner(old, _card(v: 1, sig: 'sig')), isNull, reason: 'same');
      expect(GroupCardRules.updateSigner(_card(v: 3), _card(v: 2)), isNull, reason: 'older');
      final aliAdmin = _card(v: 2, members: [_m('sajjad', 'owner'), _m('ali', 'admin')], by: 'ali');
      expect(GroupCardRules.updateSigner(old, aliAdmin), isNull,
          reason: 'Ali was not an admin in my card');
    });

    test('system lines from two cards', () {
      final old = _card();
      final next = _card(v: 2, members: [
        _m('sajjad', 'owner'),
        _m('ali', 'admin'),
        _m('zara', 'member'),
      ]);
      final kinds = GroupCardRules.events(old, next, self: 'ali').map((e) => e.kind).toList();
      expect(kinds, ['add', 'remove', 'admin']);
      final first = GroupCardRules.events(null, old, self: 'ali').single;
      expect(first.kind, 'create');
      expect(first.lines('ali').last, 'SAJJAD added you');
      final ev = GroupEvent.parse(first.encode())!;
      expect(ev.targets, ['ali', 'sara']);
      expect(ev.names['sajjad'], 'SAJJAD');
    });
  });

  group('Nearby group between phones', () {
    late _Air air;
    late _Phone sajjad, ali, sara, zara;

    setUp(() {
      air = _Air();
      sajjad = _Phone(air, 'sajjad');
      ali = _Phone(air, 'ali');
      sara = _Phone(air, 'sara');
      zara = _Phone(air, 'zara');
      // Sajjad is friends with Ali and Sara; Ali and Sara are not friends.
      sajjad.befriend(ali);
      sajjad.befriend(sara);
      ali.befriend(sajjad);
      sara.befriend(sajjad);
    });

    Future<LocalGroup> make({List<String> people = const ['ali', 'sara']}) async {
      final g = await sajjad.service.createGroup(
          gid: 'g-1', name: 'Office', memberIds: people, origin: 'nearby');
      await _settle(air);
      return g;
    }

    test('made offline: everyone gets "Sajjad added you", then messages', () async {
      final g = await make();
      expect(g.origin, 'nearby');
      expect(g.worksNearby, isTrue);
      expect(g.nearbyOnly, isTrue);
      // my own lines (mock 6)
      final mine = sajjad.got.map((m) => GroupEvent.parse(m.body)!.lines('sajjad')).single;
      expect(mine, ['You created group "Office"', 'You added ALI and SARA']);
      for (final p in [ali, sara]) {
        final local = await p.store.group('g-1');
        expect(local!.isActive, isTrue);
        expect(local.cardVersion, 1);
        expect(GroupEvent.parse(p.got.single.body)!.lines(p.id).last, 'SAJJAD added you');
      }
      final invites = await sajjad.service.invites('g-1');
      expect(invites.map((i) => i.state), ['added', 'added']);

      await sajjad.service.fanOut('g-1', 'm1', 'Lunch at 1?', '2026-11-03T10:01:00Z');
      await _settle(air);
      expect(ali.got.last.body, 'Lunch at 1?');
      expect(sara.got.last.senderId, 'sajjad');
      expect(sajjad.sentNearby, containsAll(['m1']));
      expect(sajjad.store.outbox, isEmpty, reason: 'every member said got it');
    });

    test('a member who is not my friend still gets my message (key from the card)', () async {
      await make();
      await ali.service.fanOut('g-1', 'a1', 'Yes 👍', '2026-11-03T10:02:00Z');
      await _settle(air);
      expect(sara.got.last.body, 'Yes 👍', reason: 'Sara is not Ali\'s friend');
      expect(sara.got.last.senderId, 'ali');
    });

    test('a stranger with a wrong key is refused', () async {
      await make();
      await sara.service.handlePacket({
        'type': GroupNearbyService.typeMessage,
        'gid': 'g-1',
        'id': 'x1',
        'body': 'fake',
        'created_at': '2026-11-03T10:02:00Z',
        'sender_id': 'ali',
        '_locked_spk': _key('mallory', 'seal'),
      });
      expect(sara.store.messages.containsKey('x1'), isFalse);
    });

    test('only friends can add me: a card from a stranger is refused', () async {
      zara.befriend(ali); // Zara knows Ali, Ali does not know Zara
      await zara.service.createGroup(gid: 'g-z', name: 'Spam', memberIds: ['ali'], origin: 'nearby');
      await _settle(air);
      expect(await ali.store.group('g-z'), isNull);
      expect((await zara.service.invites('g-z')).single.state, 'waiting');
    });

    test('away: queue tries again, card first, then the message', () async {
      air.away.add('ali');
      await make();
      await sajjad.service.fanOut('g-1', 'm1', 'Hi', '2026-11-03T10:01:00Z');
      await _settle(air);
      expect(await ali.store.group('g-1'), isNull);
      expect((await sajjad.service.invites('g-1')).firstWhere((i) => i.memberId == 'ali').state,
          'waiting');
      expect(sajjad.sentTo.where((s) => s == 'ali:group_msg'), isEmpty,
          reason: 'no message before the card reached Ali');
      air.away.remove('ali');
      await sajjad.service.flush(peerId: 'ali');
      await _settle(air);
      expect((await ali.store.group('g-1'))!.isActive, isTrue);
      expect(ali.got.last.body, 'Hi');
    });

    test('not reached in 7 days -> couldn\'t be added + Try again', () async {
      air.away.add('ali');
      await make();
      air.now += const Duration(days: 8).inMilliseconds;
      await sajjad.service.flush();
      final row = (await sajjad.service.invites('g-1')).firstWhere((i) => i.memberId == 'ali');
      expect(row.state, 'failed');
      air.away.remove('ali');
      await sajjad.service.retryInvite('g-1', 'ali');
      await _settle(air);
      expect((await sajjad.service.invites('g-1')).firstWhere((i) => i.memberId == 'ali').state,
          'added');
    });

    test('admin removes Sara: she is told, read only', () async {
      await make();
      await sajjad.service.removeMember('g-1', 'sara');
      await _settle(air);
      expect((await sara.store.group('g-1'))!.state, 'removed');
      expect((await ali.store.group('g-1'))!.cardVersion, 2);
      expect(GroupEvent.parse(ali.got.last.body)!.lines('ali').single, 'SAJJAD removed SARA');
      // and a member can't remove anyone
      expect(() => ali.service.removeMember('g-1', 'sajjad'),
          throwsA(isA<GroupActionException>()));
    });

    test('Ali leaves: one "ALI left" line everywhere, owner updates the card', () async {
      await make();
      await ali.service.leave('g-1');
      await _settle(air);
      expect((await ali.store.group('g-1'))!.state, 'left');
      expect((await sajjad.store.group('g-1'))!.cardVersion, 2);
      final saraLines = sara.got
          .where((m) => GroupEvent.parse(m.body)?.kind == 'leave')
          .toList();
      expect(saraLines.length, 1, reason: 'the leave note and the new card make one line');
      expect((await sara.store.memberIds('g-1')).contains('ali'), isFalse);
    });

    test('owner leaves: the next admin / oldest member is the owner', () async {
      await make();
      await sajjad.service.leave('g-1');
      await _settle(air);
      final c = await ali.service.card('g-1');
      expect(c!.owner, 'ali', reason: 'joined at the same time: lowest id');
      expect(c.has('sajjad'), isFalse);
      final line = GroupEvent.parse(sara.got.last.body)!.lines('sara');
      expect(line.last, 'ALI is now the group owner');
      expect((await sajjad.store.group('g-1'))!.state, 'left');
    });

    test('announcement group: a member\'s message is not shown', () async {
      await make();
      await sajjad.service.update('g-1', sendMessages: 'admins');
      await _settle(air);
      await ali.service.fanOut('g-1', 'a9', 'hello', '2026-11-03T10:05:00Z');
      await _settle(air);
      expect(sara.store.messages.containsKey('a9'), isFalse);
    });

    test('bridge: my phone-made groups go on the server with the same id', () async {
      await make();
      final uploaded = <String>[];
      final n = await sajjad.service.bridge((card) async {
        uploaded.add(card.gid);
        return true;
      });
      expect(n, 1);
      expect(uploaded, ['g-1']);
      expect((await sajjad.store.group('g-1'))!.origin, 'both');
      // Ali does not own it: nothing to upload
      expect(await ali.service.bridge((_) async => true), 0);
    });

    test('a card through the server (both groups) is read quietly', () async {
      await make();
      await sajjad.store.setOrigin('g-1', 'both');
      await ali.store.setOrigin('g-1', 'both');
      air.away.add('ali');
      final linesBefore = ali.got.length;
      await sajjad.service.update('g-1', name: 'Office 2', quiet: true);
      await _settle(air);
      final body = sajjad.serverPosts.single;
      expect(body.startsWith(GroupNearbyService.cardBodyPrefix), isTrue);
      final handled = await ali.service.consumeServerCard(GroupMessage(
          id: 's1', groupId: 'g-1', senderId: 'sajjad', body: body, createdAt: '2026-11-03T10:09:00Z'));
      expect(handled, isTrue);
      expect((await ali.store.group('g-1'))!.name, 'Office 2');
      expect((await ali.service.card('g-1'))!.version, 2);
      expect(ali.got.length, linesBefore, reason: 'the server wrote its own line');
      // a forged card (signer is not the sender) changes nothing
      final forged = body.replaceAll('Office 2', 'Hacked');
      await ali.service.consumeServerCard(GroupMessage(
          id: 's2', groupId: 'g-1', senderId: 'sara', body: forged, createdAt: '2026-11-03T10:10:00Z'));
      expect((await ali.store.group('g-1'))!.name, 'Office 2');
    });
  });

  group('locked group packets on the wire', () {
    late SealKeyPair sKeys, aKeys;
    late _Inner sInner, aInner;
    late SealingPeerTransport sajjad, ali;

    setUp(() async {
      sKeys = await SealKeyPair.from(await X25519().newKeyPairFromSeed(List<int>.filled(32, 31)));
      aKeys = await SealKeyPair.from(await X25519().newKeyPairFromSeed(List<int>.filled(32, 32)));
      sInner = _Inner();
      aInner = _Inner();
      sajjad = SealingPeerTransport(sInner)..bind(_Keys('sajjad', [sKeys]));
      ali = SealingPeerTransport(aInner)..bind(_Keys('ali', [aKeys])); // no friends
    });

    String b64(List<int> k) => base64Url.encode(k).replaceAll('=', '');

    test('flag 3, sealed type (queued + carried), nothing readable outside', () async {
      final ok = await sajjad.sendGroupLocked(
          recipientId: 'ali',
          theirIdentityKey: b64(aKeys.publicKey),
          payload: {'type': 'group_msg', 'gid': 'g-1', 'body': 'secret words'});
      expect(ok, isTrue);
      final out = sInner.sent.single.$2;
      expect(out['type'], MessageSealService.sealedType);
      expect(out[SealingPeerTransport.friendLinkFlag], 3);
      expect(jsonEncode(out).contains('secret words'), isFalse);
    });

    test('a non-group payload is never sent this way', () async {
      expect(
          await sajjad.sendGroupLocked(
              recipientId: 'ali',
              theirIdentityKey: b64(aKeys.publicKey),
              payload: {'type': 'direct_message', 'body': 'x'}),
          isFalse);
    });

    test('Ali opens it although Sajjad is not his friend (key given out)', () async {
      await sajjad.sendGroupLocked(
          recipientId: 'ali',
          theirIdentityKey: b64(aKeys.publicKey),
          payload: {'type': 'group_msg', 'gid': 'g-1', 'body': 'hi'});
      final got = <Map<String, dynamic>>[];
      final sub = ali.events.listen(got.add);
      aInner.controller.add({
        'type': 'message',
        'sender_id': 'sajjad',
        'mesh_final_recipient': true,
        'mesh_destination_id': 'ali',
        'payload': jsonEncode(sInner.sent.single.$2),
      });
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sub.cancel();
      final p = jsonDecode(got.single['payload'] as String) as Map;
      expect(p['type'], 'group_msg');
      expect(p['sender_id'], 'sajjad');
      expect(p[SealingPeerTransport.openedStrangerKeyField], b64(sKeys.publicKey));
    });

    test('a friend link flag cannot carry a group packet and the other way', () async {
      // forge: a chat message under flag 3 from a stranger is dropped
      final sealed = await MessageSealService().seal(
        payload: {'type': 'direct_message', 'body': 'x'},
        senderId: 'sajjad',
        recipientId: 'ali',
        mine: sKeys,
        theirPublic: aKeys.publicKey,
        outerType: MessageSealService.sealedType,
      );
      sealed['spk'] = b64(sKeys.publicKey);
      sealed['fl'] = 3;
      final got = <Map<String, dynamic>>[];
      final sub = ali.events.listen(got.add);
      aInner.controller.add({
        'type': 'message',
        'sender_id': 'sajjad',
        'mesh_final_recipient': true,
        'mesh_destination_id': 'ali',
        'payload': jsonEncode(sealed),
      });
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sub.cancel();
      expect(got.where((e) => (e['payload'] as String).contains('direct_message')), isEmpty);
    });
  });

  group('mock 6 / 7 widgets', () {
    const invites = [
      GroupInviteState(memberId: 'ali', name: 'Ali', state: 'waiting', atMs: 0),
      GroupInviteState(memberId: 'sara', name: 'Sara', state: 'added', atMs: 1762149660000),
    ];

    testWidgets('banner names who is still waiting', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: GroupAddingBanner(invites: invites, onTap: () => taps++))));
      expect(find.text('Adding Ali…'), findsOneWidget);
      expect(find.text('They are added when Nearby or Online'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group_adding_banner')));
      expect(taps, 1);
    });

    testWidgets('Adding people sheet: Added / Waiting / Close', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAddingPeopleSheet(context, invites: invites, myName: 'Sajjad'),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Adding people'), findsOneWidget);
      expect(find.textContaining('Added · '), findsOneWidget);
      expect(find.text('Waiting · added when Nearby or Online'), findsOneWidget);
      expect(find.textContaining('Ali gets "Sajjad added you" first'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Adding people'), findsNothing);
    });

    testWidgets('sealed chip text (mock 6)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GroupSealedChip())));
      expect(find.text('🔒 Messages are sealed for group members only'), findsOneWidget);
    });
  });
}

class _Inner implements PeerTransportContract {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final List<(String, Map<String, dynamic>)> sent = [];
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<void> send({required String recipientId, required Map<String, dynamic> payload}) async =>
      sent.add((recipientId, payload));
  @override
  bool get isStarted => true;
  @override
  Future<void> broadcast(Map<String, dynamic> payload) async {}
  @override
  Future<void> flushQueue() async {}
  @override
  Future<void> updateKnownPeers(List<String> peerIds) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Keys implements SealKeySource {
  _Keys(this.selfId, this.own);
  @override
  final String? selfId;
  final List<SealKeyPair> own;
  final Map<String, String> settings = {};
  @override
  Future<List<SealKeyPair>> ownKeys() async => own;
  @override
  Future<List<int>?> contactPublicKey(String peerId) async => null;
  @override
  Future<Set<String>> blockedPeerIds() async => {};
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
}
