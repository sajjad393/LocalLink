import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/features/storage/domain/media_clean_policy.dart';

final _now = DateTime(2026, 11, 3, 12);
const _mb = 1024 * 1024;

MediaFile _f(
  String id, {
  MediaKind kind = MediaKind.photo,
  int daysOld = 20,
  int? openedDaysAgo,
  bool mine = false,
  bool sent = true,
  bool removed = false,
  bool saved = false,
  int bytes = 10 * _mb,
  String chat = 'ali',
  bool group = false,
}) =>
    MediaFile(
      fileId: id,
      messageId: 'm$id',
      chatId: chat,
      isGroup: group,
      mine: mine,
      sent: sent,
      kind: kind,
      name: '$id.jpg',
      contentType: 'image/jpeg',
      rowPath: '/a/$id.jpg',
      diskPath: removed ? null : '/a/$id.jpg.enc',
      bytes: removed ? 0 : bytes,
      messageAt: _now.subtract(Duration(days: daysOld)),
      openedAt: openedDaysAgo == null ? null : _now.subtract(Duration(days: openedDaysAgo)),
      removed: removed,
      saved: saved,
    );

void main() {
  // Phone of 1000 MB, 800 MB used (80%) -> must free 100 MB to reach 70%.
  const total = 1000 * _mb;
  const free = 200 * _mb;

  group('197b clean-up rules (K3)', () {
    test('under 70% full: nothing', () {
      final r = MediaCleanPolicy.pick([_f('a')], now: _now, totalBytes: total, freeBytes: 400 * _mb);
      expect(r.picked, isEmpty);
    });

    test('exactly 70%: nothing (more than 70% only)', () {
      final r = MediaCleanPolicy.pick([_f('a')], now: _now, totalBytes: total, freeBytes: 300 * _mb);
      expect(r.picked, isEmpty);
    });

    test('10-day rule uses last opened, else message time', () {
      final files = [
        _f('old'),
        _f('new', daysOld: 3),
        _f('openedRecently', daysOld: 30, openedDaysAgo: 2),
        _f('openedLongAgo', daysOld: 30, openedDaysAgo: 15),
      ];
      final r = MediaCleanPolicy.pick(files, now: _now, totalBytes: total, freeBytes: free);
      expect(r.picked.map((f) => f.fileId), containsAll(['old', 'openedLongAgo']));
      expect(r.picked.map((f) => f.fileId), isNot(contains('new')));
      expect(r.picked.map((f) => f.fileId), isNot(contains('openedRecently')));
      expect(r.skippedRecent, 2);
    });

    test('voice notes never', () {
      final r = MediaCleanPolicy.pick([_f('v', kind: MediaKind.voice, daysOld: 99)],
          now: _now, totalBytes: total, freeBytes: free);
      expect(r.picked, isEmpty);
      expect(r.skippedVoice, 1);
    });

    test('my unsent / undelivered (and group server_seq 0) never', () {
      final r = MediaCleanPolicy.pick([
        _f('u', mine: true, sent: false),
        _f('g', mine: true, sent: false, group: true),
        _f('ok', mine: true, sent: true),
      ], now: _now, totalBytes: total, freeBytes: free);
      expect(r.picked.map((f) => f.fileId), ['ok']);
      expect(r.skippedUnsent, 2);
    });

    test('already removed or open now: skipped', () {
      final r = MediaCleanPolicy.pick([_f('r', removed: true), _f('open')],
          now: _now, totalBytes: total, freeBytes: free, openNow: {'open'});
      expect(r.picked, isEmpty);
    });

    test("saved file: LinkUp's copy may go (Gallery copy stays)", () {
      final r = MediaCleanPolicy.pick([_f('s', saved: true)], now: _now, totalBytes: total, freeBytes: free);
      expect(r.picked.single.fileId, 's');
    });

    test('Q3: oldest first, stop at 70%', () {
      final files = [
        _f('d20', daysOld: 20, bytes: 60 * _mb),
        _f('d40', daysOld: 40, bytes: 60 * _mb),
        _f('d30', daysOld: 30, bytes: 60 * _mb),
      ];
      final r = MediaCleanPolicy.pick(files, now: _now, totalBytes: total, freeBytes: free);
      // 800 -> 740 -> 680 (<= 700): two files, the two oldest.
      expect(r.picked.map((f) => f.fileId), ['d40', 'd30']);
      expect(r.bytes, 120 * _mb);
    });

    test('K7 test run: 11 days later + 80% full removes every candidate', () {
      final files = [_f('a', daysOld: 0, bytes: _mb), _f('b', daysOld: 1, bytes: _mb), _f('v', kind: MediaKind.voice)];
      final r = MediaCleanPolicy.pick(files,
          now: _now.add(const Duration(days: 11)), totalBytes: total, freeBytes: (total * 0.2).floor());
      expect(r.picked.map((f) => f.fileId).toSet(), {'a', 'b'});
    });

    test('unknown storage: nothing', () {
      expect(MediaCleanPolicy.pick([_f('a')], now: _now, totalBytes: 0, freeBytes: 0).picked, isEmpty);
    });
  });

  group('197b when a run starts (K1)', () {
    String? reason({bool on = true, bool call = false, bool busy = false, String trigger = 'start', DateTime? last}) =>
        MediaCleanPolicy.skipReason(switchOn: on, inCall: call, busy: busy, trigger: trigger, lastRun: last, now: _now);

    test('switch OFF', () => expect(reason(on: false), 'off'));
    test('during a call', () => expect(reason(call: true), 'call'));
    test('busy', () => expect(reason(busy: true), 'busy'));
    test('resume within 24 h', () {
      expect(reason(trigger: 'resume', last: _now.subtract(const Duration(hours: 3))), 'recent_run');
      expect(reason(trigger: 'resume', last: _now.subtract(const Duration(hours: 25))), isNull);
    });
    test('start always checks', () => expect(reason(last: _now), isNull));
  });

  group('197b storage summary', () {
    test('by type and by chat, biggest first, empty chats hidden', () {
      final s = StorageSummary.of([
        _f('a', chat: 'ali', bytes: 5 * _mb),
        _f('b', chat: 'fam', group: true, bytes: 9 * _mb, kind: MediaKind.video),
        _f('c', chat: 'ali', bytes: 6 * _mb, kind: MediaKind.voice),
        _f('d', chat: 'sum', removed: true),
      ]);
      expect(s.total, 20 * _mb);
      expect(s.byKind[MediaKind.photo], 5 * _mb);
      expect(s.byKind[MediaKind.video], 9 * _mb);
      expect(s.byKind[MediaKind.voice], 6 * _mb);
      expect(s.chats.map((c) => c.chatId), ['ali', 'fam']);
      expect(s.chats.first.bytes, 11 * _mb);
      expect(s.chats[1].isGroup, isTrue);
    });

    test('files of a chat: biggest first, removed not listed', () {
      final list = StorageSummary.filesOf([
        _f('s', bytes: _mb),
        _f('b', bytes: 3 * _mb),
        _f('r', removed: true),
        _f('x', chat: 'other'),
      ], 'ali', false);
      expect(list.map((f) => f.fileId), ['b', 's']);
    });

    test('labels', () {
      expect(formatStorageBytes((1.2 * 1024 * _mb).round()), '1.2 GB');
      expect(formatStorageBytes(640 * _mb), '640 MB');
      expect(formatStorageBytes((19.7 * _mb).round()), '19.7 MB');
      expect(formatStorageBytes(900 * 1024), '900 KB');
      expect(formatStorageBytes(12), '12 B');
    });

    test('kinds follow the chat bubble rules', () {
      expect(mediaKindOf(contentType: 'audio/mp4', name: 'v.m4a'), MediaKind.voice);
      expect(mediaKindOf(contentType: 'application/octet-stream', name: 'x.opus'), MediaKind.voice);
      expect(mediaKindOf(contentType: 'video/mp4', name: 'a.mp4'), MediaKind.video);
      expect(mediaKindOf(contentType: 'image/png', name: 'a.png'), MediaKind.photo);
      expect(mediaKindOf(contentType: '', name: 'a', isImage: true), MediaKind.photo);
      expect(mediaKindOf(contentType: 'application/pdf', name: 'a.pdf'), MediaKind.document);
    });
  });

  group('197b MediaBook', () {
    late MediaBook book;
    late Map<String, Map<String, Object?>> rows;
    late List<String> released;
    setUp(() {
      book = MediaBook();
      rows = {};
      released = [];
      book.load(const [], write: (r) async => rows[r['file_id'] as String] = r, delete: (ids) async {
        for (final id in ids) {
          rows.remove(id);
        }
      });
      book.onReleaseLinks = released.addAll;
    });

    test('removed / restored / saved are kept in the table', () async {
      await book.markRemoved('f1', now: _now);
      expect(book.isRemoved('f1'), isTrue);
      expect(rows['f1']!['removed_at'], isNotNull);
      await book.clearRemoved('f1');
      expect(book.isRemoved('f1'), isFalse);
      await book.setSaved('f1', 'content://x');
      expect(book.isSaved('f1'), isTrue);
    });

    test('a row read back is the same state', () async {
      await book.setThumb('f2', '/t/f2.jpg.enc', mediaMs: 42000);
      await book.setSource('f2', 'content://g/2');
      final again = MediaBook()..load([rows['f2']!]);
      expect(again.of('f2'), book.of('f2'));
      expect(again.of('f2')!.mediaMs, 42000);
    });

    test('forget returns small pictures and releases unused Gallery links only', () async {
      await book.setThumb('a', '/t/a.jpg.enc');
      await book.setSource('a', 'content://g/1');
      await book.setSource('b', 'content://g/1'); // forwarded twice: same link
      await book.setSource('c', 'content://g/3');
      final thumbs = await book.forget(['a', 'c']);
      expect(thumbs, ['/t/a.jpg.enc']);
      expect(released, ['content://g/3']);
      expect(rows.keys, ['b']);
      expect((await book.forget(const [])), isEmpty);
    });

    test('group send: pending id moves to the server id', () async {
      await book.setSource('pending1', 'content://g/9');
      await book.rename('pending1', 'server1');
      expect(book.of('pending1'), isNull);
      expect(book.of('server1')!.sourceUri, 'content://g/9');
      expect(released, isEmpty);
    });

    test('staged: link kept and small picture asked for', () async {
      final asked = <String>[];
      book.onStaged = (id, path, type, name) => asked.add('$id|$path');
      book.staged('f9', 'content://g/5', '/a/outbox-f9.jpg', 'image/jpeg', 'p.jpg');
      await Future<void>.delayed(Duration.zero);
      expect(book.of('f9')!.sourceUri, 'content://g/5');
      expect(asked, ['f9|/a/outbox-f9.jpg']);
    });
  });
}
