/// Bundle 205 (P7): words shown when a call ends for a reason the person
/// should know about (null = the normal "Call ended").
abstract final class CallEndWords {
  /// Reason used when no nearby way came back within 20 s.
  static const String noNearbyReason = 'no_nearby_connection';

  /// The call screen stays this long so the words can be read.
  static const Duration readTime = Duration(seconds: 2);

  static String? endedText(String? reason) => switch (reason) {
        noNearbyReason => 'Call ended: no nearby connection',
        _ => null,
      };

  static bool holdScreen(String? reason) => endedText(reason) != null;
}
