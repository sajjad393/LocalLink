import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locallink/core/services/app_logger.dart';

/// Bundle 206: where the round button sits. [left] = on the left edge;
/// [y] = height inside the allowed area (0.0 top … 1.0 bottom).
@immutable
class FabPosition {
  final bool left;
  final double y;
  const FabPosition({required this.left, required this.y});

  /// Today's place: bottom-right.
  static const FabPosition home = FabPosition(left: false, y: 1.0);

  @override
  bool operator ==(Object other) =>
      other is FabPosition && other.left == left && other.y == y;

  @override
  int get hashCode => Object.hash(left, y);

  @override
  String toString() => 'FabPosition(${left ? 'left' : 'right'}, $y)';
}

/// Bundle 206: the rules (pure, unit-tested).
abstract final class FabPlaceRules {
  /// Space to the screen edges / bars (same as the old button).
  static const double margin = 16;

  /// The button grows to this while it is moved.
  static const double liftScale = 1.15;

  /// The slide to the side after letting go.
  static const Duration slide = Duration(milliseconds: 200);

  /// "Drag to move" shows only the first times.
  static const int hintTimes = 2;

  /// Top-left of the button for [pos] in an area of [area] (button [size]).
  static Offset offsetFor(FabPosition pos, Size area, double size) {
    final maxX = (area.width - size - margin).clamp(margin, double.infinity);
    const top = margin;
    final bottom = (area.height - size - margin).clamp(top, double.infinity);
    final y = pos.y.isFinite ? pos.y.clamp(0.0, 1.0) : 1.0;
    return Offset(pos.left ? margin : maxX, top + (bottom - top) * y);
  }

  /// Where the button goes when let go with its top-left at [dropped]:
  /// the nearest side, the same height (kept inside the area).
  static FabPosition dropAt(Offset dropped, Size area, double size) {
    final centerX = dropped.dx + size / 2;
    const top = margin;
    final bottom = (area.height - size - margin).clamp(top, double.infinity);
    final span = bottom - top;
    final y = span <= 0 ? 1.0 : ((dropped.dy - top) / span).clamp(0.0, 1.0);
    return FabPosition(left: centerX < area.width / 2, y: y);
  }

  /// The top-left while dragging, kept inside the area.
  static Offset clampDrag(Offset raw, Size area, double size) {
    final maxX = (area.width - size - margin).clamp(margin, double.infinity);
    final maxY = (area.height - size - margin).clamp(margin, double.infinity);
    return Offset(raw.dx.clamp(margin, maxX), raw.dy.clamp(margin, maxY));
  }
}

/// Bundle 206: ONE place for the button on Chats, Calls and People, kept on
/// the phone (SharedPreferences `fab_side` / `fab_y`).
class FabPlace extends ValueNotifier<FabPosition> {
  FabPlace() : super(FabPosition.home);

  static final FabPlace instance = FabPlace();

  static const String sideKey = 'fab_side';
  static const String yKey = 'fab_y';
  static const String hintKey = 'fab_hint_count';

  bool _loaded = false;
  bool _loading = false;
  int hintCount = 0;

  /// Reads the saved place once (later calls do nothing).
  Future<void> load() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final side = prefs.getString(sideKey);
      final y = prefs.getDouble(yKey);
      hintCount = prefs.getInt(hintKey) ?? 0;
      if (side != null && y != null && y.isFinite) {
        value = FabPosition(left: side == 'left', y: y.clamp(0.0, 1.0));
      }
    } catch (_) {
      // No saved place (or no storage in tests): today's place.
    } finally {
      _loaded = true;
      _loading = false;
    }
  }

  /// A new place after a move: tell every tab and save it.
  Future<void> move(FabPosition pos) async {
    value = pos;
    AppLogger.info('FAB_MOVED',
        detail: 'side=${pos.left ? 'left' : 'right'} '
            'y=${pos.y.toStringAsFixed(2)}');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(sideKey, pos.left ? 'left' : 'right');
      await prefs.setDouble(yKey, pos.y);
    } catch (_) {}
  }

  bool get showHint => hintCount < FabPlaceRules.hintTimes;

  Future<void> noteHintShown() async {
    hintCount += 1;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(hintKey, hintCount);
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest() {
    value = FabPosition.home;
    _loaded = false;
    _loading = false;
    hintCount = 0;
  }
}

/// Bundle 206: puts [fab] over [child] at the shared place. Press and hold
/// 0.5 s, drag, let go: it slides to the nearest side. A quick tap still
/// presses the button. The area is the tab's body, so the button never goes
/// over the title, the tab bar, a bottom bar or the keyboard.
class MovableFabArea extends StatefulWidget {
  final Widget child;
  final Widget fab;
  final double fabSize;
  final FabPlace? place;

  /// What TalkBack reads for the button (its long-press tooltip is off,
  /// because holding it now moves it).
  final String? label;

  const MovableFabArea({
    super.key,
    required this.child,
    required this.fab,
    this.fabSize = 56,
    this.place,
    this.label,
  });

  @override
  State<MovableFabArea> createState() => _MovableFabAreaState();
}

class _MovableFabAreaState extends State<MovableFabArea> {
  FabPlace get _place => widget.place ?? FabPlace.instance;

  Offset? _drag; // top-left while moving
  Offset _grabAt = Offset.zero; // finger inside the button
  bool _hint = false;

  @override
  void initState() {
    super.initState();
    _place.addListener(_onPlace);
    unawaited(_place.load());
  }

  @override
  void didUpdateWidget(covariant MovableFabArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place != widget.place) {
      (oldWidget.place ?? FabPlace.instance).removeListener(_onPlace);
      _place.addListener(_onPlace);
    }
  }

  @override
  void dispose() {
    _place.removeListener(_onPlace);
    super.dispose();
  }

  void _onPlace() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final area = Size(constraints.maxWidth, constraints.maxHeight);
      final size = widget.fabSize;
      final rest = FabPlaceRules.offsetFor(_place.value, area, size);
      final at = _drag ?? rest;
      final moving = _drag != null;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: widget.child),
          AnimatedPositioned(
            key: const ValueKey('movable_fab'),
            duration: moving ? Duration.zero : FabPlaceRules.slide,
            curve: Curves.easeOutCubic,
            left: at.dx,
            top: at.dy,
            width: size,
            height: size,
            child: GestureDetector(
              onLongPressStart: (d) {
                HapticFeedback.lightImpact();
                final showHint = _place.showHint;
                if (showHint) unawaited(_place.noteHintShown());
                setState(() {
                  _grabAt = d.localPosition;
                  _drag = rest;
                  _hint = showHint;
                });
              },
              onLongPressMoveUpdate: (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                final local = box.globalToLocal(d.globalPosition) - _grabAt;
                setState(() {
                  _drag = FabPlaceRules.clampDrag(local, area, size);
                  _hint = false;
                });
              },
              onLongPressEnd: (_) => _drop(area, size),
              onLongPressCancel: () {
                if (_drag != null) _drop(area, size);
              },
              child: AnimatedScale(
                scale: moving ? FabPlaceRules.liftScale : 1.0,
                duration: const Duration(milliseconds: 120),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Lifted while moving; at rest it looks as before.
                    boxShadow: moving
                        ? [
                            BoxShadow(
                              color: const Color(0xFF1E5BFF)
                                  .withValues(alpha: 0.40),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                  child: Semantics(
                    label: widget.label,
                    child: TooltipVisibility(visible: false, child: widget.fab),
                  ),
                ),
              ),
            ),
          ),
          if (moving && _hint)
            Positioned(
              key: const ValueKey('movable_fab_hint'),
              left: (at.dx + size / 2 - 60).clamp(4.0, area.width - 124),
              top: (at.dy - 44).clamp(4.0, double.infinity),
              width: 120,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF202127),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Drag to move',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  void _drop(Size area, double size) {
    final dropped = _drag;
    if (dropped == null) return;
    final pos = FabPlaceRules.dropAt(dropped, area, size);
    setState(() {
      _drag = null;
      _hint = false;
    });
    unawaited(_place.move(pos));
  }
}
