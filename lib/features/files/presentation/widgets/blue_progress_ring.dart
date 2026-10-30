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
