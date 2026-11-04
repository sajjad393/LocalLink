import 'package:flutter/material.dart';
import 'package:locallink/core/services/media_prepare_progress.dart';

import 'blue_progress_ring.dart';

/// Bundle 208 (D5/D6): a file getting ready to show (locked file being
/// opened). Only a ring that fills up with "45%" in the middle - no words.
/// Before the first number: the same ring turning, empty middle.
class PrepareRing extends StatelessWidget {
  const PrepareRing({
    super.key,
    required this.path,
    this.size = 64,
    this.ringKey = const Key('prepare_ring'),
    this.pctKey = const Key('prepare_ring_pct'),
  });

  /// The saved (locked or still plain) path of the file.
  final String path;
  final double size;
  final Key ringKey;
  final Key pctKey;

  @override
  Widget build(BuildContext context) {
    final hub = MediaPrepareProgress.instance;
    return ListenableBuilder(
      listenable: Listenable.merge(hub.watchPath(path)),
      builder: (context, _) {
        final f = hub.fractionFor(path);
        return SizedBox(
          key: ringKey,
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            const DecoratedBox(
              decoration:
                  BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: SizedBox.expand(),
            ),
            SizedBox(
              width: size - 4,
              height: size - 4,
              child: CircularProgressIndicator(
                value: f,
                strokeWidth: size >= 56 ? 4.5 : 3.5,
                strokeCap: StrokeCap.round,
                color: kLocalLinkBlue,
                backgroundColor: Colors.white24,
              ),
            ),
            if (f != null)
              Text(MediaPrepareProgress.label(f),
                  key: pctKey,
                  maxLines: 1,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: size >= 56 ? 15 : 12.5,
                      fontWeight: FontWeight.w700)),
          ]),
        );
      },
    );
  }
}
