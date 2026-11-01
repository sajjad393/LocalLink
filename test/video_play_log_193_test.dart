import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';

void main() {
  const d = Duration(milliseconds: 30000);

  test('ready once, stop on early end, paused vs end', () {
    final log = VideoPlayLog(13000000);
    var out = log.update(
        initialized: true,
        playing: false,
        completed: false,
        hasError: false,
        position: Duration.zero,
        duration: d,
        width: 720,
        height: 1280);
    expect(out.single.$1, 'VIDEO_PLAY_READY');
    expect(out.single.$2, 'duration_ms=30000 size=13000000 w=720 h=1280');
    out = log.update(
        initialized: true,
        playing: true,
        completed: false,
        hasError: false,
        position: Duration.zero,
        duration: d);
    expect(out, isEmpty);
    out = log.update(
        initialized: true,
        playing: false,
        completed: false,
        hasError: false,
        position: const Duration(milliseconds: 800),
        duration: d);
    expect(out.single.$1, 'VIDEO_PLAY_STOP');
    expect(out.single.$2,
        'reason=paused pos_ms=800 duration_ms=30000 size=13000000');
    log.update(
        initialized: true,
        playing: true,
        completed: false,
        hasError: false,
        position: Duration.zero,
        duration: d);
    out = log.update(
        initialized: true,
        playing: false,
        completed: true,
        hasError: false,
        position: d,
        duration: d);
    expect(out.single.$2, startsWith('reason=end pos_ms=30000'));
  });

  test('error logged once with short text', () {
    final log = VideoPlayLog(5);
    log.update(
        initialized: true,
        playing: true,
        completed: false,
        hasError: false,
        position: Duration.zero,
        duration: d);
    final out = log.update(
        initialized: true,
        playing: false,
        completed: false,
        hasError: true,
        position: const Duration(milliseconds: 900),
        duration: d,
        error: 'Source error\n  ExoPlaybackException');
    expect(out.map((e) => e.$1),
        ['VIDEO_PLAY_ERROR', 'VIDEO_PLAY_STOP']);
    expect(out.first.$2, contains('error=Source error ExoPlaybackException'));
    expect(out.last.$2, startsWith('reason=error pos_ms=900'));
    expect(
        log.update(
            initialized: true,
            playing: false,
            completed: false,
            hasError: true,
            position: const Duration(milliseconds: 900),
            duration: d),
        isEmpty);
  });
}
