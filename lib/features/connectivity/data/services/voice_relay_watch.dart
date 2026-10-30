/// Bundle 167 (5.5): someone else's voice call passes through this phone.
///
/// The native side sends `voice_relay` events: `active: true` on the first
/// frame and again every 10 s, `active: false` after 8 s without voice. If
/// an "off" event is ever lost, "on" runs out by itself after [maxAge].
class VoiceRelayWatch {
  VoiceRelayWatch({this.maxAge = const Duration(seconds: 25)});

  final Duration maxAge;
  DateTime? _onAt;

  void note(bool active, DateTime now) {
    _onAt = active ? now : null;
  }

  bool active(DateTime now) {
    final at = _onAt;
    return at != null && now.difference(at) < maxAge;
  }
}
