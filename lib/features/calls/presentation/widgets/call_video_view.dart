import 'package:flutter/material.dart';

import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/widgets/call_palette.dart';

/// Quarter-turns the UI must apply so a raw Camera2 sensor buffer reads
/// upright.
/// Wire-geometry display rule. [rotation] is advertised by the SENDER as the
/// CLOCKWISE screen-rotation (Camera2 contract: sensorOrientation -
/// displayRotation) needed to make its raw camera frame upright. The wire
/// frame is the UNROTATED sensor buffer, so the receiver must rotate the
/// texture clockwise by exactly that many degrees — quarterTurns = r/90.
/// An older build accidentally undid with (360-r), i.e. rotated the frame the
/// WRONG direction: portrait feeds landed upside-down/sideways, and every
/// 'rotation fix' appears to flip-flop between sideways and inverted.
int videoDisplayQuarterTurns(int rotation) => ((rotation % 360) ~/ 90) & 3;

/// The LOCAL self-preview renders a SurfaceTexture the camera wrote into
/// directly (preview target of the same capture request) — unlike the wire
/// path that passes through encoder→network→decoder. Field evidence: the
/// wire-CLOCKWISE undo is correct for the DECODED texture, but the preview
/// texture arrives already display-composed, so undoing clockwise a second
/// time turns the user's own face sideways. Self-view therefore keeps the
/// INVERSE (counter-clockwise) undo — exactly why the remote/self renderers
/// must never share a rotation mapping again.
int localPreviewQuarterTurns(int rotation) =>
    (4 - videoDisplayQuarterTurns(rotation)) & 3;

/// WhatsApp-style video layer: the peer's stream fills the screen and the
/// caller's own camera sits as a small rounded picture-in-picture that the
/// user can DRAG to any corner. Tap the bubble to flip the camera.
///
/// Graceful states:
///  * remote expected but not streaming yet -> centered spinner + hint
///  * local camera still starting           -> spinner inside the bubble
///  * nobody sending video                  -> camera-off glyph
class CallVideoView extends StatefulWidget {
  final CallSession session;

  /// Tap on the floating self-preview flips the camera (WhatsApp-style); when
  /// null the preview is not tappable.
  final VoidCallback? onSelfPreviewTap;

  const CallVideoView({super.key, required this.session, this.onSelfPreviewTap});

  @override
  State<CallVideoView> createState() => _CallVideoViewState();
}

class _CallVideoViewState extends State<CallVideoView> {
  static const double _margin = 16.0;
  static const double _snapDistance = 8.0; // <= this px of travel counts as a tap

  Offset? _bubbleOffset; // current position inside the layout box
  Offset? _dragStartPoint;
  Offset? _dragStartOffset;
  bool _dragging = false;

  double get _localAspect {
    // Aspect (w/h) as actually rendered, mirroring _CoverTexture rotation math.
    final w = widget.session.localVideoWidth.toDouble();
    final h = widget.session.localVideoHeight.toDouble();
    final sideways = localPreviewQuarterTurns(widget.session.localVideoRotation).isOdd;
    return sideways ? (h / w) : (w / h);
  }

  void _snapToCorner(Size box, Size bubble, EdgeInsets safe) {
    final o = _bubbleOffset;
    if (o == null) return;
    final minX = _margin + safe.left;
    final maxX = box.width - bubble.width - _margin - safe.right;
    final minY = _margin + safe.top;
    final maxY = box.height - bubble.height - _margin - safe.bottom;
    final targets = [
      Offset(minX, minY), Offset(maxX, minY),
      Offset(minX, maxY), Offset(maxX, maxY),
    ];
    var best = targets.first;
    var bestDist = (best - o).distance;
    for (final t in targets.skip(1)) {
      final d = (t - o).distance;
      if (d < bestDist) { best = t; bestDist = d; }
    }
    setState(() => _bubbleOffset = best);
  }

  Offset _clamp(Offset o, Size box, Size bubble, EdgeInsets safe) {
    final minX = _margin + safe.left;
    final maxX = (box.width - bubble.width - _margin - safe.right).clamp(minX, double.infinity);
    final minY = _margin + safe.top;
    final maxY = (box.height - bubble.height - _margin - safe.bottom).clamp(minY, double.infinity);
    return Offset(o.dx.clamp(minX, maxX), o.dy.clamp(minY, maxY));
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final remoteId = session.remoteVideoTextureId;
    final localId = session.localVideoTextureId;
    final showRemote = session.peerVideoActive;
    final showLocalFull = !showRemote && session.videoEnabled;

    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final safe = MediaQuery.of(context).padding;
        // Responsive-ish PiP: 26% of width, clamped, aspect follows the real
        // local feed so it never squishes.
        final aspect = _localAspect;
        final bubbleW = (box.width * 0.26).clamp(88.0, 132.0);
        final bubbleH = (bubbleW / aspect).clamp(88.0, 200.0);
        final bubble = Size(bubbleW, bubbleH);

        final safeOffset = _bubbleOffset == null
            ? Offset(box.width - bubbleW - _margin - safe.right, _margin + safe.top)
            : _clamp(_bubbleOffset!, box, bubble, safe);
        _bubbleOffset = safeOffset;

        return Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),

            // ---- Remote, full screen, true aspect (cover-crop) ----------
            if (showRemote && remoteId != null)
              _FadeTexture(
                key: ValueKey('remote-$remoteId'),
                textureId: remoteId,
                rotation: session.remoteVideoRotation,
                sourceWidth: session.remoteVideoWidth,
                sourceHeight: session.remoteVideoHeight,
              )
            else if (showRemote)
              const _VideoLoading(label: 'Connecting video…')
            else if (showLocalFull && localId != null)
              _FadeTexture(
                key: ValueKey('local-$localId'),
                textureId: localId,
                rotation: session.localVideoRotation,
                sourceWidth: session.localVideoWidth,
                sourceHeight: session.localVideoHeight,
                selfPreview: true,
              )
            else if (showLocalFull)
              const _VideoLoading(label: 'Starting camera…')
            else
              const Center(
                child: Icon(Icons.videocam_off_rounded,
                    color: CallPalette.textSecondary, size: 56),
              ),

            // ---- Bundle 92: on-screen video pipeline verdict. One small,
            // translucent line driven by the native counters — a screenshot
            // distinguishes "no frames arrive" from "config never completes"
            // in one glance. Always visible while MY camera is on.
            if (session.videoEnabled && session.videoDebugLine.isNotEmpty)
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    session.videoDebugLine,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),

            // ---- Local PiP, draggable + snap + tap-to-flip --------------
            if (showRemote && session.videoEnabled)
              AnimatedPositioned(
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: _bubbleOffset!.dx,
                top: _bubbleOffset!.dy,
                width: bubbleW,
                height: bubbleH,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Tap lives next to the pan so sub-slop taps flip the camera
                  // instead of leaking to the screen-level show/hide toggle.
                  onTap: () => widget.onSelfPreviewTap?.call(),
                  onPanStart: (d) {
                    _dragging = true;
                    _dragStartPoint = d.globalPosition;
                    _dragStartOffset = _bubbleOffset;
                  },
                  onPanUpdate: (d) {
                    final start = _dragStartPoint;
                    final startOffset = _dragStartOffset;
                    if (start == null || startOffset == null) return;
                    setState(() {
                      _bubbleOffset = _clamp(
                          startOffset + (d.globalPosition - start), box, bubble, safe);
                    });
                  },
                  onPanEnd: (_) {
                    _dragging = false;
                    _dragStartPoint = null;
                    _dragStartOffset = null;
                    _snapToCorner(box, bubble, safe);
                  },
                  child: Semantics(
                    label: 'Your camera preview. Tap to flip camera, drag to move.',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 3)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: Colors.black, child: const Center(
                              child: SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
                            )),
                            if (localId != null)
                              _FadeTexture(
                                key: ValueKey('pip-$localId'),
                                textureId: localId,
                                rotation: session.localVideoRotation,
                                sourceWidth: session.localVideoWidth,
                                sourceHeight: session.localVideoHeight,
                                selfPreview: true,
                              ),
                            if (widget.onSelfPreviewTap != null)
                              const Positioned(
                                right: 6,
                                bottom: 6,
                                child: Icon(Icons.cameraswitch_rounded,
                                    color: Colors.white, size: 18),
                              ),
                          ],
                        ),
                      ),
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

/// Cross-fades in when the given texture becomes available so first frames
/// don't pop.
class _FadeTexture extends StatelessWidget {
  final int textureId;
  final int rotation;
  final int sourceWidth;
  final int sourceHeight;
  final bool selfPreview;

  const _FadeTexture({
    super.key,
    required this.textureId,
    required this.rotation,
    required this.sourceWidth,
    required this.sourceHeight,
    this.selfPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('fade-$textureId'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: _CoverTexture(
        textureId: textureId,
        rotation: rotation,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        selfPreview: selfPreview,
      ),
    );
  }
}

/// Centered placeholder while a stream is expected but not yet rendering.
class _VideoLoading extends StatelessWidget {
  final String label;
  const _VideoLoading({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70)),
          const SizedBox(height: 14),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _CoverTexture extends StatelessWidget {
  final int textureId;
  final int rotation;
  final int sourceWidth;
  final int sourceHeight;
  final bool selfPreview;

  const _CoverTexture({
    required this.textureId,
    this.rotation = 0,
    this.sourceWidth = 640,
    this.sourceHeight = 360,
    this.selfPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    // Cover-crop like WhatsApp video calls, first undoing the capture-side
    // sensor rotation with the ADVERTISED clockwise angle (see
    // videoDisplayQuarterTurns). The box size comes from the ACTUAL encoded
    // geometry, so any ladder rung keeps its true aspect instead of
    // stretching a hardcoded 16:9.
    final quarterTurns = selfPreview
        ? localPreviewQuarterTurns(rotation)
        : videoDisplayQuarterTurns(rotation);
    final sideways = quarterTurns.isOdd;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: sideways ? sourceHeight.toDouble() : sourceWidth.toDouble(),
        height: sideways ? sourceWidth.toDouble() : sourceHeight.toDouble(),
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: Texture(textureId: textureId),
        ),
      ),
    );
  }
}
