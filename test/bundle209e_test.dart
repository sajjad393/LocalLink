import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';

import 'support/g209_fakes.dart';

// Bundle 209 (E): the writer learns "this member already has it" - no
// resend, and its ✓✓.

final _sha = 'a' * 64;

void main() {
  group('the writer learns "I have it" (209 E)', () {
    late G9Air air;
    late G9Phone sajjad, ali, me;
    final mine = <String, GroupMessage>{};

    setUp(() async {
      mine.clear();
      air = G9Air()..now = g9T0;
      sajjad = G9Phone(air, 'sajjad');
      ali = G9Phone(air, 'ali');
      me = G9Phone(air, 'me');
      for (final p in [ali, me]) {
        sajjad.befriend(p);
        p.befriend(sajjad);
      }
      sajjad.sources['m1|f1'] = g9Picked(g9Photo);
      sajjad.sources['m1|f2'] = g9Picked(g9Voice);
      me.service.messageById = (id) async => mine[id];
      await sajjad.service.createGroup(
          gid: 'g-1', name: 'Family', memberIds: ['ali', 'me'], origin: 'nearby');
      await g9Settle(air);
    });

    GroupMessage have(List<String> ids) => GroupMessage(
        id: 'm1', groupId: 'g-1', senderId: 'sajjad', body: '', createdAt: g9At(1),
        attachments: [
          for (final f in [g9Photo, g9Voice])
            Attachment(
                id: f.id, originalName: f.name, contentType: f.type, size: f.size,
                sha256: _sha, localPath: ids.contains(f.id) ? '/files/${f.id}.enc' : null)
        ]);

    test('sendHave: ack with fh -> those rows done, no resend, ✓✓', () async {
      air.away.add('me');
      await sajjad.service.fanOut('g-1', 'm1', '', g9At(1),
          files: [g9Photo.withSha(_sha), g9Voice.withSha(_sha)]);
      await g9Settle(air);
      expect(sajjad.fileSends.where((s) => s.startsWith('me|')), isEmpty);
      air.away.remove('me');
      // A member passed both files to me; I tell the writer.
      mine['m1'] = have(['f1', 'f2']);
      await me.service.sendHave('g-1', 'm1', 'sajjad');
      await g9Settle(air);
      final ack = me.sentPayloads.lastWhere((p) => p['type'] == 'group_ack');
      expect(ack['fh'], ['f1', 'f2']);
      final rows = await sajjad.fileStore.sends(memberId: 'me');
      expect(rows.map((r) => r.status).toSet(), {'done'});
      expect(sajjad.fileSends.where((s) => s.startsWith('me|')), isEmpty);
      // ali got them from the writer:
      for (final f in ['f1', 'f2']) {
        await sajjad.service.handleEvent({
          'type': 'file_sent',
          'transfer_id': GroupFileWire.wireId(f, 'ali'),
          'message_id': 'm1',
        });
      }
      expect(await sajjad.files.allDelivered('m1', ['ali', 'me']), isTrue);
    });

    test('only some files: the rest still go from the writer', () async {
      air.away.add('me');
      await sajjad.service.fanOut('g-1', 'm1', '', g9At(1),
          files: [g9Photo.withSha(_sha), g9Voice.withSha(_sha)]);
      await g9Settle(air);
      air.away.remove('me');
      mine['m1'] = have(['f1']);
      // The writer tries the message again: my "got it" carries fh.
      await sajjad.service.flush(peerId: 'me');
      await g9Settle(air);
      final rows = {
        for (final r in await sajjad.fileStore.sends(memberId: 'me')) r.fileId: r.status
      };
      expect(rows['f1'], 'done');
      expect(sajjad.fileSends, contains('me|m1|${GroupFileWire.wireId('f2', 'me')}'));
      expect(sajjad.fileSends, isNot(contains('me|m1|${GroupFileWire.wireId('f1', 'me')}')));
    });

    test('nothing on my phone: no have note', () async {
      mine['m1'] = have(const []);
      final before = me.sentPayloads.length;
      await me.service.sendHave('g-1', 'm1', 'sajjad');
      expect(me.sentPayloads.length, before);
      await me.service.sendHave('g-1', 'm1', 'me');
      expect(me.sentPayloads.length, before);
    });

    test('an old ack (no fh) works as in 208; unknown ids are ignored', () async {
      await sajjad.service.fanOut('g-1', 'm1', '', g9At(1), files: [g9Photo.withSha(_sha)]);
      await g9Settle(air);
      expect(sajjad.fileSends, contains('me|m1|${GroupFileWire.wireId('f1', 'me')}'));
      await sajjad.service.handlePacket({
        'type': 'group_ack', 'gid': 'g-1', 'ref': 'm1', 'fv': 2,
        'fh': ['zz', 5, ''], 'sender_id': 'me',
      });
      final row = (await sajjad.fileStore.sends(memberId: 'me')).single;
      expect(row.status, 'sending');
    });

    test('a done row ignores a late failure (no resend)', () async {
      await sajjad.service.fanOut('g-1', 'm1', '', g9At(1), files: [g9Photo.withSha(_sha)]);
      await g9Settle(air);
      await sajjad.files.memberGot('me', 'm1', fv: 2, have: ['f1']);
      await sajjad.service.handleEvent({
        'type': 'file_failed',
        'transfer_id': GroupFileWire.wireId('f1', 'me'),
        'message_id': 'm1',
      });
      expect((await sajjad.fileStore.sends(memberId: 'me')).single.status, 'done');
    });

    test('wiring (scan)', () {
      final s = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(s, contains('groupMessagingService.onRelayedFile = (m, _) => unawaited(near'));
      expect(s, contains('.sendHave(m.groupId, m.id, m.senderId)'));
    });
  });
}
