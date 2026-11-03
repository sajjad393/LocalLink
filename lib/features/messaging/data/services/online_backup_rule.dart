/// Bundle 205 (P5): a words message sent over a nearby way (Wi-Fi / Wi-Fi
/// Direct / Mesh) that still has no "got it" after 15 s is ALSO sent through
/// the server, once. The server keeps the same id, and the friend's phone
/// saves a message id only once, so it never shows twice.
abstract final class OnlineBackupRule {
  static const Duration after = Duration(seconds: 15);

  /// At most this many ids are remembered (oldest dropped first).
  static const int maxRemembered = 500;

  static bool due({
    required int firstDirectSendAt,
    required int now,
    required String status,
    required bool wordsOnly,
    required bool serverConnected,
    required bool internetOnly,
    required bool alreadySent,
  }) {
    if (alreadySent || internetOnly || !serverConnected || !wordsOnly) {
      return false;
    }
    if (status != 'sending' || firstDirectSendAt <= 0) return false;
    return now - firstDirectSendAt >= after.inMilliseconds;
  }

  static String line(String id, int waitedMs) =>
      'id=$id waited_s=${waitedMs ~/ 1000}';
}
