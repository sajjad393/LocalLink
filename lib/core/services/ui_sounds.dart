import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 198: short in-app sounds (our own files in res/raw).
enum UiSound {
  messageSent('message_sent'),
  messageReceived('message_received'),
  voiceStart('voice_start'),
  voiceSend('voice_send'),
  voiceCancel('voice_cancel');

  const UiSound(this.file);
  final String file;
}

/// Plays a [UiSound] on Android. Never throws and never waits for the
/// sound. Android itself skips the sound on Silent / Vibrate and during a
/// call (UiSounds.kt).
abstract final class UiSounds {
  static const MethodChannel _channel = MethodChannel('locallink/voice_notes');

  /// "pop-pop" at most once per this time.
  static const Duration receivedGap = Duration(milliseconds: 1500);

  /// Test hook: replaces the Android call.
  @visibleForTesting
  static void Function(UiSound sound)? debugPlayer;

  static DateTime Function() _now = DateTime.now;
  static DateTime? _lastReceived;

  static void play(UiSound sound) {
    if (sound == UiSound.messageReceived) {
      final now = _now();
      final last = _lastReceived;
      if (last != null && now.difference(last) < receivedGap) return;
      _lastReceived = now;
    }
    final test = debugPlayer;
    if (test != null) {
      test(sound);
      return;
    }
    try {
      _channel.invokeMethod<bool>('tone', {'name': sound.file}).then(
          (ok) {
        if (ok == false) _fail(sound);
      }, onError: (Object e) {
        if (e is! MissingPluginException) _fail(sound);
      });
    } catch (_) {}
  }

  static void _fail(UiSound sound) =>
      AppLogger.warning('VOICE_TONE_FAIL', detail: 'name=${sound.file}');

  @visibleForTesting
  static void debugReset({DateTime Function()? now}) {
    _now = now ?? DateTime.now;
    _lastReceived = null;
    debugPlayer = null;
  }
}
