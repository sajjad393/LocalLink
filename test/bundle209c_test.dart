import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/services/locallink_api.dart' show LocalLinkApi;
import 'package:locallink/features/files/data/services/auto_fetch_service.dart';
import 'package:locallink/features/files/data/services/media_transfer_actions.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';

import 'support/g209_fakes.dart';
import 'support/phase5_fakes.dart';

// Bundle 209 (C): the writer is away - ask one member who is near.

final _sha = 'a' * 64;

void main() {
  group('asking a member (209 C)', () {
    late G9Air air;
    late G9Phone sajjad, ali, sara, me;
    late G9GStore store;
    late FakeSocket socket;
    late GroupMessagingService service;
    final near = <String>{};
    final allowed = <String>[];

    setUp(() async {
      near.clear();
      allowed.clear();
      air = G9Air()..now = g9T0;
      sajjad = G9Phone(air, 'sajjad');
      ali = G9Phone(air, 'ali');
      sara = G9Phone(air, 'sara');
      me = G9Phone(air, 'me');
      for (final p in [ali, sara, me]) {
        sajjad.befriend(p);
        p.befriend(sajjad);
      }
      await sajjad.service.createGroup(
          gid: 'g-1', name: 'Family', memberIds: ['ali', 'sara', 'me'], origin: 'nearby');
      await g9Settle(air);
      store = G9GStore()..selfId = 'me';
      socket = FakeSocket();
      store.groupsById['g-1'] = <String, dynamic>{
        'id': 'g-1',
        'name': 'Family',
        'owner_id': 'sajjad',
        'created_at': '2026-01-01T00:00:00Z',
      };
      service = GroupMessagingService(store, LocalLinkApi(store, socket), socket, G9GFiles());
      service.nearby = me.service;
      service.isNear = near.contains;
      service.clock = () => DateTime.fromMillisecondsSinceEpoch(g9T0, isUtc: true);
      service.allowIncomingFile = (w) async => allowed.add(w);
    });

    tearDown(() async {
      MediaTransferActions.instance.resetForTest();
      service.fileWatch.dispose();
      await service.dispose();
      await socket.shutdown();
    });

    Future<void> message({String sha = '', int size = 200000, int minutes = 1}) =>
        service.receiveNearby(GroupMessage(
            id: 'm1', groupId: 'g-1', senderId: 'sajjad', body: '', createdAt: g9At(minutes),
            attachments: [
              GroupNearbyFile(id: 'f1', name: 'a.jpg', type: 'image/jpeg', size: size, sha: sha)
                  .toAttachment()
            ]));

    List<Map<String, dynamic>> asks() =>
        [for (final p in me.sentPayloads) if (p['type'] == 'group_file_ask') p];

    test('writer away, a member near: the ask goes to that member', () async {
      await message(sha: _sha);
      near.add('ali');
      expect(await service.askMemberFor('m1', 'f1'), 'ali');
      final a = asks().single;
      expect(a['gid'], 'g-1');
      expect(a['id'], 'm1');
      expect(a['file'], 'f1');
      expect(a['sha'], _sha);
      expect(me.sentTo, contains('ali:group_file_ask'));
      expect(allowed, [GroupFileWire.wireId('f1', 'me')]);
      expect(service.fileWatch.watching('m1'), isTrue);
    });

    test('the member just seen is asked first; never the writer or me', () async {
      await message(sha: _sha);
      near.addAll(['sajjad', 'me', 'ali']);
      expect(await service.askMemberFor('m1', 'f1', seen: 'sara'), 'sara');
      expect(await service.askMemberFor('m1', 'f1'), 'ali');
      expect(await service.askMemberFor('m1', 'f1'), isNull, reason: 'both asked');
    });

    test('the same member at most once per 10 minutes', () async {
      await message(sha: _sha);
      near.add('ali');
      var t = DateTime.fromMillisecondsSinceEpoch(g9T0, isUtc: true);
      service.clock = () => t;
      expect(await service.askMemberFor('m1', 'f1'), 'ali');
      t = t.add(const Duration(minutes: 9));
      expect(await service.askMemberFor('m1', 'f1'), isNull);
      t = t.add(const Duration(minutes: 2));
      expect(await service.askMemberFor('m1', 'f1'), 'ali');
    });

    test('no signed sha / over 50 MB / older than 7 days / not a member: no ask', () async {
      near.addAll(['ali', 'zara']);
      await message();
      expect(await service.askMemberFor('m1', 'f1'), isNull, reason: 'no sha');
      await message(sha: _sha, size: GroupFileWire.maxBytes + 1);
      expect(await service.askMemberFor('m1', 'f1'), isNull, reason: 'too big');
      await message(sha: _sha, minutes: -(7 * 24 * 60 + 1));
      expect(await service.askMemberFor('m1', 'f1'), isNull, reason: 'too old');
      expect(asks(), isEmpty);
      await message(sha: _sha);
      near.remove('ali');
      expect(await service.askMemberFor('m1', 'f1', seen: 'zara'), isNull,
          reason: 'not in the group');
    });

    test('a file I already have: no ask', () async {
      await message(sha: _sha);
      await store.setGroupAttachmentLocalPath('m1', 'f1', '/files/a.enc');
      near.add('ali');
      expect(await service.askMemberFor('m1', 'f1'), isNull);
    });

    test('Tap to download: writer asked; writer not near -> a member too', () async {
      await message(sha: _sha);
      near.add('ali');
      expect(await service.requestFileAgain('m1', 'f1'), isTrue);
      expect(me.sentTo, contains('sajjad:group_file_need'));
      expect(me.sentTo, contains('ali:group_file_ask'));
    });

    test('Tap to download with the writer near: only the writer', () async {
      await message(sha: _sha);
      near.addAll(['sajjad', 'ali']);
      expect(await service.requestFileAgain('m1', 'f1'), isTrue);
      expect(me.sentTo.where((s) => s.endsWith('group_file_ask')), isEmpty);
    });
  });

  group('AutoFetch asks a member (209 C)', () {
    late DateTime now;
    late List<String> asks;
    late List<String> others;
    String? answer;
    bool near = false;

    AutoFile file() => AutoFile(
          messageId: 'm-g',
          senderId: 'writer',
          createdAt: DateTime.utc(2026, 11, 5, 12),
          groupId: 'gid',
          attachment: const Attachment(
              id: 'g', originalName: 'g.mp4', contentType: 'video/mp4', size: 1000, sha256: ''),
        );

    AutoFetch make({bool group = true}) => AutoFetch(
          missing: () async => [
            if (group)
              file()
            else
              AutoFile(
                messageId: 'm-1',
                senderId: 'friend',
                createdAt: DateTime.utc(2026, 11, 5, 12),
                attachment: const Attachment(
                    id: 'o', originalName: 'o.mp4', contentType: 'video/mp4', size: 1000, sha256: ''),
              )
          ],
          download: (f, {required operationId, required onProgress}) async => '/x',
          ask: (m, f) async {
            asks.add(f);
            return true;
          },
          cancelDownload: (_) async {},
          inCall: () => false,
          serverUp: () => true,
          freeBytes: () async => 0,
          isNear: (id) => near && id == 'writer',
          selfId: () => 'me',
          clock: () => now,
          askOther: (f, seen) async {
            others.add('${f.fileId}|$seen');
            return answer;
          },
        );

    setUp(() {
      now = DateTime.utc(2026, 11, 5, 12);
      asks = [];
      others = [];
      answer = 'ali';
      near = false;
      MediaTransferActions.instance.resetForTest();
    });

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('writer away, a member seen: the member is asked; 2 min gap', () async {
      final auto = make();
      await auto.check();
      now = now.add(const Duration(seconds: 61));
      await auto.peerSeen('ali');
      await settle();
      expect(asks, isEmpty);
      expect(others, ['g|ali']);
      now = now.add(const Duration(seconds: 30));
      await auto.peerSeen('ali');
      await settle();
      expect(others, hasLength(1), reason: '2 min between asks');
      now = now.add(const Duration(minutes: 2));
      await auto.peerSeen('sara');
      await settle();
      expect(others, ['g|ali', 'g|sara']);
      auto.dispose();
    });

    test('nobody to ask: tries again at the next look', () async {
      answer = null;
      final auto = make();
      await auto.check();
      now = now.add(const Duration(seconds: 61));
      await auto.check();
      await settle();
      await auto.check();
      await settle();
      expect(others, ['g|null', 'g|null']);
      auto.dispose();
    });

    test('writer near: the writer, not a member', () async {
      near = true;
      final auto = make();
      await auto.check();
      now = now.add(const Duration(seconds: 61));
      await auto.check();
      await settle();
      expect(asks, ['g']);
      expect(others, isEmpty);
      auto.dispose();
    });

    test('a 1:1 file never asks a member', () async {
      final auto = make(group: false);
      await auto.check();
      now = now.add(const Duration(seconds: 61));
      await auto.peerSeen('ali');
      await settle();
      expect(others, isEmpty);
      auto.dispose();
    });

    test('wiring (scan)', () {
      final s = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(s, contains('groupMessagingService.askMemberFor(f.messageId, f.fileId, seen: seen)'));
      expect(s, contains('groupMessagingService.isNear ='));
      final a = File('lib/features/files/data/services/auto_fetch_service.dart').readAsStringSync();
      expect(a, contains("way=group via=member"));
    });
  });
}
