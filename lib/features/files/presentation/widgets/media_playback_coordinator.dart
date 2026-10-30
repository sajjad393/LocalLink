import 'package:flutter/foundation.dart';

/// Bundle 145: one piece of chat media plays at a time.
///
/// A video or a voice note claims playback before it starts; whoever held it
/// before is told to pause. Owners release on pause/finish/dispose.
class MediaPlaybackCoordinator {
  MediaPlaybackCoordinator();

  static final MediaPlaybackCoordinator instance = MediaPlaybackCoordinator();

  Object? _owner;
  VoidCallback? _pauseOwner;

  /// [owner] is about to play. The previous owner (if another one) is paused
  /// AFTER the switch, so a re-entrant claim from its pause callback is safe.
  void claim(Object owner, VoidCallback pause) {
    if (identical(_owner, owner)) {
      _pauseOwner = pause;
      return;
    }
    final previous = _pauseOwner;
    _owner = owner;
    _pauseOwner = pause;
    if (previous != null) {
      try {
        previous();
      } catch (_) {}
    }
  }

  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _pauseOwner = null;
  }

  bool isOwner(Object owner) => identical(_owner, owner);
}
