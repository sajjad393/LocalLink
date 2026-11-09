import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';

// Bundle 247 (phase 11, logs only): who stopped the video.
void main() {
  const d = Duration(milliseconds: 52879);
  List<(String, String)> step(VideoPlayLog l, bool playing, int pos,
          {bool completed = false, bool buffering = false}) =>
      l.update(
          initialized: true,
          playing: playing,
          completed: completed,
          hasError: false,
          position: Duration(milliseconds: pos),
          duration: d,
          buffering: buffering);

  test('a stop a few ms before the length is the end', () {
    final l = VideoPlayLog(1);
    step(l, false, 0);
    step(l, true, 0);
    expect(step(l, false, 52852).single.$2, startsWith('reason=end pos_ms=52852'));
  });

  test('user pause, buffering, resume', () {
    final l = VideoPlayLog(1);
    step(l, false, 0);
    expect(step(l, true, 0), isEmpty, reason: 'first play: no resume line');
    l.userPause = true;
    expect(step(l, false, 531).single.$2, startsWith('reason=user pos_ms=531'));
    expect(step(l, true, 531).single.$1, 'VIDEO_PLAY_RESUME');
    expect(step(l, false, 900, buffering: true).single.$2, startsWith('reason=buffering'));
    step(l, true, 900);
    expect(step(l, false, 1000).single.$2, startsWith('reason=paused'), reason: 'flag used once');
  });
}
