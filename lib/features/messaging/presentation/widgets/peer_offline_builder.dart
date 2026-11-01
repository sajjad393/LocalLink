import 'package:flutter/widgets.dart';

/// Bundle 182: gives [builder] "is the friend Offline?" and rebuilds when it
/// changes - only while [enabled] (my unsent photo/video), so other bubbles
/// never rebuild on status ticks. Same widget type either way, so a video
/// keeps its player when the message gets sent.
class PeerOfflineBuilder extends StatefulWidget {
  const PeerOfflineBuilder({
    super.key,
    required this.listenable,
    required this.isOffline,
    required this.enabled,
    required this.builder,
  });

  /// Tells us when the status may have changed (the app's PresenceHub).
  final Listenable listenable;
  final bool Function() isOffline;
  final bool enabled;
  final Widget Function(bool offline) builder;

  @override
  State<PeerOfflineBuilder> createState() => _PeerOfflineBuilderState();
}

class _PeerOfflineBuilderState extends State<PeerOfflineBuilder> {
  Listenable? _listeningTo;

  void _sync() {
    final want = widget.enabled ? widget.listenable : null;
    if (identical(want, _listeningTo)) return;
    _listeningTo?.removeListener(_changed);
    want?.addListener(_changed);
    _listeningTo = want;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PeerOfflineBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _listeningTo?.removeListener(_changed);
    _listeningTo = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(widget.enabled && widget.isOffline());
}
