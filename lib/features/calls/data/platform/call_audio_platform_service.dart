import 'package:flutter/services.dart';

/// Native audio routing boundary. The adapter owns Android audio routing;
/// media transport remains local/native.
class CallAudioPlatformService {
  static const MethodChannel _channel = MethodChannel('locallink/call_audio');

  Future<void> setSpeakerphoneOn(bool enabled) async {
    await _channel.invokeMethod('setSpeakerphoneOn', {'enabled': enabled});
  }

  Future<void> clearCommunicationDevice() async {
    await _channel.invokeMethod('clearCommunicationDevice');
  }
}
