import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';
import 'package:locallink/features/files/presentation/widgets/media_grid.dart';
import 'package:locallink/features/files/presentation/widgets/media_view_cache.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';

import 'support/phase5_fakes.dart';

class _ViewFiles extends FakeFilesRepository {
  @override
  Future<String> materializeForDisplay(String protectedPath,
          {String extension = '.bin'}) async =>
      '/views/v$extension';
}

const _channel = MethodChannel('locallink/voice_notes');
// a real 1x1 PNG
final _thumb = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

void main() {
  late int infoCalls;
  late List<Object?> answers; // per call: Map / null / 'throw'

  setUp(() {
    infoCalls = 0;
    answers = <Object?>[];
    VideoInfoCache.resetForTest();
    MediaThumbs.debugReset();
    MediaBook.instance.resetMemory();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method != 'video_info') return null;
      final i = infoCalls++;
      final a = i < answers.length ? answers[i] : answers.last;
      if (a == 'throw') throw PlatformException(code: 'invalid');
      return a;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    MediaThumbs.debugReset();
    MediaBook.instance.resetMemory();
    VideoInfoCache.resetForTest();
  });

  // First on purpose: the storage service singleton must be made outside
  // testWidgets' fake time (its thumb chain future lives in that zone).
  test('208 C5: a small picture skipped in a call is remembered', () async {
    final s = MediaStorageService.instance;
    s.resetForTest();
    s.configureForTest(files: FakeFilesRepository());
    s.inCall = () => true;
    expect(await s.ensureThumb('f1', '/views/a.mp4', video: true), isFalse);
    expect(s.debugAfterCallCount, 1);
    s.resetForTest();
    expect(s.debugAfterCallCount, 0);
  });
  const video = Attachment(
      id: 'vid1',
      originalName: 'clip.mp4',
      contentType: 'video/mp4',
      size: 3000000,
      sha256: 's',
      localPath: '/protected/clip.llf');

  Widget cell() => MaterialApp(
      home: Scaffold(
          body: Center(
              child: AttachmentTile(
                  attachment: video,
                  transfer: _ViewFiles(),
                  messageId: 'm1',
                  cell: const Size(120, 120)))));

  Future<void> frames(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump();
    }
  }

  bool frameShown(WidgetTester t) {
    final f = find.byKey(const ValueKey<String>('grid_video:vid1'));
    if (f.evaluate().isEmpty) return false;
    final w = t.widget(f);
    return w is Image && w.image is MemoryImage;
  }

  testWidgets('208 C1: a grid square shows the first frame without playing',
      (t) async {
    answers = [
      {'thumbnail': _thumb, 'duration_ms': 4000, 'display_width': 640, 'display_height': 360}
    ];
    await t.pumpWidget(cell());
    await frames(t);
    expect(infoCalls, 1, reason: 'the square asked for the first frame itself');
    expect(frameShown(t), isTrue);
    expect(find.text('0:04'), findsOneWidget);
    // a redraw does not ask again
    await t.pumpWidget(cell());
    await frames(t, 2);
    expect(infoCalls, 1);
    await t.pumpWidget(const SizedBox());
    MediaViewCache.instance.resetForTest();
  });

  testWidgets('208 C4: reading fails once -> one more try after the gap, no third',
      (t) async {
    VideoInfoCache.retryGap = const Duration(milliseconds: 300);
    answers = [
      'throw',
      {'thumbnail': _thumb, 'duration_ms': 1000},
    ];
    await t.pumpWidget(cell());
    await frames(t);
    expect(infoCalls, 1);
    expect(frameShown(t), isFalse);
    // real time for the cache's clock + fake time for the tile's timer
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
    await t.pump(const Duration(milliseconds: 350));
    await frames(t);
    expect(infoCalls, 2);
    expect(frameShown(t), isTrue);
    await t.pumpWidget(const SizedBox());
    MediaViewCache.instance.resetForTest();
  });

  test('208 C4: a fresh failure is not asked again inside the gap', () async {
    answers = ['throw'];
    expect(await VideoInfoCache.load('/v.mp4', 'k'), isNull);
    expect(await VideoInfoCache.load('/v.mp4', 'k'), isNull);
    expect(infoCalls, 1, reason: 'second ask inside 3 s = no native call');
    VideoInfoCache.retryGap = Duration.zero;
    answers = [
      {'thumbnail': _thumb}
    ];
    infoCalls = 0;
    expect((await VideoInfoCache.load('/v.mp4', 'k'))?.thumbnail, isNotNull);
  });

  testWidgets('208 C2: MediaThumbFill shows the small picture once it is saved',
      (t) async {
    final dir = Directory.systemTemp.createTempSync('b208c');
    final pic = File('${dir.path}/t.jpg')..writeAsBytesSync(_thumb);
    var saved = false;
    MediaThumbs.debugLoader = (id) async => saved ? pic.path : null;
    await t.pumpWidget(const MaterialApp(
        home: SizedBox(
            width: 100,
            height: 100,
            child: MediaThumbFill(
                attachmentId: 'vid1',
                fallback: ColoredBox(key: Key('grey'), color: Colors.grey)))));
    await frames(t, 3);
    expect(find.byKey(const Key('grey')), findsOneWidget);
    // the small picture gets saved a moment later
    saved = true;
    await MediaBook.instance.setThumb('vid1', '/thumbs/vid1.jpg.enc');
    await frames(t, 3);
    expect(find.byKey(const ValueKey<String>('media_thumb:vid1')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('208 C2: same id redrawn while nothing was found -> looks again',
      (t) async {
    final dir = Directory.systemTemp.createTempSync('b208c2');
    final pic = File('${dir.path}/t.jpg')..writeAsBytesSync(_thumb);
    var saved = false;
    var asks = 0;
    MediaThumbs.debugLoader = (id) async {
      asks++;
      return saved ? pic.path : null;
    };
    Widget w(int n) => MaterialApp(
        home: SizedBox(
            width: 100 + n.toDouble(),
            height: 100,
            // ignore: prefer_const_constructors
            child: MediaThumbFill(attachmentId: 'vid1')));
    await t.pumpWidget(w(0));
    await frames(t, 2);
    saved = true;
    await t.pumpWidget(w(1));
    await frames(t, 2);
    expect(asks, greaterThanOrEqualTo(2));
    expect(find.byKey(const ValueKey<String>('media_thumb:vid1')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('208 C3/C5 wiring (source)', () {
    final tile = File('lib/features/files/presentation/widgets/attachment_tile.dart')
        .readAsStringSync();
    final ph = tile.indexOf('Widget _videoPlaceholder(');
    expect(ph, greaterThan(0));
    expect(tile.indexOf("ValueKey<String>('video_wait_thumb:", ph), greaterThan(ph),
        reason: 'the waiting video shows the saved small picture');
    final st = File('lib/features/storage/data/media_storage_service.dart')
        .readAsStringSync();
    expect(st, contains('_rememberAfterCall(fileId, plainPath, video)'));
    expect(st, contains("'THUMB_AFTER_CALL'"));
  });


}
