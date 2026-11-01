import 'dart:async';

import 'package:flutter/material.dart';

/// LocalLink brand blue (same as the notification tint).
const Color kLocalLinkBlue = Color(0xFF209DEB);

/// "58% · 6.6 / 11.4 MB". Null when the total is unknown.
String? mediaProgressLabel(int done, int total) {
  if (total <= 0) return null;
  final pct = ((done / total).clamp(0.0, 1.0) * 100).floor();
  String mb(int b) => (b / (1024 * 1024)).toStringAsFixed(1);
  return '$pct% · ${mb(done)} / ${mb(total)} MB';
}

/// Bundle 150: blue ring shown on a photo/video while it is being received
/// or sent. [fraction] null = no number yet (the ring turns), otherwise it
/// fills from 0 to 100%. [onCancel] adds an X in the middle.
class BlueProgressRing extends StatelessWidget {
  const BlueProgressRing({
    super.key,
    this.fraction,
    this.label,
    this.icon,
    this.onCancel,
    this.size = 60,
  });

  final double? fraction;
  final String? label;
  final IconData? icon;
  final VoidCallback? onCancel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final f = fraction;
    final Widget middle;
    if (onCancel != null) {
      middle = IconButton(
        key: const Key('blue_progress_cancel'),
        tooltip: 'Cancel download',
        onPressed: onCancel,
        icon: const Icon(Icons.close, color: Colors.white, size: 22),
      );
    } else if (icon != null) {
      middle = Icon(icon, color: Colors.white, size: size * .42);
    } else {
      middle = const SizedBox.shrink();
    }
    return Column(
      key: const Key('blue_progress_ring'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.expand(),
              ),
              SizedBox(
                width: size - 4,
                height: size - 4,
                child: CircularProgressIndicator(
                  key: const Key('blue_progress_indicator'),
                  value: f?.clamp(0.0, 1.0).toDouble(),
                  strokeWidth: 4.5,
                  strokeCap: StrokeCap.round,
                  color: kLocalLinkBlue,
                  backgroundColor: Colors.white24,
                ),
              ),
              middle,
            ],
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label!,
              key: const Key('blue_progress_label'),
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Bundle 174 (6): "35%". Null / unknown = no number yet.
String percentText(double? fraction) {
  final f = fraction;
  if (f == null || !f.isFinite) return '';
  return '${(f.clamp(0.0, 1.0) * 100).floor()}%';
}

/// Bundle 174 (6) / 182: "Cancel this photo?" / "Cancel this video?"
/// (No / Yes). Shared by the ring's X and the "Waiting" label.
Future<bool> confirmCancelTransfer(BuildContext context,
    {required bool isVideo}) async {
  final what = isVideo ? 'video' : 'photo';
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Cancel this $what?'),
      actions: [
        TextButton(
          key: const Key('transfer_cancel_no'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('No'),
        ),
        TextButton(
          key: const Key('transfer_cancel_yes'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
  return yes == true;
}

/// Bundle 182: my photo/video is not sent and the friend is Offline. No
/// ring (nothing can move) - a clock + "Waiting". Tap: "Cancel this photo?".
class MediaWaitingBadge extends StatefulWidget {
  const MediaWaitingBadge({super.key, required this.isVideo, this.onCancel});

  final bool isVideo;
  final Future<void> Function()? onCancel;

  @override
  State<MediaWaitingBadge> createState() => _MediaWaitingBadgeState();
}

class _MediaWaitingBadgeState extends State<MediaWaitingBadge> {
  bool _asking = false;

  Future<void> _tap() async {
    final cancel = widget.onCancel;
    if (cancel == null || _asking) return;
    _asking = true;
    final yes = await confirmCancelTransfer(context, isVideo: widget.isVideo);
    _asking = false;
    if (yes && mounted) await cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Waiting. Sends when your friend is online',
      button: widget.onCancel != null,
      child: GestureDetector(
        key: const Key('media_waiting'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onCancel == null ? null : _tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text(
                'Waiting',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bundle 174 (6): the ONE circle for sending and receiving a photo/video.
///
/// * Only the percent in the middle (e.g. 35%) - no arrow, no MB text.
/// * Tap the circle: the percent hides and an X shows in the middle.
/// * Tap the X: "Cancel this video?" (Yes / No). Yes calls [onCancel].
/// * No tap on the X for 3 seconds: back to the percent.
class TransferPercentRing extends StatefulWidget {
  const TransferPercentRing({
    super.key,
    this.fraction,
    this.onCancel,
    this.isVideo = true,
    this.size = 60,
    this.paused = false,
  });

  /// Bundle 179 (1.6): pause sign instead of the percent (file waits for a
  /// voice call to end).
  final bool paused;
  final double? fraction;
  final Future<void> Function()? onCancel;
  final bool isVideo;
  final double size;

  static const Duration xTimeout = Duration(seconds: 3);

  @override
  State<TransferPercentRing> createState() => _TransferPercentRingState();
}

class _TransferPercentRingState extends State<TransferPercentRing> {
  bool _showX = false;
  bool _asking = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onRingTap() {
    if (widget.onCancel == null) return;
    _timer?.cancel();
    setState(() => _showX = true);
    _timer = Timer(TransferPercentRing.xTimeout, () {
      if (mounted && !_asking) setState(() => _showX = false);
    });
  }

  Future<void> _onXTap() async {
    final cancel = widget.onCancel;
    if (cancel == null || _asking) return;
    _timer?.cancel();
    _asking = true;
    final yes = await confirmCancelTransfer(context, isVideo: widget.isVideo);
    _asking = false;
    if (!mounted) return;
    setState(() => _showX = false);
    if (yes == true) await cancel();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final f = widget.fraction;
    final text = percentText(f);
    final Widget middle = _showX
        ? GestureDetector(
            key: const Key('transfer_cancel_x'),
            behavior: HitTestBehavior.opaque,
            onTap: _onXTap,
            child: SizedBox(
              width: size,
              height: size,
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 28),
            ),
          )
        : widget.paused
            ? Icon(Icons.pause_rounded,
                key: const Key('transfer_paused'),
                color: Colors.white,
                size: size * .45)
            : Text(
            text,
            key: const Key('transfer_percent'),
            style: TextStyle(
              color: Colors.white,
              fontSize: size * .25,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );
    return Semantics(
      label: widget.paused
          ? 'Sends after the call'
          : (text.isEmpty ? 'Transferring' : 'Transferring $text'),
      button: widget.onCancel != null,
      child: GestureDetector(
        key: const Key('transfer_percent_ring'),
        behavior: HitTestBehavior.opaque,
        onTap: _showX ? null : _onRingTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.expand(),
              ),
              SizedBox(
                width: size - 4,
                height: size - 4,
                child: CircularProgressIndicator(
                  key: const Key('blue_progress_indicator'),
                  value: f?.clamp(0.0, 1.0).toDouble(),
                  strokeWidth: 4.5,
                  strokeCap: StrokeCap.round,
                  color: kLocalLinkBlue,
                  backgroundColor: Colors.white24,
                ),
              ),
              middle,
            ],
          ),
        ),
      ),
    );
  }
}
