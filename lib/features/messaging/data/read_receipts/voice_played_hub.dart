/// Bundle 198: the voice note player tells the read-receipt service that
/// I started playing a friend's voice note (1-to-1 only).
class VoicePlayedHub {
  VoicePlayedHub._();

  static final VoicePlayedHub instance = VoicePlayedHub._();

  /// Set by the app wiring (`ReadReceiptService.notePlayed`).
  void Function(String messageId)? onPlayed;

  void played(String messageId) {
    final id = messageId.trim();
    if (id.isEmpty) return;
    try {
      onPlayed?.call(id);
    } catch (_) {}
  }
}
