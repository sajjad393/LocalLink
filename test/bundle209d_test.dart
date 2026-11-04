import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';

import 'support/g209_fakes.dart';

// Bundle 209 (D): a member who has the file passes it on when asked.

final _sha = 'a' * 64;

void main() {
  group('passing a file on (209 D)', () {
    late G9Air air;
    late G9Phone sajjad, ali, me, sara;
    late GroupFileSender relay;
    late MemoryGroupFileSendStore relayStore;
    final relaySends = <String>[];
    final messages = <String, GroupMessage>{};
    var low = false;
    var sendFails = false;

    setUp(() async {
      relaySends.clear();
      messages.clear();
      low = false;
      sendFails = false;
      air = G9Air()..now = g9T0 + 60 * 60000;
      sajjad = G9Phone(air, 'sajjad');
      ali = G9Phone(air, 'ali');
      me = G9Phone(air, 'me');
      sara = G9Phone(air, 'sara');
      for (final p in [ali, me, sara]) {
        sajjad.befriend(p);
        p.befriend(sajjad);
      }
      await sajjad.service.createGroup(
          gid: 'g-1', name: 'Family', memberIds: ['ali', 'me', 'sara'], origin: 'nearby');
      await g9Settle(air);
      relayStore = MemoryGroupFileSendStore();
      relay = GroupFileSender(
        store: relayStore,
        source: (msg, file) async => g9Picked(g9Photo),
        sendFile: ({required memberId, required messageId, required wireId, required file}) async {
          if (sendFails) throw StateError('no route');
          relaySends.add('$memberId|$messageId|$wireId');
        },
        lowBattery: () => low,
        lowBatteryStopsAll: true,
        activeLimit: 2,
        triesLimit: 2,
        nowMs: () => air.now,
      );
      ali.service.relayFiles = relay;
      ali.service.passBlocked = () => low;
      ali.service.messageById = (id) async => messages[id];
    });

    GroupMessage msg(String id,
            {String writer = 'sajjad',
            String sha = '',
            String? path = '/files/a.enc',
            int size = 200000,
            int minutes = 1,
            String fileId = 'f1'}) =>
        GroupMessage(
            id: id,
            groupId: 'g-1',
            senderId: writer,
            body: '',
            createdAt: g9At(minutes),
            attachments: [
              Attachment(
                  id: fileId,
                  originalName: 'a.jpg',
                  contentType: 'image/jpeg',
                  size: size,
                  sha256: sha,
                  isImage: true,
                  localPath: path)
            ]);

    Future<void> ask(String id, {String file = 'f1', String sha = '', G9Phone? from}) async {
      final who = from ?? me;
      await who.service.sendFileAsk('g-1', id, file, sha.isEmpty ? _sha : sha, 'ali');
      await g9Settle(air);
    }

    test('a good ask: the file goes to the asker with its own wire id', () async {
      messages['m1'] = msg('m1', sha: _sha);
      await ask('m1');
      expect(relaySends, ['me|m1|${GroupFileWire.wireId('f1', 'me')}']);
      expect(ali.fileSends, isEmpty, reason: 'not the writer rows');
      // The phone says it arrived: the pass is done.
      await ali.service.handleEvent({
        'type': 'file_sent',
        'transfer_id': GroupFileWire.wireId('f1', 'me'),
        'message_id': 'm1',
      });
      expect((await relayStore.sends()).single.status, 'done');
    });

    test('skips: no message / no copy / no sha / other sha / too big / too old', () async {
      await ask('nope');
      messages['m2'] = msg('m2', sha: _sha, path: null);
      await ask('m2');
      messages['m3'] = msg('m3');
      await ask('m3');
      messages['m4'] = msg('m4', sha: 'b' * 64);
      await ask('m4');
      messages['m5'] = msg('m5', sha: _sha, size: GroupFileWire.maxBytes + 1);
      await ask('m5');
      messages['m6'] = msg('m6', sha: _sha, minutes: -(7 * 24 * 60 + 1));
      await ask('m6');
      expect(relaySends, isEmpty);
    });

    test('battery 10% or less: nothing is passed on', () async {
      low = true;
      messages['m1'] = msg('m1', sha: _sha);
      await ask('m1');
      expect(relaySends, isEmpty);
      expect(await relayStore.sends(), isEmpty);
    });

    test('the writer asking, or a stranger: nothing', () async {
      messages['m1'] = msg('m1', sha: _sha);
      await ask('m1', from: sajjad);
      expect(relaySends, isEmpty);
      await ali.service.handlePacket({
        'type': 'group_file_ask', 'gid': 'g-1', 'id': 'm1', 'file': 'f1',
        'sha': _sha, 'sender_id': 'zara',
      });
      expect(relaySends, isEmpty);
    });

    test('my own message: the writer road (Tap to download)', () async {
      ali.sources['m7|f1'] = g9Picked(g9Photo);
      await ali.service.fanOut('g-1', 'm7', '', g9At(1), files: [g9Photo.withSha(_sha)]);
      await g9Settle(air);
      messages['m7'] = msg('m7', writer: 'ali', sha: _sha);
      await ali.service.handleEvent({
        'type': 'file_cancelled',
        'transfer_id': GroupFileWire.wireId('f1', 'me'),
        'message_id': 'm7',
      });
      ali.fileSends.clear();
      await ask('m7');
      expect(ali.fileSends, ['me|m7|${GroupFileWire.wireId('f1', 'me')}']);
      expect(relaySends, isEmpty);
    });

    test('at most 2 passes at once; the same ask twice = one pass', () async {
      for (final id in ['a1', 'a2', 'a3']) {
        messages[id] = msg(id, sha: _sha);
      }
      await ask('a1');
      await ask('a1');
      await ask('a2', from: sara);
      await ask('a3');
      expect(relaySends, hasLength(2));
      expect(relaySends.first, startsWith('me|a1|'));
      expect(relaySends.last, startsWith('sara|a2|'));
    });

    test('at most 5 asks per member per 10 minutes', () async {
      for (var i = 0; i < 7; i++) {
        messages['r$i'] = msg('r$i', sha: _sha);
      }
      for (var i = 0; i < 7; i++) {
        await ask('r$i');
        for (final r in await relayStore.sends()) {
          r.status = 'done';
          await relayStore.updateSend(r);
        }
      }
      expect(relaySends, hasLength(5));
    });

    test('2 failed tries: give up (the asker asks again later)', () async {
      messages['m1'] = msg('m1', sha: _sha);
      await ask('m1');
      for (var i = 0; i < 2; i++) {
        await ali.service.handleEvent({
          'type': 'file_failed',
          'transfer_id': GroupFileWire.wireId('f1', 'me'),
          'message_id': 'm1',
        });
        await g9Settle(air);
        air.now += 20 * 60000;
        await relay.pump();
        await g9Settle(air);
      }
      expect((await relayStore.sends()).single.status, 'old');
      expect(relaySends, hasLength(2));
    });

    test('battery drops while waiting: even a small file waits', () async {
      sendFails = true;
      messages['m1'] = msg('m1', sha: _sha);
      await ask('m1');
      low = true;
      sendFails = false;
      air.now += 20 * 60000;
      await relay.pump();
      expect(relaySends, isEmpty);
    });

    test('wiring (scan)', () {
      final s = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(s, contains('near.relayFiles = GroupFileSender('));
      expect(s, contains('store: MemoryGroupFileSendStore(),'));
      expect(s, contains('activeLimit: 2,'));
      expect(s, contains('triesLimit: 2,'));
      expect(s, contains('lowBatteryStopsAll: true,'));
      expect(s, contains('near.passBlocked = lowForPass;'));
      expect(s, contains('near.messageById = store.groupMessageById;'));
      final g = File('lib/features/groups/data/services/group_nearby_service.dart')
          .readAsStringSync();
      expect(g, contains("if (!mine) mine = await relayFiles?.handleEvent(event) ?? false;"));
      expect(g, contains('unawaited(relayFiles?.peerUp(peer)'));
    });
  });
}
