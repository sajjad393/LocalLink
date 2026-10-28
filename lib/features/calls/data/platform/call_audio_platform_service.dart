import 'package:flutter/services.dart';

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
    await _channel.invokeMethod(
        'setCallUi', {'in_call': inCall, 'proximity': proximity});
  }

  Future<void> clearCommunicationDevice() async {
    await _channel.invokeMethod('clearCommunicationDevice');
  }
}
