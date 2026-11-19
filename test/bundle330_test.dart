// Bundle 330: the ask, carried by hand - a QR or a link that names a chat.
//
// When two phones are not on the same Wi-Fi nothing can travel, so the ask
// itself travels: the other person scans it (or pastes it) and their phone
// files the same ask it would have filed over the LAN. Nothing uploaded,
// nothing expires.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/directory/data/ask_link_330.dart';
import 'package:locallink/features/directory/presentation/ask_qr_330_screen.dart';
import 'package:locallink/l10n/l10n.dart';

const _pure = 'lib/features/directory/data/ask_link_330.dart';
const _screen = 'lib/features/directory/presentation/ask_qr_330_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String direct() => AskLink330.of(
        label: 'Ali',
        kind: 'direct',
        userA: 'u-me',
        userB: 'u-ali',
        from: 'd-me',
        at: DateTime.utc(2026, 11, 19, 7),
      );
  String grp() => AskLink330.of(
        label: 'Old team',
        kind: 'group',
        groupId: 'g-1',
        from: 'd-me',
        at: DateTime.utc(2026, 11, 19, 7),
      );

  group('330 · the link', () {
    test('330-1 a direct ask goes round trip', () {
      final ask = AskLink330.parse(direct())!;
      expect(ask.kind, 'direct');
      expect(ask.userA, 'u-me');
      expect(ask.userB, 'u-ali');
      expect(ask.label, 'Ali');
      expect(ask.from, 'd-me');
    });

    test('330-2 a group ask too', () {
      final ask = AskLink330.parse(grp())!;
      expect(ask.kind, 'group');
      expect(ask.groupId, 'g-1');
      expect(AskLink330.chatOf(ask), {'kind': 'group', 'group_id': 'g-1'});
    });

    test('330-3 the chat it names is the chat the ask service wants', () {
      final ask = AskLink330.parse(direct())!;
      final chat = AskLink330.chatOf(ask);
      expect(chat['kind'], 'direct');
      expect(chat['users'], ['u-me', 'u-ali']);
    });

    test('330-4 junk is never half-accepted', () {
      expect(AskLink330.parse(''), isNull);
      expect(AskLink330.parse('hello'), isNull);
      expect(AskLink330.parse('linkup-ask-v1:'), isNull);
      expect(AskLink330.parse('linkup-ask-v1:notbase64!!'), isNull);
      expect(AskLink330.parse('https://example.com'), isNull);
      expect(AskLink330.looksLike('hello'), isFalse);
      expect(AskLink330.looksLike(direct()), isTrue);
    });

    test('330-5 a link that names no chat is refused', () {
      // a hand-made link with an empty chat
      final bad = AskLink330.parse(
          'linkup-ask-v1:${base64UrlPad('{"v":1,"label":"x","chat":{"kind":"direct","users":[]}}')}');
      expect(bad, isNull);
    });

    test('330-6 spaces and quotes from a chat app do not break it', () {
      expect(AskLink330.parse('  ${direct()}\n'), isNotNull);
      expect(AskLink330.parse('"${direct()}"'), isNull, reason: 'quotes are not stripped, that is honest');
    });

    test('330-7 both people read the same 6 letters', () {
      final a = AskLink330.codeOf(direct());
      expect(a.length, 6);
      expect(a, AskLink330.codeOf(' ${direct()} '));
      expect(a, isNot(AskLink330.codeOf(grp())));
      expect(RegExp(r'^[0-9A-F]{6}$').hasMatch(a), isTrue);
    });

    test('330-8 nothing expires: the link has no deadline in it', () {
      expect(direct(), isNot(contains('expire')));
      expect(File(_pure).readAsStringSync(), isNot(contains('Duration')));
      final old = AskLink330.of(
          label: 'Ali', kind: 'direct', userA: 'a', userB: 'b', from: 'd',
          at: DateTime.utc(2020, 1, 1));
      expect(AskLink330.parse(old), isNotNull, reason: 'a 2020 ask still parses');
    });
  });

  group('330 · the screen', () {
    testWidgets('330-9 it shows the code, the link button and the scan button', (t) async {
      final link = direct();
      await t.pumpWidget(MaterialApp(home: AskQr330Screen(link: link, label: 'Ali')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ask_qr_330_screen')), findsOneWidget);
      expect(find.byKey(const Key('ask_qr_330_code')), findsOneWidget);
      expect(find.byKey(const Key('ask_qr_330_words')), findsOneWidget);
      expect(find.byKey(const Key('ask_qr_330_copy')), findsOneWidget);
      expect(find.byKey(const Key('ask_qr_330_scan')), findsOneWidget);
      final code = AskLink330.codeOf(link);
      expect(find.text('${code.substring(0, 3)} ${code.substring(3)}'), findsOneWidget);
    });

    testWidgets('330-10 scanning a good ask files it here (widget)', (t) async {
      Map<String, dynamic>? filed;
      await t.pumpWidget(MaterialApp(
        home: AskQr330Screen(
          link: direct(),
          scanner: (_) async => grp(),
          onTake: (chat) async {
            filed = chat;
            return 'aa_330';
          },
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ask_qr_330_scan')));
      await t.pumpAndSettle();
      expect(filed, isNotNull, reason: 'the ask was filed on this phone');
      expect(filed!['group_id'], 'g-1');
    });

    test('330-11 the app files it through the same service the LAN card uses', () {
      final src = File(_screen).readAsStringSync();
      expect(src, contains('ChatRequests221.instance'));
      expect(src, contains('svc.request(pick)'));
      expect(src, contains('ChatPick221.fromRef'));
      expect(src, isNot(contains('http')));
    });

    test('330-12 it is reachable: a row in the contact sheet, handled by People', () {
      expect(File('lib/features/directory/presentation/contact_sheets.dart').readAsStringSync(),
          contains("Key('contact_sheet_askqr330')"));
      expect(File('lib/features/directory/presentation/contacts_screen.dart').readAsStringSync(),
          contains('AskQr330Screen('));
    });

    test('330-13 the words exist in both languages', () {
      expect(L.t.askByQr330, 'Ask by QR or link');
      expect(L.t.copyAskLink330, 'Copy the link');
      expect(File('lib/l10n/app_ur.arb').readAsStringSync(), contains('"askByQr330"'));
    });

    test('330-14 the pins still live in one place, and this build follows them', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}

String base64UrlPad(String json) {
  final b = base64Url.encode(utf8Bytes(json));
  return b.replaceAll('=', '');
}

List<int> utf8Bytes(String s) => const Utf8Codec().encode(s);
