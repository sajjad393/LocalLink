import 'package:flutter/material.dart';

/// Shared spacing rhythm for the whole LocalLink app.
abstract final class LocalLinkSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const section = 28.0;
  static const screen = 20.0;
}

abstract final class LocalLinkRadius {
  static const xs = 8.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const chat = 18.0;
  static const pill = 999.0;
}

abstract final class LocalLinkSizes {
  static const iconButton = 48.0;
  static const listTileMinHeight = 64.0;
  static const avatarSmall = 44.0;
  static const avatarMedium = 52.0;
  static const avatarLarge = 72.0;
  static const sendButton = 48.0;
}

/// Brand identity: the blue→cyan gradient used for the welcome hero, outgoing
/// message bubbles and primary actions (reference messenger design).
abstract final class LocalLinkBrand {
  static const gradientStart = Color(0xFF1E5BFF);
  static const gradientEnd = Color(0xFF23E0D8);

  static const linearGradient = LinearGradient(
    colors: [gradientStart, gradientEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const heroGradient = LinearGradient(
    colors: [gradientStart, gradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Deterministic vivid avatar colors (cyan / purple / blue / pink family from
/// the reference design) — picked by display name so a contact keeps the same
/// color everywhere.
abstract final class LocalLinkAvatarColor {
  static const _palette = <Color>[
    Color(0xFF1FD7D4),
    Color(0xFF7C6BF0),
    Color(0xFF2F6FF6),
    Color(0xFFE74BC8),
    Color(0xFF2BA0F0),
    Color(0xFF8E58F5),
    Color(0xFF00A8B5),
    Color(0xFFD95FA0),
  ];

  static Color forName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return _palette[0];
    var hash = 0;
    for (final codePoint in trimmed.codeUnits) {
      hash = (hash * 31 + codePoint) & 0x7FFFFFFF;
    }
    return _palette[hash % _palette.length];
  }
}

abstract final class LocalLinkTypography {
  static const pageTitle = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15);
  static const sectionTitle = TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.2);
  static const cardTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.2);
  static const bodyEmphasis = TextStyle(fontWeight: FontWeight.w700);
  static const metadata = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.2);
}

abstract final class LocalLinkMotion {
  static const quick = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 360);
}

/// Lottie animation + brand assets that ship with the app. Referenced by the
/// shared state views so every module shows the same motion language.
abstract final class LocalLinkAssets {
  static const lottieLoadingRadar = 'assets/animations/radar_pulse.json';
  static const lottieEmptyInbox = 'assets/animations/empty_inbox.json';
  static const lottieChatHero = 'assets/animations/chat_hero.json';
  static const brandSplashLogo = 'assets/brand/splash_logo.png';
}
