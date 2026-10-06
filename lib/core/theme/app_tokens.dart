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
