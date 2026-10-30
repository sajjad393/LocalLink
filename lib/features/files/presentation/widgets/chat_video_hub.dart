import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/services/app_logger.dart';

import 'chat_video_controller.dart';
import 'chat_video_player.dart';
import 'media_frame.dart';
import 'media_playback_coordinator.dart';

/// How the full-screen video page was left.
enum FullscreenExit { back, minimize, close }

/// Bundle 147: one playing chat video, shared by the bubble, the full-screen
/// page, the floating mini player and Android picture-in-picture. It owns the
/// controller until nobody shows it any more (then it closes and gives the
/// decrypted file back via [onRelease]).
class ChatVideoSession extends ChangeNotifier {
  ChatVideoSession({
    required this.controller,
    required this.path,
    required this.coordinator,
    this.onRelease,
    this.aspectHint,
  });

  final ChatVideoController controller;
  final String path;
  final MediaPlaybackCoordinator coordinator;
  final void Function(String path)? onRelease;
  final double? aspectHint;
  ChatVideoHub? hub;

  bool inlineAlive = true;
  bool fullscreenOpen = false;
  bool _mini = false;
  bool closed = false;

  bool get inMini => _mini && !closed;
  bool get playing => !closed && controller.state.playing;

  double get aspect {
    final st = controller.state;
    if (st.initialized && st.aspectRatio.isFinite && st.aspectRatio > 0) {
      return st.aspectRatio;
    }
    return aspectHint ?? 16 / 9;
  }

  Future<void> play() async {
    if (closed) return;
    if (hub?.callActive ?? false) return; // never over a call
    coordinator.claim(this, () => unawaited(_safe(controller.pause)));
    hub?._onPlay(this);
    await controller.play();
  }

  Future<void> pause() async {
    if (closed) return;
    coordinator.release(this);
    await controller.pause();
  }

  Future<void> seekBy(int seconds) async {
    if (closed) return;
    final st = controller.state;
    var target = st.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (st.duration > Duration.zero && target > st.duration) {
      target = st.duration;
    }
    await controller.seekTo(target);
  }

  /// Closes once the bubble, full screen and mini player are all gone.
  void maybeClose() {
    if (closed || inlineAlive || fullscreenOpen || _mini) return;
    close();
  }

  /// Stops for good (mini X, full-screen X, a call, end of video in mini).
  void close() {
    if (closed) return;
    closed = true;
    _mini = false;
    coordinator.release(this);
    notifyListeners(); // bubble resets to its thumbnail
    hub?._onClosed(this);
    unawaited(_safe(controller.close));
    onRelease?.call(path);
  }

  /// Tells the bubble to redraw (e.g. back from full screen, same spot).
  void refresh() => notifyListeners();

  void _setMini(bool value) {
    if (_mini == value) return;
    _mini = value;
    notifyListeners();
  }

  static Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }
}

/// Talks to MainActivity (channel `locallink/pip`). Tests use a fake.
abstract class PipPlatform {
  /// [ready]: pressing Home now should float the video over other apps.
  Future<void> setReady(
      {required bool ready, required double aspect, required bool playing});

  /// `{type: pip, active: bool, dismissed: bool}` and
  /// `{type: action, action: play|pause|back10|fwd10}`.
  Stream<Map<Object?, Object?>> events();
}

class MethodChannelPipPlatform implements PipPlatform {
  static const MethodChannel _method = MethodChannel('locallink/pip');
  static const EventChannel _events = EventChannel('locallink/pip_events');

  @override
  Future<void> setReady(
      {required bool ready, required double aspect, required bool playing}) async {
    final a = MediaFrame.clampPip(aspect);
    try {
      await _method.invokeMethod<void>('setReady', <String, Object>{
        'ready': ready,
        'w': (a * 1000).round(),
        'h': 1000,
        'playing': playing,
      });
    } catch (_) {
      // No PiP on this platform / Android < 8.
    }
  }

  @override
  Stream<Map<Object?, Object?>> events() => _events
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => e as Map<Object?, Object?>);
}

/// Bundle 147: app-wide owner of the mini player and picture-in-picture.
///
/// * One mini player at a time; starting another video closes it.
/// * A bubble that scrolls away (or a chat that closes) while its video plays
///   hands the video to the mini player; it keeps playing.
/// * Calls: the video pauses, the mini player hides, and PiP is never
///   offered, so call screens are untouched.
/// * Leaving the app: with a video playing, Android floats it over other
///   apps (PiP); otherwise it pauses (never plays behind the lock screen).
class ChatVideoHub extends ChangeNotifier with WidgetsBindingObserver {
  ChatVideoHub({PipPlatform? pip}) : pip = pip ?? MethodChannelPipPlatform();

  static final ChatVideoHub instance = ChatVideoHub();

  PipPlatform pip;
  GlobalKey<NavigatorState>? navigatorKey;

  ChatVideoSession? _mini;
  ChatVideoSession? _current;
  bool _callActive = false;
  bool _pipActive = false;
  bool _attached = false;
  bool _lastPlaying = false;
  bool _notifyQueued = false;
  StreamSubscription<Map<Object?, Object?>>? _events;
  String? _lastPipArgs;
  AppLifecycleState _life = AppLifecycleState.resumed;

  /// Corner the mini player sits in (kept while the app runs).
  Alignment miniCorner = Alignment.bottomRight;

  ChatVideoSession? get mini => (_mini?.closed ?? true) ? null : _mini;
  ChatVideoSession? get current => (_current?.closed ?? true) ? null : _current;
  bool get callActive => _callActive;
  bool get pipActive => _pipActive;
  bool get miniVisible => mini != null && !_callActive && !_pipActive;

  /// Called once by the app shell.
  void attach({required GlobalKey<NavigatorState> navigatorKey}) {
    this.navigatorKey = navigatorKey;
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    _events = pip.events().listen(_onPipEvent, onError: (Object _) {});
  }

  @visibleForTesting
  void detachForTest() {
    if (_attached) WidgetsBinding.instance.removeObserver(this);
    _attached = false;
    unawaited(_events?.cancel());
    _events = null;
  }

  @visibleForTesting
  void resetForTest() {
    detachForTest();
    _mini?.close();
    _current?.close();
    _mini = null;
    _current = null;
    _callActive = false;
    _pipActive = false;
    _lastPipArgs = null;
    _lastPlaying = false;
    miniCorner = Alignment.bottomRight;
  }

  void register(ChatVideoSession s) => s.hub = this;

  // ---------------------------------------------------------------- mini

  /// Floats [s] in the mini player (closing any other mini video).
  void showMini(ChatVideoSession s) {
    if (s.closed) return;
    final other = mini;
    if (other != null && !identical(other, s)) {
      other._setMini(false);
      other.close();
    }
    _mini = s;
    s._setMini(true);
    AppLogger.info('VIDEO_MINI', detail: 'show inline=${s.inlineAlive}');
    _syncPip();
    _notify();
  }

  /// Bubble tapped while its video is in the mini player: back to the bubble.
  void returnInline(ChatVideoSession s) {
    if (!identical(_mini, s)) return;
    _mini = null;
    s._setMini(false);
    s.maybeClose();
    _notify();
  }

  /// Mini player X: stop; the bubble shows its thumbnail again.
  void closeMini() {
    final s = mini;
    if (s == null) return;
    AppLogger.info('VIDEO_MINI', detail: 'close');
    _mini = null;
    s.close();
    _notify();
  }

  /// Full screen for [s]. From a bubble pass its [context]; from the mini
  /// player the app navigator is used.
  Future<void> openFullscreen(ChatVideoSession s, {BuildContext? context}) async {
    final nav = context != null
        ? Navigator.maybeOf(context)
        : navigatorKey?.currentState;
    if (nav == null || s.closed) return;
    final wasMini = s.inMini;
    s.fullscreenOpen = true;
    if (wasMini) {
      _mini = null;
      s._setMini(false);
      _notify();
    }
    final exit = await nav.push<FullscreenExit>(PageRouteBuilder<FullscreenExit>(
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
    if (s.closed) return;
    switch (exit ?? FullscreenExit.back) {
      case FullscreenExit.minimize:
        showMini(s);
      case FullscreenExit.close:
        s.close();
      case FullscreenExit.back:
        if (s.playing || wasMini) {
          showMini(s);
        } else if (s.inlineAlive) {
          s.refresh(); // bubble shows it again, same spot
        } else {
          s.close();
        }
    }
  }

  /// Account reset / logout: stop every chat video.
  void stopAll() {
    closeMini();
    current?.close();
  }

  // ---------------------------------------------------------------- calls

  /// A call started/ended. During a call chat video pauses, the mini player
  /// hides and PiP is never offered.
  void setCallActive(bool active) {
    if (_callActive == active) return;
    _callActive = active;
    if (active) {
      final c = current;
      if (c != null && c.playing) unawaited(c.pause());
    }
    _syncPip();
    _notify();
  }

  // ---------------------------------------------------------------- PiP

  void _onPlay(ChatVideoSession s) {
    final old = _current;
    if (!identical(old, s)) {
      old?.controller.removeListener(_onCurrentTick);
      _current = s;
      s.controller.addListener(_onCurrentTick);
      final m = mini;
      if (m != null && !identical(m, s)) {
        m._setMini(false);
        m.close();
      }
    }
    _syncPip(playingOverride: true);
  }

  void _onClosed(ChatVideoSession s) {
    var changed = false;
    if (identical(_mini, s)) {
      _mini = null;
      changed = true;
    }
    if (identical(_current, s)) {
      s.controller.removeListener(_onCurrentTick);
      _current = null;
      changed = true;
    }
    if (changed) {
      _syncPip();
      _notify();
    }
  }

  void _onCurrentTick() {
    final playing = current?.playing ?? false;
    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      _syncPip();
    }
  }

  bool get _pipReady =>
      _attached && !_callActive && (current?.playing ?? false);

  void _syncPip({bool? playingOverride}) {
    final c = current;
    final playing = playingOverride ?? (c?.playing ?? false);
    _lastPlaying = playing;
    final ready = _attached && !_callActive && c != null && playing;
    final aspect = c?.aspect ?? 16 / 9;
    final args = '$ready|${aspect.toStringAsFixed(3)}|$playing';
    if (args == _lastPipArgs || !_attached) return;
    _lastPipArgs = args;
    unawaited(pip.setReady(ready: ready, aspect: aspect, playing: playing));
  }

  void _onPipEvent(Map<Object?, Object?> e) {
    final type = e['type'];
    if (type == 'pip') {
      final active = e['active'] == true;
      _pipActive = active;
      AppLogger.info('VIDEO_PIP',
          detail: 'active=$active dismissed=${e['dismissed']}');
      if (!active && e['dismissed'] == true) {
        // The user swiped the floating window away: stop.
        final c = current;
        if (c != null) {
          if (c.inMini || !c.inlineAlive) {
            closeMini();
            c.close();
          } else {
            unawaited(c.pause());
          }
        }
      }
      _notify();
    } else if (type == 'action') {
      final c = current;
      if (c == null) return;
      switch (e['action']) {
        case 'play':
          unawaited(c.play());
        case 'pause':
          unawaited(c.pause());
        case 'back10':
          unawaited(c.seekBy(-10));
        case 'fwd10':
          unawaited(c.seekBy(10));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _life = state;
    if (state == AppLifecycleState.resumed) return;
    final c = current;
    if (c == null || !c.playing) return;
    if (state == AppLifecycleState.inactive) {
      if (_pipActive) return;
      if (_pipReady) {
        // Give Android a moment to float the video (PiP) before deciding.
        Timer(const Duration(milliseconds: 700), () {
          if (!_pipActive && _life != AppLifecycleState.resumed) {
            unawaited(c.pause());
          }
        });
        return;
      }
    }
    // hidden / paused: the window is not visible (screen off, another app on
    // top, PiP window gone). Never play there.
    unawaited(c.pause());
  }

  /// Hub changes can come from a widget's dispose (tree locked), so
  /// listeners are told right after.
  void _notify() {
    if (_notifyQueued) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      notifyListeners();
    });
  }
}

/// Bundle 147: the floating mini player, drawn above every screen (it sits in
/// `MaterialApp.builder`, outside the Navigator). Same shape as the video.
/// Drag anywhere, it snaps to the nearest corner; fling sideways or X to
/// close; tap opens full screen.
class MiniVideoOverlay extends StatefulWidget {
  const MiniVideoOverlay({super.key, required this.hub});

  final ChatVideoHub hub;

  @override
  State<MiniVideoOverlay> createState() => _MiniVideoOverlayState();
}

class _MiniVideoOverlayState extends State<MiniVideoOverlay> {
  Offset? _drag; // top-left while dragging
  ChatVideoSession? _session;
  Timer? _endTimer;

  @override
  void initState() {
    super.initState();
    widget.hub.addListener(_onHub);
    _bind();
  }

  @override
  void dispose() {
    widget.hub.removeListener(_onHub);
    _session?.controller.removeListener(_onController);
    _endTimer?.cancel();
    super.dispose();
  }

  void _onHub() {
    _bind();
    if (mounted) setState(() {});
  }

  void _bind() {
    final s = widget.hub.mini;
    if (identical(s, _session)) return;
    _session?.controller.removeListener(_onController);
    _endTimer?.cancel();
    _session = s;
    _drag = null;
    s?.controller.addListener(_onController);
  }

  bool _ended(ChatVideoState st) =>
      st.completed ||
      (!st.playing && st.duration > Duration.zero && st.position >= st.duration);

  void _onController() {
    final s = _session;
    if (s == null || s.closed) return;
    final ended = _ended(s.controller.state);
    if (ended && _endTimer == null) {
      // Finished in the mini player: offer replay, then go away.
      _endTimer = Timer(const Duration(seconds: 5), () {
        _endTimer = null;
        final now = _session;
        if (now != null && identical(widget.hub.mini, now) &&
            _ended(now.controller.state)) {
          widget.hub.closeMini();
        }
      });
    } else if (!ended) {
      _endTimer?.cancel();
      _endTimer = null;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null || !widget.hub.miniVisible) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final size = MediaFrame.mini(s.aspect);
    const side = 12.0;
    final top = mq.padding.top + 56 + 8;
    final bottom = math.max(mq.padding.bottom, mq.viewInsets.bottom) + 76;
    final area = mq.size;
    final maxLeft = math.max(side, area.width - size.width - side);
    final maxTop = math.max(top, area.height - size.height - bottom);
    final corner = widget.hub.miniCorner;
    final rest = Offset(
      corner.x < 0 ? side : maxLeft,
      corner.y < 0 ? top : maxTop,
    );
    final pos = _drag ?? rest;
    return Stack(
      children: [
        AnimatedPositioned(
          duration:
              _drag == null ? const Duration(milliseconds: 220) : Duration.zero,
          curve: Curves.easeOutCubic,
          left: pos.dx,
          top: pos.dy,
          width: size.width,
          height: size.height,
          child: GestureDetector(
            key: const Key('mini_video'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(widget.hub.openFullscreen(s)),
            onPanStart: (_) => setState(() => _drag = pos),
            onPanUpdate: (d) => setState(() {
              final p = (_drag ?? pos) + d.delta;
              _drag = Offset(p.dx.clamp(-size.width * .6, area.width - size.width * .4),
                  p.dy.clamp(top, maxTop));
            }),
            onPanEnd: (d) {
              final p = _drag ?? pos;
              final vx = d.velocity.pixelsPerSecond.dx;
              final offLeft = p.dx < -size.width * .35;
              final offRight = p.dx > area.width - size.width * .65;
              if (vx.abs() > 1500 || offLeft || offRight) {
                widget.hub.closeMini();
                setState(() => _drag = null);
                return;
              }
              final cx = p.dx + size.width / 2;
              final cy = p.dy + size.height / 2;
              widget.hub.miniCorner = Alignment(
                cx < area.width / 2 ? -1 : 1,
                cy < (top + maxTop + size.height) / 2 ? -1 : 1,
              );
              setState(() => _drag = null);
            },
            child: _MiniPlayerCard(
              session: s,
              ended: _ended(s.controller.state),
              onClose: widget.hub.closeMini,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniPlayerCard extends StatelessWidget {
  const _MiniPlayerCard({
    required this.session,
    required this.ended,
    required this.onClose,
  });

  final ChatVideoSession session;
  final bool ended;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = session.controller;
    final st = c.state;
    final total = st.duration.inMilliseconds;
    final progress =
        total > 0 ? (st.position.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (st.initialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: st.aspectRatio,
                    child: c.buildView(),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black38, Colors.transparent, Colors.black54],
                    stops: [0, .45, 1],
                  ),
                ),
              ),
              Center(
                child: _RoundBtn(
                  key: Key(ended
                      ? 'mini_video_replay'
                      : (st.playing ? 'mini_video_pause' : 'mini_video_play')),
                  icon: ended
                      ? Icons.replay_rounded
                      : (st.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  size: 36,
                  onTap: () {
                    if (st.playing) {
                      unawaited(session.pause());
                    } else {
                      unawaited(session.play());
                    }
                  },
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: _RoundBtn(
                  key: const Key('mini_video_close'),
                  icon: Icons.close_rounded,
                  size: 26,
                  filled: false,
                  onTap: onClose,
                ),
              ),
              Positioned(
                left: 6,
                bottom: 5,
                child: Text(
                  formatVideoClock(st.position),
                  key: const Key('mini_video_time'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 2.5,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.toDouble(),
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    super.key,
    required this.icon,
    required this.size,
    required this.onTap,
    this.filled = true,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size + 8,
        height: size + 8,
        decoration: filled
            ? const BoxDecoration(color: Colors.black45, shape: BoxShape.circle)
            : null,
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: size * .72),
      ),
    );
  }
}

/// Bundle 147: what Android shows inside the floating PiP window — only the
/// video (controls are the system's back 10 / play-pause / forward 10).
class PipVideoView extends StatelessWidget {
  const PipVideoView({super.key, required this.session});

  final ChatVideoSession session;

  @override
  Widget build(BuildContext context) {
    final c = session.controller;
    return ColoredBox(
      color: Colors.black,
      child: ListenableBuilder(
        listenable: c,
        builder: (_, __) => Center(
          child: AspectRatio(
            aspectRatio: c.state.aspectRatio,
            child: c.buildView(),
          ),
        ),
      ),
    );
  }
}

/// Bundle 147: wraps the whole app (MaterialApp.builder). Adds the mini
/// player on top; while Android shows the PiP window it draws only the video
/// and keeps the app (with all its state) alive offstage.
class ChatVideoShell extends StatelessWidget {
  const ChatVideoShell({super.key, required this.hub, required this.child});

  final ChatVideoHub hub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) {
        final pipSession = hub.pipActive ? hub.current : null;
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(offstage: pipSession != null, child: child),
            if (pipSession != null)
              PipVideoView(session: pipSession)
            else
              MiniVideoOverlay(hub: hub),
          ],
        );
      },
    );
  }
}
