import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_video_controller.dart';
import 'media_playback_coordinator.dart';

/// Bundle 145: WhatsApp-like video inside the chat bubble.
///
/// Ready: first-frame thumbnail, play button, length + size chips.
/// Tap: plays in the bubble (seek, time, mute, full screen; controls fade
/// after 3 s). One medium plays at a time ([MediaPlaybackCoordinator]).
/// Full screen reuses the SAME controller, so back returns to the same spot.
///
/// [path] is the temporary decrypted view copy. [onReleaseFile] fires once
/// nothing needs it any more (bubble gone AND full screen closed).
class ChatVideoPlayer extends StatefulWidget {
  const ChatVideoPlayer({
    super.key,
    required this.path,
    required this.cacheKey,
    required this.sizeBytes,
    this.hintWidth = 0,
    this.hintHeight = 0,
    this.uploading = false,
    this.onReleaseFile,
    this.controllerFactory = defaultChatVideoControllerFactory,
    this.infoLoader = VideoInfoCache.load,
    this.coordinator,
  });

  final String path;
  final String cacheKey;
  final int sizeBytes;
  final int hintWidth;
  final int hintHeight;
  final bool uploading;
  final void Function(String path)? onReleaseFile;
  final ChatVideoControllerFactory controllerFactory;
  final VideoInfoLoader infoLoader;
  final MediaPlaybackCoordinator? coordinator;

  static const double maxWidth = 250;

  /// Natural aspect, max 250 wide, height clamped like photos.
  static Size frameSize(double? aspect) {
    final a = (aspect != null && aspect.isFinite && aspect > 0) ? aspect : 16 / 9;
    return Size(maxWidth, (maxWidth / a).clamp(140.0, 360.0));
  }

  @override
  State<ChatVideoPlayer> createState() => _ChatVideoPlayerState();
}

/// Owns the controller for as long as the bubble OR the full-screen page
/// needs it, and is the playback owner in the coordinator.
class _VideoSession {
  _VideoSession(this.controller, this.path, this.coordinator, this.onRelease);

  final ChatVideoController controller;
  final String path;
  final MediaPlaybackCoordinator coordinator;
  final void Function(String path)? onRelease;
  bool inlineAlive = true;
  bool fullscreenOpen = false;
  bool closed = false;

  Future<void> play() async {
    coordinator.claim(this, () => unawaited(_safe(controller.pause)));
    await controller.play();
  }

  Future<void> pause() async {
    coordinator.release(this);
    await controller.pause();
  }

  void maybeClose() {
    if (closed || inlineAlive || fullscreenOpen) return;
    closed = true;
    coordinator.release(this);
    unawaited(_safe(controller.close));
    onRelease?.call(path);
  }

  static Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }
}

class _ChatVideoPlayerState extends State<ChatVideoPlayer>
    with WidgetsBindingObserver {
  VideoInfo? _info;
  _VideoSession? _session;
  bool _starting = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  MediaPlaybackCoordinator get _coordinator =>
      widget.coordinator ?? MediaPlaybackCoordinator.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _info = VideoInfoCache.peek(widget.cacheKey);
    if (_info == null) _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await widget.infoLoader(widget.path, widget.cacheKey);
    if (mounted && info != null) setState(() => _info = info);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never keep playing behind the lock screen / another app.
    if (state != AppLifecycleState.resumed) {
      final s = _session;
      if (s != null && !s.closed && s.controller.state.playing) {
        unawaited(s.pause());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    final s = _session;
    if (s == null) {
      widget.onReleaseFile?.call(widget.path);
    } else {
      s.controller.removeListener(_onController);
      s.inlineAlive = false;
      // Closing stops playback; with full screen open it keeps playing there
      // and the full-screen exit closes it.
      s.maybeClose();
    }
    super.dispose();
  }

  void _onController() {
    final s = _session;
    if (s == null || !mounted) return;
    final st = s.controller.state;
    if (st.completed || (!st.playing && _coordinator.isOwner(s) && st.duration > Duration.zero && st.position >= st.duration)) {
      _coordinator.release(s);
      _hideTimer?.cancel();
      _controlsVisible = true;
    } else if (!st.playing && !_controlsVisible) {
      // Paused from elsewhere (another video / a voice note): show controls.
      _hideTimer?.cancel();
      _controlsVisible = true;
    }
    setState(() {});
  }

  Future<void> _start() async {
    if (_starting || widget.uploading) return;
    setState(() => _starting = true);
    final controller = widget.controllerFactory(widget.path);
    final session = _VideoSession(
        controller, widget.path, _coordinator, widget.onReleaseFile);
    try {
      await controller.initialize();
    } catch (_) {
      unawaited(_VideoSession._safe(controller.close));
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text("Can't play this video")));
      }
      return;
    }
    if (!mounted) {
      unawaited(_VideoSession._safe(controller.close));
      return;
    }
    controller.addListener(_onController);
    setState(() {
      _session = session;
      _starting = false;
    });
    await _play();
  }

  Future<void> _play() async {
    final s = _session;
    if (s == null) return;
    await s.play();
    _showControls(autoHide: true);
  }

  Future<void> _pause() async {
    final s = _session;
    if (s == null) return;
    await s.pause();
    _showControls(autoHide: false);
  }

  void _togglePlay() {
    final s = _session;
    if (s == null) return;
    if (s.controller.state.playing) {
      unawaited(_pause());
    } else {
      unawaited(_play());
    }
  }

  void _showControls({required bool autoHide}) {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    if (autoHide) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        final s = _session;
        if (mounted && s != null && s.controller.state.playing) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  void _onSurfaceTap() {
    if (_session == null) {
      unawaited(_start());
      return;
    }
    if (_controlsVisible) {
      final playing = _session!.controller.state.playing;
      if (playing) {
        _hideTimer?.cancel();
        setState(() => _controlsVisible = false);
      }
    } else {
      _showControls(autoHide: _session!.controller.state.playing);
    }
  }

  Future<void> _openFullscreen() async {
    final s = _session;
    if (s == null) return;
    _hideTimer?.cancel();
    s.fullscreenOpen = true;
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => ChatVideoFullscreen(
        controller: s.controller,
        onPlay: s.play,
        onPause: s.pause,
      ),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
    s.fullscreenOpen = false;
    if (!mounted || !s.inlineAlive) {
      s.maybeClose();
      return;
    }
    _showControls(autoHide: s.controller.state.playing);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final hint = widget.hintWidth > 0 && widget.hintHeight > 0
        ? widget.hintWidth / widget.hintHeight
        : null;
    final size = ChatVideoPlayer.frameSize(info?.aspectRatio ?? hint);
    final s = _session;
    final st = s?.controller.state;
    final active = s != null && st != null && st.initialized;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (active)
                Center(
                  child: AspectRatio(
                    aspectRatio: st.aspectRatio,
                    child: s.controller.buildView(),
                  ),
                )
              else
                _Thumbnail(bytes: info?.thumbnail),
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('chat_video_surface'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _onSurfaceTap,
                ),
              ),
              if (!active && !widget.uploading)
                _ReadyOverlay(
                  durationMs: info?.durationMs ?? 0,
                  sizeBytes: widget.sizeBytes,
                  starting: _starting,
                  onPlay: _start,
                ),
              if (active)
                AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: _InlineControls(
                      controller: s.controller,
                      onTogglePlay: _togglePlay,
                      onFullscreen: _openFullscreen,
                      onInteract: () => _showControls(
                          autoHide: s.controller.state.playing),
                    ),
                  ),
                ),
              if (widget.uploading) const _UploadOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.bytes});
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final b = bytes;
    if (b != null) {
      return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return ColoredBox(
      color: const Color(0xFF2A2F3A),
      child: Center(
        child: Icon(Icons.videocam_rounded,
            color: Colors.white.withValues(alpha: .35), size: 40),
      ),
    );
  }
}

/// Ready state (mock 1): play button + length chip + size chip.
class _ReadyOverlay extends StatelessWidget {
  const _ReadyOverlay({
    required this.durationMs,
    required this.sizeBytes,
    required this.starting,
    required this.onPlay,
  });

  final int durationMs;
  final int sizeBytes;
  final bool starting;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: starting
              ? const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: Colors.white),
                )
              : Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const Key('chat_video_play_big'),
                    customBorder: const CircleBorder(),
                    onTap: onPlay,
                    child: const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 36),
                    ),
                  ),
                ),
        ),
        if (durationMs > 0)
          Positioned(
            left: 8,
            bottom: 8,
            child: VideoChip(
              key: const Key('chat_video_length_chip'),
              icon: Icons.videocam_rounded,
              label: formatVideoClock(Duration(milliseconds: durationMs)),
            ),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: VideoChip(
            key: const Key('chat_video_size_chip'),
            label: formatVideoBytes(sizeBytes),
          ),
        ),
      ],
    );
  }
}

class VideoChip extends StatelessWidget {
  const VideoChip({super.key, required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Playing in the bubble (mock 2).
class _InlineControls extends StatelessWidget {
  const _InlineControls({
    required this.controller,
    required this.onTogglePlay,
    required this.onFullscreen,
    required this.onInteract,
  });

  final ChatVideoController controller;
  final VoidCallback onTogglePlay;
  final VoidCallback onFullscreen;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final st = controller.state;
        final playing = st.playing;
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: InkWell(
                  key: Key(playing ? 'chat_video_pause' : 'chat_video_play'),
                  customBorder: const CircleBorder(),
                  onTap: onTogglePlay,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 22,
                        child: ChatVideoSeekBar(
                          controller: controller,
                          thumbRadius: 6,
                          onInteract: onInteract,
                        ),
                      ),
                      Row(
                        children: [
                          _IconBtn(
                            icon: playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onTap: onTogglePlay,
                          ),
                          Text(
                            '${formatVideoClock(st.position)} / ${formatVideoClock(st.duration)}',
                            key: const Key('chat_video_time'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                          const Spacer(),
                          _IconBtn(
                            key: const Key('chat_video_mute'),
                            icon: controller.muted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            onTap: () {
                              unawaited(controller.setMuted(!controller.muted));
                              onInteract();
                            },
                          ),
                          _IconBtn(
                            key: const Key('chat_video_fullscreen'),
                            icon: Icons.fullscreen_rounded,
                            onTap: onFullscreen,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({super.key, required this.icon, required this.onTap, this.size = 20});
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: size + 4,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }
}

/// Draggable seek bar: drag shows the target, release seeks.
class ChatVideoSeekBar extends StatefulWidget {
  const ChatVideoSeekBar({
    super.key,
    required this.controller,
    this.thumbRadius = 7,
    this.onInteract,
  });

  final ChatVideoController controller;
  final double thumbRadius;
  final VoidCallback? onInteract;

  @override
  State<ChatVideoSeekBar> createState() => _ChatVideoSeekBarState();
}

class _ChatVideoSeekBarState extends State<ChatVideoSeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final st = widget.controller.state;
    final total = st.duration.inMilliseconds;
    final live = total > 0
        ? (st.position.inMilliseconds / total).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final r = widget.thumbRadius;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: r),
        overlayShape: RoundSliderOverlayShape(overlayRadius: r * 2),
        activeTrackColor: Colors.white,
        inactiveTrackColor: Colors.white30,
        thumbColor: Colors.white,
        overlayColor: Colors.white24,
      ),
      child: Slider(
        key: const Key('chat_video_seek'),
        value: _drag ?? live,
        onChangeStart: total > 0
            ? (v) {
                setState(() => _drag = v);
                widget.onInteract?.call();
              }
            : null,
        onChanged: total > 0 ? (v) => setState(() => _drag = v) : null,
        onChangeEnd: total > 0
            ? (v) async {
                await widget.controller
                    .seekTo(Duration(milliseconds: (v * total).round()));
                if (mounted) setState(() => _drag = null);
                widget.onInteract?.call();
              }
            : null,
      ),
    );
  }
}

class _UploadOverlay extends StatelessWidget {
  const _UploadOverlay();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black38,
      child: Center(
        child: SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: null,
                strokeWidth: 4,
                color: Colors.white,
                backgroundColor: Colors.white30,
              ),
              Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full screen (mock 4): same controller, black background, seek,
/// play/pause, back/forward 10 s. Rotates with the phone (the app has no
/// orientation lock); system bars hidden while open.
class ChatVideoFullscreen extends StatefulWidget {
  const ChatVideoFullscreen({
    super.key,
    required this.controller,
    required this.onPlay,
    required this.onPause,
  });

  final ChatVideoController controller;
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;

  @override
  State<ChatVideoFullscreen> createState() => _ChatVideoFullscreenState();
}

class _ChatVideoFullscreenState extends State<ChatVideoFullscreen> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
        .catchError((Object _) {}));
    if (widget.controller.state.playing) _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values)
        .catchError((Object _) {}));
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.controller.state.playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _interact() {
    setState(() => _controlsVisible = true);
    if (widget.controller.state.playing) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  Future<void> _togglePlay() async {
    if (widget.controller.state.playing) {
      await widget.onPause();
      _hideTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    } else {
      await widget.onPlay();
      if (mounted) _interact();
    }
  }

  Future<void> _skip(int seconds) async {
    final st = widget.controller.state;
    var target = st.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (st.duration > Duration.zero && target > st.duration) target = st.duration;
    await widget.controller.seekTo(target);
    _interact();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final st = c.state;
          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: st.aspectRatio,
                  child: c.buildView(),
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_controlsVisible && st.playing) {
                      _hideTimer?.cancel();
                      setState(() => _controlsVisible = false);
                    } else {
                      _interact();
                    }
                  },
                ),
              ),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: SafeArea(
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            key: const Key('chat_video_fs_back'),
                            tooltip: 'Back',
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: Colors.white),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 28,
                                child: ChatVideoSeekBar(
                                    controller: c, onInteract: _interact),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(formatVideoClock(st.position),
                                        key: const Key('chat_video_fs_pos'),
                                        style: const TextStyle(
                                            color: Color(0xFFDDDDDD),
                                            fontSize: 12)),
                                    Text(formatVideoClock(st.duration),
                                        style: const TextStyle(
                                            color: Color(0xFFDDDDDD),
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _IconBtn(
                                    key: const Key('chat_video_back10'),
                                    icon: Icons.replay_10_rounded,
                                    size: 30,
                                    onTap: () => _skip(-10),
                                  ),
                                  const SizedBox(width: 28),
                                  Material(
                                    color: Colors.white.withValues(alpha: .16),
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      key: const Key('chat_video_fs_toggle'),
                                      customBorder: const CircleBorder(),
                                      onTap: _togglePlay,
                                      child: SizedBox(
                                        width: 60,
                                        height: 60,
                                        child: Icon(
                                          st.playing
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 38,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 28),
                                  _IconBtn(
                                    key: const Key('chat_video_fwd10'),
                                    icon: Icons.forward_10_rounded,
                                    size: 30,
                                    onTap: () => _skip(10),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String formatVideoClock(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

String formatVideoBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
