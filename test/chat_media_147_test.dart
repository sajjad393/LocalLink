// Bundle 147: smooth media scrolling, real shapes, mini player / PiP.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/security/sensitive_file_protection_service.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';
import 'package:locallink/features/files/presentation/widgets/chat_photo.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_hub.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_player.dart';
import 'package:locallink/features/files/presentation/widgets/media_frame.dart';
import 'package:locallink/features/files/presentation/widgets/media_playback_coordinator.dart';
import 'package:locallink/features/files/presentation/widgets/media_view_cache.dart';

import 'support/chat_video_fakes.dart';
import 'support/phase5_fakes.dart';

class _ViewFiles extends FakeFilesRepository {
  _ViewFiles(this.viewPath);
  final String viewPath;
  int materialized = 0;
  final deleted = <String>[];

  @override
  Future<String> materializeForDisplay(String protectedPath,
      {String extension = '.bin'}) async {
    materialized++;
    return viewPath;
  }

  @override
  Future<void> deleteLocalFile(String path) async => deleted.add(path);
}

Future<void> _settleScroll(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

/// Real players pause asynchronously: state still says "playing" for a bit.
class _SlowPause extends FakeVideoController {
  _SlowPause() : super('/v/slow.mp4');
  @override
  Future<void> pause() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await super.pause();
  }
}

void main() {
  setUp(() {
    MediaViewCache.instance.resetForTest();
    MediaSizeCache.clearForTest();
  });

  group('MediaFrame: real shape, scaled to fit 250 x 360, no crop', () {
    test('camera photos and videos', () {
      expect(MediaFrame.fit(4000, 3000), const Size(250, 187.5));
      final portrait = MediaFrame.fit(3000, 4000);
      expect(portrait.width, 250);
      expect(portrait.height, closeTo(333.3, .1));
      expect(MediaFrame.fit(1080, 1920), const Size(202.5, 360));
      expect(MediaFrame.fit(1920, 1080).height, closeTo(140.6, .1));
      expect(MediaFrame.fit(500, 500), const Size(250, 250));
    });

    test('ratio is always kept exactly', () {
      for (final s in const [
        [6000, 1000], [1000, 6000], [123, 457], [4032, 3024], [20, 1], [1, 20]
      ]) {
        final f = MediaFrame.fit(s[0], s[1]);
        expect(f.width / f.height, closeTo(s[0] / s[1], 1e-6), reason: '$s');
        expect(f.width, lessThanOrEqualTo(250));
        expect(f.height, lessThanOrEqualTo(360));
        expect(math.max(f.width / 250, f.height / 360), closeTo(1, 1e-9),
            reason: 'as big as fits: $s');
      }
    });

    test('unknown size → placeholder', () {
      expect(MediaFrame.fit(0, 0), MediaFrame.unknown);
      expect(MediaFrame.fit(100, 0), MediaFrame.unknown);
      expect(MediaFrame.fitAspect(null), MediaFrame.unknown);
      expect(MediaFrame.fitAspect(double.nan), MediaFrame.unknown);
    });

    test('mini player: same shape, about the same area', () {
      final wide = MediaFrame.mini(16 / 9);
      expect(wide.width, closeTo(192, .5));
      expect(wide.height, closeTo(108, .5));
      final tall = MediaFrame.mini(9 / 16);
      expect(tall.width, closeTo(108, .5));
      expect(tall.height, closeTo(192, .5));
      final square = MediaFrame.mini(1);
      expect(square.width, closeTo(144, .5));
      final pano = MediaFrame.mini(5);
      expect(pano.width / pano.height, closeTo(2.39, .001), reason: 'PiP limit');
      expect(MediaFrame.clampPip(0.1), closeTo(1 / 2.39, 1e-9));
      expect(MediaFrame.clampPip(double.infinity), 16 / 9);
    });
  });

  group('MediaViewCache: decrypt once, share, keep while shown', () {
    test('two holders share one decrypt; kept after release until idle', () async {
      var now = DateTime(2026, 10, 30, 12);
      final cache = MediaViewCache(clock: () => now);
      final deleted = <String>[];
      var decrypts = 0;
      Future<String> materialize() async {
        decrypts++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return '/views/a.jpg';
      }

      final results = await Future.wait([
        cache.acquire('k', materialize, delete: (p) async => deleted.add(p)),
        cache.acquire('k', materialize, delete: (p) async => deleted.add(p)),
      ]);
      expect(results, ['/views/a.jpg', '/views/a.jpg']);
      expect(decrypts, 1, reason: 'concurrent callers share the decrypt');
      expect(cache.refsOf('k'), 2);
      expect(SensitiveFileProtectionService.pinnedViews, contains('/views/a.jpg'),
          reason: 'background sweep must skip views on screen');

      cache.release('k');
      cache.release('k');
      await cache.evict();
      expect(cache.length, 1, reason: 'scrolling back must not decrypt again');
      expect(deleted, isEmpty);

      now = now.add(const Duration(minutes: 5));
      await cache.evict();
      await Future<void>.delayed(Duration.zero);
      expect(cache.length, 0);
      expect(deleted, ['/views/a.jpg']);
      expect(SensitiveFileProtectionService.pinnedViews,
          isNot(contains('/views/a.jpg')));
    });

    test('over budget: drops least recently used views nobody holds', () async {
      final dir = await Directory.systemTemp.createTemp('mvc');
      addTearDown(() => dir.delete(recursive: true));
      Future<String> file(String name) async {
        final f = File('${dir.path}/$name');
        await f.writeAsBytes(List<int>.filled(1000, 1));
        return f.path;
      }

      final cache = MediaViewCache(maxBytes: 2500);
      final deleted = <String>[];
      Future<void> del(String p) async => deleted.add(p);
      final a = await cache.acquire('a', () => file('a'), delete: del);
      await cache.acquire('b', () => file('b'), delete: del);
      await cache.acquire('c', () => file('c'), delete: del);
      await Future<void>.delayed(const Duration(milliseconds: 50)); // sizes
      cache.release('a');
      cache.release('c');
      await cache.evict(); // 3000 > 2500: a (oldest, unused) goes
      await Future<void>.delayed(Duration.zero);
      expect(deleted, [a]);
      expect(cache.peek('b'), isNotNull, reason: 'still held: never dropped');
      expect(cache.peek('c'), isNotNull);
    });

    test('retain keeps a playing video file after its bubble lets go', () async {
      final cache = MediaViewCache(idleRetention: Duration.zero);
      final deleted = <String>[];
      await cache.acquire('v', () async => '/views/v.mp4',
          delete: (p) async => deleted.add(p));
      cache.retain('v'); // playback hold
      cache.release('v'); // bubble gone
      await cache.evict();
      expect(deleted, isEmpty);
      cache.release('v'); // mini player closed
      await cache.evict();
      await Future<void>.delayed(Duration.zero);
      expect(deleted, ['/views/v.mp4']);
    });
  });

  test('isolate crypto: same file format, round trip', () async {
    final dir = await Directory.systemTemp.createTemp('crypt');
    addTearDown(() => dir.delete(recursive: true));
    final key = List<int>.generate(32, (i) => i * 7 % 256);
    final plain = List<int>.generate(300000, (i) => (i * 31) % 256);
    final src = File('${dir.path}/src.bin')..writeAsBytesSync(plain);
    final enc = '${dir.path}/enc.llf';
    final out = '${dir.path}/out.bin';
    await SensitiveFileProtectionService.encryptFileForTest(src.path, enc, key);
    final bytes = File(enc).readAsBytesSync();
    expect(String.fromCharCodes(bytes.sublist(0, 7)), 'LLFILE1');
    expect(bytes[7], 12, reason: 'nonce length');
    expect(bytes[8], 16, reason: 'mac length');
    expect(bytes.length, 7 + 2 + 12 + 16 + plain.length);
    await SensitiveFileProtectionService.decryptFileForTest(enc, out, key);
    expect(File(out).readAsBytesSync(), plain);

    final wrong = List<int>.filled(32, 9);
    await expectLater(
        SensitiveFileProtectionService.decryptFileForTest(enc, out, wrong),
        throwsA(anything));
  });

  group('photos', () {
    testWidgets('known size → bubble has the photo\'s own shape (no crop)', (t) async {
      MediaSizeCache.put('p1', const Size(1080, 1920));
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: Center(
                  child: ChatPhoto(path: '/nope/p1.jpg', sizeKey: 'p1')))));
      final frame = t.getSize(find.byKey(const Key('chat_photo_frame')));
      expect(frame.width, closeTo(202.5, .01));
      expect(frame.height, closeTo(360, .01));
      final img = t.widget<Image>(find.byType(Image));
      expect(img.fit, BoxFit.contain);
      expect(img.image, isA<ResizeImage>(),
          reason: 'decoded at bubble size, not 12 MP');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('size read from the decoded photo; viewer opens and closes', (t) async {
      final dir = Directory.systemTemp.createTempSync('photo');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/wide.png';
      await t.runAsync(() async {
        final rec = ui.PictureRecorder();
        Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 400, 100),
            Paint()..color = const Color(0xFF3366FF));
        final image = await rec.endRecording().toImage(400, 100);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(path).writeAsBytesSync(png!.buffer.asUint8List());
      });
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(child: ChatPhoto(path: path, sizeKey: 'wide')))));
      expect(t.getSize(find.byKey(const Key('chat_photo_frame'))),
          MediaFrame.unknown);
      for (var i = 0; i < 20 && MediaSizeCache.get('wide') == null; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
      await t.pump(const Duration(milliseconds: 200));
      expect(MediaSizeCache.get('wide'), const Size(400, 100));
      expect(t.getSize(find.byKey(const Key('chat_photo_frame'))),
          const Size(250, 62.5));

      await t.tap(find.byKey(const Key('chat_photo_tap')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('chat_photo_viewer')), findsOneWidget);
      await t.tap(find.byKey(const Key('chat_photo_viewer_close')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('chat_photo_viewer')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('tile: scrolling off and back reuses the view (one decrypt)', (t) async {
      final files = _ViewFiles('/views/photo.jpg');
      MediaSizeCache.put('img1', const Size(800, 600));
      const a = Attachment(
          id: 'img1', originalName: 'p.jpg', contentType: 'image/jpeg',
          size: 1000, sha256: 'b', isImage: true, localPath: '/protected/p.llf');
      Widget tile() => MaterialApp(
          home: Scaffold(
              body: AttachmentTile(
                  key: UniqueKey(), attachment: a, transfer: files, messageId: 'm')));
      await t.pumpWidget(tile());
      await t.pump();
      await t.pump();
      expect(find.byType(ChatPhoto), findsOneWidget);
      expect(files.materialized, 1);
      await t.pumpWidget(const SizedBox()); // scrolled away
      await t.pumpWidget(tile()); // scrolled back
      await t.pump();
      await t.pump();
      expect(files.materialized, 1, reason: 'no second decrypt');
      expect(files.deleted, isEmpty, reason: 'view kept, not deleted on dispose');
      await t.pumpWidget(const SizedBox());
      MediaViewCache.instance.resetForTest(); // stops the 60 s sweep timer
    });
  });

  group('mini player', () {
    testWidgets('scrolled out of view while playing → mini; X stops; bubble resets', (t) async {
      final r = Rig();
      final scroll = ScrollController();
      await t.pumpWidget(MaterialApp(
        builder: (c, child) => ChatVideoShell(hub: r.hub, child: child!),
        home: Scaffold(
          body: ListView(
              controller: scroll,
              // ignore: deprecated_member_use
              cacheExtent: 3000,
              children: [
            r.player('/v/a.mp4'),
            for (var i = 0; i < 30; i++) SizedBox(height: 80, child: Text('m$i')),
          ]),
        ),
      ));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      expect(r.hub.mini, isNull);
      scroll.jumpTo(100); // still partly visible
      await _settleScroll(t);
      expect(r.hub.mini, isNull, reason: 'partly visible: stays in the bubble');
      scroll.jumpTo(1200);
      await _settleScroll(t);
      expect(r.hub.mini, isNotNull);
      expect(find.byKey(const Key('mini_video')), findsOneWidget);
      expect(c.state.playing, isTrue, reason: 'keeps playing');
      final mini = t.getSize(find.byKey(const Key('mini_video')));
      expect(mini.width / mini.height, closeTo(16 / 9, .01),
          reason: 'mini player has the video shape');

      scroll.jumpTo(0);
      await _settleScroll(t);
      expect(find.byKey(const Key('chat_video_in_mini')), findsOneWidget);

      await t.tap(find.byKey(const Key('mini_video_close')));
      await t.pump();
      await t.pump();
      expect(c.closed, isTrue);
      expect(find.byKey(const Key('mini_video')), findsNothing);
      expect(find.byKey(const Key('chat_video_play_big')), findsOneWidget,
          reason: 'bubble back to its thumbnail');
      expect(r.released, ['/v/a.mp4']);
      expect(r.retained, 1);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('chat closed while playing → mini; bubble back → tap returns it inline', (t) async {
      final r = Rig();
      final show = ValueNotifier<bool>(true);
      await t.pumpWidget(MaterialApp(
        builder: (c, child) => ChatVideoShell(hub: r.hub, child: child!),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, v, __) =>
                ListView(children: [if (v) r.player('/v/a.mp4')]),
          ),
        ),
      ));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      show.value = false;
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('mini_video')), findsOneWidget);
      expect(c.closed, isFalse);

      show.value = true; // chat opened again
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('chat_video_in_mini')), findsOneWidget);
      await t.tap(find.byKey(const Key('chat_video_surface')));
      await t.pump();
      await t.pump();
      expect(r.hub.mini, isNull);
      expect(find.byKey(const Key('mini_video')), findsNothing);
      expect(find.byKey(const Key('fake_view')), findsOneWidget,
          reason: 'playing in the bubble again, same player');
      expect(r.controllers, hasLength(1));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('full screen: minimize → mini; mini tap → full screen; X stops', (t) async {
      final r = Rig();
      await t.pumpWidget(host([r.player('/v/a.mp4')], hub: r.hub));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      await tapKey(t, 'chat_video_fullscreen');
      await t.pumpAndSettle();
      await tapKey(t, 'chat_video_fs_minimize');
      await t.pumpAndSettle();
      expect(find.byType(ChatVideoFullscreen), findsNothing);
      expect(find.byKey(const Key('mini_video')), findsOneWidget);
      expect(find.byKey(const Key('chat_video_in_mini')), findsOneWidget);

      r.hub.navigatorKey = GlobalKey<NavigatorState>(); // no app navigator here
      await t.tap(find.byKey(const Key('mini_video')));
      await t.pumpAndSettle();
      expect(find.byType(ChatVideoFullscreen), findsNothing,
          reason: 'no navigator → nothing (no crash)');

      await tapKey(t, 'chat_video_surface'); // back into the bubble
      await tapKey(t, 'chat_video_fullscreen');
      await t.pumpAndSettle();
      await tapKey(t, 'chat_video_fs_close');
      await t.pumpAndSettle();
      expect(c.closed, isTrue);
      expect(find.byKey(const Key('mini_video')), findsNothing);
      expect(find.byKey(const Key('chat_video_play_big')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('playing another video closes the mini player', (t) async {
      final r = Rig();
      final showA = ValueNotifier<bool>(true);
      await t.pumpWidget(MaterialApp(
        builder: (c, child) => ChatVideoShell(hub: r.hub, child: child!),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: showA,
            builder: (_, v, __) => ListView(children: [
              if (v) r.player('/v/a.mp4'),
              r.player('/v/b.mp4'),
            ]),
          ),
        ),
      ));
      await t.pump();
      await tapKey(t, 'chat_video_play_big', index: 0);
      final a = r.controllers[0];
      showA.value = false;
      await t.pump();
      await t.pump();
      expect(r.hub.mini, isNotNull);
      await tapKey(t, 'chat_video_play_big');
      expect(a.closed, isTrue);
      expect(r.hub.mini, isNull);
      expect(r.controllers[1].state.playing, isTrue);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('drag snaps to the nearest corner; fling sideways closes', (t) async {
      final r = Rig();
      final show = ValueNotifier<bool>(true);
      await t.pumpWidget(MaterialApp(
        builder: (c, child) => ChatVideoShell(hub: r.hub, child: child!),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, v, __) =>
                ListView(children: [if (v) r.player('/v/a.mp4')]),
          ),
        ),
      ));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      show.value = false;
      await t.pump();
      await t.pump();
      await t.pumpAndSettle();
      final start = t.getCenter(find.byKey(const Key('mini_video')));
      expect(r.hub.miniCorner, Alignment.bottomRight);
      await t.timedDrag(find.byKey(const Key('mini_video')),
          const Offset(-500, -400), const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(r.hub.miniCorner, Alignment.topLeft);
      final moved = t.getCenter(find.byKey(const Key('mini_video')));
      expect(moved.dx, lessThan(start.dx));
      expect(moved.dy, lessThan(start.dy));

      await t.fling(find.byKey(const Key('mini_video')), const Offset(-300, 0), 3000);
      await t.pumpAndSettle();
      expect(r.hub.mini, isNull);
      expect(r.controllers.single.closed, isTrue);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('finished in the mini player: replay button, then closes after 5 s', (t) async {
      final r = Rig();
      final show = ValueNotifier<bool>(true);
      await t.pumpWidget(MaterialApp(
        builder: (c, child) => ChatVideoShell(hub: r.hub, child: child!),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, v, __) =>
                ListView(children: [if (v) r.player('/v/a.mp4')]),
          ),
        ),
      ));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      show.value = false;
      await t.pump();
      await t.pump();
      await c.seekTo(const Duration(seconds: 31));
      await c.pause();
      await t.pump();
      expect(find.byKey(const Key('mini_video_replay')), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      expect(r.hub.mini, isNotNull);
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(r.hub.mini, isNull);
      expect(c.closed, isTrue);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a call pauses the video, hides the mini player and blocks play', (t) async {
      final r = Rig();
      final show = ValueNotifier<bool>(true);
      await t.pumpWidget(MaterialApp(
        builder: (c, child) => ChatVideoShell(hub: r.hub, child: child!),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, v, __) =>
                ListView(children: [if (v) r.player('/v/a.mp4')]),
          ),
        ),
      ));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      show.value = false;
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('mini_video')), findsOneWidget);

      r.hub.setCallActive(true);
      await t.pump();
      expect(c.state.playing, isFalse);
      expect(find.byKey(const Key('mini_video')), findsNothing);
      await r.hub.mini!.play();
      expect(c.state.playing, isFalse, reason: 'no video over a call');

      r.hub.setCallActive(false);
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('mini_video')), findsOneWidget,
          reason: 'back after the call, paused');
      expect(c.state.playing, isFalse);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('picture-in-picture (Android)', () {
    Future<(Rig, FakeVideoController)> playing(WidgetTester t) async {
      final r = Rig();
      r.hub.attach(navigatorKey: GlobalKey<NavigatorState>());
      addTearDown(r.hub.detachForTest);
      await t.pumpWidget(host([r.player('/v/a.mp4')], hub: r.hub));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      return (r, r.controllers.single);
    }

    testWidgets('ready only while a video plays and no call', (t) async {
      final (r, c) = await playing(t);
      expect(r.pip.calls.last, startsWith('ready=true playing=true'));
      await tapKey(t, 'chat_video_pause');
      expect(r.pip.calls.last, startsWith('ready=false'));
      await tapKey(t, 'chat_video_play');
      expect(r.pip.calls.last, startsWith('ready=true'));
      r.hub.setCallActive(true);
      await t.pump();
      expect(r.pip.calls.last, startsWith('ready=false'),
          reason: 'call screens are never put into PiP');
      expect(c.state.playing, isFalse);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('call starts while the player is still pausing: PiP is off at once', (t) async {
      final pip = FakePip();
      final hub = ChatVideoHub(pip: pip)
        ..attach(navigatorKey: GlobalKey<NavigatorState>());
      addTearDown(hub.detachForTest);
      final c = _SlowPause();
      await c.initialize();
      final s = ChatVideoSession(
          controller: c, path: c.path, coordinator: MediaPlaybackCoordinator());
      hub.register(s);
      await s.play();
      expect(pip.calls.last, startsWith('ready=true'));
      hub.setCallActive(true);
      expect(c.state.playing, isTrue, reason: 'pause still in progress');
      expect(pip.calls.last, startsWith('ready=false'));
      await t.pump(const Duration(milliseconds: 60));
      expect(c.state.playing, isFalse);
      s.close();
    });

    testWidgets('leave app: PiP keeps playing (only the video drawn); no PiP → pause', (t) async {
      final (r, c) = await playing(t);
      r.hub.didChangeAppLifecycleState(AppLifecycleState.inactive);
      r.pip.events$.add({'type': 'pip', 'active': true, 'dismissed': false});
      await t.pump(const Duration(milliseconds: 800));
      expect(c.state.playing, isTrue);
      expect(find.byType(PipVideoView), findsOneWidget);
      expect(find.byType(ListView), findsNothing, reason: 'app kept offstage');

      r.pip.events$.add({'type': 'action', 'action': 'fwd10'});
      await t.pump();
      expect(c.state.position, const Duration(seconds: 10));
      r.pip.events$.add({'type': 'action', 'action': 'pause'});
      await t.pump();
      expect(c.state.playing, isFalse);
      r.pip.events$.add({'type': 'action', 'action': 'play'});
      await t.pump();
      expect(c.state.playing, isTrue);

      // Expanded back into the app.
      r.pip.events$.add({'type': 'pip', 'active': false, 'dismissed': false});
      r.hub.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await t.pump();
      expect(find.byType(PipVideoView), findsNothing);
      expect(c.state.playing, isTrue);

      // Screen off without PiP: pause.
      r.hub.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await t.pump(const Duration(milliseconds: 800));
      expect(c.state.playing, isFalse);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('PiP window swiped away → video stops', (t) async {
      final (r, c) = await playing(t);
      final show = r.hub.current!;
      r.hub.showMini(show);
      await t.pump();
      r.pip.events$.add({'type': 'pip', 'active': true, 'dismissed': false});
      await t.pump();
      r.pip.events$.add({'type': 'pip', 'active': false, 'dismissed': true});
      await t.pump();
      await t.pump();
      expect(c.closed, isTrue);
      expect(r.hub.mini, isNull);
      await t.pumpWidget(const SizedBox());
    });
  });
}
