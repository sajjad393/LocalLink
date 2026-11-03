import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:locallink/features/messaging/data/chat_text_scale.dart';

/// Bundle 199: what one pointer event meant for the pinch.
enum PinchKind { none, start, change, end, reset }

class PinchUpdate {
  final PinchKind kind;

  /// Wanted size (not snapped yet) for [PinchKind.change].
  final double? scale;

  const PinchUpdate(this.kind, [this.scale]);

  static const PinchUpdate none = PinchUpdate(PinchKind.none);
}

/// Bundle 199: the gesture brain for chat text zoom (pure Dart, testable).
///
/// * Only the first two fingers count; a 3rd finger is ignored.
/// * Nothing changes until a finger has moved more than [slop] px, so a
///   two-finger tap never changes the size.
/// * Two two-finger taps (each shorter than [tapMaxMs], the second starting
///   within [doubleGapMs] after the first ended) = reset to normal size.
class PinchZoomTracker {
  PinchZoomTracker({
    required this.current,
    this.slop = 12,
    this.tapMaxMs = 250,
    this.doubleGapMs = 350,
  });

  /// The size when a pinch starts.
  final double Function() current;
  final double slop;
  final int tapMaxMs;
  final int doubleGapMs;

  final Map<int, Offset> _downAt = <int, Offset>{};
  final Map<int, Offset> _now = <int, Offset>{};
  bool _pinching = false;
  bool _moved = false;
  double _startDist = 0;
  double _startScale = 1;
  int _twoDownMs = 0;
  int? _lastTapEndMs;
  bool _secondTapCandidate = false;

  bool get pinching => _pinching;

  PinchUpdate down(int id, Offset pos, int ms) {
    if (_downAt.length >= 2) return PinchUpdate.none; // 3rd finger
    _downAt[id] = pos;
    _now[id] = pos;
    if (_downAt.length != 2) return PinchUpdate.none;
    _pinching = true;
    _moved = false;
    _startDist = _distance();
    _startScale = current();
    _twoDownMs = ms;
    final last = _lastTapEndMs;
    _secondTapCandidate = last != null && ms - last <= doubleGapMs;
    return const PinchUpdate(PinchKind.start);
  }

  PinchUpdate move(int id, Offset pos, int ms) {
    if (!_downAt.containsKey(id)) return PinchUpdate.none;
    _now[id] = pos;
    if (!_pinching) return PinchUpdate.none;
    if (!_moved) {
      for (final key in _downAt.keys) {
        if ((_now[key]! - _downAt[key]!).distance > slop) _moved = true;
      }
      if (!_moved) return PinchUpdate.none;
      // Start measuring from here, so the slop itself causes no jump.
      _startDist = _distance();
      _startScale = current();
    }
    if (_startDist < 1) return PinchUpdate.none;
    return PinchUpdate(PinchKind.change, _startScale * _distance() / _startDist);
  }

  PinchUpdate up(int id, int ms) => _lift(id, ms, cancelled: false);

  PinchUpdate cancel(int id, int ms) => _lift(id, ms, cancelled: true);

  PinchUpdate _lift(int id, int ms, {required bool cancelled}) {
    if (!_downAt.containsKey(id)) return PinchUpdate.none;
    _downAt.remove(id);
    _now.remove(id);
    if (!_pinching) return PinchUpdate.none;
    _pinching = false;
    // A lifted finger ends the pinch; the other finger alone does nothing.
    final tap = !cancelled && !_moved && ms - _twoDownMs <= tapMaxMs;
    if (!tap) {
      _lastTapEndMs = null;
      return const PinchUpdate(PinchKind.end);
    }
    if (_secondTapCandidate) {
      _lastTapEndMs = null;
      _secondTapCandidate = false;
      return const PinchUpdate(PinchKind.reset);
    }
    _lastTapEndMs = ms;
    return const PinchUpdate(PinchKind.end);
  }

  double _distance() {
    final points = _now.values.toList(growable: false);
    if (points.length < 2) return 0;
    return (points[0] - points[1]).distance;
  }
}

/// Bundle 199: wraps a chat's message list. Two fingers change the message
/// text size ([ChatTextScale]); one finger is untouched (scroll, tap,
/// long-press, swipe to reply). No label is drawn (user: no percentage).
///
/// [builder] gets `pinching` so the screen can stop the list scrolling while
/// two fingers are down.
class PinchTextZoom extends StatefulWidget {
  const PinchTextZoom({
    super.key,
    required this.builder,
    this.scrollController,
    this.enabled = true,
    this.scale,
  });

  final Widget Function(BuildContext context, bool pinching) builder;
  final ScrollController? scrollController;
  final bool enabled;
  final ChatTextScale? scale;

  /// True while two fingers are on any chat list (swipe to reply backs off).
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  @override
  State<PinchTextZoom> createState() => _PinchTextZoomState();
}

class _PinchTextZoomState extends State<PinchTextZoom> {
  late final PinchZoomTracker _tracker =
      PinchZoomTracker(current: () => _scale.value);
  bool _pinching = false;
  bool _limitTicked = false;

  ChatTextScale get _scale => widget.scale ?? ChatTextScale.instance;

  int _ms(PointerEvent e) => e.timeStamp.inMilliseconds;

  void _handle(PinchUpdate u) {
    switch (u.kind) {
      case PinchKind.none:
        return;
      case PinchKind.start:
        _limitTicked = false;
        _setPinching(true);
      case PinchKind.change:
        _apply(u.scale ?? _scale.value);
      case PinchKind.end:
        _setPinching(false);
        _scale.commit(from: 'pinch');
      case PinchKind.reset:
        _setPinching(false);
        final keep = _keepPlace();
        if (_scale.value != ChatTextScale.min) _tick();
        _scale.reset();
        keep();
    }
  }

  void _apply(double raw) {
    final snapped = ChatTextScale.snap(raw);
    if (snapped != _scale.value) {
      final keep = _keepPlace();
      _scale.preview(snapped);
      keep();
      _tick();
      _limitTicked =
          snapped == ChatTextScale.min || snapped == ChatTextScale.max;
      return;
    }
    final outside = raw < ChatTextScale.min - 0.05 ||
        raw > ChatTextScale.max + 0.05;
    if (outside && !_limitTicked) {
      _limitTicked = true;
      _tick();
    }
  }

  void _tick() {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Remember where the list is; after the next frame put it back (bottom
  /// stays bottom, otherwise the same share of the way down).
  VoidCallback _keepPlace() {
    final c = widget.scrollController;
    if (c == null || !c.hasClients) return () {};
    final pos = c.position;
    final max = pos.maxScrollExtent;
    final atBottom = pos.pixels >= max - 24;
    final ratio = max <= 0 ? 1.0 : (pos.pixels / max).clamp(0.0, 1.0);
    return () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !c.hasClients) return;
        final p = c.position;
        final target = atBottom ? p.maxScrollExtent : p.maxScrollExtent * ratio;
        c.jumpTo(math.max(0.0, math.min(target, p.maxScrollExtent)));
      });
    };
  }

  void _setPinching(bool on) {
    PinchTextZoom.active.value = on;
    if (on == _pinching || !mounted) return;
    setState(() => _pinching = on);
  }

  @override
  void dispose() {
    if (_pinching) PinchTextZoom.active.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.builder(context, false);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (e.kind != PointerDeviceKind.touch &&
            e.kind != PointerDeviceKind.stylus) {
          return;
        }
        _handle(_tracker.down(e.pointer, e.position, _ms(e)));
      },
      onPointerMove: (e) => _handle(_tracker.move(e.pointer, e.position, _ms(e))),
      onPointerUp: (e) => _handle(_tracker.up(e.pointer, _ms(e))),
      onPointerCancel: (e) => _handle(_tracker.cancel(e.pointer, _ms(e))),
      child: widget.builder(context, _pinching),
    );
  }
}

/// Bundle 199: the message text inside a bubble. Grows with [ChatTextScale];
/// at the normal size it is exactly the old `Text(text, style: color)`.
class ChatBodyText extends StatelessWidget {
  const ChatBodyText(this.text, {super.key, required this.color, this.scale});

  final String text;
  final Color color;
  final ChatTextScale? scale;

  @override
  Widget build(BuildContext context) {
    final s = scale ?? ChatTextScale.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final factor = s.value;
        if (factor == ChatTextScale.min) {
          return Text(text, style: TextStyle(color: color));
        }
        final base = DefaultTextStyle.of(context).style.fontSize ?? 14;
        return Text(text,
            style: TextStyle(color: color, fontSize: base * factor));
      },
    );
  }
}
