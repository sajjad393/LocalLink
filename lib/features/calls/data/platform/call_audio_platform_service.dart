import 'package:flutter/services.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Native audio routing boundary. The adapter owns Android audio routing;
/// media transport remains local/native.
class CallAudioPlatformService {
  static const MethodChannel _channel = MethodChannel('locallink/call_audio');

  Future<void> setSpeakerphoneOn(bool enabled) async {
    await _channel.invokeMethod('setSpeakerphoneOn', {'enabled': enabled});
  }

  /// Bundle 143: in-call phone behaviour.
  /// [inCall] — volume keys control CALL volume (not media/ringer).
  /// [proximity] — screen turns off near the ear (earpiece voice calls only).
  Future<void> setCallUi({required bool inCall, required bool proximity}) async {
    final sensor = await _channel.invokeMethod<Object?>(
        'setCallUi', {'in_call': inCall, 'proximity': proximity});
    // Bundle 303 (E): one line per change, so a phone whose sensor does
    // nothing ("unsupported", e.g. some Android Go phones) shows in the logs.
    AppLogger.info('CALL_PROXIMITY',
        detail: 'in_call=$inCall want=$proximity sensor=${sensor ?? 'none'}');
  }

  Future<void> clearCommunicationDevice() async {
    await _channel.invokeMethod('clearCommunicationDevice');
  }
}
