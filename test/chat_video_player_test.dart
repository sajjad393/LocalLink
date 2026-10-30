// Bundle 145: inline chat video player (fake controller, no platform).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_player.dart';
import 'package:locallink/features/files/presentation/widgets/media_view_cache.dart';

import 'support/chat_video_fakes.dart';
import 'support/phase5_fakes.dart';

class _SlowFiles extends FakeFilesRepository {
  final downloads = <String>[];
  final pending = Completer<String>();
  @override
  Future<String> downloadForMessage(String messageId, Attachment attachment,
      {String? operationId, void Function(TransferProgress progress)? onProgress}) {
    downloads.add(attachment.id);
    onProgress?.call(TransferProgress(
        operationId: operationId ?? 'op',
        direction: FileTransferDirection.download,
        completed: 4299162, // 4.1 MB
        total: attachment.size,
        status: FileTransferStatus.running));
    return pending.future;
  }

  @override
  Future<void> cancel(String operationId) async {}
}

Attachment video(int size) => Attachment(
    id: 'f-$size', originalName: 'clip.mp4', contentType: 'video/mp4',
    size: size, sha256: 'a' * 64);

void main() {
  setUp(MediaViewCache.instance.resetForTest);

  testWidgets('ready: length + size chips, nothing created until tapped', (t) async {
    final r = Rig();
    await t.pumpWidget(host([r.player('/v/a.mp4')]));
    await t.pump();
    expect(find.text('0:31'), findsOneWidget);
    expect(find.text('6.6 MB'), findsOneWidget);
    expect(r.controllers, isEmpty);
    await t.pumpWidget(const SizedBox());
    expect(r.retained, 0, reason: 'never played: the tile keeps the only hold');
    expect(r.released, isEmpty);
  });

  testWidgets('tap plays inline; pause; controls fade after 3 s and come back', (t) async {
    final r = Rig();
    await t.pumpWidget(host([r.player('/v/a.mp4')]));
    await t.pump();
    await tapKey(t, 'chat_video_play_big');
    final c = r.controllers.single;
    expect(c.state.playing, isTrue);
    expect(find.byKey(const Key('fake_view')), findsOneWidget);
    expect(find.text('0:00 / 0:31'), findsOneWidget);

    AnimatedOpacity controls() =>
        t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(controls().opacity, 1);
    await t.pump(const Duration(seconds: 3, milliseconds: 100));
    expect(controls().opacity, 0, reason: 'faded while playing');
    await t.tap(find.byKey(const Key('chat_video_surface')));
    await t.pump();
    expect(controls().opacity, 1, reason: 'tap shows controls again');

    await tapKey(t, 'chat_video_pause');
    expect(c.state.playing, isFalse);
    await t.pump(const Duration(seconds: 4));
    expect(controls().opacity, 1, reason: 'paused: controls stay');
    await t.pumpWidget(const SizedBox());
    expect(c.closed, isTrue, reason: 'paused + bubble gone: stops (no mini)');
    expect(r.hub.mini, isNull);
    expect(r.retained, 1);
    expect(r.released, ['/v/a.mp4']);
  });

  testWidgets('mute and seek', (t) async {
    final r = Rig();
    await t.pumpWidget(host([r.player('/v/a.mp4')]));
    await t.pump();
    await tapKey(t, 'chat_video_play_big');
    final c = r.controllers.single;
    await tapKey(t, 'chat_video_mute');
    expect(c.muted, isTrue);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    final seek = find.byKey(const Key('chat_video_seek'));
    final box = t.getRect(seek);
    await t.tapAt(Offset(box.left + box.width * .75, box.center.dy));
    await t.pump();
    await t.pump();
    expect(c.seeks, isNotEmpty);
    expect(c.seeks.last.inSeconds, inInclusiveRange(17, 29));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('one at a time: starting B pauses A; a voice note pauses B', (t) async {
    final r = Rig();
    await t.pumpWidget(host([r.player('/v/a.mp4'), r.player('/v/b.mp4')]));
    await t.pump();
    await tapKey(t, 'chat_video_play_big', index: 0);
    final a = r.controllers[0];
    expect(a.state.playing, isTrue);
    await tapKey(t, 'chat_video_play_big'); // the only one left is B
    final b = r.controllers[1];
    expect(b.state.playing, isTrue);
    expect(a.state.playing, isFalse, reason: 'A paused when B started');

    var voicePaused = false;
    final voice = Object();
    r.coordinator.claim(voice, () => voicePaused = true);
    await t.pump();
    expect(b.state.playing, isFalse, reason: 'voice note pauses the video');
    expect(voicePaused, isFalse);
    await tapKey(t, 'chat_video_play', index: 1);
    expect(b.state.playing, isTrue);
    expect(voicePaused, isTrue, reason: 'video pauses the voice note');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('full screen keeps the same controller and position', (t) async {
    final r = Rig();
    await t.pumpWidget(host([r.player('/v/a.mp4')]));
    await t.pump();
    await tapKey(t, 'chat_video_play_big');
    final c = r.controllers.single;
    await tapKey(t, 'chat_video_fullscreen');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChatVideoFullscreen), findsOneWidget);
    await tapKey(t, 'chat_video_fwd10');
    expect(c.state.position, const Duration(seconds: 10));
    await tapKey(t, 'chat_video_fwd10');
    await tapKey(t, 'chat_video_back10');
    expect(c.state.position, const Duration(seconds: 10));
    await tapKey(t, 'chat_video_fs_toggle');
    expect(c.state.playing, isFalse);
    await tapKey(t, 'chat_video_fs_back');
    await t.pumpAndSettle();
    expect(find.byType(ChatVideoFullscreen), findsNothing);
    expect(r.controllers, hasLength(1), reason: 'no new player, no restart');
    expect(c.closed, isFalse);
    expect(find.text('0:10 / 0:31'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    expect(c.closed, isTrue);
  });

  testWidgets('sender while uploading: ring, no play', (t) async {
    final r = Rig();
    await t.pumpWidget(host([r.player('/v/a.mp4', uploading: true)]));
    await t.pump();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byKey(const Key('chat_video_play_big')), findsNothing);
    // The upload ring covers the video: the tap must not start playback.
    await t.tap(find.byKey(const Key('chat_video_surface')), warnIfMissed: false);
    await t.pump();
    expect(r.controllers, isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('bubble destroyed while full screen is open: closes only after full screen', (t) async {
    final r = Rig();
    final show = ValueNotifier<bool>(true);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ValueListenableBuilder<bool>(
                valueListenable: show,
                builder: (_, v, __) => ListView(
                    children: [if (v) r.player('/v/a.mp4')])))));
    await t.pump();
    await tapKey(t, 'chat_video_play_big');
    final c = r.controllers.single;
    await tapKey(t, 'chat_video_fullscreen');
    await t.pumpAndSettle();
    show.value = false; // e.g. rotation re-lays out the chat under full screen
    await t.pump();
    expect(c.closed, isFalse, reason: 'still playing in full screen');
    expect(r.released, isEmpty);
    await tapKey(t, 'chat_video_fs_back');
    await t.pumpAndSettle();
    // Bundle 147: Back while playing keeps it going in the mini player.
    expect(c.closed, isFalse);
    expect(r.hub.mini, isNotNull);
    expect(c.state.playing, isTrue);
    r.hub.closeMini();
    await t.pump();
    expect(c.closed, isTrue);
    expect(r.released, ['/v/a.mp4']);
  });

  testWidgets('tile: video > 10 MB waits for a tap; <= 10 MB auto-downloads with progress', (t) async {
    final files = _SlowFiles();
    await t.pumpWidget(host([
      AttachmentTile(attachment: video(12373197), transfer: files, messageId: 'm1'),
    ]));
    await t.pump();
    await t.pump();
    expect(files.downloads, isEmpty);
    expect(find.byKey(const Key('chat_video_download')), findsOneWidget);
    expect(find.text('11.8 MB'), findsOneWidget);

    await t.pumpWidget(const SizedBox()); // fresh tile (no element reuse)
    final files2 = _SlowFiles();
    await t.pumpWidget(host([
      AttachmentTile(attachment: video(6920601), transfer: files2, messageId: 'm2'),
    ]));
    await t.pump();
    await t.pump();
    expect(files2.downloads, ['f-6920601'], reason: 'auto-download <= 10 MB');
    await t.pump(const Duration(milliseconds: 1)); // tile binds the operation
    await t.pump();
    expect(find.byKey(const Key('chat_video_cancel')), findsOneWidget);
    expect(find.text('4.1 / 6.6 MB'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  test('frame size: real shape, fits 250 x 360, never cropped', () {
    expect(ChatVideoPlayer.frameSize(16 / 9).width, 250);
    expect(ChatVideoPlayer.frameSize(16 / 9).height, closeTo(140.6, .1));
    expect(ChatVideoPlayer.frameSize(9 / 16).height, 360);
    expect(ChatVideoPlayer.frameSize(9 / 16).width, closeTo(202.5, .1),
        reason: 'tall video: narrower bubble, not 250 wide + cropped');
    expect(ChatVideoPlayer.frameSize(null).width, 250);
    expect(formatVideoClock(const Duration(seconds: 3725)), '1:02:05');
  });
}
