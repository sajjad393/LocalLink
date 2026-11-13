import 'dart:async';

import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:flutter/services.dart';

import 'package:flutter/scheduler.dart';

import 'chat_video_controller.dart';
import 'chat_video_hub.dart';
import 'media_frame.dart';
import 'media_playback_coordinator.dart';
import 'media_tile_look.dart';

/// Bundle 145: WhatsApp-like video inside the chat bubble.
///
/// Ready: first-frame thumbnail, play button, length + size chips.
/// Tap: plays in the bubble (seek, time, mute, full screen; controls fade
/// after 3 s). One medium plays at a time ([MediaPlaybackCoordinator]).
/// Full screen reuses the SAME controller, so back returns to the same spot.
///
/// [path] is the decrypted view copy (shared via MediaViewCache). Playing
/// takes an extra hold on it ([onRetainFile]); [onReleaseFile] gives that
/// hold back once nothing shows the video any more (bubble, full screen,
/// mini player, PiP).
///
/// Bundle 147: the playing session lives in [ChatVideoHub], so the video can
/// leave the bubble: scrolled away / chat closed while playing → it keeps
/// playing in the floating mini player.
class ChatVideoPlayer extends StatefulWidget {
  const ChatVideoPlayer({
    super.key,
    required this.path,
    required this.cacheKey,
    required this.sizeBytes,
    this.hintWidth = 0,
    this.hintHeight = 0,
    this.uploading = false,
    this.onRetainFile,
    this.onReleaseFile,
    this.controllerFactory = defaultChatVideoControllerFactory,
    this.infoLoader = VideoInfoCache.load,
    this.coordinator,
    this.hub,
    this.uploadOverlay,
    this.page = false,
    this.active = true,
  });

  final String path;
  final String cacheKey;
  final int sizeBytes;
  final int hintWidth;
  final int hintHeight;
  final bool uploading;
  final VoidCallback? onRetainFile;
  final void Function(String path)? onReleaseFile;
  final ChatVideoControllerFactory controllerFactory;
  final VideoInfoLoader infoLoader;
  final MediaPlaybackCoordinator? coordinator;
  final ChatVideoHub? hub;

  /// Bundle 150: drawn while [uploading] (blue ring with %). Null = default.
  final Widget? uploadOverlay;

  /// Bundle 207 (I): a page of the media viewer: fills the screen, plays by
  /// itself while [active], pauses when swiped away, stays on the last
  /// frame at the end (the viewer stays open), never goes to the mini
  /// player.
  final bool page;

  /// Bundle 207 (I): this page is the one shown now.
  final bool active;

  /// Bundle 147: the video's real shape, scaled to fit 250 x 360 (no crop).
  static Size frameSize(double? aspect) => MediaFrame.fitAspect(aspect);

  @override
  State<ChatVideoPlayer> createState() => _ChatVideoPlayerState();
}

class _ChatVideoPlayerState extends State<ChatVideoPlayer> {
  VideoInfo? _info;
  ChatVideoSession? _session;
  bool _starting = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  ScrollPosition? _scroll;
  bool _scrollCheckQueued = false;

  MediaPlaybackCoordinator get _coordinator =>
      widget.coordinator ?? MediaPlaybackCoordinator.instance;
  ChatVideoHub get _hub => widget.hub ?? ChatVideoHub.instance;

  @override
  void initState() {
    super.initState();
    _info = VideoInfoCache.peek(widget.cacheKey);
    if (_info == null) _loadInfo();
    // Scrolled back to a bubble whose video is in the mini player: show
    // "Playing in mini player" (tap brings it back here).
    final mini = _hub.mini;
    if (!widget.page &&
        mini != null &&
        mini.path == widget.path &&
        !mini.closed) {
      mini.inlineAlive = true;
      _session = mini;
      _bind(mini);
    }
    if (widget.page && widget.active) _autoStart();
  }

  /// Bundle 207 (I): the shown viewer page plays by itself.
  void _autoStart() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active || _session != null || _starting) return;
      AppLogger.info('VIEWER_VIDEO_AUTOPLAY');
      unawaited(_start());
    });
  }

  @override
  void didUpdateWidget(covariant ChatVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.page || oldWidget.active == widget.active) return;
    final s = _session;
    if (!widget.active) {
      // Swiped away: pause.
      if (s != null && !s.closed && s.controller.state.playing) {
        unawaited(_pause());
      }
    } else if (s == null) {
      _autoStart();
    } else if (!s.closed && !s.controller.state.playing &&
        !videoEnded(s.controller.state)) {
      unawaited(_play());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Bundle 207 (I): a viewer page never moves to the mini player.
    final p = widget.page ? null : Scrollable.maybeOf(context)?.position;
    if (!identical(p, _scroll)) {
      _scroll?.removeListener(_onScroll);
      _scroll = p;
      p?.addListener(_onScroll);
    }
  }

  bool _infoRetried = false;
  Timer? _infoRetry;

  Future<void> _loadInfo() async {
    final info = await widget.infoLoader(widget.path, widget.cacheKey);
    if (mounted && info != null) setState(() => _info = info);
    // Bundle 208 (C4): reading failed (file still being written) - one
    // more try a moment later instead of a picture-less bubble.
    if (mounted && info == null && !_infoRetried) {
      _infoRetried = true;
      _infoRetry = Timer(VideoInfoCache.retryGap, () {
        if (mounted && _info == null) unawaited(_loadInfo());
      });
    }
  }

  // Bundle 147: no per-bubble app-lifecycle pause any more. ChatVideoHub
  // decides for the whole app (PiP over other apps, otherwise pause).

  @override
  void dispose() {
    _hideTimer?.cancel();
    _infoRetry?.cancel();
    _scroll?.removeListener(_onScroll);
    final s = _session;
    if (s != null) {
      _unbind(s);
      s.inlineAlive = false;
      if (widget.page) {
        // Bundle 207 (I): leaving the viewer stops its video.
        if (!s.closed && !s.fullscreenOpen && !s.inMini) {
          s.close();
        } else {
          s.maybeClose();
        }
      } else if (!s.closed && !s.fullscreenOpen && !s.inMini && s.playing) {
        // Chat closed / bubble recycled while playing: keep playing in the
        // mini player instead of stopping.
        _hub.showMini(s);
      } else {
        s.maybeClose();
      }
    }
    super.dispose();
  }

  void _bind(ChatVideoSession s) {
    s.controller.addListener(_onController);
    s.addListener(_onSession);
  }

  void _unbind(ChatVideoSession s) {
    s.controller.removeListener(_onController);
    s.removeListener(_onSession);
  }

  /// Hub changed the session: closed (mini/full-screen X) → back to the
  /// thumbnail; moved to/from the mini player → redraw.
  void _onSession() {
    final s = _session;
    if (s == null || !mounted) return;
    if (s.closed) {
      _unbind(s);
      _hideTimer?.cancel();
      setState(() {
        _session = null;
        _controlsVisible = true;
      });
      return;
    }
    if (!s.inMini && !s.fullscreenOpen) {
      _showControls(autoHide: s.playing);
    } else {
      setState(() {});
    }
  }

  void _onScroll() {
    if (_scrollCheckQueued) return;
    final s = _session;
    if (s == null || s.closed || s.inMini || s.fullscreenOpen || !s.playing) {
      return;
    }
    _scrollCheckQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scrollCheckQueued = false;
      _checkVisible();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Scrolled completely out of view while playing → mini player.
  void _checkVisible() {
    final s = _session;
    if (!mounted || s == null || s.closed || s.inMini || s.fullscreenOpen ||
        !s.playing) {
      return;
    }
    final box = context.findRenderObject();
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || viewport is! RenderBox) return;
    if (!box.attached || !box.hasSize || !viewport.attached || !viewport.hasSize) {
      return;
    }
    final mine = box.localToGlobal(Offset.zero) & box.size;
    final view = viewport.localToGlobal(Offset.zero) & viewport.size;
    if (!mine.overlaps(view)) _hub.showMini(s);
  }

  void _onController() {
    final s = _session;
    if (s == null || !mounted || s.closed) return;
    final st = s.controller.state;
    if (st.completed || (!st.playing && _coordinator.isOwner(s) && st.duration > Duration.zero && st.position >= st.duration)) {
      _coordinator.release(s);
      _hideTimer?.cancel();
      _controlsVisible = true;
      if (widget.page) {
        // Bundle 207 (I): the viewer page stays on the last frame with the
        // play (replay) button; the viewer stays open.
      } else if (!s.inMini && !s.fullscreenOpen) {
        // Bundle 174 (3b): finished in the bubble -> back to the preview
        // picture + play button + length (not stuck on the last frame).
        // After this listener returns (the controller is still notifying).
        scheduleMicrotask(() {
          if (!s.closed && !s.inMini && !s.fullscreenOpen &&
              videoEnded(s.controller.state)) {
            s.close();
          }
        });
      }
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
    try {
      await controller.initialize();
    } catch (_) {
      unawaited(_closeQuietly(controller));
      if (mounted) {
        setState(() => _starting = false);
        LinkToast.show(context, "Can't play this video", kind: LinkToastKind.error);
      }
      return;
    }
    if (!mounted) {
      unawaited(_closeQuietly(controller));
      return;
    }
    final hint = widget.hintWidth > 0 && widget.hintHeight > 0
        ? widget.hintWidth / widget.hintHeight
        : null;
    widget.onRetainFile?.call();
    final session = ChatVideoSession(
      controller: controller,
      path: widget.path,
      coordinator: _coordinator,
      onRelease: widget.onReleaseFile,
      aspectHint: _info?.aspectRatio ?? hint,
      durationHintMs: _info?.durationMs ?? 0,
    );
    _hub.register(session);
    _bind(session);
    setState(() {
      _session = session;
      _starting = false;
    });
    await _play();
  }

  static Future<void> _closeQuietly(ChatVideoController c) async {
    try {
      await c.close();
    } catch (_) {}
  }

  Future<void> _play() async {
    final s = _session;
    if (s == null) return;
    // Bundle 207 (I): play at the end = from the start again.
    if (widget.page && videoEnded(s.controller.state)) {
      await s.controller.seekTo(Duration.zero);
    }
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
    final s = _session;
    if (s == null) {
      unawaited(_start());
      return;
    }
    if (s.inMini) {
      // "Playing in mini player": tap brings it back into the bubble.
      _hub.returnInline(s);
      return;
    }
    if (_controlsVisible) {
      if (s.controller.state.playing) {
        _hideTimer?.cancel();
        setState(() => _controlsVisible = false);
      }
    } else {
      _showControls(autoHide: s.controller.state.playing);
    }
  }

  Future<void> _openFullscreen() async {
    final s = _session;
    if (s == null) return;
    _hideTimer?.cancel();
    await _hub.openFullscreen(s, context: context);
  }

  /// Bundle 207 (I, mock 207 page 4 screen 11): the viewer page - the
  /// video fills the screen; tap shows -10 / pause / +10, the seek bar and
  /// sound (above the small pictures strip); they hide after 3 s.
  Widget _pageView(VideoInfo? info, ChatVideoSession? s, ChatVideoState? st,
      bool active) {
    return SizedBox.expand(
      key: const Key('chat_video_page'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (active)
            Center(
              child: AspectRatio(
                aspectRatio: st!.aspectRatio,
                child: s!.controller.buildView(),
              ),
            )
          else
            Center(
              child: AspectRatio(
                aspectRatio: info?.aspectRatio ?? (9 / 16),
                child: _Thumbnail(bytes: info?.thumbnail),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              key: const Key('chat_video_surface'),
              behavior: HitTestBehavior.opaque,
              onTap: _onSurfaceTap,
            ),
          ),
          if (!active)
            Center(
              child: _starting
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white))
                  : Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: InkWell(
                        key: const Key('chat_video_page_play'),
                        customBorder: const CircleBorder(),
                        onTap: _start,
                        child: const SizedBox(
                          width: 64,
                          height: 64,
                          child: Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 40),
                        ),
                      ),
                    ),
            ),
          if (active)
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Padding(
                  // above the small pictures strip of the viewer
                  padding: const EdgeInsets.only(bottom: 76),
                  child: _InlineControls(
                    controller: s!.controller,
                    durationHintMs: s.durationHintMs > 0
                        ? s.durationHintMs
                        : (info?.durationMs ?? 0),
                    onTogglePlay: _togglePlay,
                    onFullscreen: null,
                    onSeekBy: (sec) {
                      unawaited(s.seekBy(sec));
                      _showControls(autoHide: s.controller.state.playing);
                    },
                    onInteract: () =>
                        _showControls(autoHide: s.controller.state.playing),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
    final inMini = s != null && s.inMini;
    final active = s != null && st != null && st.initialized && !inMini;

    if (widget.page) return _pageView(info, s, st, active);

    return Padding(
      padding: EdgeInsets.only(top: MediaTileLook.topOf(context)),
      child: ClipRRect(
        borderRadius: MediaTileLook.radiusOf(context),
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
                Opacity(
                  opacity: inMini ? .45 : 1,
                  child: _Thumbnail(bytes: info?.thumbnail),
                ),
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('chat_video_surface'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _onSurfaceTap,
                ),
              ),
              if (inMini)
                const IgnorePointer(child: _InMiniLabel()),
              if (!active && !inMini && !widget.uploading)
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
                      durationHintMs:
                          s.durationHintMs > 0 ? s.durationHintMs : (info?.durationMs ?? 0),
                      onTogglePlay: _togglePlay,
                      onFullscreen: _openFullscreen,
                      onInteract: () => _showControls(
                          autoHide: s.controller.state.playing),
                    ),
                  ),
                ),
              if (widget.uploading)
                widget.uploadOverlay ?? const _UploadOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bundle 147: shown on the bubble while its video plays in the mini player.
/// (Bundle 207 page view is in the state class above.)
class _InMiniLabel extends StatelessWidget {
  const _InMiniLabel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_in_picture_alt_rounded,
              color: Colors.white, size: 30),
          SizedBox(height: 6),
          Text(
            'Playing in mini player',
            key: Key('chat_video_in_mini'),
            style: TextStyle(
                color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
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
      // Bundle 164 (4.4): a broken picture falls back to the dark box.
      return Image.memory(b,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const _Thumbnail());
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
          top: MediaTileLook.freeCornerOf(context) ? 8 : null,
          bottom: MediaTileLook.freeCornerOf(context) ? null : 8,
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
    this.durationHintMs = 0,
    this.onSeekBy,
  });

  final ChatVideoController controller;
  final int durationHintMs;
  final VoidCallback onTogglePlay;

  /// Null = no full-screen button (Bundle 207: the viewer page).
  final VoidCallback? onFullscreen;
  final VoidCallback onInteract;

  /// Bundle 207 (I): -10 / +10 buttons beside the middle one.
  final void Function(int seconds)? onSeekBy;

  Widget _skip(String key, String label, int sec) => Material(
        color: Colors.black38,
        shape: const CircleBorder(),
        child: InkWell(
          key: Key(key),
          customBorder: const CircleBorder(),
          onTap: () => onSeekBy!(sec),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final st = controller.state;
        final playing = st.playing;
        final clock = VideoClock.of(st, durationHintMs);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (onSeekBy != null)
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _skip('chat_video_back10', '-10', -10),
                    const SizedBox(width: 92),
                    _skip('chat_video_fwd10', '+10', 10),
                  ],
                ),
              ),
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
                          durationHintMs: durationHintMs,
                        ),
                      ),
                      Row(
                        children: [
                          // Bundle 174 (4.3): only the middle pause/play
                          // button; the small one here is gone.
                          const SizedBox(width: 8),
                          Text(
                            '${formatVideoClock(clock.position)} / ${formatVideoClock(clock.duration)}',
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
                          if (onFullscreen != null)
                            _IconBtn(
                              key: const Key('chat_video_fullscreen'),
                              icon: Icons.fullscreen_rounded,
                              onTap: onFullscreen!,
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
    this.durationHintMs = 0,
  });

  final ChatVideoController controller;
  final double thumbRadius;
  final VoidCallback? onInteract;
  final int durationHintMs;

  @override
  State<ChatVideoSeekBar> createState() => _ChatVideoSeekBarState();
}

class _ChatVideoSeekBarState extends State<ChatVideoSeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final st = widget.controller.state;
    final clock = VideoClock.of(st, widget.durationHintMs);
    final total = clock.duration.inMilliseconds;
    final live = clock.progress;
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
/// play/pause, back/forward 10 s. Bundle 147: minimize (mini player) and X
/// (stop); Back goes to the mini player while playing. Rotates with the phone (the app has no
/// orientation lock); system bars hidden while open.
class ChatVideoFullscreen extends StatefulWidget {
  const ChatVideoFullscreen({
    super.key,
    required this.controller,
    required this.onPlay,
    required this.onPause,
    this.durationHintMs = 0,
  });

  final ChatVideoController controller;
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final int durationHintMs;

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
          final clock = VideoClock.of(st, widget.durationHintMs);
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
                        Row(
                          children: [
                            IconButton(
                              key: const Key('chat_video_fs_back'),
                              tooltip: 'Back',
                              icon: const Icon(Icons.arrow_back_rounded,
                                  color: Colors.white),
                              onPressed: () => Navigator.of(context)
                                  .maybePop(FullscreenExit.back),
                            ),
                            const Spacer(),
                            // Bundle 147: keep watching in the mini player.
                            IconButton(
                              key: const Key('chat_video_fs_minimize'),
                              tooltip: 'Mini player',
                              icon: const Icon(
                                  Icons.picture_in_picture_alt_rounded,
                                  color: Colors.white),
                              onPressed: () => Navigator.of(context)
                                  .maybePop(FullscreenExit.minimize),
                            ),
                            IconButton(
                              key: const Key('chat_video_fs_close'),
                              tooltip: 'Close video',
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white),
                              onPressed: () => Navigator.of(context)
                                  .maybePop(FullscreenExit.close),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 28,
                                child: ChatVideoSeekBar(
                                    controller: c,
                                    onInteract: _interact,
                                    durationHintMs: widget.durationHintMs),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(formatVideoClock(clock.position),
                                        key: const Key('chat_video_fs_pos'),
                                        style: const TextStyle(
                                            color: Color(0xFFDDDDDD),
                                            fontSize: 12)),
                                    Text(formatVideoClock(clock.duration),
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
