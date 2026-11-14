import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:locallink/l10n/by_english_304.dart';
import 'package:locallink/l10n/gen/app_localizations.dart';

export 'package:locallink/l10n/gen/app_localizations.dart';

/// 304 (H3): the app's words in the chosen language (English / Urdu).
///
/// Flutter's standard system: the words live in `lib/l10n/app_en.arb` and
/// `lib/l10n/app_ur.arb`; `flutter gen-l10n` (run by `flutter pub get`)
/// makes `AppLocalizations`. `L.t` is the current language, so a text works
/// without a BuildContext (toasts, notifications, labels in models). A
/// screen shown without the language setup (tests) is English, as before.
///
/// The layout stays left-to-right in Urdu too (user, 15 Nov). Every Urdu
/// text in `app_ur.arb` is wrapped in RLI ... PDI (U+2067 / U+2069) so it
/// reads right-to-left inside the left-to-right screen; each {placeholder}
/// is wrapped in FSI ... PDI (U+2068 / U+2069) so @names, sizes and numbers
/// keep their own order. `test/urdu_304_test.dart` checks this.
abstract final class L {
  static AppLocalizations _t = lookupAppLocalizations(const Locale('en'));
  static Locale _locale = const Locale('en');

  /// The words of the current language.
  static AppLocalizations get t => _t;

  static Locale get locale => _locale;
  static bool get isUrdu => _locale.languageCode == 'ur';

  /// English + Urdu (Pakistan; `ur_PK` phones use `ur`).
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('ur')];

  static const List<LocalizationsDelegate<dynamic>> delegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  /// Urdu letters: Roboto first (English looks the same), then Noto Naskh.
  static const List<String> fontFallback = <String>['NotoNaskh304'];

  /// Switch the words (the app rebuilds its screens after this).
  static void use(Locale locale) {
    final l = locale.languageCode == 'ur' ? const Locale('ur') : const Locale('en');
    _locale = l;
    _t = lookupAppLocalizations(l);
  }

  /// English text that stays in the code because the app also uses it as a
  /// key (admin pages, filters, roles) or it comes back from an error ->
  /// the same words in the chosen language. Unknown text is shown as is.
  static String en(String english) {
    final exact = byEnglish304(_t, english);
    if (exact != null) return exact;
    // English made in code with values ("Ali removed Sara"): Urdu only.
    if (!isUrdu || english.length < 6 || !english.contains(' ')) return english;
    if (_enFor != _locale) {
      _enCache.clear();
      _enFor = _locale;
    }
    final hit = _enCache[english];
    if (hit != null) return hit;
    var out = english;
    for (final (re, words) in byEnglishPatterns304) {
      final m = re.firstMatch(english);
      if (m == null) continue;
      out = words(_t, [for (var i = 1; i <= m.groupCount; i++) m.group(i)]);
      break;
    }
    if (_enCache.length > 400) _enCache.clear();
    _enCache[english] = out;
    return out;
  }

  static final Map<String, String> _enCache = <String, String>{};
  static Locale? _enFor;

  /// The parts of one sentence (some in bold) for `Text.rich`: in Urdu the
  /// parts read right-to-left inside the left-to-right screen.
  static List<InlineSpan> spans(List<InlineSpan> parts) => !isUrdu
      ? parts
      : <InlineSpan>[const TextSpan(text: '\u2067'), ...parts, const TextSpan(text: '\u2069')];

  /// Text people type (messages, names): Urdu reads right-to-left inside
  /// the left-to-right screen. Text that starts with a Latin letter or a
  /// digit is not touched.
  static String typed(String text) {
    for (final r in text.runes) {
      if (_isRtl(r)) return '\u2068$text\u2069';
      if (_isStrongLtr(r)) return text;
    }
    return text;
  }

  static bool _isRtl(int r) =>
      (r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF);
  static bool _isStrongLtr(int r) =>
      (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F) || (r >= 0x30 && r <= 0x39);
}

/// The English words of a text shown in the chosen language (Urdu toast ->
/// its English words), so rules that read English words (the toast kind)
/// work in every language. Unknown text comes back as is.
String englishOf304(String shown) {
  if (!L.isUrdu) return shown;
  _Back304.build();
  final exact = _Back304.exact[shown];
  if (exact != null) return exact;
  for (final (re, english) in _Back304.patterns) {
    final m = re.firstMatch(shown);
    if (m == null) continue;
    var out = english;
    for (var i = 0; i < m.groupCount; i++) {
      out = out.replaceFirst('{$i}', m.group(i + 1) ?? '');
    }
    return out;
  }
  return shown;
}

abstract final class _Back304 {
  static Locale? _for;
  static Map<String, String> exact = const {};
  static List<(RegExp, String)> patterns = const [];

  static void build() {
    if (_for == L.locale) return;
    _for = L.locale;
    final e = <String, String>{};
    final p = <(RegExp, String)>[];
    for (final (shown, english) in englishPairs304(L.t, _sentinel)) {
      if (!shown.contains(_sentinel)) {
        e[shown] = english;
        continue;
      }
      final parts = shown.split(_sentinel).map(RegExp.escape).toList();
      p.add((RegExp('^${parts.join('(.*?)')}\$', dotAll: true), english));
    }
    exact = e;
    patterns = p;
  }

  static const String _sentinel = '\u0001';
}

/// 304 (H3): Settings > Language.
enum AppLanguage304 { phone, english, urdu }

/// The saved language choice (`app_language_304`: phone / en / ur).
class LanguageBook304 extends ValueNotifier<AppLanguage304> {
  LanguageBook304._() : super(AppLanguage304.phone);

  static final LanguageBook304 instance = LanguageBook304._();
  static const String settingKey = 'app_language_304';

  /// Set by the app: writes the choice to the app settings.
  Future<void> Function(String value)? save;

  @visibleForTesting
  List<Locale>? phoneLocalesForTest;

  static AppLanguage304 parse(String? stored) => switch (stored) {
        'en' => AppLanguage304.english,
        'ur' => AppLanguage304.urdu,
        _ => AppLanguage304.phone,
      };

  static String store(AppLanguage304 v) => switch (v) {
        AppLanguage304.english => 'en',
        AppLanguage304.urdu => 'ur',
        AppLanguage304.phone => 'phone',
      };

  /// Phone language: an Urdu phone -> Urdu, any other language -> English.
  bool get phoneIsUrdu {
    final list = phoneLocalesForTest ?? PlatformDispatcher.instance.locales;
    return list.isNotEmpty && list.first.languageCode == 'ur';
  }

  Locale get locale => switch (value) {
        AppLanguage304.english => const Locale('en'),
        AppLanguage304.urdu => const Locale('ur'),
        AppLanguage304.phone => phoneIsUrdu ? const Locale('ur') : const Locale('en'),
      };

  /// Read at start (no save).
  void load(String? stored) {
    value = parse(stored);
    L.use(locale);
    _tellPhone();
  }

  /// The Android-side notification words (incoming call, friend requests,
  /// "LinkUp is running") follow the same choice.
  void _tellPhone() {
    if (phoneLocalesForTest != null) return;
    try {
      unawaited(const MethodChannel('locallink/device')
          .invokeMethod<bool>('language304', <String, String>{'code': L.locale.languageCode})
          .catchError((Object _) => false));
    } catch (_) {}
  }

  /// The user picked a language: words change at once and it is saved.
  Future<void> choose(AppLanguage304 v) async {
    L.use(_localeFor(v));
    if (value == v) {
      notifyListeners();
    } else {
      value = v;
    }
    _tellPhone();
    await save?.call(store(v));
  }

  Locale _localeFor(AppLanguage304 v) => switch (v) {
        AppLanguage304.english => const Locale('en'),
        AppLanguage304.urdu => const Locale('ur'),
        AppLanguage304.phone => phoneIsUrdu ? const Locale('ur') : const Locale('en'),
      };

  @visibleForTesting
  void resetForTest() {
    phoneLocalesForTest = null;
    save = null;
    value = AppLanguage304.phone;
    L.use(const Locale('en'));
  }
}

/// Marks every screen for a rebuild so all words change at once (no restart,
/// the open screens and their state stay).
void rebuildAllWords304(BuildContext context) {
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  (context as Element).visitChildren(mark);
}
