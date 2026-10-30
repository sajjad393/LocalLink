import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

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
      : _c = VideoPlayerController.file(File(path)) {
    _c.addListener(notifyListeners);
  }

  final VideoPlayerController _c;
  bool _muted = false;
  bool _closed = false;

  @override
  ChatVideoState get state {
    final v = _c.value;
    final ratio = v.aspectRatio;
    return ChatVideoState(
      initialized: v.isInitialized,
      playing: v.isPlaying,
      completed: v.isCompleted,
      hasError: v.hasError,
      position: v.position,
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
    await _c.play();
  }

  @override
  Future<void> pause() => _c.pause();

  @override
  Future<void> seekTo(Duration position) => _c.seekTo(position);

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
    _c.removeListener(notifyListeners);
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
