import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/storage/database_config.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';

import 'support/b212_fakes.dart';

/// Bundle 212 (H1 b): store. Kept in the settings table (no DB change),
/// the book feeds isBlockedPeer / blockedPeerIds, changes fire.
void main() {
  test('no database change: still v34', () {
    expect(DatabaseConfig.version, 34);
  });

  test('isBlockedPeer and blockedPeerIds include admin blocks', () {
    final s = File('lib/core/services/local_store.dart').readAsStringSync();
    final ids = s.substring(s.indexOf('Future<Set<String>> blockedPeerIds()'),
        s.indexOf('Future<bool> isBlockedPeer('));
    expect(ids.contains('...await _adminBlockedIds()'), isTrue);
    final peer = s.substring(s.indexOf('Future<bool> isBlockedPeer('));
    expect(peer.substring(0, 400).contains('_adminBlockedIds()'), isTrue);
    expect(s.contains('static void notifyBlockedChanged() => _blockedChanges.add(null);'), isTrue);
  });

  test('book: block covers account + phones; unblock clears; self', () async {
    final book = AdminBlockBook.separate();
    final server = await Keys212.make();
    final mesh = Mesh212();
    final settings = <String, String>{AdminBlockService.trustKeySetting: server.pub};
    var changed = 0;
    final s = mesh.phone('dev-ali', userId: 'ali', settings: settings, book: book,
        onChanged: () => changed++);
    await s.load();
    expect(book.selfBlocked, isFalse);
    final r1 = (await serverRecord212(server, target: 'ali', action: 'block', seq: 1, id: 'a1'));
    expect(await s.offer(_rec(r1), source: 'server'), isTrue);
    expect(book.isBlocked('ali'), isTrue);
    expect(book.selfBlocked, isTrue);
    expect(changed, 1);
    // saved, and loaded again by a fresh service
    final again = Mesh212().phone('dev-ali', userId: 'ali', settings: settings,
        book: AdminBlockBook.separate());
    await again.load();
    expect(again.book.selfBlocked, isTrue);
    expect(again.entries.single.serverDone, isTrue);
    final r2 = await serverRecord212(server, target: 'ali', action: 'unblock', seq: 2, id: 'a2');
    expect(await s.offer(_rec(r2), source: 'server'), isTrue);
    expect(book.selfBlocked, isFalse);
    expect(book.blockedIds, isEmpty);
    // older again: ignored
    expect(await s.offer(_rec(r1), source: 'nearby'), isFalse);
  });

  test('chat bar text', () {
    final book = AdminBlockBook.instance;
    addTearDown(book.resetForTest);
    book.resetForTest();
    expect(adminBlockBarText('Ali', peerId: 'dev-ali'), isNull);
    book.setSelf(userId: 'me', deviceId: 'dev-me');
    expect(book.selfBlocked, isFalse);
  });
}

AdminBlockRecord _rec(SignedBlob blob) => AdminBlockRecord.fromBlob(blob)!;
