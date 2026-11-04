import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/security/sensitive_file_protection_service.dart';
import 'package:locallink/core/services/file_in_use.dart';
import 'package:locallink/features/files/data/services/file_transfer_service.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/presentation/widgets/media_gallery_viewer.dart';
import 'package:locallink/features/files/presentation/widgets/media_view_cache.dart';

import 'support/phase5_fakes.dart';

/// Locks by writing "LOCKED:<plain>" next to it; slow like a big video.
class _SlowLock extends SensitiveFileProtectionService {
  int runs = 0;
  Completer<void>? gate;

  @override
  Future<void> protectFile(String plaintextPath, String protectedPath) async {
    runs++;
    final text = await File(plaintextPath).readAsString();
    await (gate?.future ?? Future<void>.delayed(const Duration(milliseconds: 20)));
    await File('$protectedPath.part').writeAsString('LOCKED:$text');
    await File('$protectedPath.part').rename(protectedPath);
  }

  @override
  Future<bool> isProtected(String path) async =>
      path.endsWith('.enc') && await File(path).exists();
}

class _Store extends FakeStore {
  final replaced = <String, String>{};
  @override
  Future<void> replaceAttachmentLocalPath(String oldPath, String newPath) async =>
      replaced[oldPath] = newPath;
}

class _Files implements FileTransferRepositoryContract {
  _Files(this.dir);
  final Directory dir;
  final locked = <String>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
  @override
  Future<bool> isProtectedLocalFile(String path) async => path.endsWith('.enc');
  @override
  Future<String> protectLegacyLocalFile(String plaintextPath) async {
    locked.add(plaintextPath);
    return '$plaintextPath.enc';
  }

  @override
  Future<String> materializeForDisplay(String protectedPath, {String extension = '.bin'}) async {
    final f = File('${dir.path}/view$extension');
    await f.writeAsBytes(const [1, 2, 3]);
    return f.path;
  }

  @override
  Future<void> deleteLocalFile(String path) async {}
}

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('b207g');
    FileInUse.debugReset();
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('207 G1-G3 lock once', () {
    test('3 callers at once -> 1 lock job, same .enc, no error, plain gone', () async {
      final lock = _SlowLock();
      final store = _Store();
      final svc = FileTransferService(store, sensitiveFiles: lock);
      final plain = File('${dir.path}/outbox-a.mp4')..writeAsStringSync('video');
      final results = await Future.wait([
        svc.protectLegacyLocalFile(plain.path),
        svc.protectLegacyLocalFile(plain.path),
        svc.protectLegacyLocalFile(plain.path),
      ]);
      expect(lock.runs, 1);
      expect(results.toSet(), {'${plain.path}.enc'});
      expect(plain.existsSync(), isFalse);
      expect(File('${plain.path}.enc').readAsStringSync(), 'LOCKED:video');
      // G2: the rows now name the .enc
      expect(store.replaced[plain.path], '${plain.path}.enc');
      // later call: plain is gone, the .enc is used
      expect(await svc.protectLegacyLocalFile(plain.path), '${plain.path}.enc');
      expect(lock.runs, 1);
    });

    test('big files are locked one at a time', () async {
      final lock = _SlowLock()..gate = Completer<void>();
      final svc = FileTransferService(_Store(), sensitiveFiles: lock);
      final big = List<int>.filled(FileTransferService.protectQueueMinBytes + 1, 97);
      final a = File('${dir.path}/outbox-a.mp4')..writeAsBytesSync(big);
      final b = File('${dir.path}/outbox-b.mp4')..writeAsBytesSync(big);
      final small = File('${dir.path}/outbox-c.jpg')..writeAsStringSync('c');
      final fa = svc.protectLegacyLocalFile(a.path);
      final fb = svc.protectLegacyLocalFile(b.path);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(lock.runs, 1, reason: 'the second big one waits for the first');
      // a small picture does not wait behind the big video
      final fc = svc.protectLegacyLocalFile(small.path);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(lock.runs, 2);
      lock.gate!.complete();
      await Future.wait([fa, fb, fc]);
      expect(lock.runs, 3);
    });

    test('a file being copied for sending is not deleted until the copy ends', () async {
      final svc = FileTransferService(_Store(), sensitiveFiles: _SlowLock());
      final plain = File('${dir.path}/outbox-s.mp4')..writeAsStringSync('send me');
      final copyDone = Completer<void>();
      final held = FileInUse.hold(plain.path, () => copyDone.future);
      final enc = await svc.protectLegacyLocalFile(plain.path);
      expect(File(enc).existsSync(), isTrue);
      expect(plain.existsSync(), isTrue, reason: 'still being sent');
      copyDone.complete();
      await held;
      expect(plain.existsSync(), isFalse);
    });

    test('a failed lock does not block the next one', () async {
      final svc = FileTransferService(_Store(), sensitiveFiles: _SlowLock());
      await expectLater(
          svc.protectLegacyLocalFile('${dir.path}/missing.mp4'), throwsStateError);
      final ok = File('${dir.path}/outbox-ok.jpg')..writeAsStringSync('x');
      expect(await svc.protectLegacyLocalFile(ok.path), '${ok.path}.enc');
    });
  });

  group('207 G4 viewer opens the file itself', () {
    testWidgets('no chat view but the file is here -> Preparing… then shows it', (tester) async {
      final plain = File('${dir.path}/own.jpg')..writeAsBytesSync(const [9]);
      final files = _Files(dir);
      MediaGalleryViewer.files = files;
      addTearDown(() => MediaGalleryViewer.files = null);
      final a = Attachment(
        id: 'att-own-207',
        originalName: 'own.jpg',
        contentType: 'image/jpeg',
        size: 1,
        sha256: '',
        isImage: true,
        localPath: plain.path,
      );
      await tester.pumpWidget(MaterialApp(
        home: MediaGalleryViewer(items: [GalleryItem.fromAttachment(a)]),
      ));
      expect(find.byKey(const Key('media_gallery_preparing')), findsOneWidget);
      expect(find.byKey(const Key('media_gallery_not_ready')), findsNothing);
      // Bundle 207 (M2, mock page 4 screen 12): the short line under it.
      expect(find.textContaining('Your photo'), findsOneWidget);
      expect(find.textContaining('opens in a moment'), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      expect(files.locked, [plain.path]);
      expect(find.byKey(const ValueKey<String>('media_gallery_photo:att-own-207')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      MediaViewCache.instance.resetForTest();
    });

    testWidgets('really not on the phone -> Not downloaded yet', (tester) async {
      MediaGalleryViewer.files = _Files(dir);
      addTearDown(() => MediaGalleryViewer.files = null);
      final a = Attachment(
        id: 'att-gone-207',
        originalName: 'x.jpg',
        contentType: 'image/jpeg',
        size: 1,
        sha256: '',
        isImage: true,
        localPath: '${dir.path}/nothing.jpg',
      );
      await tester.pumpWidget(MaterialApp(
        home: MediaGalleryViewer(items: [GalleryItem.fromAttachment(a)]),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      expect(find.byKey(const Key('media_gallery_not_ready')), findsOneWidget);
    });
  });

  group('207 N log fixes (source)', () {
    test('N1: discovery socket errors end quietly (onError + cancelOnError)', () {
      final src = File('lib/features/connectivity/data/services/discovery_service.dart')
          .readAsStringSync();
      expect(src, contains('onError: (Object _)'));
      expect(src, contains('cancelOnError: true'));
    });
    test('N2: a small picture is tried once more after 2 s', () {
      final src = File('lib/features/storage/data/media_storage_service.dart')
          .readAsStringSync();
      expect(src, contains("'THUMB_RETRY'"));
      expect(src, contains('retry: false'));
    });
  });
}
