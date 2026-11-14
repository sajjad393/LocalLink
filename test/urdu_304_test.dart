// 304 (H3): Pakistani Urdu. Every English text has Urdu words with the same
// {placeholders}; English stays the same; English kept in code as a key
// (admin titles, roles, errors) is shown in Urdu; Urdu toasts still get the
// right kind; the layout stays left-to-right; the choice is saved.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/presence/block_hub.dart' show blockDateLabel;
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/core/widgets/unread_bar_304.dart';
import 'package:locallink/features/groups/presentation/screens/group_info_screen.dart' show groupDateLabel;
import 'package:locallink/features/home/presentation/screens/language_settings_screen.dart';
import 'package:locallink/l10n/l10n.dart';

Map<String, String> _arb(String path) {
  final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

Set<String> _holders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

String _plain(String s) => s.replaceAll(RegExp('[\u2066-\u2069\u200e\u200f]'), '');

Widget _app(Widget home) => MaterialApp(
      locale: L.locale,
      localizationsDelegates: L.delegates,
      supportedLocales: L.supportedLocales,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.ltr, child: child!),
      home: home,
    );

void main() {
  tearDown(() => LanguageBook304.instance.resetForTest());

  group('words', () {
    final en = _arb('lib/l10n/app_en.arb');
    final ur = _arb('lib/l10n/app_ur.arb');

    test('every English text has Urdu words', () {
      final missing = en.keys.where((k) => (ur[k] ?? '').trim().isEmpty).toList();
      expect(missing, isEmpty);
      expect(ur.length, en.length);
    });

    test('Urdu uses only the placeholders the English has', () {
      final bad = <String>[];
      for (final k in en.keys) {
        final u = _holders(ur[k]!);
        final e = _holders(en[k]!);
        if (!e.containsAll(u)) bad.add(k);
        // At most one value may be left out (an English-only "s" / "is").
        if (e.length - u.length > 1) bad.add(k);
      }
      expect(bad, isEmpty);
    });

    test('Urdu reads right-to-left inside the left-to-right screen', () {
      for (final v in ur.values) {
        expect(v.startsWith('\u2067') && v.endsWith('\u2069'), isTrue, reason: v);
      }
      // "@name", "80%" and "5:40 PM" stay whole and left-to-right.
      expect(ur['accountPhonesBackup'], contains('\u2068@{nickname}\u2069'));
      expect(ur['until'], contains('\u2068{hh}:{mm} {ampm}\u2069'));
      expect(ur['diskFull'], contains('\u2068{disk}%\u2069'));
    });

    test('Urdu text is in Urdu letters (no English left by mistake)', () {
      const keep = {'k7qm2XPA9TRC4WNE8D3F', 'llgq1', 'android', 'sajjad'};
      final latinOnly = <String>[];
      for (final e in ur.entries) {
        final p = _plain(e.value);
        if (keep.any((k) => e.key.toLowerCase().startsWith(k.toLowerCase()))) continue;
        if (!RegExp('[\u0600-\u06FF]').hasMatch(p) && RegExp('[A-Za-z]{3}').hasMatch(p)) {
          latinOnly.add('${e.key}: $p');
        }
      }
      // Only names, LinkUp, "My Android Phone" and debug lines stay English.
      expect(latinOnly.length, lessThan(12), reason: latinOnly.join('\n'));
    });
  });

  group('switching', () {
    test('English stays exactly the same', () {
      LanguageBook304.instance.load('en');
      expect(L.isUrdu, isFalse);
      expect(L.t.settings, 'Settings');
      expect(L.t.owner, 'Owner');
      expect(L.en('Owner'), 'Owner');
      expect(L.t.unreadMessages(3), '3 unread messages');
      expect(englishOf304('Couldn\'t be added'), 'Couldn\'t be added');
    });

    test('Urdu: words, English kept in code, values built in code', () {
      LanguageBook304.instance.load('ur');
      expect(L.isUrdu, isTrue);
      expect(_plain(L.t.settings), 'سیٹنگز');
      // Kept in code as a key (roles, admin titles) -> shown in Urdu.
      expect(_plain(L.en('Owner')), 'اونر');
      expect(_plain(L.en('Audit Log')), 'آڈٹ لاگ');
      // Built in code with values -> the Urdu sentence with the same values.
      final shown = _plain(L.en('Ali removed Sara'));
      expect(shown, contains('Ali'));
      expect(shown, contains('Sara'));
      expect(shown, isNot(contains('removed')));
      // Unknown text (a name, a server message) is shown as it is.
      expect(L.en('Hello 👋'), 'Hello 👋');
    });

    test('month names follow the language (digits and order stay)', () {
      final d = DateTime(2026, 1, 2, 9, 5);
      expect(blockDateLabel(d), '2 Jan 2026');
      expect(groupDateLabel(d.toIso8601String()), '2 Jan 2026');
      LanguageBook304.instance.load('ur');
      expect(_plain(blockDateLabel(d)), '2 جنوری 2026');
      expect(_plain(groupDateLabel(d.toIso8601String())), '2 جنوری 2026');
    });

    test('Urdu words map back to English (toast kinds keep working)', () {
      LanguageBook304.instance.load('ur');
      expect(englishOf304(L.t.owner), 'Owner');
      expect(LinkToast.guess(L.t.couldnTBeAdded), LinkToastKind.error);
      expect(LinkToast.guess(L.t.codeCopied), LinkToastKind.done);
      expect(englishOf304(L.t.removed4('Ali', 'Sara')), 'Ali removed Sara');
    });

    test('phone language: an Urdu phone -> Urdu, any other -> English', () {
      final book = LanguageBook304.instance;
      book.phoneLocalesForTest = const [Locale('ur', 'PK')];
      book.load(null);
      expect(book.value, AppLanguage304.phone);
      expect(L.isUrdu, isTrue);
      book.phoneLocalesForTest = const [Locale('en', 'US')];
      book.load('phone');
      expect(L.isUrdu, isFalse);
    });

    test('the choice is saved and read back', () async {
      final book = LanguageBook304.instance;
      book.phoneLocalesForTest = const [Locale('en')];
      String? saved;
      book.save = (v) async => saved = v;
      await book.choose(AppLanguage304.urdu);
      expect(saved, 'ur');
      expect(L.isUrdu, isTrue);
      book.load(saved);
      expect(book.value, AppLanguage304.urdu);
      await book.choose(AppLanguage304.english);
      expect(saved, 'en');
      expect(L.t.settings, 'Settings');
    });
  });

  group('screens', () {
    testWidgets('Language screen switches the words at once, layout stays LTR', (tester) async {
      LanguageBook304.instance.phoneLocalesForTest = const [Locale('en')];
      LanguageBook304.instance.load('en');
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const LanguageSettingsScreen()));
      expect(find.text('Language'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('language_304_ur')));
      await tester.pump();
      expect(find.text(L.t.language304), findsOneWidget);
      expect(_plain(L.t.language304), 'زبان');
      final dir = Directionality.of(tester.element(find.text(L.t.language304)));
      expect(dir, TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unread bar in Urdu at 320 px: no overflow', (tester) async {
      LanguageBook304.instance.load('ur');
      tester.view.physicalSize = const Size(320, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const Scaffold(
          body: Column(children: [UnreadBar304(count: 1), UnreadBar304(count: 128)]))));
      expect(find.text(L.t.unreadMessages(128)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('Android notification words: Urdu for every English text used', () {
    final words = File('android/app/src/main/kotlin/com/sajjad/locallink/Words304.kt').readAsStringSync();
    final keys = RegExp(r'^\s*"([^"]+)" to "', multiLine: true)
        .allMatches(words)
        .map((m) => m.group(1)!)
        .toSet();
    final dir = Directory('android/app/src/main/kotlin/com/sajjad/locallink');
    final used = <String>{};
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.kt'))) {
      for (final m in RegExp(r'Words304\.w\((?:context|this),\s*"([^"]+)"').allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    used.addAll(const ['Accept', 'Decline', 'Remove', 'Block']); // through button(label)
    expect(used.length, greaterThan(20));
    expect(used.difference(keys), isEmpty);
    final main = File('android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt').readAsStringSync();
    expect(main, contains('call.method == "language304"'));
  });
}
