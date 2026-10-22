import 'package:flutter/services.dart';

/// Maps accept/setup exceptions onto a user-actionable failure reason used by
/// the call screen copy AND the structured logs. Distinct causes must stay
/// distinct here — collapsing them into one code was what hid the "missing
/// microphone permission after a fresh install" failure behind a generic
/// "Call failed".
String callFailureReason(Object error, {String fallback = 'media_setup_failed'}) {
  if (error is PlatformException) {
    // The native call-media adapter rejects with code PERMISSION when the mic
    // grant is missing (fresh install / wiped app data). The rationale prompt
    // already fired natively; the user can answer again once granted.
    if (error.code == 'PERMISSION') return 'microphone_permission';
    return fallback;
  }
  if (error is StateError) {
    final text = error.message;
    if (text.contains('identity')) return 'identity_blocked';
    if (text.contains('transport is unavailable')) return 'transport_unavailable';
  }
  return fallback;
}
