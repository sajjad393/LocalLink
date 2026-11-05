import 'package:flutter/material.dart';

/// Bundle 216: design tokens for the redesigned admin pages
/// (UI_SPEC_216 §1). `admin_theme.dart` is NOT changed – its own test
/// checks it. Only admin pages use these tokens and the Roboto216 font.
const String kAdminFont216 = 'Roboto216';

enum A216Tone { blue, green, red, orange, grey, gold, amber, purple, teal }

enum A216Link { server, wifiDirect, mesh, lan, blocked, offline, removed }

/// Colours for one brightness (§1.2 light = the mock, §1.3 dark).
@immutable
class A216Colors {
  final bool dark;
  final Color bg;
  final Color bgMap;
  final Color mapDot;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceSoft;
  final Color ink;
  final Color ink2;
  final Color grey;
  final Color grey2;
  final Color line;
  final Color div;
  final Color ctrlBorder;
  final Color blue;
  final Color blueSel;
  final Color blueSelBorder;
  final Color blueCard;
  final Color red;

  const A216Colors._({
    required this.dark,
    required this.bg,
    required this.bgMap,
    required this.mapDot,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceSoft,
    required this.ink,
    required this.ink2,
    required this.grey,
    required this.grey2,
    required this.line,
    required this.div,
    required this.ctrlBorder,
    required this.blue,
    required this.blueSel,
    required this.blueSelBorder,
    required this.blueCard,
    required this.red,
  });

  static const light = A216Colors._(
    dark: false,
    bg: Color(0xFFF5F6FA),
    bgMap: Color(0xFFF3F5F9),
    mapDot: Color(0xFFD5DAE3),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFFAFAFB),
    surfaceSoft: Color(0xFFF9FAFB),
    ink: Color(0xFF101828),
    ink2: Color(0xFF344054),
    grey: Color(0xFF667085),
    grey2: Color(0xFF98A2B3),
    line: Color(0xFFEAECF0),
    div: Color(0xFFF2F4F7),
    ctrlBorder: Color(0xFFD0D5DD),
    blue: Color(0xFF1E5BFF),
    blueSel: Color(0xFFE6EDFF),
    blueSelBorder: Color(0xFFB9CCFF),
    blueCard: Color(0xFFF5F8FF),
    red: Color(0xFFD92D20),
  );

  static const darkColors = A216Colors._(
    dark: true,
    bg: Color(0xFF0D1117),
    bgMap: Color(0xFF0D1117),
    mapDot: Color(0xFF2A313C),
    surface: Color(0xFF161B22),
    surfaceMuted: Color(0xFF12161C),
    surfaceSoft: Color(0xFF1B2028),
    ink: Color(0xFFE6EDF3),
    ink2: Color(0xFFC9D1D9),
    grey: Color(0xFF8B949E),
    grey2: Color(0xFF6E7681),
    line: Color(0xFF2A313C),
    div: Color(0xFF21262D),
    ctrlBorder: Color(0xFF3A424D),
    blue: Color(0xFF4C8DFF),
    blueSel: Color(0xFF1F2A44),
    blueSelBorder: Color(0xFF2F6BFF),
    blueCard: Color(0xFF16213A),
    red: Color(0xFFF87171),
  );

  Color toneBg(A216Tone t) => dark ? _darkTones[t]!.$1 : _lightTones[t]!.$1;
  Color toneFg(A216Tone t) => dark ? _darkTones[t]!.$2 : _lightTones[t]!.$2;

  static const Map<A216Tone, (Color, Color)> _lightTones = {
    A216Tone.blue: (Color(0xFFEEF3FF), Color(0xFF1E5BFF)),
    A216Tone.green: (Color(0xFFE7F7EE), Color(0xFF12805C)),
    A216Tone.red: (Color(0xFFFEF0EF), Color(0xFFD92D20)),
    A216Tone.orange: (Color(0xFFFFF4E5), Color(0xFFB54708)),
    A216Tone.grey: (Color(0xFFF2F4F7), Color(0xFF475467)),
    A216Tone.gold: (Color(0xFFFFF6DB), Color(0xFF946200)),
    A216Tone.amber: (Color(0xFFFFF6DB), Color(0xFFB07800)),
    A216Tone.purple: (Color(0xFFF2EEFF), Color(0xFF6941C6)),
    A216Tone.teal: (Color(0xFFE6F6F4), Color(0xFF0E7C73)),
  };

  static const Map<A216Tone, (Color, Color)> _darkTones = {
    A216Tone.blue: (Color(0xFF16274A), Color(0xFF7AA7FF)),
    A216Tone.green: (Color(0xFF12351F), Color(0xFF4ADE80)),
    A216Tone.red: (Color(0xFF3B1518), Color(0xFFF87171)),
    A216Tone.orange: (Color(0xFF3A2A10), Color(0xFFFBBF24)),
    A216Tone.grey: (Color(0xFF262C36), Color(0xFFC0C7D1)),
    A216Tone.gold: (Color(0xFF3A2F0E), Color(0xFFF5C542)),
    A216Tone.amber: (Color(0xFF3A2F0E), Color(0xFFF5C542)),
    A216Tone.purple: (Color(0xFF2A2245), Color(0xFFB49CFF)),
    A216Tone.teal: (Color(0xFF0F3330), Color(0xFF5EEAD4)),
  };
}

/// Fixed colours, the same in light and dark (§1.2).
abstract final class A216 {
  static const gold = Color(0xFFE7B416);
  static const crownFill = Color(0xFFFFC727);
  static const crownBand = Color(0xFFEFA300);
  static const crownLine = Color(0xFFA87400);
  static const crownGem = Color(0xFFE5484D);
  static const adminTagBg = Color(0xFFFFF6DB);
  static const adminTagBorder = Color(0xFFF2D27A);
  static const adminTagText = Color(0xFF7A5200);
  static const blockedRed = Color(0xFFF04438);
  static const online = Color(0xFF12B76A);
  static const okText = Color(0xFF079455);

  static const linkServer = Color(0xFF12A150);
  static const linkWifiDirect = Color(0xFFE8A317);
  static const linkMesh = Color(0xFF7C5CDB);
  static const linkLan = Color(0xFF14A3A0);
  static const linkBlocked = Color(0xFF98A2B3);

  static const heroFrom = Color(0xFF2554F5);
  static const heroTo = Color(0xFF6A3DF0);
  static const heroSub = Color(0xFFDCE3FF);
  static const heroChip = Color(0xFF5B66F4);
  static const heroDivider = Color(0xFF6669F4);
  static const heroOnline = Color(0xFF5BE49B);
  static const heroOffline = Color(0xFFFDB022);

  static const barTrack = Color(0xFFEEF2F6);
  static const barOk = Color(0xFF12B76A);
  static const barWarn = Color(0xFFF79009);
  static const barBad = Color(0xFFD92D20);
  static const chartBar = Color(0xFFC7D7FE);

  static const barrier = Color(0x52101828);
  static const cardShadow = BoxShadow(
      color: Color(0x12101828), blurRadius: 6, offset: Offset(0, 1.5));
  static const heroShadow = BoxShadow(
      color: Color(0x28101828), blurRadius: 10, offset: Offset(0, 4));
  static const pillShadow =
      BoxShadow(color: Color(0x14101828), blurRadius: 4);

  // §1.5 sizes.
  static const double pagePad = 16;
  static const double appBarHeight = 60;
  static const double cardRadius = 16;
  static const double heroRadius = 20;
  static const double sheetRadius = 28;
  static const double rowMenu = 56;
  static const double rowList = 60;
  static const double rowPeople = 64;
  static const double searchHeight = 44;
  static const double chipHeight = 32;
  static const double tagHeight = 21;
  static const double buttonHeight = 44;
  static const double pillHeight = 30;

  static A216Colors colors(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? A216Colors.darkColors
          : A216Colors.light;

  static Color linkColor(A216Link l) => switch (l) {
        A216Link.server => linkServer,
        A216Link.wifiDirect => linkWifiDirect,
        A216Link.mesh => linkMesh,
        A216Link.lan => linkLan,
        A216Link.blocked => linkBlocked,
        A216Link.offline => linkBlocked,
        A216Link.removed => blockedRed,
      };

  static String linkLabel(A216Link l) => switch (l) {
        A216Link.server => 'Server',
        A216Link.wifiDirect => 'Wi-Fi Direct',
        A216Link.mesh => 'Mesh',
        A216Link.lan => 'Local Wi-Fi',
        A216Link.blocked => 'Blocked',
        A216Link.offline => 'Offline',
        A216Link.removed => 'Removed',
      };

  static A216Tone linkTone(A216Link l) => switch (l) {
        A216Link.server => A216Tone.green,
        A216Link.wifiDirect => A216Tone.amber,
        A216Link.mesh => A216Tone.purple,
        A216Link.lan => A216Tone.teal,
        A216Link.blocked => A216Tone.red,
        A216Link.offline => A216Tone.grey,
        A216Link.removed => A216Tone.red,
      };

  /// Server words → link (`wifi_direct`, `mesh`, `lan`, `server`).
  static A216Link? linkFromWire(String? s) => switch ((s ?? '').toLowerCase()) {
        'server' || 'online' => A216Link.server,
        'wifi_direct' || 'wifidirect' || 'p2p' => A216Link.wifiDirect,
        'mesh' => A216Link.mesh,
        'lan' || 'local' || 'local_wifi' => A216Link.lan,
        'offline' => A216Link.offline,
        _ => null,
      };
}

/// §1.4 text styles. Colour defaults come from [c].
class A216Text {
  final A216Colors c;
  const A216Text(this.c);

  static A216Text of(BuildContext context) => A216Text(A216.colors(context));

  static TextStyle _s(double size, FontWeight w, Color color, double h,
          {double letter = 0}) =>
      TextStyle(
        fontFamily: kAdminFont216,
        fontSize: size,
        fontWeight: w,
        color: color,
        height: h,
        letterSpacing: letter,
        decoration: TextDecoration.none,
      );

  TextStyle get pageTitleBig => _s(26, FontWeight.w600, c.ink, 1.2);
  TextStyle get appBarTitle => _s(19, FontWeight.w600, c.ink, 1.2);
  TextStyle get appBarTitleSub => _s(18, FontWeight.w600, c.ink, 1.2);
  TextStyle get appBarSub => _s(12, FontWeight.w400, c.grey, 1.3);
  TextStyle get sheetTitle => _s(17, FontWeight.w600, c.ink, 1.25);
  TextStyle get heroName => _s(16, FontWeight.w600, Colors.white, 1.2);
  TextStyle get heroSub => _s(12, FontWeight.w400, A216.heroSub, 1.3);
  TextStyle get heroNumber => _s(20, FontWeight.w700, Colors.white, 1.1);
  TextStyle get heroLabel => _s(11.5, FontWeight.w400, A216.heroSub, 1.2);
  TextStyle get section => _s(13, FontWeight.w600, c.ink2, 1.3);
  TextStyle get sectionRight => _s(12.5, FontWeight.w500, c.blue, 1.3);
  TextStyle get rowTitle => _s(14.5, FontWeight.w500, c.ink, 1.2);
  TextStyle get rowSub => _s(12.5, FontWeight.w400, c.grey, 1.25);
  TextStyle get cardTitle => _s(14.5, FontWeight.w600, c.ink, 1.2);
  TextStyle get cardSub => _s(12, FontWeight.w400, c.grey, 1.3);
  TextStyle get radioTitle => _s(14.5, FontWeight.w500, c.ink, 1.2);
  TextStyle get radioTitleSheet => _s(14, FontWeight.w500, c.ink, 1.2);
  TextStyle get radioSub => _s(12, FontWeight.w400, c.grey, 1.3);
  TextStyle tag(Color fg) => _s(11, FontWeight.w600, fg, 1.0);
  TextStyle chip(bool selected) => _s(12.5,
      selected ? FontWeight.w600 : FontWeight.w500, selected ? c.blue : c.ink2, 1.0);
  TextStyle pillBtn(Color fg) => _s(12.5, FontWeight.w600, fg, 1.0);
  TextStyle button(Color fg) => _s(14, FontWeight.w600, fg, 1.0);
  TextStyle get search => _s(13.5, FontWeight.w400, c.ink, 1.0);
  TextStyle get searchHint => _s(13.5, FontWeight.w400, c.grey2, 1.0);
  TextStyle get statBig => _s(19, FontWeight.w700, c.ink, 1.1);
  TextStyle get statSmall => _s(11.5, FontWeight.w400, c.grey, 1.2);
  TextStyle get tileBig => _s(22, FontWeight.w700, c.ink, 1.1);
  TextStyle get tileSmall => _s(12, FontWeight.w400, c.grey, 1.2);
  TextStyle get emptyTitle => _s(15.5, FontWeight.w600, c.ink, 1.25);
  TextStyle get emptyBody => _s(12.5, FontWeight.w400, c.grey, 1.44);
  TextStyle get note => _s(12, FontWeight.w400, c.grey, 1.42);
  TextStyle get mapName => _s(11.5, FontWeight.w600, c.ink, 1.0);
  TextStyle get miniMapName => _s(10.5, FontWeight.w600, c.ink2, 1.0);
  TextStyle get legend => _s(10.5, FontWeight.w400, c.grey, 1.0);
  TextStyle get bigCode => _s(22, FontWeight.w700, c.blue, 1.0, letter: 1);
  TextStyle get timeSmall => _s(11.5, FontWeight.w400, c.grey, 1.0);
  TextStyle get dayLabel => _s(11.5, FontWeight.w600, c.grey2, 1.0);
  TextStyle get kvKey => _s(13, FontWeight.w400, c.grey, 1.2);
  TextStyle get kvValue => _s(13, FontWeight.w500, c.ink, 1.2);
  TextStyle custom(double size, FontWeight w, Color color, [double h = 1.2]) =>
      _s(size, w, color, h);
}

/// Bundle 216: theme for admin pages only (font Roboto216, page bg).
abstract final class AdminTheme216 {
  static ThemeData build(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final c = dark ? A216Colors.darkColors : A216Colors.light;
    return base.copyWith(
      scaffoldBackgroundColor: c.bg,
      textTheme: base.textTheme.apply(fontFamily: kAdminFont216),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: kAdminFont216),
      colorScheme: base.colorScheme.copyWith(primary: c.blue),
      dividerColor: c.div,
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: const TextStyle(
            fontFamily: kAdminFont216, fontSize: 13.5, color: Colors.white),
      ),
    );
  }
}

/// Wraps an admin route so it uses [AdminTheme216].
class AdminTheme216Scope extends StatelessWidget {
  final Widget child;
  const AdminTheme216Scope({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      Theme(data: AdminTheme216.build(Theme.of(context)), child: child);
}
