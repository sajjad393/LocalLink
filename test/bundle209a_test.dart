import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/storage/database_config.dart';
import 'package:locallink/features/groups/data/group_file_hash.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';

import 'support/g209_fakes.dart';

// Bundle 209 (A): the writer signs each file's fingerprint (sha256) with
// the message ('llgm3'), so any member who has the file can pass it on.

final _sha = 'a' * 64;
final _sha2 = 'b' * 64;

void main() {
  group('fingerprint in the file list (209 A)', () {
    test('toJson adds sha only when there is one; old lists stay the same', () {
      expect(g9Photo.toJson().containsKey('sha'), isFalse);
      expect(g9Photo.toJson(), {'id': 'f1', 'name': 'a.jpg', 'type': 'image/jpeg', 'size': 200000});
      final f = g9Photo.withSha(_sha);
      expect(f.toJson()['sha'], _sha);
      final back = GroupNearbyFile.fromJson(jsonDecode(jsonEncode(f.toJson())));
      expect(back!.sha, _sha);
      expect(back.toAttachment().sha256, _sha);
      expect(GroupNearbyFile.fromAttachment(back.toAttachment()).sha, _sha);
    });

    test('a bad sha is dropped (file kept, no fingerprint)', () {
      for (final bad in ['xyz', 'A' * 64, 'a' * 63, '']) {
        final f = GroupNearbyFile.fromJson({...g9Photo.toJson(), 'sha': bad});
        expect(f, isNotNull);
        expect(f!.sha, '');
      }
      expect(g9Photo.withSha('nope').sha, '');
      expect(g9Photo.withSha(_sha).withoutSha.sha, '');
    });

    test('the old signed text (llgm2) does not change with a sha', () {
      final a = GroupFileWire.messageText2('g', 'm', 'w', 'c', 'b', [g9Photo]);
      final b = GroupFileWire.messageText2('g', 'm', 'w', 'c', 'b', [g9Photo.withSha(_sha)]);
      expect(a, b);
    });

    test('llgm3 covers the sha', () {
      final a = GroupFileWire.messageText3('g', 'm', 'w', 'c', 'b', [g9Photo.withSha(_sha)]);
      final b = GroupFileWire.messageText3('g', 'm', 'w', 'c', 'b', [g9Photo.withSha(_sha2)]);
      expect(a, startsWith('llgm3\ng\nm\nw\nc\nb\n'));
      expect(a, contains(_sha));
      expect(a, isNot(b));
      expect(GroupFileWire.allHaveSha([g9Photo.withSha(_sha)]), isTrue);
      expect(GroupFileWire.allHaveSha([g9Photo.withSha(_sha), g9Voice]), isFalse);
      expect(GroupFileWire.allHaveSha(const []), isFalse);
      expect(GroupFileWire.passFor, const Duration(days: 7));
    });

    test('the copy row keeps sig3', () {
      const c = GroupCopy(id: 'm', gid: 'g', writer: 'w', createdAt: 'c', body: 'b',
          sig: 's', keptAt: 1, att: '[]', sig2: 's2', sig3: 's3');
      expect(c.toRow()['sig3'], 's3');
      expect(GroupCopy.fromRow(c.toRow()).sig3, 's3');
      expect(GroupCopy.fromRow({'id': 'm'}).sig3, '');
    });
  });

  group('file hash (209 A)', () {
    test('sha256 of the file bytes, read in parts', () async {
      final dir = await Directory.systemTemp.createTemp('h209');
      final f = File('${dir.path}/a.bin');
      final bytes = List<int>.generate(300000, (i) => i % 251);
      await f.writeAsBytes(bytes);
      final got = await GroupFileHash.hashNow(f.path);
      expect(got, sha256.convert(bytes).toString());
      expect(await GroupFileHash.hashNow('${dir.path}/missing'), '');
      await dir.delete(recursive: true);
    });

    test('too big / no path / a failing worker = no fingerprint', () async {
      final old = GroupFileHash.worker;
      addTearDown(() => GroupFileHash.worker = old);
      GroupFileHash.worker = (p) async => _sha;
      expect(await GroupFileHash.ofFile('/a', size: 10), _sha);
      expect(await GroupFileHash.ofFile('/a', size: GroupFileWire.maxBytes + 1), '');
      expect(await GroupFileHash.ofFile(''), '');
      GroupFileHash.worker = (p) async => throw StateError('x');
      expect(await GroupFileHash.ofFile('/a'), '');
      GroupFileHash.worker = (p) async => 'short';
      expect(await GroupFileHash.ofFile('/a'), '');
    });
  });

  group('the writer signs llgm3 (209 A)', () {
    late G9Air air;
    late G9Phone sajjad, ali;

    setUp(() async {
      air = G9Air()..now = g9T0;
      sajjad = G9Phone(air, 'sajjad');
      ali = G9Phone(air, 'ali');
      sajjad.befriend(ali);
      ali.befriend(sajjad);
      await sajjad.service.createGroup(
          gid: 'g-1', name: 'Family', memberIds: ['ali'], origin: 'nearby');
      await g9Settle(air);
    });

    test('files with a sha: sig2 + sig3, sha in att, copy keeps sig3', () async {
      await sajjad.service.fanOut('g-1', 'm1', 'Look', g9At(1), files: [g9Photo.withSha(_sha)]);
      await g9Settle(air);
      final p = sajjad.sentPayloads.firstWhere((p) => p['type'] == 'group_msg');
      expect(p['sig2'], isNotEmpty);
      expect(p['sig3'], isNotEmpty);
      expect(p['sig3'], isNot(p['sig2']));
      expect((p['att'] as List).single['sha'], _sha);
      final copy = sajjad.copyStore.rows['m1']!;
      expect(copy.sig3, p['sig3']);
      expect(copy.att, contains(_sha));
    });

    test('a file without a sha: no sig3 and no sha sent (as in 208)', () async {
      await sajjad.service.fanOut('g-1', 'm1', '', g9At(1),
          files: [g9Photo.withSha(_sha), g9Voice]);
      await g9Settle(air);
      final p = sajjad.sentPayloads.firstWhere((p) => p['type'] == 'group_msg');
      expect(p.containsKey('sig3'), isFalse);
      expect([for (final f in p['att'] as List) (f as Map).containsKey('sha')], [false, false]);
      expect(sajjad.copyStore.rows['m1']!.sig3, '');
      // The member still gets it (old check).
      expect(ali.got.where((m) => m.id == 'm1'), hasLength(1));
    });
  });

  group('code checks (209 A)', () {
    test('database v34 only adds group_copies.sig3', () {
      expect(DatabaseConfig.version, 34);
      final s = File('lib/core/services/local_store.dart').readAsStringSync();
      expect(s, contains('if (oldVersion < 34) await _upgradeTo34(db);'));
      final i = s.indexOf('Future<void> _upgradeTo34(');
      final up = s.substring(i, s.indexOf('\n  }\n', i));
      expect(up, contains('ALTER TABLE group_copies ADD COLUMN sig3'));
      expect(up, isNot(contains('messages')));
      // A copy without a fingerprint keeps the one already saved.
      expect(s, contains("sha256=CASE WHEN COALESCE(excluded.sha256,'')='' THEN group_message_attachments.sha256 ELSE excluded.sha256 END"));
    });

    test('sending a group file makes its fingerprint (Nearby groups only)', () {
      final s = File('lib/features/groups/data/services/group_messaging_service.dart')
          .readAsStringSync();
      expect(s, contains('? await GroupFileHash.ofFile(staged.path, size: staged.size)'));
      expect(s, contains('final sha = group.worksNearby'));
    });
  });
}
