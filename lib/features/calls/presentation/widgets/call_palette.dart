import 'package:flutter/material.dart';

/// WhatsApp-style palette for the call screens (audio + video).
/// Dark teal-charcoal backdrop, translucent control pills, WhatsApp green for
/// accept/connected states and red for destructive actions.
abstract final class CallPalette {
  static const Color background = Color(0xFF0B141A);
  static const Color backgroundSoft = Color(0xFF111B21);
  static const Color pill = Color(0xFF1F2C34);
  static const Color controlInactive = Color(0x662A3942);
  static const Color controlActive = Colors.white;
  static const Color controlActiveIcon = Color(0xFF111B21);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF8696A0);
  static const Color green = Color(0xFF00A884);
  static const Color red = Color(0xFFE53935);
  static const Color amber = Color(0xFFF2A33C);

  static const LinearGradient backdrop = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0B141A), Color(0xFF111B21), Color(0xFF0B141A)],
  );
}
