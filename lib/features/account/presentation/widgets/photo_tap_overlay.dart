import 'dart:async';

import 'package:flutter/material.dart';

/// Bundle 211 (A3): tap my picture → a dark circle with a camera in the
/// middle shows for [visibleFor]; tap the camera → [onCamera] (the usual
/// Take photo / Gallery / Remove photo choice). Nothing shows until a tap.
///
/// The dark circle covers only the inner picture ([innerRadius]) so the
/// Private ring and lock stay clear.
class PhotoTapOverlay extends StatefulWidget {
  final Widget child;
  final double radius;
  final double innerRadius;
  final VoidCallback onCamera;
  final ValueChanged<bool>? onShowingChanged;
  final Duration visibleFor;

  const PhotoTapOverlay({
    super.key,
    required this.child,
    required this.radius,
    required this.innerRadius,
    required this.onCamera,
    this.onShowingChanged,
    this.visibleFor = const Duration(seconds: 3),
  });

  /// Same inner size as AccountAvatar's locked circle (ring + gap removed).
  static double innerFor(double radius, {required bool locked}) {
    if (!locked) return radius;
    final ring = radius * 0.06 < 2 ? 2.0 : radius * 0.06;
    final gap = radius * 0.05 < 1.5 ? 1.5 : radius * 0.05;
    return radius - ring - gap;
  }

  @override
  State<PhotoTapOverlay> createState() => _PhotoTapOverlayState();
}

class _PhotoTapOverlayState extends State<PhotoTapOverlay> {
  bool _showing = false;
  Timer? _hide;

  void _set(bool on) {
    _hide?.cancel();
    _hide = null;
    if (on) _hide = Timer(widget.visibleFor, () => _set(false));
    if (!mounted || _showing == on) return;
    setState(() => _showing = on);
    widget.onShowingChanged?.call(on);
  }

  void _camera() {
    _set(false);
    widget.onCamera();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    final inner = widget.innerRadius * 2;
    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: GestureDetector(
        key: const ValueKey('profile_photo_tap'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _set(!_showing),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              widget.child,
              if (_showing)
                GestureDetector(
                  key: const ValueKey('profile_photo_overlay'),
                  onTap: _camera,
                  child: Container(
                    width: inner,
                    height: inner,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.photo_camera_rounded,
                        key: const ValueKey('profile_photo_camera'),
                        size: widget.radius * 0.5,
                        color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
