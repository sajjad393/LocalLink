import 'package:flutter/material.dart';

abstract final class LocalLinkSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

abstract final class LocalLinkRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

abstract final class LocalLinkTypography {
  static const pageTitle = TextStyle(fontSize: 28, fontWeight: FontWeight.w800);
  static const sectionTitle = TextStyle(fontSize: 17, fontWeight: FontWeight.w800);
  static const cardTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  static const bodyEmphasis = TextStyle(fontWeight: FontWeight.w700);
}

abstract final class LocalLinkMotion {
  static const quick = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 260);
}
