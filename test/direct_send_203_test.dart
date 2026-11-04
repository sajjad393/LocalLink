// Bundle 203: many files over Nearby with no internet.
// One flush at a time, files answer early / wait in a line, continue
// instead of restarting, no double sends, >50 MB dropped, lock ring on my
// own picture, one ring per file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/security/sensitive_file_protection_service.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/account/presentation/widgets/private_profile_card.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/files/data/services/media_progress_hub.dart';
import 'package:locallink/features/files/domain/file_size_rule.dart';
import 'package:locallink/features/files/presentation/widgets/file_too_big_dialog.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';
import 'package:locallink/features/messaging/data/services/send_copy_book.dart';
import 'package:locallink/features/messaging/presentation/screens/forward_screen.dart';

import 'support/phase5_fakes.dart';

const _mb = 1024 * 1024;

/// The first outbox read waits until the test lets it go.
class _SlowStore extends FakeStore {
  int reads = 0;
  final Completer<void> gate = Completer<void>();

  @override
  Future<List<Map<String, dynamic>>> outbox({bool pendingOnly = false}) async {
    reads++;
    if (reads == 1) await gate.future;
    return super.outbox(pendingOnly: pendingOnly);
  }
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('203 (1) one flush at a time', () {
    test('a flush asked for while one runs runs again at the end (not two at once)',
        () async {
      final store = _SlowStore();
      final transport = FakePeerTransport();
      final policy = LocalRoutePolicyService(transport);
      await policy.start();
      final service = ReliableMessagingService(
        store,
        LocalLinkApi(store, WebSocketService()),
        WebSocketService(),
        FakeFilesRepository(),
        FakeConnectivity(),
        transport,
        routePolicy: policy,
      );
      await transport.configure(
          deviceId: 'self-device',
          connected: true,
          groupOwner: false,
          knownPeers: const []);
      final first = service.flush();
      await Future<void>.delayed(Duration.zero);
      expect(store.reads, 1);
      // Asked again while the first one waits: no second read now.
      await service.flush();
      await service.flush();
      expect(store.reads, 1, reason: 'never two flushes at once');
      store.gate.complete();
      await first;
      // ...but ONE more flush runs at the end.
      for (var i = 0; i < 20 && store.reads < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(store.reads, 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.reads, 2, reason: 'the extra run happens once');
    });

    test('watchdog waits 90 s of no life and retires the old flush', () {
      final src = _read(
          'lib/features/messaging/data/services/reliable_messaging_service.dart');
      expect(src, contains('_flushWatchdog = Duration(seconds: 90)'));
      expect(src, contains("'MESSAGE_FLUSH_WATCHDOG_RESET'"));
      expect(src, contains("detail: 'idle="));
      expect(src, contains("'MESSAGE_FLUSH_STALE_STOP'"));
      expect(src, contains("'MESSAGE_FLUSH_AGAIN'"));
      expect(src, contains('if (gen == _flushGen) {'));
      expect(src, contains('store.outboxItem(id)'));
      expect(src, isNot(contains("'MESSAGE_FLUSH_SKIPPED_ALREADY_RUNNING'")));
      // Small files first.
      expect(src, contains('..sort((a, b) => (int.tryParse('));
    });
  });

  group('203 (2) native answers early + waiting line', () {
    final kt = _read(
        'android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt');
    final policy = _read(
        'android/app/src/main/kotlin/com/sajjad/locallink/DirectFileTransferPolicy.kt');

    test('answer (cb true) comes before the parts are sent', () {
      final i = kt.indexOf('answered=true;cb(true,null)');
      final j = kt.indexOf('sendMissingChunks(t,true)}catch');
      expect(i, greaterThan(0));
      expect(j, greaterThan(i));
      expect(kt, isNot(contains('persistOutgoingTransfer(t);sendMissingChunks(t,true);transportEvent("file_queued"')));
    });

    test('no free place = wait in a line, not an error', () {
      expect(kt, isNot(contains('too many active outgoing file transfers')));
      expect(kt, isNot(contains('active outgoing file byte budget exceeded')));
      expect(kt, contains('FILE_SEND_WAITING'));
      expect(kt, contains('FILE_SEND_FROM_LINE'));
      expect(kt, contains('private fun startWaitingFile()'));
      expect(kt, contains('type == "file_sent" || type == "file_failed" || type == "file_cancelled" || type == "file_expired"'));
      expect(kt, contains('outgoingWaitLine.remove(id)'), reason: 'cancel removes from the line');
      expect(policy, contains('fun mustWait('));
      expect(policy, contains('MAX_WAITING_OUTGOING = 200'));
    });
  });

  group('203 (3) continue instead of restarting', () {
    test('native continues the same file under a new path', () {
      final kt = _read(
          'android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt');
      expect(kt, contains('FILE_SEND_CONTINUE'));
      expect(kt, contains('existing.copy(filePath=file.absolutePath'));
      expect(
          _read('android/app/src/main/kotlin/com/sajjad/locallink/DirectFileTransferPolicy.kt'),
          contains('fun canContinue(sameRecipient: Boolean, sameSize: Boolean, sameSha: Boolean)'));
    });

    test('one fixed .send- copy: made once, reused, dropped when done', () async {
      final dir = await Directory.systemTemp.createTemp('send203');
      addTearDown(() => dir.delete(recursive: true));
      final plain = File('${dir.path}/photo-1.jpg')..writeAsBytesSync(List.filled(1000, 7));
      var opens = 0;
      Future<String> open(String locked, String ext) async {
        opens++;
        final v = File('${dir.path}/.view-abc$ext')..writeAsBytesSync(List.filled(500, 3));
        return v.path;
      }

      final book = SendCopyBook.instance;
      final a = await book.pathFor(
          localPath: plain.path, fileId: 'file-1', originalName: 'Photo.JPG', open: open);
      expect(a, '${dir.path}/.send-file-1.jpg');
      expect(File(a).lengthSync(), 1000);
      final b = await book.pathFor(
          localPath: plain.path, fileId: 'file-1', originalName: 'Photo.JPG', open: open);
      expect(b, a, reason: 'same path every retry');

      // A locked (.enc) file: opened once, then the same copy is reused.
      final locked = File('${dir.path}/vid-2.mp4.enc')..writeAsBytesSync([1, 2, 3]);
      final c = await book.pathFor(
          localPath: '${dir.path}/vid-2.mp4', fileId: 'file-2', originalName: 'v.mp4', open: open);
      final d = await book.pathFor(
          localPath: locked.path, fileId: 'file-2', originalName: 'v.mp4', open: open);
      expect(c, '${dir.path}/.send-file-2.mp4');
      expect(d, c);
      expect(opens, 1);
      expect(File('${dir.path}/.view-abc.mp4').existsSync(), isFalse,
          reason: 'the view copy became the send copy');

      expect(await book.drop('file-1'), isTrue);
      expect(File(a).existsSync(), isFalse);
      expect(await book.drop('file-1'), isFalse);
    });

    test('the 5-minute sweep keeps .send- copies (gone after 7 days)', () async {
      final dir = await Directory.systemTemp.createTemp('sweep203');
      addTearDown(() => dir.delete(recursive: true));
      final now = DateTime(2026, 11, 4, 12);
      File f(String n, Duration age) {
        final x = File('${dir.path}/$n')..writeAsStringSync('x');
        x.setLastModifiedSync(now.subtract(age));
        return x;
      }

      final send1 = f('.send-a.jpg', const Duration(days: 1));
      final send8 = f('.send-b.jpg', const Duration(days: 8));
      final view = f('.view-c.jpg', const Duration(minutes: 6));
      await SensitiveFileProtectionService().cleanupSensitiveArtifacts(dir, now: now);
      expect(send1.existsSync(), isTrue);
      expect(send8.existsSync(), isFalse);
      expect(view.existsSync(), isFalse);
    });

    test('1:1 and group sends use the fixed copy', () {
      final rms = _read(
          'lib/features/messaging/data/services/reliable_messaging_service.dart');
      expect(rms, contains('SendCopyBook.instance.pathFor('));
      expect(rms, contains('fileId: fileId,\n                );'));
      expect(rms, contains('await SendCopyBook.instance.drop(endedId);'));
      final grp = _read('lib/features/groups/data/services/group_messaging_service.dart');
      expect(grp, contains('SendCopyBook.instance.pathFor('));
    });
  });

  group('203 (4) no double sends', () {
    test('done is remembered (saved), 7 days, max 500; resend clears it', () async {
      final saved = <String, String>{};
      var now = DateTime(2026, 11, 4);
      DirectFilesDoneBook make() => DirectFilesDoneBook(
          read: (k) async => saved[k],
          write: (k, v) async => saved[k] = v,
          now: () => now);
      final book = make();
      expect(await book.isDone('f1'), isFalse);
      book.markSending('f1');
      expect(book.isSending('f1'), isTrue);
      await book.markDone('f1');
      expect(book.isSending('f1'), isFalse);
      expect(await book.isDone('f1'), isTrue);
      expect(jsonDecode(saved[DirectFilesDoneBook.settingKey]!), contains('f1'));
      // After a restart it is still known.
      expect(await make().isDone('f1'), isTrue);
      await book.clear('f1');
      expect(await make().isDone('f1'), isFalse);

      await book.markDone('old');
      now = now.add(const Duration(days: 8));
      expect(await make().isDone('old'), isFalse);

      for (var i = 0; i < 510; i++) {
        await book.markDone('n$i');
      }
      final map = jsonDecode(saved[DirectFilesDoneBook.settingKey]!) as Map;
      expect(map.length, DirectFilesDoneBook.maxEntries);
    });

    test('still sending ends after 10 minutes', () {
      var now = DateTime(2026, 11, 4);
      final book = DirectFilesDoneBook(
          read: (_) async => null, write: (_, __) async {}, now: () => now);
      book.markSending('x');
      now = now.add(const Duration(minutes: 9));
      expect(book.isSending('x'), isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(book.isSending('x'), isFalse);
    });

    test('flush skips files already done / on their way', () {
      final src = _read(
          'lib/features/messaging/data/services/reliable_messaging_service.dart');
      expect(src, contains("'DIRECT_FILE_ALREADY_DONE'"));
      expect(src, contains("'DIRECT_FILE_STILL_SENDING'"));
      expect(src, contains('await directFilesDone.markDone(endedId);'));
      expect(src, contains('await directFilesDone.clear(a.id);'));
    });
  });

  group('203 (5) files over 50 MB', () {
    PickedFile p(String n, int size, [String type = 'image/jpeg']) =>
        PickedFile(path: '/x/$n', name: n, contentType: type, size: size);

    test('split keeps <= 50 MB and drops bigger', () {
      final r = FileSizeRule.split([
        p('a.jpg', 3 * _mb),
        p('v.mp4', 63 * _mb, 'video/mp4'),
        p('edge.bin', 50 * _mb),
        p('b.jpg', 50 * _mb + 1),
      ]);
      expect(r.keep.map((f) => f.name), ['a.jpg', 'edge.bin']);
      expect(r.dropped.map((f) => f.name), ['v.mp4', 'b.jpg']);
      expect(FileSizeRule.maxBytes, 52428800);
    });

    test('words (mock 203)', () {
      expect(FileSizeRule.title(1), 'File too big');
      expect(FileSizeRule.title(2), '2 files too big');
      expect(FileSizeRule.body(1), 'This file is bigger than 50 MB, so it was not added.');
      expect(FileSizeRule.body(2),
          'These files are bigger than 50 MB, so they were not added.');
      expect(FileSizeRule.body(1, forward: true),
          "This file is bigger than 50 MB and can't be forwarded. The other items were forwarded.");
      expect(FileSizeRule.body(1, forward: true, othersSent: false),
          "This file is bigger than 50 MB and can't be forwarded.");
      expect(FileSizeRule.sizeLabel(63 * _mb), '63 MB');
      expect(FileSizeRule.sizeLabel(212 * _mb), '212 MB');
    });

    testWidgets('pop-up shows the title, words, file and OK', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFileTooBigDialog(context,
                const [TooBigFile('VID_20261104_1712.mp4', 63 * _mb, isVideo: true)]),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('File too big'), findsOneWidget);
      expect(find.text('This file is bigger than 50 MB, so it was not added.'), findsOneWidget);
      expect(find.text('VID_20261104_1712.mp4'), findsOneWidget);
      expect(find.text('63 MB'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('file-too-big-dialog')), findsNothing);
    });

    test('forward drops only the big files', () {
      const small = Attachment(
          id: 'a', originalName: 'a.jpg', contentType: 'image/jpeg', size: 2 * _mb, sha256: '');
      const big = Attachment(
          id: 'b', originalName: 'b.mp4', contentType: 'video/mp4', size: 58 * _mb, sha256: '');
      final out = ForwardScreen.withoutTooBig(const [
        ForwardItem(text: 'hi', attachments: [small, big]),
        ForwardItem(text: '', attachments: [big]),
      ]);
      expect(out.length, 1);
      expect(out.first.attachments.map((a) => a.id), ['a']);
      expect(out.first.text, 'hi');
    });

    test('wired at pick (1:1 + group), forward and in send', () {
      for (final f in [
        'lib/features/messaging/presentation/screens/chat_screen.dart',
        'lib/features/groups/presentation/screens/group_chat_screen.dart',
      ]) {
        final s = _read(f);
        expect(s, contains('FileSizeRule.split('), reason: f);
        expect(s, contains('showFileTooBigDialog('), reason: f);
      }
      expect(_read('lib/features/messaging/presentation/screens/forward_screen.dart'),
          contains('ForwardScreen.withoutTooBig(items)'));
      expect(
          _read('lib/features/messaging/data/services/reliable_messaging_service.dart'),
          contains("'DIRECT_FILE_TOO_BIG_DROPPED'"));
    });
  });

  group('203 (5b) private lock ring on my picture', () {
    testWidgets('ring + lock only when locked; same size', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            AccountAvatar(key: ValueKey('a'), name: 'Sajjad', radius: 52),
            AccountAvatar(key: ValueKey('b'), name: 'Sajjad', radius: 52, locked: true),
          ]),
        ),
      ));
      expect(find.byKey(const ValueKey('avatar_private_lock')), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('a'))),
          tester.getSize(find.byKey(const ValueKey('b'))));
    });

    test('used on Profile + Settings card only, from my own switch', () {
      expect(_read('lib/features/account/presentation/screens/profile_screen.dart'),
          contains('locked: own ?? ProfilePrivacyRule.isPrivate(value)'));
      final settings =
          _read('lib/features/home/presentation/screens/messenger_settings_screen.dart');
      expect(settings, contains('SettingsOwnAvatar('));
      expect(settings, contains('locked: own == true'));
      expect(_read('lib/features/account/presentation/widgets/private_profile_card.dart'),
          contains('ProfilePrivacyRule.ownPrivate.value = makePrivate;'));
      expect(ProfilePrivacyRule.ownPrivate, isNotNull);
      // Friends' pictures never get it.
      expect(_read('lib/features/home/presentation/screens/home_screen.dart'),
          contains('AccountAvatar(name: name, radius: 22, peerId: device.id)'));
    });
  });

  group('203 (6) one ring per file', () {
    setUp(() => MediaProgressHub.instance.resetForTest());

    test('each file has its own number; ending one keeps the other', () {
      final hub = MediaProgressHub.instance;
      final a = hub.watchFile('m1', 'fa');
      final b = hub.watchFile('m1', 'fb');
      hub.update('m1', done: 10, total: 100, fileId: 'fa');
      hub.update('m1', done: 80, total: 100, fileId: 'fb');
      expect(a.value!.fraction, closeTo(0.1, 1e-9));
      expect(b.value!.fraction, closeTo(0.8, 1e-9));
      expect(hub.hasFileProgress('m1'), isTrue);
      hub.clear('m1', fileId: 'fb');
      expect(b.value, isNull);
      expect(a.value!.fraction, closeTo(0.1, 1e-9));
      expect(hub.peek('m1'), isNotNull, reason: 'message ring follows file a');
      hub.clear('m1', fileId: 'fa');
      expect(hub.peek('m1'), isNull);
      expect(hub.hasFileProgress('m1'), isFalse);
    });

    test('group wire ids map to the file', () {
      expect(MediaProgressHub.baseFileId('att-1.g0a1b2c3d'), 'att-1');
      expect(MediaProgressHub.baseFileId('att-1'), 'att-1');
      final hub = MediaProgressHub.instance;
      hub.update('gm', done: 5, total: 10, fileId: 'att-1.g0a1b2c3d');
      expect(hub.peekFile('gm', 'att-1')!.done, 5);
    });

    test('clear without a file clears all files of the message', () {
      final hub = MediaProgressHub.instance;
      hub.update('m2', done: 1, total: 4, fileId: 'x');
      hub.update('m2', done: 2, total: 4, fileId: 'y');
      hub.clear('m2');
      expect(hub.peekFile('m2', 'x'), isNull);
      expect(hub.peekFile('m2', 'y'), isNull);
      expect(hub.peek('m2'), isNull);
    });

    test('the tile ring watches its own file', () {
      final s = _read('lib/features/files/presentation/widgets/attachment_tile.dart');
      expect('fileId: widget.attachment.id'.allMatches(s).length, 3);
      expect(s, contains('hub.watchFile(messageId, file)'));
    });
  });
}
