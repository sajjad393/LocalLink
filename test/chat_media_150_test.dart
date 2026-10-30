import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/data/services/media_progress_hub.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';
import 'package:locallink/features/files/presentation/widgets/blue_progress_ring.dart';
import 'package:locallink/features/files/presentation/widgets/chat_photo.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';
import 'package:locallink/features/files/presentation/widgets/media_view_cache.dart';

import 'support/phase5_fakes.dart';

class _Files extends FakeFilesRepository {
  int materialized = 0;
  final downloads = <String>[];

  @override
  Future<String> materializeForDisplay(String protectedPath,
      {String extension = '.bin'}) async {
    materialized++;
    return '/views/${protectedPath.split('/').last}$extension';
  }

  @override
  Future<String> downloadForMessage(String messageId, Attachment attachment,
      {String? operationId,
      void Function(TransferProgress progress)? onProgress}) async {
    downloads.add(attachment.id);
    throw Exception('Attachment download URL is missing');
  }
}

const _photoArriving = Attachment(
  id: 'p1',
  originalName: 'photo.jpg',
  contentType: 'image/jpeg',
  size: 2 * 1024 * 1024,
  sha256: 'x',
  isImage: true,
);

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  const channel = MethodChannel('locallink/voice_notes');

  setUp(() {
    MediaProgressHub.instance.resetForTest();
    MediaViewCache.instance.resetForTest();
    VideoInfoCache.resetForTest();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('item 1: video info no longer hangs', () {
    test('first load completes (was stuck until a refresh)', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        return <String, dynamic>{
          'duration_ms': 29000,
          'display_width': 720,
          'display_height': 1280,
        };
      });
      final info = await VideoInfoCache.load('/v/a.mp4', 'k1')
          .timeout(const Duration(seconds: 2));
      expect(info, isNotNull);
      expect(info!.durationMs, 29000);
      final again = await VideoInfoCache.load('/v/a.mp4', 'k1')
          .timeout(const Duration(seconds: 2));
      expect(again, same(info));
      expect(calls, 1, reason: 'second call comes from the cache');
    });

    test('two bubbles asking at once share one read and both finish', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        return <String, dynamic>{'duration_ms': 1000};
      });
      final both = await Future.wait([
        VideoInfoCache.load('/v/b.mp4', 'k2'),
        VideoInfoCache.load('/v/b.mp4', 'k2'),
      ]).timeout(const Duration(seconds: 2));
      expect(both.every((i) => i != null), isTrue);
      expect(calls, 1);
    });

    test('a failing read returns null instead of hanging', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'x');
      });
      final info = await VideoInfoCache.load('/v/c.mp4', 'k3')
          .timeout(const Duration(seconds: 2));
      expect(info, isNull);
    });
  });

  group('item 3: progress hub + label', () {
    test('label shows % and MB', () {
      expect(mediaProgressLabel(0, 0), isNull);
      expect(mediaProgressLabel(3 * 1024 * 1024, 6 * 1024 * 1024),
          '50% · 3.0 / 6.0 MB');
      expect(mediaProgressLabel(10, 5), '100% · 0.0 / 0.0 MB');
    });

    test('update / clear; slots do not pile up', () {
      final hub = MediaProgressHub.instance;
      hub.update('m1', done: 5, total: 10);
      expect(hub.peek('m1')!.fraction, .5);
      hub.update('m1', done: 50, total: 10);
      expect(hub.peek('m1')!.fraction, 1.0, reason: 'clamped');
      hub.clear('m1');
      expect(hub.peek('m1'), isNull);
      expect(hub.slotCount, 0);
      hub.update('', done: 1, total: 2);
      hub.update('m2', done: 1, total: 0);
      expect(hub.slotCount, 0, reason: 'bad input ignored');
    });
  });

  group('item 2: photo arriving over Wi-Fi', () {
    testWidgets(
        'no server download, no error; blue ring fills; photo shows when the file lands',
        (t) async {
      final files = _Files();
      Widget tile(Attachment a) => _host(AttachmentTile(
            key: const ValueKey('att:m1:p1'),
            attachment: a,
            transfer: files,
            messageId: 'm1',
          ));

      await t.pumpWidget(tile(_photoArriving));
      await t.pump();
      await t.pump();
      expect(files.downloads, isEmpty,
          reason: 'no link: a server download can only fail');
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const Key('chat_photo_placeholder')), findsOneWidget);
      expect(find.byKey(const Key('chat_media_receiving')), findsOneWidget);
      expect(find.text('Receiving… · 2.0 MB'), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file), findsNothing,
          reason: 'never the old grey file row');

      // Wi-Fi progress arrives.
      MediaProgressHub.instance.update('m1', done: 1024 * 1024, total: 2 * 1024 * 1024);
      await t.pump();
      expect(find.text('50% · 1.0 / 2.0 MB'), findsOneWidget);
      final ring = t.widget<CircularProgressIndicator>(
          find.byKey(const Key('blue_progress_indicator')));
      expect(ring.value, .5);
      expect(ring.color, kLocalLinkBlue);

      // File lands: the chat rebuilds the same tile with the saved path.
      MediaProgressHub.instance.clear('m1');
      await t.pumpWidget(tile(const Attachment(
        id: 'p1',
        originalName: 'photo.jpg',
        contentType: 'image/jpeg',
        size: 2 * 1024 * 1024,
        sha256: 'x',
        isImage: true,
        localPath: '/db/attachments/p1.jpg.enc',
      )));
      await t.pump();
      await t.pump();
      expect(files.materialized, 1);
      expect(find.byType(ChatPhoto), findsOneWidget,
          reason: 'shows by itself, no refresh');
      expect(find.byKey(const Key('chat_media_receiving')), findsNothing);

      await t.pumpWidget(const SizedBox());
      MediaViewCache.instance.resetForTest();
    });

    testWidgets('big video arriving: receiving ring, no download button, no download', (t) async {
      final files = _Files();
      const video = Attachment(
        id: 'v1',
        originalName: 'clip.mp4',
        contentType: 'video/mp4',
        size: 30 * 1024 * 1024, // > 10 MB: would normally wait for a tap
        sha256: 'y',
      );
      await t.pumpWidget(_host(AttachmentTile(
          attachment: video, transfer: files, messageId: 'm9')));
      await t.pump();
      expect(find.byKey(const Key('chat_media_receiving')), findsOneWidget);
      expect(find.byKey(const Key('chat_video_download')), findsNothing);
      expect(files.downloads, isEmpty);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('item 1/3: sender sees the real photo with a blue ring', () {
    testWidgets('uploading photo: ChatPhoto + live ring', (t) async {
      final files = _Files();
      const mine = Attachment(
        id: 'p2',
        originalName: 'mine.jpg',
        contentType: 'image/jpeg',
        size: 4 * 1024 * 1024,
        sha256: 'z',
        isImage: true,
        localPath: '/db/attachments/outbox-p2.jpg.enc',
      );
      await t.pumpWidget(_host(AttachmentTile(
          attachment: mine, transfer: files, messageId: 'm2', uploading: true)));
      await t.pump();
      await t.pump();
      expect(find.byType(ChatPhoto), findsOneWidget);
      expect(find.byKey(const Key('chat_media_sending')), findsOneWidget);
      expect(find.text('Sending… · 4.0 MB'), findsOneWidget);

      // Sender progress comes as chunks; MB comes from the real size.
      MediaProgressHub.instance.update('m2', done: 3, total: 4);
      await t.pump();
      expect(find.text('75% · 3.0 / 4.0 MB'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      MediaViewCache.instance.resetForTest();
    });

    testWidgets('own photo still opening: photo frame, not the file row',
        (t) async {
      final files = _SlowView();
      const mine = Attachment(
        id: 'p3',
        originalName: 'mine.jpg',
        contentType: 'image/jpeg',
        size: 1000,
        sha256: 'z',
        isImage: true,
        width: 1200,
        height: 1600,
        localPath: '/db/attachments/p3.jpg.enc',
      );
      await t.pumpWidget(_host(AttachmentTile(
          attachment: mine, transfer: files, messageId: 'm3')));
      await t.pump();
      final frame = t.getSize(find.byKey(const Key('chat_photo_placeholder')));
      expect(frame.width, 250);
      expect(frame.height, closeTo(333.3, .1),
          reason: 'real (tall) shape from the hint');
      expect(find.byIcon(Icons.insert_drive_file), findsNothing);
      files.gate.complete('/views/p3.jpg');
      await t.pump();
      await t.pump();
      expect(find.byType(ChatPhoto), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      MediaViewCache.instance.resetForTest();
    });
  });
}

class _SlowView extends FakeFilesRepository {
  final gate = Completer<String>();

  @override
  Future<String> materializeForDisplay(String protectedPath,
          {String extension = '.bin'}) =>
      gate.future;
}
