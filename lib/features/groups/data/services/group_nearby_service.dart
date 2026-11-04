import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;

import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/group_card.dart';
import 'package:locallink/core/models/group_event.dart';
import 'package:locallink/core/models/group_join_code.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/locallink_api.dart'
    show GroupActionException;
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';

/// Sends one locked group packet (SealingPeerTransport.sendGroupLocked).
typedef GroupLockedSend = Future<bool> Function({
  required String recipientId,
  required String theirIdentityKey,
  required Map<String, dynamic> payload,
});

/// Bundle G3: signing keys of this phone (IdentityCryptoService).
class GroupCardKeys {
  const GroupCardKeys({
    required this.sign,
    required this.verify,
    required this.ownSignKey,
    required this.ownSealKey,
  });
  final Future<String> Function(String text) sign;
  final Future<bool> Function(String text, String signature, String key)
      verify;
  final Future<String> Function() ownSignKey;
  final Future<String> Function() ownSealKey;
}

/// Bundle G3: thrown when none of the picked people can be put on a group
/// card (no profile keys on this phone yet).
class NoNearbyMembersException implements Exception {
  const NoNearbyMembersException(this.names);
  final List<String> names;
  @override
  String toString() => 'NO_NEARBY_MEMBERS';
}

/// Bundle G3 (TODO_groups §9): groups without the server.
///
/// * A group made on this phone has a phone-made id and a signed group
///   card (members, their keys, roles, settings).
/// * Every packet goes to each member on its own, locked with that
///   member's key ([GroupLockedSend]); any LinkUp phone near us can carry
///   it, only the member can open it. Each member answers `group_ack`.
/// * A per-member queue tries again (15 s ... 15 min) for 7 days; a member
///   not reached in 7 days shows "couldn't be added" + Try again.
/// * Only the sender bridges its own messages to the server later (the
///   normal group outbox keeps them until the group is on the server).
class GroupNearbyService {
  GroupNearbyService({
    required this.store,
    required this.keys,
    required this.send,
    required Stream<Map<String, dynamic>> events,
    required this.onMessage,
    this.onSentNearby,
    this.postToServer,
    this.copies,
    this.catchUpAllowed,
    this.joins,
    int Function()? nowMs,
  })  : _events = events,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final GroupNearbyStore store;
  final GroupCardKeys keys;
  final GroupLockedSend send;
  final Stream<Map<String, dynamic>> _events;

  /// A member's message (or reaction / delete note) arrived Nearby; the
  /// group messaging service saves and shows it.
  final Future<void> Function(GroupMessage message) onMessage;

  /// My message reached a member's phone (the bubble shows ✓).
  final Future<void> Function(String messageId)? onSentNearby;

  /// Groups that are also on the server: a new card goes there too (as a
  /// group message the app reads quietly), so Online-only members get it.
  final Future<void> Function(String gid, String body)? postToServer;

  /// Bundle G4: signed copies for catch-up (null = no catch-up).
  final GroupCopyStore? copies;

  /// Bundle G4: false at 10% battery or less (no catch-up then).
  final bool Function()? catchUpAllowed;

  /// Bundle G4: Join with QR (null = off).
  final GroupJoinStore? joins;
  final int Function() _nowMs;

  static const String typeCard = 'group_card';
  static const String typeMessage = 'group_msg';
  static const String typeLeave = 'group_leave';
  static const String typeAck = 'group_ack';

  /// Bundle G5: "I read these" to the writer (best effort, not queued).
  static const String typeRead = 'group_read';

  /// Bundle G5: a member got / read my message (Message info). Set by the
  /// group messaging service.
  Future<void> Function(String gid, String messageId, String member,
      String status)? onReceipt;

  /// Bundle G4 catch-up: "these I have" / "take these" / "send me the card".
  static const String typeHave = 'group_have';
  static const String typeGive = 'group_give';
  static const String typeNeed = 'group_need';
  static const int catchUpMax = 500;
  static const int pageItems = 50;
  static const int pageBytes = 24 * 1024;
  static const Duration catchUpGap = Duration(minutes: 2);
  final Map<String, int> _lastHave = <String, int>{};
  final Map<String, int> _lastNeed = <String, int>{};
  bool _batteryLogged = false;

  /// Bundle G4: what a writer signs for each Nearby group message, so a
  /// member who passes it on can't change it.
  static String messageText(String gid, String id, String writer,
          String createdAt, String body) =>
      'llgm1\n$gid\n$id\n$writer\n$createdAt\n$body';

  /// Short form of a message id in `group_have` (12 hex).
  static String shortId(String id) =>
      sha256.convert(utf8.encode(id)).toString().substring(0, 12);

  /// Body prefix of a card sent through the server ('both' groups).
  static const String cardBodyPrefix = 'llgc:v1:';
  static const Duration keepFor = Duration(days: 7);
  static const List<int> _backoffSeconds = [15, 30, 60, 120, 300, 600, 900];

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _timer;
  bool _flushing = false;
  bool _flushAgain = false;

  String get _self => store.selfId;

  void start() {
    _sub ??= _events.listen((event) {
      unawaited(handleEvent(event).catchError((Object e) {
        AppLogger.warning('GROUP_NEARBY_EVENT_FAILED', detail: '$e');
      }));
    });
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(flush());
    });
    unawaited(flush());
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _sub?.cancel();
  }

  // ------------------------------------------------------------- cards

  Future<GroupCard?> card(String gid) async =>
      GroupCard.decode(await store.cardJson(gid));

  /// Bundle G6: a member's seal key from the signed card, else from the
  /// friend list ('' = not known here).
  Future<String> memberSealKey(String gid, String id) async {
    try {
      final c = await card(gid);
      final k = c?.member(id)?.seal ?? '';
      if (k.isNotEmpty) return k;
      return (await store.friend(id))?.seal ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<GroupCard> _signed(GroupCard unsigned) async =>
      unsigned.withSignature(await keys.sign(unsigned.canonical()));

  Future<GroupCardMember> _me(String role, String joinedAt) async =>
      GroupCardMember(
        id: _self,
        name: await store.selfName(),
        role: role,
        seal: (await keys.ownSealKey()).replaceAll('=', ''),
        sign: (await keys.ownSignKey()).replaceAll('=', ''),
        joinedAt: joinedAt,
      );

  /// Friends among [ids] whose keys this phone has (can be on a card).
  Future<List<GroupFriendKeys>> keyedFriends(Iterable<String> ids) async {
    final out = <GroupFriendKeys>[];
    final seen = <String>{};
    for (final id in ids) {
      if (id == _self || !seen.add(id)) continue;
      final f = await store.friend(id);
      if (f != null) out.add(f);
    }
    return out;
  }

  static String newGroupId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Makes the card of a new group on this phone and sends it to every
  /// member. [origin] "nearby" (not on the server) or "both" (the server
  /// already has this id). Returns the local group.
  Future<LocalGroup> createGroup({
    required String gid,
    required String name,
    required List<String> memberIds,
    String description = '',
    String editInfo = 'admins',
    String sendMessages = 'all',
    String addMembers = 'admins',
    String origin = 'nearby',
    String? createdAt,
  }) async {
    final people = await keyedFriends(memberIds);
    if (people.isEmpty) throw const NoNearbyMembersException([]);
    if (people.length + 1 > GroupCard.maxMembers) {
      throw const GroupActionException(
          'GROUP_TOO_BIG', 'Nearby groups can have up to 32 people.');
    }
    final now = _nowMs();
    final made = createdAt ??
        DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String();
    final members = <GroupCardMember>[
      await _me('owner', made),
      for (final p in people)
        GroupCardMember(
            id: p.id,
            name: p.name,
            role: 'member',
            seal: p.seal,
            sign: p.sign,
            addedBy: _self,
            joinedAt: made),
    ];
    final card = await _signed(GroupCard(
      gid: gid,
      version: 1,
      name: name.trim(),
      description: description.trim(),
      owner: _self,
      editInfo: editInfo,
      sendMessages: sendMessages,
      addMembers: addMembers,
      members: members,
      by: _self,
      at: now,
      createdAt: made,
    ));
    await store.saveGroupRow({...card.groupRow(), 'state': 'active'});
    await store.saveCard(gid, card.encode(), card.version, origin: origin);
    await store.replaceMembers(gid, card.memberRows());
    if (origin == 'nearby') {
      await _writeLines(gid, null, card);
    }
    // Mock 6/7: "Adding…" only for a group made without the server.
    if (origin == 'nearby') {
      for (final p in people) {
        await store.setInvite(gid, p.id, 'waiting', now);
      }
    }
    await _queueCard(card, [for (final p in people) p.id]);
    AppLogger.info('GROUP_NEARBY_CREATED',
        detail: 'members=${people.length} origin=$origin');
    GroupChangeHub.instance.changed(gid);
    unawaited(flush());
    return (await store.group(gid))!;
  }

  /// A new signed card from me (an admin) for [gid]: saved, lines written,
  /// sent to everyone in the old and the new card.
  Future<GroupCard> issue(
    String gid,
    GroupCard Function(GroupCard old, int now) change, {
    bool quiet = false,
  }) async {
    final old = await card(gid);
    if (old == null) {
      throw const GroupActionException(
          'GROUP_NOT_MEMBER', "You're no longer a participant in this group.");
    }
    if (!old.isAdmin(_self)) {
      throw const GroupActionException(
          'GROUP_ADMINS_ONLY', 'Only admins can do this.');
    }
    final now = _nowMs();
    final next = await _signed(change(old, now));
    final local = await store.group(gid);
    await store.saveCard(gid, next.encode(), next.version);
    await store.saveGroupRow(next.groupRow()
      ..['state'] = next.has(_self) ? 'active' : (local?.state ?? 'left'));
    await store.replaceMembers(gid, next.memberRows());
    if (!quiet) await _writeLines(gid, old, next);
    final added = next.memberIds.toSet().difference(old.memberIds.toSet());
    if (local?.origin == 'nearby') {
      for (final id in added) {
        await store.setInvite(gid, id, 'waiting', now);
      }
    }
    final to = {...old.memberIds, ...next.memberIds}..remove(_self);
    await _queueCard(next, to.toList());
    if (local != null && local.origin == 'both') {
      try {
        await postToServer?.call(gid, '$cardBodyPrefix${next.encode()}');
      } catch (_) {}
    }
    GroupChangeHub.instance.changed(gid);
    unawaited(flush());
    return next;
  }

  /// Members I can add (friends with keys); throws when it can't be done.
  Future<void> addMember(String gid, String deviceId, {bool quiet = false}) async {
    final f = (await keyedFriends([deviceId])).firstOrNull;
    if (f == null) {
      throw const GroupActionException(
          'GROUP_NOT_CONTACT', 'You can only add your friends.');
    }
    await issue(gid, (old, now) {
      if (old.has(f.id)) return old.next(by: _self, at: now);
      if (old.members.length >= GroupCard.maxMembers) {
        throw const GroupActionException(
            'GROUP_TOO_BIG', 'Nearby groups can have up to 32 people.');
      }
      final joined =
          DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String();
      return old.next(by: _self, at: now, members: [
        ...old.members,
        GroupCardMember(
            id: f.id,
            name: f.name,
            role: 'member',
            seal: f.seal,
            sign: f.sign,
            addedBy: _self,
            joinedAt: joined),
      ]);
    }, quiet: quiet);
  }

  Future<void> removeMember(String gid, String deviceId, {bool quiet = false}) =>
      issue(gid, (old, now) {
        if (deviceId == old.owner) {
          throw const GroupActionException(
              'GROUP_ADMINS_ONLY', 'Only admins can do this.');
        }
        return old.next(
            by: _self,
            at: now,
            members: old.members.where((m) => m.id != deviceId).toList());
      }, quiet: quiet);

  Future<void> setAdmin(String gid, String deviceId,
          {required bool admin, bool quiet = false}) =>
      issue(gid, (old, now) {
        if (deviceId == old.owner) return old.next(by: _self, at: now);
        return old.next(by: _self, at: now, members: [
          for (final m in old.members)
            m.id == deviceId ? m.copyWith(role: admin ? 'admin' : 'member') : m
        ]);
      }, quiet: quiet);

  Future<void> update(String gid,
          {String? name,
          String? description,
          String? editInfo,
          String? sendMessages,
          String? addMembers,
          bool? approve,
          bool quiet = false}) =>
      issue(
          gid,
          (old, now) => old.next(
              by: _self,
              at: now,
              name: name?.trim(),
              description: description?.trim(),
              editInfo: editInfo,
              sendMessages: sendMessages,
              addMembers: addMembers,
              approve: approve),
          quiet: quiet);

  /// Exit group. The owner names the next owner in a last card; anyone
  /// else sends a signed "I left" note (the owner then makes the card).
  Future<void> leave(String gid) async {
    final old = await card(gid);
    if (old == null || !old.has(_self)) return;
    final others = old.members.where((m) => m.id != _self).toList();
    if (old.owner == _self && others.isNotEmpty) {
      others.sort((a, b) {
        if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
        final j = a.joinedAt.compareTo(b.joinedAt);
        return j != 0 ? j : a.id.compareTo(b.id);
      });
      final heir = others.first.id;
      await issue(
          gid,
          (o, now) => o.next(
                by: _self,
                at: now,
                owner: heir,
                left: [_self],
                members: [
                  for (final m in o.members)
                    if (m.id != _self)
                      m.id == heir ? m.copyWith(role: 'owner') : m
                ],
              ));
    } else if (others.isNotEmpty) {
      final at = _nowMs();
      final sig = await keys.sign(_leaveText(gid, _self, at));
      final id = 'leave:$gid:$_self:$at';
      for (final m in others) {
        await _queue(m.id, gid, id, 'leave', {
          'type': typeLeave,
          'gid': gid,
          'by': _self,
          'at': at,
          'sig': sig,
        });
      }
      await _writeLeaveLine(gid, old, _self, at);
    }
    await store.setState(gid, 'left');
    GroupChangeHub.instance.changed(gid);
    unawaited(flush());
  }

  static String _leaveText(String gid, String by, int at) =>
      'llgl1|$gid|$by|$at';

  // --------------------------------------------------------- messages

  /// My message (or reaction / delete note) to every member Nearby.
  Future<void> fanOut(String gid, String id, String body, String createdAt) async {
    final c = await card(gid);
    if (c == null || !c.has(_self)) return;
    // Bundle G4: signed by me (the writer) and kept for catch-up.
    String sig = '';
    try {
      sig = await keys.sign(messageText(gid, id, _self, createdAt, body));
    } catch (_) {}
    if (sig.isNotEmpty) {
      await _keepCopy(gid, id, _self, createdAt, body, sig);
    }
    final payload = {
      'type': typeMessage,
      'gid': gid,
      'id': id,
      'body': body,
      'created_at': createdAt,
      if (sig.isNotEmpty) 'w': _self,
      if (sig.isNotEmpty) 'sig': sig,
    };
    for (final m in c.members) {
      if (m.id == _self) continue;
      await _queue(m.id, gid, id, 'msg', payload);
    }
    unawaited(flush());
  }

  // ------------------------------------------------------------ queue

  Future<void> _queue(String member, String gid, String id, String kind,
      Map<String, dynamic> payload) async {
    final now = _nowMs();
    await store.putOutbox({
      'id': id,
      'member_id': member,
      'group_id': gid,
      'kind': kind,
      'payload': jsonEncode(payload),
      'tries': 0,
      'next_at': 0,
      'created_at': now,
    });
  }

  Future<void> _queueCard(GroupCard c, List<String> to) async {
    final id = 'card:${c.gid}:${c.version}';
    final rows = await store.outboxFor(c.gid);
    for (final member in to) {
      // Only the newest card waits for a member.
      for (final row in rows) {
        if (row['kind'] == 'card' && row['member_id'] == member) {
          await store.removeOutbox(row['id'].toString(), member);
        }
      }
      await _queue(member, c.gid, id, 'card',
          {'type': typeCard, 'gid': c.gid, 'card': c.toJson()});
    }
  }

  /// Sends what is due. [peerId] = that phone just came near: its packets
  /// go now (not at their next try time).
  Future<void> flush({String? peerId}) async {
    if (_flushing) {
      _flushAgain = true;
      return;
    }
    _flushing = true;
    try {
      do {
        _flushAgain = false;
        await _flushOnce(peerId);
      } while (_flushAgain);
    } finally {
      _flushing = false;
    }
  }

  Future<void> _flushOnce(String? peerId) async {
    final now = _nowMs();
    var rows = await store.dueOutbox(peerId == null ? now : 1 << 62);
    if (peerId != null) {
      rows = rows
          .where((r) =>
              r['member_id'] == peerId ||
              (int.tryParse(r['next_at']?.toString() ?? '') ?? 0) <= now)
          .toList();
    }
    if (rows.isEmpty) return;
    final cards = <String, GroupCard?>{};
    // Members that still wait for a card (due now or later).
    final waitingCard = <String>{};
    for (final gid in {for (final r in rows) r['group_id']?.toString() ?? ''}) {
      for (final r in await store.outboxFor(gid)) {
        if (r['kind'] == 'card') waitingCard.add('$gid|${r['member_id']}');
      }
    }
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      final member = row['member_id']?.toString() ?? '';
      final gid = row['group_id']?.toString() ?? '';
      final kind = row['kind']?.toString() ?? '';
      final created = int.tryParse(row['created_at']?.toString() ?? '') ?? now;
      if (now - created > keepFor.inMilliseconds) {
        await store.removeOutbox(id, member);
        if (kind == 'card') {
          final invite = (await store.invites(gid))
              .where((r) => r['member_id'] == member)
              .firstOrNull;
          if (invite?['state'] == 'waiting') {
            await store.setInvite(gid, member, 'failed', now);
            GroupChangeHub.instance.changed(gid);
          }
        }
        continue;
      }
      // "Sajjad added you" first, then the messages.
      if (kind != 'card' &&
          kind != 'leave' &&
          waitingCard.contains('$gid|$member')) {
        continue;
      }
      final c = cards.containsKey(gid) ? cards[gid] : (cards[gid] = await card(gid));
      // The member's key: from my newest card, else from an older card the
      // packet itself carries (a removed member still gets its last card).
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map);
      } catch (_) {
        await store.removeOutbox(id, member);
        continue;
      }
      var key = c?.member(member)?.seal;
      if (key == null && kind == 'card') {
        key = GroupCard.fromJson(payload['card'])?.member(member)?.seal;
      }
      key ??= (await store.friend(member))?.seal;
      if (key == null || key.isEmpty) {
        await store.removeOutbox(id, member);
        continue;
      }
      final tries = (int.tryParse(row['tries']?.toString() ?? '') ?? 0) + 1;
      final wait = _backoffSeconds[min(tries - 1, _backoffSeconds.length - 1)];
      await store.markTry(id, member, tries, now + wait * 1000);
      final ok = await send(
          recipientId: member, theirIdentityKey: key, payload: payload);
      if (tries == 1 || !ok) {
        AppLogger.info('GROUP_NEARBY_SEND',
            detail: 'kind=$kind try=$tries ok=$ok to=${_id6(member)}');
      }
    }
  }

  static String _id6(String id) =>
      id.length <= 6 ? id : id.substring(id.length - 6);

  Future<void> _ack(String to, String gid, String ref, {String? key}) async {
    final k = key ?? (await card(gid))?.member(to)?.seal ?? (await store.friend(to))?.seal;
    if (k == null || k.isEmpty) return;
    await send(
        recipientId: to,
        theirIdentityKey: k,
        payload: {'type': typeAck, 'gid': gid, 'ref': ref});
  }

  // --------------------------------------------------------- receiving

  Future<void> handleEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString() ?? '';
    if (type == 'peer_connected' || type == 'route_recovered' ||
        type == 'relay_connected') {
      final peer = event['peer_id']?.toString();
      unawaited(flush(peerId: (peer == null || peer.isEmpty) ? null : peer));
      // Bundle G4: a member came near - tell it what I have.
      if (peer != null && peer.isNotEmpty) {
        unawaited(catchUpWith(peer).catchError((Object e) {
          AppLogger.warning('GROUP_CATCHUP_FAILED', detail: '$e');
        }));
      }
      return;
    }
    if (type != 'message' || event['sealed'] != true) return;
    if (event['mesh_final_recipient'] == false) return;
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains('"group_')) return;
    Map<String, dynamic> p;
    try {
      p = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    await handlePacket(p);
  }

  /// One opened group packet (sender_id is the proven sender).
  Future<void> handlePacket(Map<String, dynamic> p) async {
    final type = p['type']?.toString() ?? '';
    final from = p['sender_id']?.toString() ?? '';
    final gid = p['gid']?.toString() ?? '';
    final self = _self;
    if (from.isEmpty || gid.isEmpty || self.isEmpty || from == self) return;
    if (await store.isBlocked(from)) return;
    // A not-friend opened with its own key: it must be that member's key.
    final strangerKey = (p['_locked_spk']?.toString() ?? '').replaceAll('=', '');
    switch (type) {
      case typeAck:
        await _onAck(from, gid, p['ref']?.toString() ?? '');
      case typeRead:
        await _onRead(from, gid, p, strangerKey);
      case typeCard:
        await _onCard(from, gid, p['card'], strangerKey);
      case typeMessage:
        await _onMessage(from, gid, p, strangerKey);
      case typeLeave:
        await _onLeave(from, gid, p, strangerKey);
      case typeHave:
        await _onHave(from, gid, p, strangerKey);
      case typeGive:
        await _onGive(from, gid, p, strangerKey);
      case typeNeed:
        await _onNeed(from, gid, strangerKey);
      case typeJoin:
        await _onJoin(from, gid, p, strangerKey);
      case typeJoinNo:
        await _onJoinNo(from, gid, strangerKey);
    }
  }

  bool _keyOk(GroupCard c, String from, String strangerKey) =>
      strangerKey.isEmpty || c.member(from)?.seal == strangerKey;

  Future<void> _onAck(String from, String gid, String ref) async {
    if (ref.isEmpty) return;
    await store.removeOutbox(ref, from);
    if (ref.startsWith('card:')) {
      final invite =
          (await store.invites(gid)).where((r) => r['member_id'] == from).firstOrNull;
      if (invite != null && invite['state'] != 'added') {
        await store.setInvite(gid, from, 'added', _nowMs());
        GroupChangeHub.instance.changed(gid);
      }
      // The card is there: its messages can go now.
      unawaited(flush(peerId: from));
      return;
    }
    if (ref.startsWith('leave:')) return;
    await store.markNearbySent(ref);
    await onSentNearby?.call(ref);
    // Bundle G5: this member got it.
    await onReceipt?.call(gid, ref, from, 'delivered');
  }

  /// Bundle G5: tell the writer I read these (only when my read receipts
  /// are on - the caller checks). Not kept for later.
  Future<bool> sendRead(String gid, String writer, List<String> ids) async {
    if (ids.isEmpty || writer.isEmpty || writer == _self) return false;
    final c = await card(gid);
    final k = c?.member(writer)?.seal ?? (await store.friend(writer))?.seal;
    if (k == null || k.isEmpty) return false;
    final list = ids.length > 200 ? ids.sublist(ids.length - 200) : ids;
    return send(
        recipientId: writer,
        theirIdentityKey: k,
        payload: {'type': typeRead, 'gid': gid, 'ids': list});
  }

  Future<void> _onRead(
      String from, String gid, Map<String, dynamic> p, String strangerKey) async {
    final c = await card(gid);
    if (c == null || c.member(from) == null || !_keyOk(c, from, strangerKey)) {
      return;
    }
    final raw = p['ids'];
    if (raw is! List) return;
    for (final id in raw.take(200)) {
      final text = id?.toString() ?? '';
      if (text.isEmpty || text.length > 128) continue;
      await onReceipt?.call(gid, text, from, 'read');
    }
  }

  Future<void> _onCard(
      String from, String gid, Object? raw, String strangerKey) async {
    final next = GroupCard.fromJson(raw);
    if (next == null || next.gid != gid) return;
    await applyCard(next, from: from, strangerKey: strangerKey);
  }

  /// Checks and keeps a card (from a packet or from the server). True =
  /// this phone now has this card (new or the same).
  Future<bool> applyCard(GroupCard next,
      {String from = '', String strangerKey = '', bool viaServer = false}) async {
    final self = _self;
    final gid = next.gid;
    final old = await card(gid);
    final local = await store.group(gid);
    String? signKey;
    if (old == null) {
      final friend = await store.friend(next.by);
      signKey = GroupCardRules.firstSigner(next,
          self: self, signerFriendSignKey: friend?.sign);
      // Bundle G4: or the admin whose group QR I scanned.
      final ask = signKey == null ? await _askFor(gid) : null;
      if (ask != null) {
        signKey = GroupCardRules.joinSigner(next,
            self: self, issuer: ask.issuer, issuerSign: ask.sign);
      }
      if (signKey == null) {
        AppLogger.info('GROUP_CARD_REFUSED', detail: 'why=not_friend_or_shape');
        return false;
      }
      if (from.isNotEmpty && strangerKey.isNotEmpty && !_keyOk(next, from, strangerKey)) {
        return false;
      }
    } else {
      if (from.isNotEmpty && !_keyOk(old, from, strangerKey) &&
          !_keyOk(next, from, strangerKey)) {
        return false;
      }
      if (next.version == old.version && next.signature == old.signature) {
        if (from.isNotEmpty) {
          await _ack(from, gid, 'card:$gid:${next.version}');
        }
        return true;
      }
      signKey = GroupCardRules.updateSigner(old, next);
      if (signKey == null) {
        // Older (or not allowed): say "got it" so the sender stops.
        if (from.isNotEmpty) {
          await _ack(from, gid, 'card:$gid:${next.version}');
        }
        return false;
      }
    }
    if (!await keys.verify(next.canonical(), next.signature, signKey)) {
      AppLogger.warning('GROUP_CARD_REFUSED', detail: 'why=signature');
      return false;
    }
    final inIt = next.has(self);
    var state = local?.state ?? 'active';
    if (inIt) {
      state = 'active';
    } else if (old != null && old.has(self)) {
      state = next.left.contains(self) ? 'left' : 'removed';
    } else if (old == null) {
      return false;
    }
    final origin = local?.origin ?? 'nearby';
    await store.saveGroupRow({...next.groupRow(), 'state': state});
    await store.saveCard(gid, next.encode(), next.version,
        origin: origin == 'server' ? 'both' : origin);
    final beforeIds = await store.memberIds(gid);
    if (inIt) await store.replaceMembers(gid, next.memberRows());
    final quietGroup = origin != 'nearby' || viaServer;
    if (!quietGroup) {
      await _writeLines(gid, old, next, presentBefore: beforeIds);
    }
    AppLogger.info('GROUP_CARD_APPLIED',
        detail: 'v=${next.version} new=${old == null} state=$state');
    if (old == null && inIt) {
      try {
        if ((await joins?.joins('ask', gid: gid))?.isNotEmpty ?? false) {
          await joins!.removeJoin('ask', gid);
          AppLogger.info('GROUP_JOIN_ADDED', detail: 'me by=${_id6(next.by)}');
        }
      } catch (_) {}
    }
    if (from.isNotEmpty) {
      await _ack(from, gid, 'card:$gid:${next.version}',
          key: next.member(from)?.seal ?? old?.member(from)?.seal);
    }
    GroupChangeHub.instance.changed(gid);
    return true;
  }

  Future<void> _onMessage(
      String from, String gid, Map<String, dynamic> p, String strangerKey) async {
    final id = p['id']?.toString() ?? '';
    final body = p['body']?.toString() ?? '';
    final createdAt = p['created_at']?.toString() ?? '';
    if (id.isEmpty || id.length > 128 || body.isEmpty || body.length > 16 * 1024) {
      return;
    }
    if (DateTime.tryParse(createdAt) == null) return;
    final c = await card(gid);
    final local = await store.group(gid);
    // Unknown group / sender not in my card yet: no "got it", the sender
    // tries again (after the card reaches me).
    if (c == null || local == null || !c.has(from) || !_keyOk(c, from, strangerKey)) {
      return;
    }
    // Bundle G4: copies from others come only through catch-up.
    final writer = p['w']?.toString() ?? '';
    if (writer.isNotEmpty && writer != from) return;
    final sig = p['sig']?.toString() ?? '';
    if (sig.isNotEmpty &&
        !await keys.verify(messageText(gid, id, from, createdAt, body), sig,
            c.member(from)!.sign)) {
      AppLogger.warning('GROUP_RX_BAD_SIG', detail: 'from=${_id6(from)}');
      return;
    }
    if (!local.isActive) {
      await _ack(from, gid, id);
      return;
    }
    final announcement = c.sendMessages == 'admins' && !c.isAdmin(from);
    if (!announcement && !await store.messageExists(id)) {
      await onMessage(GroupMessage(
          id: id, groupId: gid, senderId: from, body: body, createdAt: createdAt));
    }
    if (!announcement && sig.isNotEmpty) {
      await _keepCopy(gid, id, from, createdAt, body, sig);
    }
    await _ack(from, gid, id);
  }

  Future<void> _onLeave(
      String from, String gid, Map<String, dynamic> p, String strangerKey) async {
    final by = p['by']?.toString() ?? '';
    final at = int.tryParse(p['at']?.toString() ?? '') ?? 0;
    final sig = p['sig']?.toString() ?? '';
    final c = await card(gid);
    final ref = 'leave:$gid:$by:$at';
    if (c == null || by != from || at <= 0 || !_keyOk(c, from, strangerKey)) {
      return;
    }
    final m = c.member(by);
    if (m == null) {
      await _ack(from, gid, ref);
      return;
    }
    if (!await keys.verify(_leaveText(gid, by, at), sig, m.sign)) return;
    final present = await store.memberIds(gid);
    if (present.contains(by)) {
      await store.removeMember(gid, by);
      await _writeLeaveLine(gid, c, by, at);
    }
    await _ack(from, gid, ref, key: m.seal);
    // The owner makes the card without them (everyone gets it).
    if (c.owner == _self) {
      try {
        await issue(
            gid,
            (o, now) => o.next(
                by: _self,
                at: now,
                left: [by],
                members: o.members.where((x) => x.id != by).toList()),
            quiet: true);
      } catch (_) {}
    }
    GroupChangeHub.instance.changed(gid);
  }

  // ------------------------------------------ Bundle G4: Join with QR

  static const String typeJoin = 'group_join';
  static const String typeJoinNo = 'group_join_no';
  static const Duration qrLife = Duration(hours: 24);
  static const int maxRequests = 20;

  /// What the scanner signs when it asks to join.
  static String joinText(String gid, String token, String who) =>
      'llgj1\n$gid\n$token\n$who';

  /// A friend of the scanner, as a short hash (the friend list never
  /// leaves the phone).
  static String friendHash(String gid, String id) =>
      sha256.convert(utf8.encode('$gid|$id')).toString().substring(0, 12);

  static String _token() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// Mock 36: this group's code. A new one is put on the card when there is
  /// none, it is older than 1 hour (so "Expires in 24 hours" stays true) or
  /// on "Reset code" (the old one stops working). Admins only.
  Future<GroupJoinCode> inviteCode(String gid, {bool reset = false}) async {
    var c = await card(gid);
    if (c == null || !c.has(_self)) {
      throw const GroupActionException(
          'GROUP_NOT_MEMBER', "You're no longer a participant in this group.");
    }
    if (!c.isAdmin(_self)) {
      throw const GroupActionException(
          'GROUP_ADMINS_ONLY', 'Only admins can do this.');
    }
    final now = _nowMs();
    final fresh = c.qrToken.isNotEmpty &&
        c.qrUntil - now > qrLife.inMilliseconds - const Duration(hours: 1).inMilliseconds;
    if (reset || !fresh) {
      final token = _token();
      c = await issue(
          gid,
          (old, at) => old.next(
              by: _self,
              at: at,
              qrToken: token,
              qrUntil: at + qrLife.inMilliseconds),
          quiet: true);
      AppLogger.info('GROUP_QR_MADE', detail: 'reset=$reset');
    }
    final me = c.member(_self)!;
    return GroupJoinCode(
      gid: gid,
      name: c.name,
      count: c.members.length,
      issuer: _self,
      issuerName: me.name,
      seal: me.seal,
      sign: me.sign,
      token: c.qrToken,
      until: c.qrUntil,
      names: [for (final m in c.members.take(4)) m.name],
    );
  }

  Future<GroupJoinCode?> _askFor(String gid) async {
    final rows = await joins?.joins('ask', gid: gid) ?? const [];
    for (final r in rows) {
      final at = int.tryParse(r['at']?.toString() ?? '') ?? 0;
      if (_nowMs() - at > qrLife.inMilliseconds) continue;
      try {
        final code = GroupJoinCode.fromJson(jsonDecode(r['data']?.toString() ?? ''));
        if (code != null) return code;
      } catch (_) {}
    }
    return null;
  }

  /// I am in this group now (e.g. after "Sajjad added you").
  Future<bool> inGroup(String gid) async =>
      (await store.group(gid))?.isActive ?? false;

  /// Mock 38: "none" | "asked" (Requested ✓) | "expired" (the admin's
  /// phone said the code is old / was reset).
  Future<String> joinState(String gid) async {
    final rows = await joins?.joins('ask', gid: gid) ?? const [];
    if (rows.isEmpty) return 'none';
    final r = rows.first;
    final at = int.tryParse(r['at']?.toString() ?? '') ?? 0;
    if (_nowMs() - at > qrLife.inMilliseconds) {
      await joins?.removeJoin('ask', gid);
      return 'none';
    }
    try {
      final data = jsonDecode(r['data']?.toString() ?? '');
      if (data is Map && data['no']?.toString() == '1') return 'expired';
    } catch (_) {}
    return 'asked';
  }

  /// I scanned a group QR: ask the admin who made it (locked with the key
  /// from the code; any LinkUp phone can carry it, no internet needed).
  Future<void> askToJoin(GroupJoinCode code) async {
    final j = joins;
    if (j == null) {
      throw const GroupActionException(
          'GROUP_JOIN_OFF', "Couldn't ask to join. Try again.");
    }
    final now = _nowMs();
    if (code.expired(now)) {
      AppLogger.info('GROUP_JOIN_QR', detail: 'why=expired');
      throw const GroupActionException(
          'GROUP_QR_EXPIRED', GroupJoinCode.expiredText);
    }
    final local = await store.group(code.gid);
    if (code.issuer == _self || (local != null && local.isActive)) {
      throw const GroupActionException(
          'GROUP_ALREADY_IN', "You're already in this group.");
    }
    if (await store.isBlocked(code.issuer)) {
      throw const GroupActionException(
          'GROUP_JOIN_BLOCKED', "You can't join this group.");
    }
    AppLogger.info('GROUP_JOIN_QR', detail: 'from=${_id6(code.issuer)}');
    final sig = await keys.sign(joinText(code.gid, code.token, _self));
    final friends = await j.friendIds();
    await j.putJoin('ask', code.gid, code.issuer, jsonEncode(code.toJson()), now);
    await send(recipientId: code.issuer, theirIdentityKey: code.seal, payload: {
      'type': typeJoin,
      'gid': code.gid,
      't': code.token,
      'n': await store.selfName(),
      'u': j.selfUsername,
      'k': (await keys.ownSealKey()).replaceAll('=', ''),
      's': (await keys.ownSignKey()).replaceAll('=', ''),
      'sig': sig,
      'fr': [for (final f in friends.take(200)) friendHash(code.gid, f)],
    });
    AppLogger.info('GROUP_JOIN_ASKED', detail: 'to=${_id6(code.issuer)}');
    GroupChangeHub.instance.changed(code.gid);
  }

  Future<void> _onJoin(
      String from, String gid, Map<String, dynamic> p, String strangerKey) async {
    final j = joins;
    final c = await card(gid);
    final local = await store.group(gid);
    if (j == null || c == null || local == null || !local.isActive) return;
    if (!c.isAdmin(_self)) return;
    final friend = await store.friend(from);
    final packetSeal = (p['k']?.toString() ?? '').replaceAll('=', '');
    if (strangerKey.isNotEmpty && packetSeal != strangerKey) return;
    final seal = friend?.seal.replaceAll('=', '') ?? strangerKey;
    final sign = friend?.sign.replaceAll('=', '') ??
        (p['s']?.toString() ?? '').replaceAll('=', '');
    if (seal.length < 42 || seal.length > 44 || sign.length < 42 || sign.length > 44) {
      return;
    }
    final token = p['t']?.toString() ?? '';
    final now = _nowMs();
    if (!c.qrValid(token, now)) {
      AppLogger.info('GROUP_JOIN_REFUSED', detail: 'why=expired from=${_id6(from)}');
      await send(
          recipientId: from,
          theirIdentityKey: seal,
          payload: {'type': typeJoinNo, 'gid': gid, 'why': 'expired'});
      return;
    }
    if (!await keys.verify(
        joinText(gid, token, from), p['sig']?.toString() ?? '', sign)) {
      AppLogger.warning('GROUP_JOIN_REFUSED', detail: 'why=signature');
      return;
    }
    if (c.has(from)) {
      await _queueCard(c, [from]);
      unawaited(flush(peerId: from));
      return;
    }
    var name = (p['n']?.toString() ?? '').trim();
    if (name.isEmpty) name = friend?.name ?? 'LinkUp user';
    if (name.length > 40) name = name.substring(0, 40);
    if (!c.approve) {
      try {
        await _addJoiner(gid, from, name, seal, sign);
      } on GroupActionException catch (e) {
        AppLogger.info('GROUP_JOIN_REFUSED', detail: 'why=${e.code}');
      }
      return;
    }
    final pending = await j.joins('req', gid: gid);
    if (pending.length >= maxRequests &&
        !pending.any((r) => r['member_id'] == from)) {
      AppLogger.info('GROUP_JOIN_REFUSED', detail: 'why=too_many');
      return;
    }
    final raw = p['fr'];
    final hashes = <String>{
      if (raw is List)
        for (final e in raw.take(300)) e.toString(),
    };
    final via = [
      for (final m in c.members)
        if (m.id != _self && hashes.contains(friendHash(gid, m.id))) m.id
    ];
    var username = (p['u']?.toString() ?? '').trim();
    if (username.length > 40) username = username.substring(0, 40);
    await j.putJoin(
        'req',
        gid,
        from,
        jsonEncode({
          'n': name,
          'u': username,
          'k': seal,
          's': sign,
          'via': via,
          'f': friend != null ? 1 : 0,
        }),
        now);
    AppLogger.info('GROUP_JOIN_REQUEST', detail: 'from=${_id6(from)}');
    GroupChangeHub.instance.changed(gid);
  }

  Future<void> _onJoinNo(String from, String gid, String strangerKey) async {
    final j = joins;
    final code = await _askFor(gid);
    if (j == null || code == null || code.issuer != from) return;
    if (strangerKey.isNotEmpty && strangerKey != code.seal.replaceAll('=', '')) {
      return;
    }
    await j.putJoin('ask', gid, from,
        jsonEncode({...code.toJson(), 'no': 1}), _nowMs());
    GroupChangeHub.instance.changed(gid);
  }

  Future<void> _addJoiner(
      String gid, String id, String name, String seal, String sign) async {
    await issue(gid, (old, now) {
      if (old.has(id)) return old.next(by: _self, at: now);
      if (old.members.length >= GroupCard.maxMembers) {
        throw const GroupActionException(
            'GROUP_TOO_BIG', 'Nearby groups can have up to 32 people.');
      }
      final joined =
          DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String();
      return old.next(by: _self, at: now, members: [
        ...old.members,
        GroupCardMember(
            id: id,
            name: name,
            role: 'member',
            seal: seal,
            sign: sign,
            addedBy: _self,
            joinedAt: joined),
      ]);
    });
    await joins?.removeJoin('req', gid, member: id);
    AppLogger.info('GROUP_JOIN_ADDED', detail: 'who=${_id6(id)}');
  }

  /// Bundle G6: my public keys for a card, sent with "Ask to join" by link.
  Future<(String, String)> ownCardKeys() async => (
        (await keys.ownSealKey()).replaceAll('=', ''),
        (await keys.ownSignKey()).replaceAll('=', ''),
      );

  /// Bundle G6: an admin said yes to someone who asked by invite link. The
  /// keys came with the request (through the server).
  Future<void> addByKeys(String gid, String id, String name, String seal,
      String sign, {bool quiet = false}) async {
    if (seal.isEmpty || sign.isEmpty) {
      throw const GroupActionException('GROUP_NO_KEYS',
          'Ask them to open the link again with the newest LinkUp.');
    }
    await issue(gid, (old, now) {
      if (old.has(id)) return old.next(by: _self, at: now);
      if (old.members.length >= GroupCard.maxMembers) {
        throw const GroupActionException(
            'GROUP_TOO_BIG', 'Nearby groups can have up to 32 people.');
      }
      final joined =
          DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String();
      return old.next(by: _self, at: now, members: [
        ...old.members,
        GroupCardMember(
            id: id,
            name: name,
            role: 'member',
            seal: seal.replaceAll('=', ''),
            sign: sign.replaceAll('=', ''),
            addedBy: _self,
            joinedAt: joined),
      ]);
    }, quiet: quiet);
    AppLogger.info('GROUP_LINK_ADDED', detail: 'who=${_id6(id)}');
  }

  /// Mock 37: people who scanned the QR and wait (newest 24 hours).
  Future<List<GroupJoinRequest>> joinRequests(String gid) async {
    final j = joins;
    final c = await card(gid);
    if (j == null || c == null || !c.isAdmin(_self)) return const [];
    final now = _nowMs();
    final out = <GroupJoinRequest>[];
    for (final r in await j.joins('req', gid: gid)) {
      final id = r['member_id']?.toString() ?? '';
      final at = int.tryParse(r['at']?.toString() ?? '') ?? 0;
      if (now - at > qrLife.inMilliseconds || c.has(id)) {
        await j.removeJoin('req', gid, member: id);
        continue;
      }
      Map data = const {};
      try {
        final d = jsonDecode(r['data']?.toString() ?? '');
        if (d is Map) data = d;
      } catch (_) {}
      final via = data['via'];
      out.add(GroupJoinRequest(
        memberId: id,
        name: data['n']?.toString() ?? 'LinkUp user',
        username: data['u']?.toString() ?? '',
        atMs: at,
        friend: data['f']?.toString() == '1',
        viaNames: [
          if (via is List)
            for (final v in via)
              if (c.member(v.toString()) != null) c.member(v.toString())!.name
        ],
      ));
    }
    return out;
  }

  /// Mock 37 "Add to group".
  Future<void> addJoiner(String gid, String memberId) async {
    final rows = await joins?.joins('req', gid: gid) ?? const [];
    final r = rows.where((r) => r['member_id'] == memberId).firstOrNull;
    if (r == null) return;
    final d = jsonDecode(r['data']?.toString() ?? '{}') as Map;
    await _addJoiner(gid, memberId, d['n']?.toString() ?? 'LinkUp user',
        d['k']?.toString() ?? '', d['s']?.toString() ?? '');
  }

  /// Mock 37 "Ignore" (the scanner is not told).
  Future<void> ignoreJoiner(String gid, String memberId) async {
    await joins?.removeJoin('req', gid, member: memberId);
    AppLogger.info('GROUP_JOIN_REFUSED', detail: 'why=ignored');
    GroupChangeHub.instance.changed(gid);
  }

  // ---------------------------------------------- Bundle G4: catch-up

  Future<void> _keepCopy(String gid, String id, String writer, String createdAt,
      String body, String sig) async {
    final c = copies;
    if (c == null) return;
    try {
      await c.putCopy(GroupCopy(
          id: id,
          gid: gid,
          writer: writer,
          createdAt: createdAt,
          body: body,
          sig: sig,
          keptAt: _nowMs()));
    } catch (_) {}
  }

  bool _batteryOk() {
    bool ok;
    try {
      ok = catchUpAllowed?.call() ?? true;
    } catch (_) {
      ok = true;
    }
    if (!ok && !_batteryLogged) {
      _batteryLogged = true;
      AppLogger.info('GROUP_CATCHUP', detail: 'skipped why=battery');
    } else if (ok) {
      _batteryLogged = false;
    }
    return ok;
  }

  /// [peer] came near: for each Nearby group we share, say which messages
  /// I have (last 7 days, at most 500). At most once per 2 min per group
  /// and member; never at 10% battery or less.
  Future<void> catchUpWith(String peer) async {
    final store2 = copies;
    if (store2 == null || peer.isEmpty || peer == _self) return;
    if (!_batteryOk()) return;
    final now = _nowMs();
    await store2.purgeCopies(now - keepFor.inMilliseconds);
    for (final g in await store.groups()) {
      if (!g.isActive) continue;
      final c = await card(g.id);
      if (c == null || !c.has(_self) || !c.has(peer)) continue;
      await _sendHave(c, peer, now);
    }
  }

  Future<void> _sendHave(GroupCard c, String peer, int now) async {
    final store2 = copies;
    if (store2 == null) return;
    final key = '${c.gid}|$peer';
    final last = _lastHave[key];
    if (last != null && now - last < catchUpGap.inMilliseconds) return;
    _lastHave[key] = now;
    final seal = c.member(peer)?.seal ?? '';
    if (seal.isEmpty) return;
    final mine = await store2.copies(c.gid, limit: catchUpMax);
    await send(recipientId: peer, theirIdentityKey: seal, payload: {
      'type': typeHave,
      'gid': c.gid,
      'v': c.version,
      'ids': [for (final m in mine) shortId(m.id)],
    });
  }

  Future<void> _sendNeed(String to, String gid, String key) async {
    if (key.isEmpty) return;
    final now = _nowMs();
    final last = _lastNeed[gid];
    if (last != null && now - last < catchUpGap.inMilliseconds) return;
    _lastNeed[gid] = now;
    AppLogger.info('GROUP_CATCHUP', detail: 'need_card from=${_id6(to)}');
    await send(
        recipientId: to,
        theirIdentityKey: key,
        payload: {'type': typeNeed, 'gid': gid});
  }

  Future<void> _onHave(
      String from, String gid, Map<String, dynamic> p, String strangerKey) async {
    final c = await card(gid);
    if (c == null) {
      // A group I don't know yet: I missed "… added you". Ask for the card.
      final key = strangerKey.isNotEmpty
          ? strangerKey
          : (await store.friend(from))?.seal ?? '';
      await _sendNeed(from, gid, key);
      return;
    }
    if (!c.has(_self) || !c.has(from) || !_keyOk(c, from, strangerKey)) return;
    final local = await store.group(gid);
    if (local == null || !local.isActive) return;
    final theirVersion = int.tryParse(p['v']?.toString() ?? '') ?? 0;
    if (theirVersion < c.version) {
      await _queueCard(c, [from]);
      unawaited(flush(peerId: from));
    } else if (theirVersion > c.version) {
      await _sendNeed(from, gid, c.member(from)!.seal);
    }
    final store2 = copies;
    if (store2 == null || !_batteryOk()) return;
    final raw = p['ids'];
    final theirs = <String>{
      if (raw is List)
        for (final e in raw.take(catchUpMax + 100)) e.toString(),
    };
    final joined = DateTime.tryParse(c.member(from)!.joinedAt);
    final missing = <GroupCopy>[];
    for (final copy in await store2.copies(gid, limit: catchUpMax)) {
      if (copy.writer == from || theirs.contains(shortId(copy.id))) continue;
      final at = DateTime.tryParse(copy.createdAt);
      if (at == null) continue;
      // A new member gets only messages from when they joined.
      if (joined != null && at.isBefore(joined)) continue;
      if (!c.has(copy.writer)) continue;
      missing.add(copy);
    }
    // Answer with my own list too (the other phone may not have asked).
    unawaited(_sendHave(c, from, _nowMs()));
    if (missing.isEmpty) return;
    missing.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final seal = c.member(from)!.seal;
    var page = <Map<String, String>>[];
    var bytes = 0;
    var gave = 0;
    Future<void> sendPage() async {
      if (page.isEmpty) return;
      final items = page;
      page = <Map<String, String>>[];
      bytes = 0;
      await send(
          recipientId: from,
          theirIdentityKey: seal,
          payload: {'type': typeGive, 'gid': gid, 'items': items});
    }

    for (final copy in missing) {
      final item = {
        'id': copy.id,
        'w': copy.writer,
        'c': copy.createdAt,
        'b': copy.body,
        's': copy.sig,
      };
      final size = copy.body.length + copy.id.length + copy.sig.length + 120;
      if (page.length >= pageItems || (page.isNotEmpty && bytes + size > pageBytes)) {
        await sendPage();
      }
      page.add(item);
      bytes += size;
      gave++;
    }
    await sendPage();
    AppLogger.info('GROUP_CATCHUP', detail: 'gave=$gave to=${_id6(from)}');
  }

  Future<void> _onGive(
      String from, String gid, Map<String, dynamic> p, String strangerKey) async {
    final c = await card(gid);
    final local = await store.group(gid);
    if (c == null || local == null || !local.isActive) return;
    if (!c.has(_self) || !c.has(from) || !_keyOk(c, from, strangerKey)) return;
    final raw = p['items'];
    if (raw is! List) return;
    final myJoin = DateTime.tryParse(c.member(_self)!.joinedAt);
    var got = 0;
    for (final e in raw.take(pageItems + 10)) {
      if (e is! Map) continue;
      final id = e['id']?.toString() ?? '';
      final writer = e['w']?.toString() ?? '';
      final createdAt = e['c']?.toString() ?? '';
      final body = e['b']?.toString() ?? '';
      final sig = e['s']?.toString() ?? '';
      if (id.isEmpty || id.length > 128 || body.isEmpty ||
          body.length > 16 * 1024 || sig.isEmpty || writer == _self) {
        continue;
      }
      final w = c.member(writer);
      if (w == null) continue;
      final at = DateTime.tryParse(createdAt);
      if (at == null) continue;
      if (myJoin != null && at.isBefore(myJoin)) continue;
      if (c.sendMessages == 'admins' && !c.isAdmin(writer)) continue;
      if (await store.messageExists(id)) continue;
      if (!await keys.verify(
          messageText(gid, id, writer, createdAt, body), sig, w.sign)) {
        AppLogger.warning('GROUP_RX_BAD_SIG',
            detail: 'via=${_id6(from)} writer=${_id6(writer)}');
        continue;
      }
      await onMessage(GroupMessage(
          id: id, groupId: gid, senderId: writer, body: body, createdAt: createdAt));
      await _keepCopy(gid, id, writer, createdAt, body, sig);
      got++;
      // The writer gets "got it" too (its ✓ for me).
      unawaited(_ack(writer, gid, id).catchError((Object _) {}));
    }
    if (got > 0) {
      AppLogger.info('GROUP_CATCHUP', detail: 'got=$got via=${_id6(from)}');
    }
  }

  Future<void> _onNeed(String from, String gid, String strangerKey) async {
    final c = await card(gid);
    if (c == null || !c.has(_self) || !c.has(from)) return;
    if (!_keyOk(c, from, strangerKey)) return;
    await _queueCard(c, [from]);
    unawaited(flush(peerId: from));
  }

  // ------------------------------------------------------ system lines

  Future<void> _writeLines(String gid, GroupCard? old, GroupCard next,
      {Set<String>? presentBefore}) async {
    final events = GroupCardRules.events(old, next, self: _self);
    var i = 0;
    for (final e in events) {
      i++;
      // A leave line was already written from the leave note.
      if (e.kind == 'leave' &&
          presentBefore != null &&
          !presentBefore.contains(e.by)) {
        continue;
      }
      final id = '${next.at}000-gev-${next.version}-$i-$gid';
      await _saveLine(gid, id, e, next.at, e.kind == 'leave' ? e.by : next.by);
    }
  }

  Future<void> _writeLeaveLine(String gid, GroupCard c, String by, int at) async {
    final names = {
      for (final m in c.members)
        if (m.name.isNotEmpty && m.id != _self) m.id: m.name
    };
    await _saveLine(gid, '${at}000-gev-left-$by-$gid',
        GroupEvent(kind: 'leave', by: by, names: names), at, by);
  }

  Future<void> _saveLine(
      String gid, String id, GroupEvent e, int atMs, String sender) async {
    if (await store.messageExists(id)) return;
    final message = GroupMessage(
      id: id,
      groupId: gid,
      senderId: sender,
      body: e.encode(),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: true).toIso8601String(),
    );
    await onMessage(message);
  }

  // --------------------------------------------------- "Adding…" banner

  /// Mock 6/7: who is added / waiting / couldn't be added (my invites).
  Future<List<GroupInviteState>> invites(String gid) async {
    final c = await card(gid);
    final rows = await store.invites(gid);
    final out = <GroupInviteState>[];
    for (final r in rows) {
      final id = r['member_id']?.toString() ?? '';
      final m = c?.member(id);
      if (m == null) continue;
      out.add(GroupInviteState(
        memberId: id,
        name: m.name,
        state: r['state']?.toString() ?? 'waiting',
        atMs: int.tryParse(r['at']?.toString() ?? '') ?? 0,
      ));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// "Try again" for someone not reached in 7 days.
  Future<void> retryInvite(String gid, String memberId) async {
    final c = await card(gid);
    if (c == null || !c.has(memberId)) return;
    await store.setInvite(gid, memberId, 'waiting', _nowMs());
    await _queueCard(c, [memberId]);
    GroupChangeHub.instance.changed(gid);
    unawaited(flush(peerId: memberId));
  }

  // ------------------------------------------------------------ bridge

  /// The server is back: groups I own that are only on phones are put on
  /// the server with the same id ([upload] true = done). From then on the
  /// normal group outbox sends my waiting messages (the bridge).
  Future<int> bridge(Future<bool> Function(GroupCard card) upload) async {
    var done = 0;
    for (final g in await store.groups()) {
      if (g.origin != 'nearby' || !g.isActive) continue;
      final c = await card(g.id);
      if (c == null || c.owner != _self) continue;
      try {
        if (await upload(c)) {
          await store.setOrigin(g.id, 'both');
          done++;
          GroupChangeHub.instance.changed(g.id);
        }
      } catch (e) {
        AppLogger.warning('GROUP_BRIDGE_FAILED', detail: '$e');
      }
    }
    if (done > 0) AppLogger.info('GROUP_BRIDGED', detail: 'groups=$done');
    return done;
  }

  /// A card that came through the server ('both' groups). True = handled.
  Future<bool> consumeServerCard(GroupMessage m) async {
    if (!m.body.startsWith(cardBodyPrefix)) return false;
    try {
      final next =
          GroupCard.fromJson(jsonDecode(m.body.substring(cardBodyPrefix.length)));
      if (next != null && next.gid == m.groupId && next.by == m.senderId) {
        await applyCard(next, viaServer: true);
      }
    } catch (_) {}
    return true;
  }
}

/// Bundle G4 (mock 37): someone who scanned the group QR.
class GroupJoinRequest {
  const GroupJoinRequest({
    required this.memberId,
    required this.name,
    required this.username,
    required this.atMs,
    this.friend = false,
    this.viaNames = const [],
    this.via = 'qr',
    this.seal = '',
    this.sign = '',
  });
  final String memberId;
  final String name;
  final String username;
  final int atMs;

  /// Bundle G6: 'qr' (scanned, Nearby) or 'link' (opened the invite link).
  final String via;

  /// Bundle G6: the asker's card keys (link requests, through the server).
  final String seal;
  final String sign;

  /// Already my friend.
  final bool friend;

  /// Members who are the scanner's friends.
  final List<String> viaNames;
}

/// Bundle G3 (mock 7): one row of "Adding people".
class GroupInviteState {
  const GroupInviteState(
      {required this.memberId,
      required this.name,
      required this.state,
      required this.atMs});
  final String memberId;
  final String name;

  /// "waiting" | "added" | "failed".
  final String state;
  final int atMs;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
