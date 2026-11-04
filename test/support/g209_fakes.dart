// Bundle 209: the G7 group fakes (copied from groups_g7_test.dart, public)
// for the bundle 209 tests: phones near each other, a group store, files.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';

import 'phase5_fakes.dart';

String g9Key(String who, String kind) => '$who-$kind-'.padRight(43, 'x');


// ------------------------------------------------------------ fakes ---

class G9Store implements GroupNearbyStore {
  G9Store(this.selfId);
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

class G9Copies implements GroupCopyStore {
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

class G9Joins implements GroupJoinStore {
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
class G9Air {
  final phones = <String, G9Phone>{};
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

class G9Phone {
  G9Phone(this.air, this.id) : store = G9Store(id) {
    service = GroupNearbyService(
      store: store,
      keys: GroupCardKeys(
        sign: (text) async => 'S:${g9Key(id, 'sign')}:${text.hashCode}',
        verify: (text, sig, key) async => sig == 'S:$key:${text.hashCode}',
        ownSignKey: () async => g9Key(id, 'sign'),
        ownSealKey: () async => g9Key(id, 'seal'),
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
    files = GroupFileSender(
      store: fileStore,
      source: (msg, file) async => sources['$msg|$file'],
      sendFile: ({required memberId, required messageId, required wireId, required file}) async {
        if (sendFails) throw StateError('no route');
        fileSends.add('$memberId|$messageId|$wireId');
      },
      lowBattery: () => lowBattery,
      nowMs: () => air.now,
    );
    service.files = files;
    service.onTyping = (gid, member, on) => typing.add('$gid|$member|$on');
    service.onPhotoNote = (gid, v, h, by) async {
      photoNotes.add('$gid|$v|$h|$by');
      return true;
    };
  }

  final MemoryGroupFileSendStore fileStore = MemoryGroupFileSendStore();
  late final GroupFileSender files;
  final sources = <String, PickedFile>{};
  final fileSends = <String>[];
  final typing = <String>[];
  final photoNotes = <String>[];
  bool sendFails = false;
  bool lowBattery = false;

  /// An old app (3.0.42): its "got it" has no fv.
  bool oldApp = false;

  final G9Air air;
  final String id;
  final G9Store store;
  final G9Copies copyStore = G9Copies();
  final G9Joins joinStore = G9Joins();
  bool batteryOk = true;
  late final GroupNearbyService service;
  final got = <GroupMessage>[];
  final sentNearby = <String>[];
  final sentTo = <String>[];
  final serverPosts = <String>[];
  final sentPayloads = <Map<String, dynamic>>[];

  void befriend(G9Phone other) {
    store.friends[other.id] = GroupFriendKeys(
        id: other.id,
        name: other.id.toUpperCase(),
        seal: g9Key(other.id, 'seal'),
        sign: g9Key(other.id, 'sign'));
  }

  Future<bool> _send({
    required String recipientId,
    required String theirIdentityKey,
    required Map<String, dynamic> payload,
  }) async {
    sentTo.add('$recipientId:${payload['type']}');
    sentPayloads.add(Map<String, dynamic>.from(payload));
    if (oldApp && payload['type'] == 'group_ack') {
      payload = Map<String, dynamic>.from(payload)..remove('fv');
    }
    expect(theirIdentityKey, g9Key(recipientId, 'seal'),
        reason: 'locked with the member key');
    final to = air.phones[recipientId];
    if (to == null || air.away.contains(recipientId)) return true;
    final stranger = !to.store.friends.containsKey(id);
    air._queue.add(() => to.service.handlePacket({
          ...jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
          'sender_id': id,
          'recipient_id': recipientId,
          if (stranger) '_locked_spk': g9Key(id, 'seal'),
        }));
    return true;
  }
}

Future<void> g9Settle(G9Air air) async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
    await air.pump();
  }
}

// 2026-11-03 10:00 UTC
const g9T0 = 1793700000000;


/// Bundle G7: FakeStore + what the group file code reads / writes.
class G9GStore extends FakeStore {
  final direct = <String, Map<String, dynamic>>{};
  final pending = <String, List<Map<String, dynamic>>>{};

  @override
  Future<GroupMessage?> groupMessageById(String id) async {
    for (final rows in groupMessageRows.values) {
      for (final r in rows) {
        if (r['id'] == id) return GroupMessage.fromJson(r);
      }
    }
    return null;
  }

  @override
  Future<void> setGroupAttachmentLocalPath(
      String messageId, String fileId, String path) async {
    for (final rows in groupMessageRows.values) {
      for (final r in rows) {
        if (r['id'] != messageId) continue;
        r['attachments'] = [
          for (final a in (r['attachments'] as List))
            (a as Map)['id'] == fileId
                ? {...Map<String, dynamic>.from(a), 'local_path': path}
                : a
        ];
      }
    }
  }

  @override
  Future<Map<String, dynamic>?> directFile(String fileId) async => direct[fileId];

  @override
  Future<void> addPendingGroupAttachment(
      {required String id, required String messageId, required PickedFile file}) async {
    (pending[messageId] ??= []).add({
      'id': id,
      'message_id': messageId,
      'local_path': file.path,
      'original_name': file.name,
      'content_type': file.contentType,
      'size': file.size,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> pendingGroupAttachments(String messageId) async =>
      pending[messageId] ?? const [];
}

class G9GFiles extends FakeFilesRepository {
  final staged = <String>[];
  final cancelled = <String>[];
  @override
  Future<String> stageOutgoingFile({required PickedFile file, required String fileId}) async {
    staged.add(fileId);
    return '/app/attachments/$fileId';
  }

  @override
  Future<void> cancelDirectFile(String fileId) async => cancelled.add(fileId);
}

String g9At(int minutes) =>
    DateTime.fromMillisecondsSinceEpoch(g9T0 + minutes * 60000, isUtc: true)
        .toIso8601String();

const g9Photo = GroupNearbyFile(
    id: 'f1', name: 'a.jpg', type: 'image/jpeg', size: 200000);
const g9Voice = GroupNearbyFile(
    id: 'f2', name: 'v.m4a', type: 'audio/mp4', size: 40000);

PickedFile g9Picked(GroupNearbyFile f) =>
    PickedFile(path: '/x/${f.name}', name: f.name, contentType: f.type, size: f.size);

/// Bundle 209: a copy with another sig3 (tests).
extension GroupCopyX on GroupCopy {
  static GroupCopy withSig3(GroupCopy c, String sig3) => GroupCopy(
      id: c.id,
      gid: c.gid,
      writer: c.writer,
      createdAt: c.createdAt,
      body: c.body,
      sig: c.sig,
      keptAt: c.keptAt,
      att: c.att,
      sig2: c.sig2,
      sig3: sig3);
}
