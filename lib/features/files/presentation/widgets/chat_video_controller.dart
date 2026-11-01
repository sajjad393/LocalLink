import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:video_player/video_player.dart';

/// Bundle 193 (logs only): one line when a video is ready, one when it stops
/// (end / pause / error) — never per frame. Shows if the player sees the full
/// length but stops early (e.g. after 1 s).
///   VIDEO_PLAY_READY duration_ms=<n> size=<bytes> w=<n> h=<n>
///   VIDEO_PLAY_STOP reason=end|paused|error pos_ms=<n> duration_ms=<n> size=<bytes>
///   VIDEO_PLAY_ERROR pos_ms=<n> duration_ms=<n> size=<bytes> error=<text>
class VideoPlayLog {
  VideoPlayLog(this.size);

  final int size;
  bool _ready = false;
  bool _wasPlaying = false;
  bool _errorLogged = false;

  /// Returns (event, detail) pairs to log for this state change.
  List<(String, String)> update({
    required bool initialized,
    required bool playing,
    required bool completed,
    required bool hasError,
    required Duration position,
    required Duration duration,
    double width = 0,
    double height = 0,
    String? error,
  }) {
    final out = <(String, String)>[];
    final pos = position.inMilliseconds;
    final dur = duration.inMilliseconds;
    if (initialized && !_ready) {
      _ready = true;
      out.add(('VIDEO_PLAY_READY',
          'duration_ms=$dur size=$size w=${width.round()} h=${height.round()}'));
    }
    if (hasError && !_errorLogged) {
      _errorLogged = true;
      final text = (error ?? '-').replaceAll(RegExp(r'\s+'), ' ');
      out.add(('VIDEO_PLAY_ERROR',
          'pos_ms=$pos duration_ms=$dur size=$size '
              'error=${text.length > 120 ? text.substring(0, 120) : text}'));
    }
    if (_wasPlaying && !playing) {
      final reason = hasError
          ? 'error'
          : (completed || (dur > 0 && pos >= dur) ? 'end' : 'paused');
      out.add(('VIDEO_PLAY_STOP',
          'reason=$reason pos_ms=$pos duration_ms=$dur size=$size'));
    }
    _wasPlaying = playing;
    return out;
  }
}

/// Bundle 145: snapshot of an inline chat video.
@immutable
class ChatVideoState {
  final bool initialized;
  final bool playing;
  final bool completed;
  final bool hasError;
  final Duration position;
  final Duration duration;
  final double aspectRatio;

  const ChatVideoState({
    this.initialized = false,
    this.playing = false,
    this.completed = false,
    this.hasError = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.aspectRatio = 16 / 9,
  });
}

/// Bundle 174 (3b): the video reached its end (finished, not just paused).
bool videoEnded(ChatVideoState st) =>
    st.completed ||
    (!st.playing &&
        st.duration > Duration.zero &&
        st.position >= st.duration);

/// Bundle 174 (4): the time and length to SHOW. Some phones report a length
/// of 0 (or a tiny one) for a playing file, which showed "0:00 / 0:00" with a
/// full bar. Then the length read from the file itself is used, and the time
/// never goes past the length.
@immutable
class VideoClock {
  final Duration position;
  final Duration duration;

  const VideoClock(this.position, this.duration);

  factory VideoClock.of(ChatVideoState st, int durationHintMs) {
    var d = st.duration;
    final hint = durationHintMs;
    if (hint > 0 &&
        (d.inMilliseconds <= 0 || d.inMilliseconds < hint ~/ 2)) {
      d = Duration(milliseconds: hint);
    }
    if (d < Duration.zero) d = Duration.zero;
    var p = st.position;
    if (p < Duration.zero) p = Duration.zero;
    if (d > Duration.zero && p > d) p = d;
    return VideoClock(p, d);
  }

  /// 0..1 for the bar (0 while the length is unknown).
  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
  }
}

/// The small surface the chat player needs. The real one wraps
/// `video_player` (ExoPlayer on Android); tests use a fake.
abstract class ChatVideoController implements Listenable {
  ChatVideoState get state;
  bool get muted;
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setMuted(bool muted);
  Widget buildView();
  Future<void> close();
}

typedef ChatVideoControllerFactory = ChatVideoController Function(String path);

ChatVideoController defaultChatVideoControllerFactory(String path) =>
    VideoPlayerChatController(path);

class VideoPlayerChatController extends ChangeNotifier
    implements ChatVideoController {
  VideoPlayerChatController(String path)
      : _c = VideoPlayerController.file(File(path)),
        _playLog = VideoPlayLog(_sizeOf(path)) {
    _c.addListener(notifyListeners);
    _c.addListener(_logPlay);
  }

  final VideoPlayerController _c;
  final VideoPlayLog _playLog;

  static int _sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return -1;
    }
  }

  // Bundle 193 (logs only): ready / stop lines; never changes playback.
  void _logPlay() {
    try {
      final v = _c.value;
      final lines = _playLog.update(
        initialized: v.isInitialized,
        playing: v.isPlaying,
        completed: v.isCompleted,
        hasError: v.hasError,
        position: v.position,
        duration: v.duration,
        width: v.size.width,
        height: v.size.height,
        error: v.errorDescription,
      );
      for (final (event, detail) in lines) {
        if (event == 'VIDEO_PLAY_ERROR') {
          AppLogger.warning(event, detail: detail);
        } else {
          AppLogger.info(event, detail: detail);
        }
      }
    } catch (_) {}
  }
  bool _muted = false;
  bool _closed = false;
  // Bundle 174: the real time, asked 4x a second while playing (some phones
  // never moved the time / bar in the bubble).
  Timer? _poll;
  Duration? _livePos;

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (_closed || !_c.value.isPlaying) {
        _stopPoll();
        return;
      }
      try {
        final p = await _c.position;
        if (_closed || p == null || !_c.value.isPlaying) return;
        _livePos = p;
        notifyListeners();
      } catch (_) {}
    });
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
    _livePos = null;
  }

  @override
  ChatVideoState get state {
    final v = _c.value;
    final ratio = v.aspectRatio;
    final live = _livePos;
    return ChatVideoState(
      initialized: v.isInitialized,
      playing: v.isPlaying,
      completed: v.isCompleted,
      hasError: v.hasError,
      position: v.isPlaying && live != null && live > v.position
          ? live
          : v.position,
      duration: v.duration,
      aspectRatio: ratio.isFinite && ratio > 0 ? ratio : 16 / 9,
    );
  }

  @override
  bool get muted => _muted;

  @override
  Future<void> initialize() => _c.initialize();

  @override
  Future<void> play() async {
    // Replay from the start once finished (WhatsApp behaviour).
    final v = _c.value;
    if (v.isCompleted || (v.duration > Duration.zero && v.position >= v.duration)) {
      await _c.seekTo(Duration.zero);
    }
    _livePos = null;
    await _c.play();
    _startPoll();
  }

  @override
  Future<void> pause() {
    _stopPoll();
    return _c.pause();
  }

  @override
  Future<void> seekTo(Duration position) {
    _livePos = null;
    return _c.seekTo(position);
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    await _c.setVolume(muted ? 0 : 1);
    notifyListeners();
  }

  @override
  Widget buildView() => VideoPlayer(_c);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stopPoll();
    _c.removeListener(notifyListeners);
    _c.removeListener(_logPlay);
    await _c.dispose();
    super.dispose();
  }
}

/// Bundle 145: first frame + length + natural size, read natively
/// (MediaMetadataRetriever) from the temporary decrypted view copy.
@immutable
class VideoInfo {
  final Uint8List? thumbnail;
  final int durationMs;
  final int width;
  final int height;

  const VideoInfo({
    this.thumbnail,
    this.durationMs = 0,
    this.width = 0,
    this.height = 0,
  });

  double? get aspectRatio =>
      width > 0 && height > 0 ? width / height : null;
}

typedef VideoInfoLoader = Future<VideoInfo?> Function(String path, String cacheKey);

/// In-memory cache (per app run) so scrolling never redoes the work. Only
/// small JPEG thumbnails (<=480 px), capped at 60 entries.
class VideoInfoCache {
  VideoInfoCache._();

  static const MethodChannel _channel = MethodChannel('locallink/voice_notes');
  static const int _max = 60;
  static final Map<String, VideoInfo> _cache = <String, VideoInfo>{};
  static final Map<String, Future<VideoInfo?>> _inFlight =
      <String, Future<VideoInfo?>>{};

  static VideoInfo? peek(String cacheKey) => _cache[cacheKey];

  @visibleForTesting
  static void resetForTest() {
    _cache.clear();
    _inFlight.clear();
  }

  /// Bundle 185 (B1): low memory while hidden. Returns how many were dropped.
  static int clear() {
    final n = _cache.length;
    _cache.clear();
    return n;
  }

  static Future<VideoInfo?> load(String path, String cacheKey) {
    final hit = _cache[cacheKey];
    if (hit != null) return Future<VideoInfo?>.value(hit);
    // Bundle 150: block body. `() => _inFlight.remove(k)` returned the very
    // future being completed, so it waited on itself forever (blank video
    // bubble until a refresh).
    return _inFlight[cacheKey] ??= _read(path, cacheKey).whenComplete(() {
      _inFlight.remove(cacheKey);
    });
  }

  static Future<VideoInfo?> _read(String path, String cacheKey) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
          'video_info', <String, dynamic>{'path': path, 'max_px': 480});
      if (raw == null) return null;
      final thumb = raw['thumbnail'];
      final info = VideoInfo(
        thumbnail: thumb is Uint8List && thumb.isNotEmpty ? thumb : null,
        durationMs: (raw['duration_ms'] as num?)?.toInt() ?? 0,
        width: (raw['display_width'] as num?)?.toInt() ?? 0,
        height: (raw['display_height'] as num?)?.toInt() ?? 0,
      );
      _cache.remove(cacheKey);
      _cache[cacheKey] = info;
      while (_cache.length > _max) {
        _cache.remove(_cache.keys.first);
      }
      return info;
    } catch (_) {
      return null;
    }
  }
}
