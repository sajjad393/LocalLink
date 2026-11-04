import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/storage/database_config.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  group('197b database v27 + wiring (source checks)', () {
    final store = _read('lib/core/services/local_store.dart');

    test('version 27 with a side table (attachment rows untouched)', () {
      expect(DatabaseConfig.version, 32); // Bundle G5: v32 = group receipts
      expect(store, contains('if (oldVersion < 27) await _upgradeTo27(db);'));
      expect(store, contains('CREATE TABLE IF NOT EXISTS media_state ('));
      for (final c in ['file_id TEXT PRIMARY KEY', 'thumb_path TEXT', 'media_ms INTEGER NOT NULL DEFAULT 0',
          'source_uri TEXT', 'opened_at TEXT', 'removed_at TEXT', 'saved_uri TEXT']) {
        expect(store, contains(c), reason: c);
      }
      // fresh install path too
      expect(RegExp(r'await _upgradeTo26\(db\);\s*await _upgradeTo27\(db\);').hasMatch(store), isTrue);
    });

    test('loaded at start, wiped on reset / clear all', () {
      expect(store, contains('await _loadMediaBook();'));
      expect('MediaBook.instance.resetMemory()'.allMatches(store).length, greaterThanOrEqualTo(2));
      expect("'media_state'".allMatches(store).length, greaterThanOrEqualTo(3));
    });

    test('delete message / group message: small pictures + server -thumb files go too (L3, T4)', () {
      expect('paths.addAll(await _mediaExtrasFor('.allMatches(store).length, 2);
      expect(store, contains(r"'$id-thumb.png'"));
    });

    test('failed message delete removes its files (L1)', () {
      expect(store, contains('Future<List<String>> deleteFailedOutbox(String id)'));
      final svc = _read('lib/features/messaging/data/services/reliable_messaging_service.dart');
      expect(svc, contains('final paths = await store.deleteFailedOutbox(id);'));
      expect(svc, contains('await deletes.deleteFiles(paths);'));
      final actions = _read('lib/features/messaging/data/message_delete_actions.dart');
      expect(actions, contains(r"await deleteFile('$path.enc');"));
    });

    test('picker keeps the Gallery link; staging asks for the small picture', () {
      const f = PickedFile(path: '/p', name: 'a.jpg', contentType: 'image/jpeg', size: 1, sourceUri: 'content://x');
      expect(f.sourceUri, 'content://x');
      final kt = _read('android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt');
      expect(kt, contains('MediaStorageNative.keepLink(this,u)'));
      for (final m in ['"make_thumb"', '"storage_stats"', '"uri_alive"', '"release_uris"', '"restore_from_uri"', '"save_to_phone"']) {
        expect(kt, contains(m), reason: m);
      }
      final fts = _read('lib/features/files/data/services/file_transfer_service.dart');
      expect("MediaBook.instance.staged(fileId, file.sourceUri, target".allMatches(fts).length, 2);
      final groups = _read('lib/features/groups/data/services/group_messaging_service.dart');
      expect(groups, contains('MediaBook.instance.rename('));
    });

    test('picks sweep never deletes a file a row still uses', () {
      final svc = _read('lib/features/storage/data/media_storage_service.dart');
      expect(svc, contains('final used = await store.referencedLocalPaths();'));
      expect(svc, contains('Duration(hours: 24)'));
      expect(store, contains("'pending_group_attachments',"));
    });

    test('home starts it; never during a call', () {
      final home = _read('lib/features/home/presentation/screens/home_screen.dart');
      expect(home, contains('inCall: () => ChatVideoHub.instance.callActive'));
      expect(home, contains('AppLifecycleListener(onResume: service.onResume)'));
    });

    test('all logs from TODO 11 exist', () {
      final svc = _read('lib/features/storage/data/media_storage_service.dart');
      for (final l in ['STORAGE_CHECK', 'MEDIA_CLEANED', 'MEDIA_CLEAN_SKIPPED', 'MEDIA_CLEAN_TEST', 'THUMB_BACKFILL',
          'THUMB_FAILED', 'GALLERY_LINKS', 'GALLERY_LINK_DEAD', 'MEDIA_RESTORED_FROM_GALLERY', 'MEDIA_SAVED_TO_PHONE',
          'MEDIA_SAVE_FAILED', 'MEDIA_DELETED_MANUAL', 'STORAGE_AUTO_CLEAN', 'PICKS_SWEPT', 'STORAGE_ORPHANS']) {
        expect(svc, contains("'$l'"), reason: l);
      }
    });

    test('Kotlin service untouched; no new permission', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
      expect(manifest, isNot(contains('READ_MEDIA_IMAGES')));
    });
  });
}
