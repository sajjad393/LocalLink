import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';
import 'package:locallink/features/files/data/services/media_transfer_actions.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:io';
import 'package:locallink/core/services/locallink_api.dart' show LocalLinkApi;
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';
import 'support/phase5_fakes.dart';

// Bundle G7: group photos / videos / voice notes / files with no
// internet (file list in the message, the sender sends to each member,
// fv:2, old phones, catch-up with files, Tap to download asks, typing,
// group photo note, pair file keys, upload rule, watch).

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
  final sentPayloads = <Map<String, dynamic>>[];

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
    sentPayloads.add(Map<String, dynamic>.from(payload));
    if (oldApp && payload['type'] == 'group_ack') {
      payload = Map<String, dynamic>.from(payload)..remove('fv');
    }
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


/// Bundle G7: FakeStore + what the group file code reads / writes.
class _GStore extends FakeStore {
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

class _GFiles extends FakeFilesRepository {
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

String _at(int minutes) =>
    DateTime.fromMillisecondsSinceEpoch(_t0 + minutes * 60000, isUtc: true)
        .toIso8601String();

const _photo = GroupNearbyFile(
    id: 'f1', name: 'a.jpg', type: 'image/jpeg', size: 200000);
const _voice = GroupNearbyFile(
    id: 'f2', name: 'v.m4a', type: 'audio/mp4', size: 40000);

PickedFile _picked(GroupNearbyFile f) =>
    PickedFile(path: '/x/${f.name}', name: f.name, contentType: f.type, size: f.size);

void main() {
  group('file list + wire ids (G7)', () {
    test('a file id per member; the member finds its own file', () {
      final a = GroupFileWire.wireId('f1', 'ali');
      final s = GroupFileWire.wireId('f1', 'sara');
      expect(a, isNot(s));
      expect(GroupFileWire.isWire(a), isTrue);
      expect(GroupFileWire.isWire('f1'), isFalse);
      expect(GroupFileWire.fileIdOf(a), 'f1');
      expect(GroupFileWire.isFor(a, 'ali'), isTrue);
      expect(GroupFileWire.isFor(a, 'sara'), isFalse);
      // Native allows 2-128 of [A-Za-z0-9_.-].
      expect(RegExp(r'^[A-Za-z0-9_.-]{2,128}$').hasMatch(
          GroupFileWire.wireId('1793700000000-0123456789abcdef', 'android-5bb3430f26da19f3')), isTrue);
    });

    test('bad entries are dropped; 50 MB and 10 files at most', () {
      final list = GroupFileWire.parseList([
        _photo.toJson(),
        {'id': 'big', 'name': 'b.mp4', 'type': 'video/mp4', 'size': 60 * 1024 * 1024},
        {'id': '../x', 'name': 'x', 'type': 'image/jpeg', 'size': 1},
        {'id': 'f1.gabcdef01', 'name': 'x', 'type': 'image/jpeg', 'size': 1},
        {'id': 'n1', 'name': '', 'type': 'image/jpeg', 'size': 1},
        _photo.toJson(), // twice
      ]);
      expect(list.map((f) => f.id), ['f1']);
      final many = GroupFileWire.parseList([
        for (var i = 0; i < 14; i++)
          {'id': 'id$i', 'name': 'n', 'type': 'image/jpeg', 'size': 1}
      ]);
      expect(many, hasLength(GroupFileWire.maxFiles));
      expect(_photo.toAttachment().isImage, isTrue);
      expect(_voice.toAttachment().isImage, isFalse);
    });

    test('the signed text covers the file list', () {
      final a = GroupFileWire.messageText2('g', 'm', 'w', 't', '', [_photo]);
      final b = GroupFileWire.messageText2('g', 'm', 'w', 't', '', [
        const GroupNearbyFile(id: 'f1', name: 'a.jpg', type: 'image/jpeg', size: 1)
      ]);
      expect(a, startsWith('llgm2\n'));
      expect(a, isNot(b));
    });
  });

  group('sending files to each member (G7)', () {
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
      sajjad.sources['m1|f1'] = _picked(_photo);
      sajjad.sources['m1|f2'] = _picked(_voice);
    });

    Future<void> make() async {
      await sajjad.service.createGroup(
          gid: 'g-1', name: 'Family', memberIds: ['ali', 'sara'], origin: 'nearby');
      await _settle(air);
    }

    test('a photo with no words goes Nearby with its file list', () async {
      await make();
      await sajjad.service.fanOut('g-1', 'm1', '', _at(1), files: [_photo]);
      await _settle(air);
      final got = ali.got.singleWhere((m) => m.id == 'm1');
      expect(got.body, '');
      expect(got.attachments.single.id, 'f1');
      expect(got.attachments.single.localPath, isNull);
      expect(got.attachments.single.isImage, isTrue);
      // Kept for catch-up with the file list.
      expect(ali.copyStore.rows['m1']!.att, contains('a.jpg'));
      expect(ali.copyStore.rows['m1']!.sig2, isNotEmpty);
    });

    test('words + files: old signature for words, new one for files', () async {
      await make();
      await sajjad.service.fanOut('g-1', 'm1', 'Look', _at(1), files: [_photo]);
      await _settle(air);
      final p = sajjad.sentPayloads.firstWhere((p) => p['type'] == 'group_msg');
      expect(p['sig'], isNotEmpty);
      expect(p['sig2'], isNotEmpty);
      expect(p['sig'], isNot(p['sig2']));
      expect(ali.got.singleWhere((m) => m.id == 'm1').body, 'Look');
    });

    test('a changed file list is refused', () async {
      await make();
      air.away.add('ali');
      await sajjad.service.fanOut('g-1', 'm1', '', _at(1), files: [_photo]);
      await _settle(air);
      final p = sajjad.sentPayloads.firstWhere((p) => p['type'] == 'group_msg');
      final bad = jsonDecode(jsonEncode(p)) as Map<String, dynamic>;
      (bad['att'] as List).first['name'] = 'evil.apk';
      await ali.service.handlePacket({...bad, 'sender_id': 'sajjad'});
      expect(ali.got.where((m) => m.id == 'm1'), isEmpty);
      // The same packet untouched opens.
      await ali.service.handlePacket({...p, 'sender_id': 'sajjad'});
      expect(ali.got.where((m) => m.id == 'm1'), hasLength(1));
    });

    test('files without the new signature are refused', () async {
      await make();
      await ali.service.handlePacket({
        'type': 'group_msg',
        'gid': 'g-1',
        'id': 'm9',
        'body': '',
        'created_at': _at(2),
        'att': [_photo.toJson()],
        'sender_id': 'sajjad',
      });
      expect(ali.got.where((m) => m.id == 'm9'), isEmpty);
    });

    test('"got it" with fv:2 starts that member\'s files, one id each', () async {
      await make();
      await sajjad.service.fanOut('g-1', 'm1', 'Hi', _at(1), files: [_photo, _voice]);
      await _settle(air);
      final acks = ali.sentPayloads.where((p) => p['type'] == 'group_ack');
      expect(acks.first['fv'], GroupFileWire.filesVersion);
      expect(sajjad.fileSends, hasLength(4));
      expect(sajjad.fileSends.map((s) => s.split('|').last).toSet(), hasLength(4));
      expect(sajjad.fileSends, contains('ali|m1|${GroupFileWire.wireId('f1', 'ali')}'));
      expect(sajjad.fileSends, contains('sara|m1|${GroupFileWire.wireId('f2', 'sara')}'));
    });

    test('file_sent marks done; everyone done = no upload (P1)', () async {
      await make();
      await sajjad.service.fanOut('g-1', 'm1', '', _at(1), files: [_photo]);
      await _settle(air);
      expect(await sajjad.files.allDelivered('m1', ['ali', 'sara']), isFalse);
      for (final m in ['ali', 'sara']) {
        await sajjad.service.handleEvent({
          'type': 'file_sent',
          'transfer_id': GroupFileWire.wireId('f1', m),
          'message_id': 'm1',
        });
      }
      expect(await sajjad.files.allDelivered('m1', ['ali', 'sara']), isTrue);
      // A file that never went Nearby (over 50 MB) still needs the server.
      expect(
          await sajjad.files.allDelivered('m1', ['ali', 'sara'], fileIds: ['f1', 'big']),
          isFalse);
    });

    test('an old phone gets files from the server only (P2)', () async {
      await make();
      sara.oldApp = true;
      await sajjad.service.fanOut('g-1', 'm1', 'Hi', _at(1), files: [_photo]);
      await _settle(air);
      expect(sajjad.fileSends.where((s) => s.startsWith('sara|')), isEmpty);
      expect(sajjad.fileSends.where((s) => s.startsWith('ali|')), hasLength(1));
      final rows = await sajjad.fileStore.sends(memberId: 'sara');
      expect(rows.single.status, 'old');
      expect(await sajjad.files.allDelivered('m1', ['ali', 'sara']), isFalse);
    });

    test('over 50 MB never goes Nearby', () async {
      await make();
      const big = GroupNearbyFile(
          id: 'f9', name: 'b.mp4', type: 'video/mp4', size: GroupFileWire.maxBytes + 1);
      await sajjad.service.fanOut('g-1', 'm1', '', _at(1), files: [big]);
      await _settle(air);
      expect(ali.got.where((m) => m.id == 'm1'), isEmpty,
          reason: 'nothing left to send Nearby');
      expect(sajjad.fileStore.rows, isEmpty);
    });

    test('a failed send waits and tries again when the member comes near', () async {
      await make();
      sajjad.sendFails = true;
      await sajjad.service.fanOut('g-1', 'm1', '', _at(1), files: [_photo]);
      await _settle(air);
      expect(sajjad.fileSends, isEmpty);
      final row = (await sajjad.fileStore.sends(memberId: 'ali')).single;
      expect(row.status, 'ready');
      expect(row.nextAt, greaterThan(air.now));
      sajjad.sendFails = false;
      await sajjad.service.handleEvent({'type': 'peer_connected', 'peer_id': 'ali'});
      await _settle(air);
      expect(sajjad.fileSends.where((s) => s.startsWith('ali|')), hasLength(1));
    });

    test('file_failed from the engine: retry later; cancelled: wait for a tap', () async {
      await make();
      await sajjad.service.fanOut('g-1', 'm1', '', _at(1), files: [_photo]);
      await _settle(air);
      await sajjad.service.handleEvent({
        'type': 'file_failed',
        'transfer_id': GroupFileWire.wireId('f1', 'ali'),
        'message_id': 'm1',
        'reason': 'retry_limit_exceeded',
      });
      var row = (await sajjad.fileStore.sends(memberId: 'ali')).single;
      expect(row.status, 'ready');
      expect(row.tries, 1);
      await sajjad.service.handleEvent({
        'type': 'file_cancelled',
        'transfer_id': GroupFileWire.wireId('f1', 'sara'),
        'message_id': 'm1',
      });
      row = (await sajjad.fileStore.sends(memberId: 'sara')).single;
      expect(row.status, 'stop');
    });

    test('Tap to download asks the writer (max 5 per 10 minutes)', () async {
      await make();
      await sajjad.service.fanOut('g-1', 'm1', '', _at(1), files: [_photo]);
      await _settle(air);
      await sajjad.service.handleEvent({
        'type': 'file_cancelled',
        'transfer_id': GroupFileWire.wireId('f1', 'ali'),
        'message_id': 'm1',
      });
      sajjad.fileSends.clear();
      expect(await ali.service.sendFileNeed('g-1', 'm1', 'f1', 'sajjad'), isTrue);
      await _settle(air);
      expect(sajjad.fileSends, ['ali|m1|${GroupFileWire.wireId('f1', 'ali')}']);
      for (var i = 0; i < 6; i++) {
        await ali.service.sendFileNeed('g-1', 'm1', 'f1', 'sajjad');
        await _settle(air);
      }
      expect(sajjad.fileSends, hasLength(5), reason: '1 + 4 more, then refused');
    });

    test('at most 6 files at once', () async {
      final many = [
        for (var i = 0; i < 5; i++)
          GroupNearbyFile(id: 'p$i', name: 'p$i.jpg', type: 'image/jpeg', size: 10)
      ];
      for (final f in many) {
        sajjad.sources['m1|${f.id}'] = _picked(f);
      }
      await make();
      await sajjad.service.fanOut('g-1', 'm1', '', _at(1), files: many);
      await _settle(air);
      expect(sajjad.fileSends, hasLength(GroupFileSender.maxActive));
      await sajjad.service.handleEvent({
        'type': 'file_sent',
        'transfer_id': sajjad.fileSends.first.split('|').last,
        'message_id': 'm1',
      });
      await _settle(air);
      expect(sajjad.fileSends, hasLength(GroupFileSender.maxActive + 1));
    });

    test('battery 10% or less: voice notes still go, big files wait', () async {
      const video = GroupNearbyFile(
          id: 'f3', name: 'v.mp4', type: 'video/mp4', size: 5 * 1024 * 1024);
      sajjad.sources['m1|f3'] = _picked(video);
      sajjad.lowBattery = true;
      await make();
      await sajjad.service.fanOut('g-1', 'm1', '', _at(1), files: [_voice, video]);
      await _settle(air);
      expect(sajjad.fileSends.every((s) => s.contains('f2.g')), isTrue);
      expect(sajjad.fileSends, hasLength(2));
    });

    test('catch-up carries the file list; the writer then sends the file', () async {
      await make();
      air.away.add('sara');
      await sajjad.service.fanOut('g-1', 'm1', '', _at(1), files: [_photo]);
      await _settle(air);
      expect(sajjad.fileSends.where((s) => s.startsWith('sara|')), isEmpty);
      air.away.remove('sara');
      await ali.service.catchUpWith('sara');
      await _settle(air);
      final got = sara.got.singleWhere((m) => m.id == 'm1');
      expect(got.attachments.single.id, 'f1');
      expect(got.senderId, 'sajjad');
      // Sara's "got it" reached the writer: the file goes from Sajjad.
      expect(sajjad.fileSends.where((s) => s.startsWith('sara|')), hasLength(1));
    });

    test('typing goes to members; a stranger is ignored', () async {
      await make();
      expect(await ali.service.sendTyping('g-1', true), 2);
      await _settle(air);
      expect(sajjad.typing, ['g-1|ali|true']);
      expect(sara.typing, ['g-1|ali|true']);
      await sajjad.service.handlePacket(
          {'type': 'group_typing', 'gid': 'g-1', 'on': true, 'sender_id': 'zara'});
      expect(sajjad.typing, hasLength(1));
    });
  });

  group('group photo with no internet (G7)', () {
    late _Air air;
    late _Phone sajjad, ali;

    setUp(() async {
      air = _Air()..now = _t0;
      sajjad = _Phone(air, 'sajjad');
      ali = _Phone(air, 'ali');
      sajjad.befriend(ali);
      ali.befriend(sajjad);
      await sajjad.service.createGroup(
          gid: 'g-1', name: 'Family', memberIds: ['ali'], origin: 'nearby');
      await _settle(air);
    });

    test('admin: signed note, member takes it, picture follows', () async {
      expect(await sajjad.service.canSetPhoto('g-1'), isTrue);
      expect(await ali.service.canSetPhoto('g-1'), isFalse);
      final h = 'a' * 64;
      sajjad.sources['${GroupFileWire.photoMessageId('g-1')}|gp1'] =
          const PickedFile(path: '/p.jpg', name: 'group.jpg', contentType: 'image/jpeg', size: 9000);
      await sajjad.service.sharePhoto('g-1', 1, h, 9000);
      await _settle(air);
      expect(ali.photoNotes, ['g-1|1|$h|sajjad']);
      expect(sajjad.fileSends,
          ['ali|${GroupFileWire.photoMessageId('g-1')}|${GroupFileWire.wireId('gp1', 'ali')}']);
      expect(sajjad.store.outbox.keys.where((k) => k.startsWith('photo:')), isEmpty);
    });

    test('a note from a non-admin or with a bad signature is refused', () async {
      final h = 'b' * 64;
      await ali.service.handlePacket({
        'type': 'group_photo', 'gid': 'g-1', 'v': 2, 'h': h, 'by': 'ali',
        'at': _t0, 'sig': 'x', 'sender_id': 'ali',
      });
      await sajjad.service.handlePacket({
        'type': 'group_photo', 'gid': 'g-1', 'v': 2, 'h': h, 'by': 'ali',
        'at': _t0, 'sig': 'S:${_key('ali', 'sign')}:${GroupNearbyService.photoText('g-1', 2, h, 'ali', _t0).hashCode}',
        'sender_id': 'ali',
      });
      expect(sajjad.photoNotes, isEmpty, reason: 'ali is not an admin');
      await ali.service.handlePacket({
        'type': 'group_photo', 'gid': 'g-1', 'v': 2, 'h': h, 'by': 'sajjad',
        'at': _t0, 'sig': 'bad', 'sender_id': 'sajjad',
      });
      expect(ali.photoNotes, isEmpty, reason: 'bad signature');
    });

    test('remove photo = note with no picture', () async {
      await sajjad.service.sharePhoto('g-1', 3, '', 0);
      await _settle(air);
      expect(ali.photoNotes, ['g-1|3||sajjad']);
      expect(sajjad.fileSends, isEmpty);
    });
  });

  group('pair file keys (G7)', () {
    test('both phones get the same key and id', () async {
      final x = X25519();
      final a = await SealKeyPair.from(await x.newKeyPair());
      final b = await SealKeyPair.from(await x.newKeyPair());
      final ab = await GroupPairFileKeys.derive(a, b.publicKey, 'ali', 'sara');
      final ba = await GroupPairFileKeys.derive(b, a.publicKey, 'sara', 'ali');
      expect(ab, ba);
      expect(ab, hasLength(32));
      final kid = GroupPairFileKeys.kidOf(ab);
      expect(RegExp(r'^[A-Za-z0-9_-]{8,24}$').hasMatch(kid), isTrue,
          reason: 'native kid pattern');
    });

    test('pushes once per change; never my own id', () async {
      final x = X25519();
      final me = await SealKeyPair.from(await x.newKeyPair());
      final other = await SealKeyPair.from(await x.newKeyPair());
      final pushed = <Map<String, Map<String, String>>>[];
      var members = <String, List<int>>{'ali': other.publicKey, 'me': me.publicKey};
      final keys = GroupPairFileKeys(
        selfId: () => 'me',
        ownKey: () async => me,
        members: () async => members,
        push: (m) async {
          pushed.add(m);
          return true;
        },
      );
      await keys.refresh(force: true);
      await keys.refresh(force: true);
      expect(pushed, hasLength(1));
      expect(pushed.single.keys, ['ali']);
      expect(pushed.single['ali']!['o'], pushed.single['ali']!['p']);
      members = {};
      await keys.refresh(force: true);
      expect(pushed, hasLength(2));
      expect(pushed.last, isEmpty);
    });
  });

  group('receiving watch (G7)', () {
    tearDown(() => MediaTransferActions.instance.resetForTest());

    test('nothing moved for 3 minutes: Tap to download', () {
      var now = DateTime(2026, 11, 4, 10);
      final w = GroupFileWatch(clock: () => now);
      w.expect('m1');
      now = now.add(const Duration(minutes: 2));
      w.check();
      expect(MediaTransferActions.instance.isCancelled('m1'), isFalse);
      expect(w.handleEvent({'type': 'file_progress', 'message_id': 'm1'}), isTrue);
      now = now.add(const Duration(minutes: 2));
      w.check();
      expect(MediaTransferActions.instance.isCancelled('m1'), isFalse);
      now = now.add(const Duration(minutes: 2));
      w.check();
      expect(MediaTransferActions.instance.isCancelled('m1'), isTrue);
      w.moved('m1');
      expect(MediaTransferActions.instance.isCancelled('m1'), isFalse);
      expect(w.handleEvent({'type': 'file_expired', 'message_id': 'm1'}), isTrue);
      expect(MediaTransferActions.instance.isCancelled('m1'), isTrue);
      w.done('m1');
      expect(w.watching('m1'), isFalse);
      expect(w.handleEvent({'type': 'file_progress', 'message_id': 'other'}), isFalse);
      w.dispose();
    });
  });


  group('group messaging service (G7)', () {
    late _GStore store;
    late FakeSocket socket;
    late _GFiles files;
    late GroupMessagingService service;

    setUp(() {
      store = _GStore()..selfId = 'me';
      socket = FakeSocket();
      files = _GFiles();
      store.groupsById['g1'] = <String, dynamic>{
        'id': 'g1',
        'name': 'Family',
        'owner_id': 'ali',
        'created_at': '2026-01-01T00:00:00Z',
      };
      service = GroupMessagingService(store, LocalLinkApi(store, socket), socket, files);
      service.cancelIncomingFile = files.cancelDirectFile; // as in the app
    });

    tearDown(() async {
      MediaTransferActions.instance.resetForTest();
      service.fileWatch.dispose();
      await service.dispose();
      await socket.shutdown();
    });

    GroupMessage msg({List<Attachment> att = const []}) => GroupMessage(
        id: 'm1', groupId: 'g1', senderId: 'ali', body: '', createdAt: _at(1),
        attachments: att);

    test('a member\'s file lands on the message', () async {
      await service.receiveNearby(msg(att: [_photo.toAttachment()]));
      expect(service.fileWatch.watching('m1'), isTrue);
      final updates = <GroupMessage>[];
      final sub = service.incoming.listen(updates.add);
      final ok = await service.receiveNearbyFile({
        'file_id': GroupFileWire.wireId('f1', 'me'),
        'message_id': 'm1',
        'path': '/files/a.jpg.enc',
        'sender_id': 'ali',
      });
      await Future<void>.delayed(Duration.zero);
      expect(ok, isTrue);
      final m = await store.groupMessageById('m1');
      expect(m!.attachments.single.localPath, '/files/a.jpg.enc');
      expect(service.fileWatch.watching('m1'), isFalse);
      expect(updates.single.attachments.single.localPath, '/files/a.jpg.enc');
      await sub.cancel();
    });

    test('file before its message: picked up when the message comes', () async {
      store.direct[GroupFileWire.wireId('f1', 'me')] = {'local_path': '/files/early.enc'};
      await service.receiveNearbyFile({
        'file_id': GroupFileWire.wireId('f1', 'me'),
        'message_id': 'm1',
        'path': '/files/early.enc',
        'sender_id': 'ali',
      });
      await service.receiveNearby(msg(att: [_photo.toAttachment()]));
      final m = await store.groupMessageById('m1');
      expect(m!.attachments.single.localPath, '/files/early.enc');
      expect(service.fileWatch.watching('m1'), isFalse);
    });

    test('a file for another member or from someone else is refused', () async {
      await service.receiveNearby(msg(att: [_photo.toAttachment()]));
      await service.receiveNearbyFile({
        'file_id': GroupFileWire.wireId('f1', 'sara'),
        'message_id': 'm1',
        'path': '/x',
        'sender_id': 'ali',
      });
      await service.receiveNearbyFile({
        'file_id': GroupFileWire.wireId('f1', 'me'),
        'message_id': 'm1',
        'path': '/y',
        'sender_id': 'zara',
      });
      final m = await store.groupMessageById('m1');
      expect(m!.attachments.single.localPath, isNull);
      // Not a group wire id: the 1:1 code keeps it.
      expect(await service.receiveNearbyFile({
        'file_id': 'f1', 'message_id': 'm1', 'path': '/z', 'sender_id': 'ali',
      }), isFalse);
    });

    test('a file the old copy did not list is added to the message', () async {
      await service.receiveNearby(GroupMessage(
          id: 'm1', groupId: 'g1', senderId: 'ali', body: 'Hi', createdAt: _at(1)));
      await service.receiveNearbyFile({
        'file_id': GroupFileWire.wireId('f7', 'me'),
        'message_id': 'm1',
        'path': '/files/v.enc',
        'sender_id': 'ali',
        'original_name': 'v.mp4',
        'content_type': 'video/mp4',
        'size': 1234,
      });
      final m = await store.groupMessageById('m1');
      expect(m!.attachments.single.id, 'f7');
      expect(m.attachments.single.localPath, '/files/v.enc');
    });

    test('send: my copy is kept and my bubble has the photo at once', () async {
      final sent = await service.send('g1', '', attachments: [
        const PickedFile(path: '/cache/a.jpg', name: 'a.jpg', contentType: 'image/jpeg', size: 10)
      ]);
      expect(files.staged, hasLength(1));
      expect(sent.attachments.single.localPath, '/app/attachments/${files.staged.single}');
      expect(sent.attachments.single.id, files.staged.single);
      final saved = await store.groupMessageById(sent.id);
      expect(saved!.attachments.single.localPath, startsWith('/app/attachments/'));
      expect(store.pending[sent.id]!.single['local_path'], startsWith('/app/attachments/'));
    });

    test('X and Tap to download on a group file', () async {
      await service.receiveNearby(msg(att: [_photo.toAttachment()]));
      expect(await service.cancelFile('m1', 'f1'), isTrue);
      expect(MediaTransferActions.instance.isCancelled('m1'), isTrue);
      expect(files.cancelled, [GroupFileWire.wireId('f1', 'me')]);
      // Not a group message: the 1:1 code handles it.
      expect(await service.cancelFile('nope', 'f1'), isFalse);
      // No Nearby service in this test: can't ask.
      expect(await service.requestFileAgain('m1', 'f1'), isFalse);
    });

    test('my own file source: the copy saved with my message', () async {
      final sent = await service.send('g1', 'Hi', attachments: [
        const PickedFile(path: '/cache/b.pdf', name: 'b.pdf', contentType: 'application/pdf', size: 10)
      ]);
      final fileId = sent.attachments.single.id;
      // The staged path does not exist in tests -> no locked copy either.
      expect(await service.fileSource(sent.id, fileId), isNull);
      expect(await service.fileSource(sent.id, 'other'), isNull);
    });
  });

  group('code checks (G7)', () {
    String read(String p) => File(p).readAsStringSync();

    test('DB v33: file rows table + file list in copies', () {
      final s = read('lib/core/services/local_store.dart');
      expect(s, contains('if (oldVersion < 33) await _upgradeTo33(db);'));
      expect(s, contains('CREATE TABLE IF NOT EXISTS group_file_sends'));
      expect(s, contains('ALTER TABLE group_copies ADD COLUMN'));
    });

    test('1:1 file code hands group files over; Tap to download / X too', () {
      final s = read('lib/features/messaging/data/services/reliable_messaging_service.dart');
      expect(s, contains('onGroupFile'));
      expect(s, contains('groupMediaResend'));
      expect(s, contains('groupMediaCancel'));
      // After the file is saved and locked, before the 1:1 message lookup.
      expect(s.indexOf('_groupWire.hasMatch(fileId)'),
          greaterThan(s.indexOf('protectLegacyLocalFile(path!)')));
      expect(s.indexOf('_groupWire.hasMatch(fileId)'),
          lessThan(s.indexOf('await store.messagesFor(senderId)')));
    });

    test('group bubble shows the receiving ring for members', () {
      final s = read('lib/features/files/presentation/widgets/attachment_tile.dart');
      expect(s, contains('if (widget.groupMessageId != null && widget.mine) return false;'));
      expect(s, isNot(contains('widget.uploading || widget.groupMessageId != null')));
    });

    test('send keeps my copy, upload rule, typing Nearby', () {
      final s = read('lib/features/groups/data/services/group_messaging_service.dart');
      expect(s, contains('files.stageOutgoingFile('));
      expect(s, contains('GROUP_FILE_UPLOAD_SKIPPED'));
      expect(s, isNot(contains('for (final path in localPaths)')));
      expect(s, contains('near.sendTyping(gid, on)'));
      // Files are added before the message is queued.
      expect(s.indexOf('addPendingGroupAttachment(id: pendingId'),
          lessThan(s.indexOf("}, files: [for (final a in mine)")));
    });

    test('typing uses the live lock', () {
      final s = read('lib/features/connectivity/data/services/sealing_peer_transport.dart');
      expect(s, contains("payload['type'] == 'group_typing'"));
      expect(s, contains('MessageSealService.sealedLiveType'));
    });

    test('native: group file keys only for files, friend key first', () {
      final s = read('android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt');
      expect(s, contains('private val peerFileKeys'));
      expect(s, contains('fun updatePeerFileKeys(json:String)'));
      expect(s, contains('val shared = fileKeysFor(target).firstOrNull()'));
      expect(s, contains('listOfNotNull(peerFileKeys[from])'));
      expect(s, contains('j.put("peer_file_keys",peerFileKeysJson())'));
      // The link hello still uses only friend keys.
      expect(s, contains('val myKeys = linkKeys[peerId].orEmpty()'));
      for (final f in ['MainActivity.kt', 'BackgroundChannels.kt']) {
        expect(read('android/app/src/main/kotlin/com/sajjad/locallink/$f'),
            contains('"updatePeerFileKeys"'));
      }
    });

    test('group photo with no internet is no longer refused', () {
      final s = read('lib/features/groups/data/repositories/group_repository.dart');
      expect(s, contains('await nearbyPhoto(groupId, jpeg);'));
    });

    test('attachments stay a plain model', () {
      const a = Attachment(id: 'x', originalName: 'n', contentType: 'image/jpeg', size: 1, sha256: '');
      expect(GroupNearbyFile.fromAttachment(a).id, 'x');
    });
  });
}
