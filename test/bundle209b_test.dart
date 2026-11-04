import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/services/locallink_api.dart' show LocalLinkApi;
import 'package:locallink/features/files/data/services/media_transfer_actions.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';

import 'support/g209_fakes.dart';
import 'support/phase5_fakes.dart';

// Bundle 209 (B): the receiver keeps the writer's signed fingerprint and
// takes a group file from any member only when it matches.

final _sha = 'a' * 64;
final _other = 'c' * 64;

void main() {
  group('signed fingerprints on the receiver (209 B)', () {
    late G9Air air;
    late G9Phone sajjad, ali, sara;

    setUp(() async {
      air = G9Air()..now = g9T0;
      sajjad = G9Phone(air, 'sajjad');
      ali = G9Phone(air, 'ali');
      sara = G9Phone(air, 'sara');
      sajjad.befriend(ali);
      sajjad.befriend(sara);
      ali.befriend(sajjad);
      sara.befriend(sajjad);
      sajjad.sources['m1|f1'] = g9Picked(g9Photo);
      await sajjad.service.createGroup(
          gid: 'g-1', name: 'Family', memberIds: ['ali', 'sara'], origin: 'nearby');
      await g9Settle(air);
    });

    test('a good llgm3: the member keeps the sha (message + copy)', () async {
      await sajjad.service.fanOut('g-1', 'm1', 'Hi', g9At(1), files: [g9Photo.withSha(_sha)]);
      await g9Settle(air);
      final got = ali.got.singleWhere((m) => m.id == 'm1');
      expect(got.attachments.single.sha256, _sha);
      expect(ali.copyStore.rows['m1']!.sig3, isNotEmpty);
      expect(ali.copyStore.rows['m1']!.att, contains(_sha));
    });

    test('a changed sha: message still opens (llgm2), but without the sha', () async {
      air.away.add('ali');
      await sajjad.service.fanOut('g-1', 'm1', '', g9At(1), files: [g9Photo.withSha(_sha)]);
      await g9Settle(air);
      final p = sajjad.sentPayloads.firstWhere((p) => p['type'] == 'group_msg');
      final bad = jsonDecode(jsonEncode(p)) as Map<String, dynamic>;
      (bad['att'] as List).first['sha'] = _other;
      await ali.service.handlePacket({...bad, 'sender_id': 'sajjad'});
      final got = ali.got.singleWhere((m) => m.id == 'm1');
      expect(got.attachments.single.sha256, '');
      expect(ali.copyStore.rows['m1']!.sig3, '');
      expect(ali.copyStore.rows['m1']!.att, isNot(contains(_other)));
    });

    test('a sha with no sig3 is not taken', () async {
      air.away.add('ali');
      await sajjad.service.fanOut('g-1', 'm1', '', g9At(1), files: [g9Photo.withSha(_sha)]);
      await g9Settle(air);
      final p = Map<String, dynamic>.from(
          sajjad.sentPayloads.firstWhere((p) => p['type'] == 'group_msg'))
        ..remove('sig3');
      await ali.service.handlePacket({...p, 'sender_id': 'sajjad'});
      expect(ali.got.singleWhere((m) => m.id == 'm1').attachments.single.sha256, '');
    });

    test('catch-up passes s3: the late member gets the sha too', () async {
      air.away.add('sara');
      await sajjad.service.fanOut('g-1', 'm1', '', g9At(1), files: [g9Photo.withSha(_sha)]);
      await g9Settle(air);
      air.away.remove('sara');
      await ali.service.catchUpWith('sara');
      await g9Settle(air);
      final give = ali.sentPayloads.firstWhere((p) => p['type'] == 'group_give');
      expect(((give['items'] as List).single as Map)['s3'], isNotEmpty);
      final got = sara.got.singleWhere((m) => m.id == 'm1');
      expect(got.attachments.single.sha256, _sha);
      expect(sara.copyStore.rows['m1']!.sig3, isNotEmpty);
    });

    test('catch-up with a bad s3: message comes, no sha', () async {
      air.away.add('sara');
      await sajjad.service.fanOut('g-1', 'm1', '', g9At(1), files: [g9Photo.withSha(_sha)]);
      await g9Settle(air);
      final copy = ali.copyStore.rows['m1']!;
      ali.copyStore.rows['m1'] = GroupCopyX.withSig3(copy, 'S:bad');
      air.away.remove('sara');
      await ali.service.catchUpWith('sara');
      await g9Settle(air);
      expect(sara.got.singleWhere((m) => m.id == 'm1').attachments.single.sha256, '');
    });
  });

  group('taking a passed-on file (209 B)', () {
    late G9GStore store;
    late FakeSocket socket;
    late G9GFiles files;
    late GroupMessagingService service;
    final relayed = <String>[];

    setUp(() {
      relayed.clear();
      store = G9GStore()..selfId = 'me';
      socket = FakeSocket();
      files = G9GFiles();
      store.groupsById['g1'] = <String, dynamic>{
        'id': 'g1',
        'name': 'Family',
        'owner_id': 'ali',
        'created_at': '2026-01-01T00:00:00Z',
      };
      service = GroupMessagingService(store, LocalLinkApi(store, socket), socket, files);
      service.cancelIncomingFile = files.cancelDirectFile;
      service.onRelayedFile = (m, f) => relayed.add('${m.id}|$f');
    });

    tearDown(() async {
      MediaTransferActions.instance.resetForTest();
      service.fileWatch.dispose();
      await service.dispose();
      await socket.shutdown();
    });

    GroupMessage msg({String sha = ''}) => GroupMessage(
        id: 'm1', groupId: 'g1', senderId: 'ali', body: '', createdAt: g9At(1),
        attachments: [g9Photo.withSha(sha).toAttachment()]);

    Map<String, dynamic> file(String from, String sha, {String path = '/files/a.enc'}) => {
          'file_id': GroupFileWire.wireId('f1', 'me'),
          'message_id': 'm1',
          'path': path,
          'sender_id': from,
          'sha256': sha,
        };

    Future<String?> pathNow() async =>
        (await store.groupMessageById('m1'))!.attachments.single.localPath;

    test('from another member with the signed sha: taken', () async {
      await service.receiveNearby(msg(sha: _sha));
      expect(await service.receiveNearbyFile(file('sara', _sha)), isTrue);
      expect(await pathNow(), '/files/a.enc');
      expect(relayed, ['m1|f1']);
      expect(service.fileWatch.watching('m1'), isFalse);
    });

    test('from another member with a wrong sha: refused and deleted', () async {
      final dir = await Directory.systemTemp.createTemp('r209');
      final f = File('${dir.path}/bad.enc')..writeAsStringSync('x');
      await service.receiveNearby(msg(sha: _sha));
      await service.receiveNearbyFile(file('sara', _other, path: f.path));
      expect(await pathNow(), isNull);
      expect(f.existsSync(), isFalse);
      expect(relayed, isEmpty);
      await dir.delete(recursive: true);
    });

    test('from another member when there is no signed sha: refused (as 208)', () async {
      await service.receiveNearby(msg());
      await service.receiveNearbyFile(file('sara', _sha));
      expect(await pathNow(), isNull);
    });

    test('from the writer: taken (a different sha is only logged)', () async {
      await service.receiveNearby(msg(sha: _sha));
      await service.receiveNearbyFile(file('ali', _other));
      expect(await pathNow(), '/files/a.enc');
      expect(relayed, isEmpty);
    });

    test('a member can not add a file the list does not have', () async {
      await service.receiveNearby(GroupMessage(
          id: 'm1', groupId: 'g1', senderId: 'ali', body: 'Hi', createdAt: g9At(1)));
      await service.receiveNearbyFile({
        ...file('sara', _sha),
        'file_id': GroupFileWire.wireId('f7', 'me'),
      });
      expect((await store.groupMessageById('m1'))!.attachments, isEmpty);
    });

    test('early file: from the writer or with the signed sha only', () async {
      final wire = GroupFileWire.wireId('f1', 'me');
      store.direct[wire] = {'local_path': '/files/e.enc', 'sender_id': 'sara', 'sha256': _other};
      await service.receiveNearby(msg(sha: _sha));
      expect(await pathNow(), isNull, reason: 'wrong sha from a member');
      store.direct[wire] = {'local_path': '/files/e.enc', 'sender_id': 'sara', 'sha256': _sha};
      await service.receiveNearby(msg(sha: _sha));
      expect(await pathNow(), '/files/e.enc');
    });

    test('earlyFileOk rules', () {
      expect(GroupMessagingService.earlyFileOk({'sender_id': 'ali'}, 'ali', ''), isTrue);
      expect(GroupMessagingService.earlyFileOk({'sender_id': 'sara'}, 'ali', ''), isFalse);
      expect(GroupMessagingService.earlyFileOk({'sender_id': 'sara', 'sha256': _sha}, 'ali', _sha), isTrue);
      expect(GroupMessagingService.earlyFileOk({'sender_id': 'sara', 'sha256': ''}, 'ali', ''), isFalse);
      expect(GroupMessagingService.earlyFileOk({}, 'ali', ''), isFalse);
    });
  });

  test('a saved fingerprint stays when a copy without one comes (scan)', () {
    final s = File('lib/core/services/local_store.dart').readAsStringSync();
    expect(s, contains("THEN group_message_attachments.sha256 ELSE excluded.sha256 END"));
    final a = Attachment.fromJson({'id': 'x', 'original_name': 'a', 'content_type': 'a/b', 'size': 1, 'sha256': _sha});
    expect(GroupNearbyFile.fromAttachment(a).sha, _sha);
  });
}
