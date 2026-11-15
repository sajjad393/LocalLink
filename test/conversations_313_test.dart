// Bundle 313 (E): Conversations page - full title, no shadow corners, Fab
// room, "1 part", and FULL text (no "...") on every phone: 320 / 360 /
// 411 dp, text size 1.0 / 1.3, light / dark, English / Urdu.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';
import 'package:locallink/l10n/l10n.dart';

import 'support/b216_fonts.dart';

bool _urduLoaded = false;
Future<void> _loadUrdu() async {
  if (_urduLoaded) return;
  final loader = FontLoader('NotoNaskh304');
  for (final w in ['Regular', 'Bold']) {
    final bytes = File('assets/fonts/NotoNaskhArabic-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
  }
  await loader.load();
  _urduLoaded = true;
}

class _Srv implements ChatAdminServer {
  _Srv(this.chats, this.reqs);
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> reqs;
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => chats;
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => reqs;
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async => {'id': 'aa_new'};
  @override
  Future<ChatAnswerView> answer(String token, String id) async => ChatAnswerView(id: id);
  @override
  Future<Uint8List?> download(String token, String id) async => null;
  @override
  Future<void> close(String token, String id) async {}
  @override
  Future<Map<String, dynamic>> file(String token, String id,
          {required String fileId, String messageId = '', String name = ''}) async =>
      {'id': 'aa_file'};
  @override
  Future<Map<String, dynamic>> purge(String token, Map<String, dynamic> body) async => {'need': 2};
}

ChatRequests221 _svc(_Srv server) {
  final saved = <String, String>{};
  return ChatRequests221(
    server: server,
    signIn: () async => (token: 't', role: 'owner', username: 'sajjad'),
    serverOnline: () => true,
    actions: null,
    reader: ChatAnswerReader(
        store: MemoryAnswerPartStore(),
        selfDeviceId: () => 'dev-admin',
        boxKeys: () async => const [],
        nameOf: (_) async => ''),
    myBoxKey: () async => '',
    selfUserId: () => 'u-admin',
    selfDeviceId: () => 'dev-admin',
    phonesOf: (u) async => [u],
    groupDevices: (_) async => const [],
    localChats: () async => const [],
    people: () async => const [],
    localGroups: () async => const [],
    read: (k) async => saved[k],
    write: (k, v) async => saved[k] = v,
  );
}

Map<String, dynamic> _who(String id, String n) => {'id': id, 'name': n, 'username': n};

// Long names on purpose: they used to end in "...".
final _chats = [
  {
    'id': 'c1',
    'kind': 'direct',
    'participants': [_who('u-s', 'muhammad sajjad ahmed'), _who('u-i', 'ibrahim khan yousafzai')],
    'message_count': 128,
    'last_message_at': '2026-11-14T09:20:00Z',
  },
  {
    'id': 'c2',
    'kind': 'group',
    'group_name': 'Islamabad office family and friends group',
    'member_count': 12,
    'participants': [_who('u-k', 'kiran'), _who('u-a', 'ayesha')],
    'message_count': 56,
    'last_message_at': '2026-11-13T12:00:00Z',
  },
  {
    'id': 'c3',
    'kind': 'direct',
    'participants': [_who('u-k', 'kiran shahzadi'), _who('u-a', 'ayesha siddiqua')],
    'message_count': 9,
    'last_message_at': '2026-11-12T12:00:00Z',
  },
];

final _reqs = [
  {
    'id': 'r1', 'action': 'get_chat', 'label': 'muhammad sajjad ahmed & ibrahim khan yousafzai',
    'words': 'Full chat', 'state': 'done', 'parts': 1, 'of': 1, 'made_at': '2026-11-14T10:00:00Z',
    'chat': {'kind': 'direct', 'users': ['u-s', 'u-i']},
  },
  {
    'id': 'r2', 'action': 'get_chat', 'label': 'kiran shahzadi & ayesha siddiqua', 'words': 'Last 7 days',
    'state': 'done', 'parts': 2, 'of': 2, 'made_at': '2026-11-13T10:00:00Z', 'closed': true,
    'chat': {'kind': 'direct', 'users': ['u-k2', 'u-a2']},
  },
  {
    'id': 'r3', 'action': 'get_chat', 'label': 'kiran shahzadi & ayesha siddiqua', 'words': 'From 1 Nov to 14 Nov 2026',
    'state': 'pending', 'parts': 12, 'of': 40, 'made_at': '2026-11-14T09:00:00Z',
    'chat': {'kind': 'direct', 'users': ['u-k', 'u-a']},
  },
  {
    'id': 'r4', 'action': 'get_chat', 'label': 'Islamabad office family and friends group', 'words': 'Full chat',
    'state': 'pending', 'phones': 2, 'reached': 1, 'made_at': '2026-11-14T08:00:00Z',
    'chat': {'kind': 'group', 'group_id': 'g1'},
  },
];

Future<void> _open(WidgetTester tester, {required double width, required double scale, required bool dark}) async {
  tester.view.physicalSize = Size(width * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(MaterialApp(
    theme: dark ? ThemeData.dark() : ThemeData.light(),
    locale: L.locale,
    localizationsDelegates: L.delegates,
    supportedLocales: L.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(textDirection: TextDirection.ltr, child: child!),
    ),
    home: AdminConversationsScreen(requests: _svc(_Srv(_chats, _reqs))),
  ));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Every text on the page that was cut (ellipsis / more lines than allowed).
List<String> _cut(WidgetTester tester) {
  final out = <String>[];
  final root = tester.renderObject(find.byType(AdminConversationsScreen));
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.hasSize && o.didExceedMaxLines) {
      out.add("${o.text.toPlainText()} @ ${o.debugCreator.toString().split(" ← ").take(6).join(" < ")}");
    }
    o.visitChildren(visit);
  }

  visit(root);
  // And no text on the page may be set to end in "..." at all (a search
  // box hint is Flutter's own one-line field: checked by the cut test above).
  final hints = tester
      .renderObjectList<RenderParagraph>(find.descendant(of: find.byType(InputDecorator), matching: find.byType(RichText)))
      .toSet();
  for (final p in tester.renderObjectList<RenderParagraph>(
      find.descendant(of: find.byType(AdminConversationsScreen), matching: find.byType(RichText)))) {
    if (hints.contains(p)) continue;
    if (p.overflow == TextOverflow.ellipsis) out.add('ellipsis: ${p.text.toPlainText()}');
  }
  return out;
}

Future<void> _tab(WidgetTester tester, int i) async {
  await tester.tap(find.byKey(ValueKey('tabs221_$i')));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  tearDown(() => LanguageBook304.instance.resetForTest());

  for (final lang in ['en', 'ur']) {
    for (final width in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 1.3]) {
        for (final dark in [false, true]) {
          testWidgets('$lang ${width.toInt()} dp x$scale ${dark ? 'dark' : 'light'}: full text, nothing overflows',
              (tester) async {
            await tester.runAsync(loadRoboto216);
            await tester.runAsync(_loadUrdu);
            addTearDown(tester.view.reset);
            LanguageBook304.instance.load(lang);
            await _open(tester, width: width, scale: scale, dark: dark);
            expect(tester.takeException(), isNull);

            // E1: the whole title, never cut.
            final title = tester.widget<Text>(find.byKey(const ValueKey('conv313_title')));
            expect(title.maxLines, isNull);
            expect(title.overflow, isNull);
            expect(title.data, L.en('Conversations'));

            // E5: Chats tab - no text cut anywhere.
            expect(_cut(tester), isEmpty, reason: 'chats tab');

            // E3: the Fab text has 22 dp room on both sides.
            final fab = find.byKey(const ValueKey('chats221_new_request'));
            final label = find.descendant(of: fab, matching: find.text(L.t.newRequest));
            final box = tester.getRect(find.descendant(of: fab, matching: find.byType(BigButton307)));
            final text = tester.getRect(label);
            expect(text.left - box.left, greaterThanOrEqualTo(22 - 0.5));
            expect(box.right - text.right, greaterThanOrEqualTo(22 - 0.5));

            // E5: Requests tab (Live card, in progress, finished).
            await _tab(tester, 1);
            expect(tester.takeException(), isNull);
            expect(_cut(tester), isEmpty, reason: 'requests tab');
          });
        }
      }
    }
  }

  testWidgets('E1: at 320 dp the pill goes under the title', (tester) async {
    await tester.runAsync(loadRoboto216);
    addTearDown(tester.view.reset);
    await _open(tester, width: 320, scale: 1.3, dark: false);
    final title = tester.getRect(find.byKey(const ValueKey('conv313_title')));
    final pill = tester.getRect(find.byType(ServerPill307));
    expect(pill.top, greaterThanOrEqualTo(title.bottom));
    expect(pill.left, moreOrLessEquals(title.left, epsilon: 1));
  });

  testWidgets('E4: "1 part" and "2 parts" in Finished (English and Urdu)', (tester) async {
    await tester.runAsync(loadRoboto216);
    addTearDown(tester.view.reset);
    await _open(tester, width: 411, scale: 1.0, dark: false);
    await _tab(tester, 1);
    expect(find.textContaining('1 part \u00b7', findRichText: true), findsWidgets);
    expect(find.textContaining('2 parts', findRichText: true), findsWidgets);
    expect(find.textContaining('1 parts', findRichText: true), findsNothing);
    LanguageBook304.instance.load('ur');
    expect(L.t.onePart313, '\u2067\u20681\u2069 حصہ\u2069');
    expect(L.t.tapToOpenOnePart313, contains('حصہ'));
  });

  test('E2: the Live card clip leaves room for its shadow', () {
    const clip = ShadowRoom313();
    expect(clip.getClip(const Size(300, 200)), const Rect.fromLTRB(-16, -40, 316, 256));
  });
}
