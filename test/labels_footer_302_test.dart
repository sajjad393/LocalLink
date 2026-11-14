import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/widgets/admin_blocked_banner.dart';
import 'package:locallink/core/widgets/blocked_pill.dart';
import 'package:locallink/core/widgets/chat_notice_bar_302.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/core/widgets/peer_mark_302.dart';
import 'package:locallink/core/widgets/version_banner.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/models/version_rule.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/share_app/domain/silent_update_275.dart';
import 'package:locallink/features/share_app/domain/update_request_service.dart';
import 'package:locallink/features/share_app/presentation/update_sheet.dart';

import 'support/b212_fakes.dart';
import 'support/b216_fonts.dart';
import 'support/g210_fakes.dart';

/// Bundle 302: the right label for each case (my block / admin block / old
/// app version), the new footer card, the Chats banner, the update sheet's
/// Try again, and stopped phones keep their link (E).
final String? _out = Platform.environment['UI_CHECK_OUT'];

String _src(String p) => File(p).readAsStringSync();

Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final f = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(f.readAsBytesSync()))));
  await loader.load();
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  if (_out == null) return;
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

const _kiran = BlockedPerson(userId: 'u-kiran', deviceId: 'dev-k', name: 'kiran');

SilentUpdate275 _update() => SilentUpdate275(
      requests: UpdateRequestService(
        send: (_, __) async {},
        events: const Stream.empty(),
        selfDeviceId: () => 'me',
        myName: () => 'Me',
        peerName: (_) async => '',
        peerBuilds: () => {},
        native: FakeShareNative(),
      ),
      read: (_) async => null,
      write: (_, __) async {},
    );

void main() {
  final guard = VersionGuard.instance;
  final book = AdminBlockBook.instance;
  late AdminBlockRecord ibrahimBlock;

  setUpAll(() async {
    await loadRoboto216();
    await _loadIcons();
  });

  setUp(() async {
    final server = await Keys212.make();
    ibrahimBlock = AdminBlockRecord.fromBlob(
        await serverRecord212(server, target: 'ibrahim', action: 'block', seq: 1))!;
    guard.resetForTest();
    book.resetForTest();
    book.setSelf(userId: 'me', deviceId: 'dev-me');
    BlockHub.resetForTest();
    VersionGuard.openUpdate = null;
  });
  tearDown(() {
    guard.resetForTest();
    book.resetForTest();
    BlockHub.resetForTest();
    VersionGuard.openUpdate = null;
  });

  void dropAyesha() => guard.update(rule: null, state: VersionState.ok, droppedPeers: {'dev-a'});

  group('A: one mark per case', () {
    test('my block, admin block, old app, nothing', () {
      BlockHub.instance.setForTest(people: [_kiran], peerIds: {'u-kiran', 'dev-k', 'dev-a', 'ibrahim'});
      book.put(ibrahimBlock);
      dropAyesha();
      expect(peerMark302('dev-k'), PeerMark302.blocked);
      expect(peerMark302('dev-i', userId: 'ibrahim'), PeerMark302.admin);
      expect(peerMark302('dev-a'), PeerMark302.old);
      expect(peerMark302('dev-s'), PeerMark302.none);
    });

    test('my own block wins over an old app version', () {
      BlockHub.instance.setForTest(people: [const BlockedPerson(userId: 'u-a', deviceId: 'dev-a', name: 'ayesha')]);
      dropAyesha();
      expect(peerMark302('dev-a'), PeerMark302.blocked);
    });

    test('a hub id with no person and no admin record stays my block (196 rows)', () {
      BlockHub.instance.setForTest(peerIds: {'dev-x'});
      expect(peerMark302('dev-x'), PeerMark302.blocked);
    });

    testWidgets('Chats row: Old LinkUp is a normal row, not Blocked', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MessengerConversationTile(
                  title: 'ayesha', subtitle: 'there', time: 'Thu', label: markPill302(PeerMark302.old)))));
      expect(find.text('Old LinkUp'), findsOneWidget);
      expect(find.byType(BlockedPill), findsNothing);
      expect(find.byType(MutedAvatar), findsNothing);
    });

    testWidgets('Chats row: admin block says Admin blocked', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MessengerConversationTile(
                  title: 'ibrahim',
                  subtitle: 'see you',
                  blocked: true,
                  label: markPill302(PeerMark302.admin)))));
      expect(find.text('Admin blocked'), findsOneWidget);
      expect(find.byType(BlockedPill), findsNothing);
      expect(find.byType(MutedAvatar), findsOneWidget);
    });

    testWidgets('Chats row: my block keeps the 196 Blocked pill', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: MessengerConversationTile(title: 'kiran', subtitle: 'hello', blocked: true))));
      expect(find.byType(BlockedPill), findsOneWidget);
    });

    test('screens use the mark (chat header, Chats, Calls)', () {
      final chat = _src('lib/features/messaging/presentation/screens/chat_screen.dart');
      expect(chat, contains('final iBlocked = hubBlocked && mark == PeerMark302.blocked;'));
      expect(chat, contains('_markSubtitle302(context, mark)'));
      expect(chat, contains("admin ? 'Blocked by admin' : 'Old LinkUp'"));
      final home = _src('lib/features/home/presentation/screens/home_screen.dart');
      expect(home, contains('label: markPill302(mark),'));
      expect(home, contains('final rowBlocked = hubBlocked && mark != PeerMark302.old;'));
      final calls = _src('lib/features/calls/presentation/widgets/call_history_tile.dart');
      expect(calls, contains('markPill302(mark) ?? const BlockedPill()'));
      expect(calls, contains('onTap: mine'));
    });
  });

  group('B: footer card', () {
    test('words per case, same order as 212/213', () {
      expect(chatNotice302('ayesha', peerId: 'dev-a'), isNull);
      dropAyesha();
      final old = chatNotice302('ayesha', peerId: 'dev-a')!;
      expect(old.title, 'ayesha has an old LinkUp');
      expect(old.line, 'You can message and call after they update.');
      expect(old.tone, NoticeTone302.amber);
      book.put(ibrahimBlock);
      final admin = chatNotice302('ibrahim', peerUserId: 'ibrahim')!;
      expect(admin.title, 'ibrahim is blocked by admin');
      expect(admin.line, "You can't message or call ibrahim.");
      guard.update(rule: null, state: const VersionState(VersionStateKind.stopped));
      expect(chatNotice302('ayesha', peerId: 'dev-a'), same(ChatNotice302.selfOld));
    });

    testWidgets('their old app: title + line, no Update button', (tester) async {
      dropAyesha();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AdminBlockedBar(
                  text: 'ayesha has an old LinkUp. They need to update.',
                  notice: chatNotice302('ayesha', peerId: 'dev-a')))));
      expect(find.byKey(const ValueKey('chat_admin_blocked_bar')), findsOneWidget);
      expect(find.text('ayesha has an old LinkUp'), findsOneWidget);
      expect(find.text('You can message and call after they update.'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_version_update')), findsNothing);
    });

    testWidgets('my old app: Update pill opens the update', (tester) async {
      var opened = 0;
      VersionGuard.openUpdate = (_) => opened++;
      guard.update(rule: null, state: const VersionState(VersionStateKind.stopped));
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: AdminBlockedBar(text: 'Old version. Update to send.', notice: ChatNotice302.selfOld))));
      expect(find.text('Your LinkUp is old'), findsOneWidget);
      expect(find.text('Stopped by admin. Update to send and call.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat_version_update')));
      expect(opened, 1);
    });

    test('no flat strip with a top line any more', () {
      final bar = _src('lib/core/widgets/admin_blocked_banner.dart');
      expect(bar, contains('return ChatNoticeBar302('));
      final chat = _src('lib/features/messaging/presentation/screens/chat_screen.dart');
      expect(chat, isNot(contains('border: Border(top: BorderSide(color: colors.outlineVariant)),')));
      expect(chat, contains('return ChatNoticeBar302('));
      final group = _src('lib/features/groups/presentation/screens/group_chat_screen.dart');
      expect(group, contains('notice: ChatNotice302.selfOld'));
      expect(group, contains('notice: ChatNotice302.selfAdmin'));
    });
  });

  group('C: Chats banner', () {
    testWidgets('stopped: short title + line + Update', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VersionBanner())));
      guard.update(rule: null, state: const VersionState(VersionStateKind.stopped));
      await tester.pump();
      expect(find.text('Stopped by admin'), findsOneWidget);
      expect(find.text('Read chats only. Update to send and call.'), findsOneWidget);
      expect(find.byKey(const ValueKey('version_banner_update')), findsOneWidget);
    });
  });

  group('D: update sheet', () {
    testWidgets('could not get it: OK + Try again', (tester) async {
      final s = _update()..debugShow(SilentStage275.none);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      })));
      // ignore: unawaited_futures
      showSilentUpdateSheet275(ctx, s);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Could not get it now'), findsOneWidget);
      expect(find.byKey(const ValueKey('update275_ok')), findsOneWidget);
      expect(find.byKey(const ValueKey('update275_retry')), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('getting: size and percent', (tester) async {
      final s = _update()..debugShow(SilentStage275.getting, version: '3.0.98', size: 36278230, got: 16777216);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      })));
      // ignore: unawaited_futures
      showSilentUpdateSheet275(ctx, s);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('16.0 of 34.6 MB · 46%'), findsOneWidget);
      expect(find.byKey(const ValueKey('update275_cancel')), findsOneWidget);
    });
  });

  group('E: stopped phones keep their link', () {
    test('the link layer gets my blocks + admin blocks only', () {
      final store = _src('lib/core/services/local_store.dart');
      expect(store, contains('Future<Set<String>> linkBlockedPeerIds() async {'));
      // The app still refuses their messages and calls.
      expect(store, contains('...await linkBlockedPeerIds(),\n        // Bundle 213: phones with an app version stopped by admin.\n        ...VersionGuard.instance.droppedPeers,'));
      expect(store, contains('if (VersionGuard.instance.isPeerDropped(peerId)) return true;'));
      final seal = _src('lib/features/connectivity/data/services/sealing_peer_transport.dart');
      expect(seal, contains('static Future<Set<String>> Function()? linkBlockedSource302;'));
      expect(seal, contains('final ids = source != null ? await source() : await keys.blockedPeerIds();'));
      expect(seal, contains('(source != null ? await source() : await keys.blockedPeerIds()).toSet();'));
      final deps = _src('lib/app/app_dependencies.dart');
      expect(deps, contains('SealingPeerTransport.linkBlockedSource302 = store.linkBlockedPeerIds;'));
    });
  });

  // UI check pictures (only with UI_CHECK_OUT): the real widgets, light + dark.
  for (final dark in [false, true]) {
    testWidgets('pictures ${dark ? 'dark' : 'light'}', (tester) async {
      if (_out == null) return;
      tester.view.physicalSize = const Size(360, 1180);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      BlockHub.instance.setForTest(people: [_kiran]);
      final key = GlobalKey();
      Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)));
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? LocalLinkTheme.dark() : LocalLinkTheme.light(),
          home: Scaffold(
            body: ListView(children: [
              const VersionBannerShot302(),
              MessengerConversationTile(
                  title: 'ayesha', subtitle: 'there', time: 'Thu', label: markPill302(PeerMark302.old)),
              MessengerConversationTile(
                  title: 'ibrahim',
                  subtitle: 'see you',
                  time: 'Wed',
                  blocked: true,
                  label: markPill302(PeerMark302.admin)),
              const MessengerConversationTile(title: 'kiran', subtitle: 'hello', time: 'Tue', blocked: true),
              label('I blocked them'),
              ChatNoticeBar302(
                  tone: NoticeTone302.red,
                  icon: Icons.block,
                  title: 'You blocked kiran.',
                  line: "They can't message or call you.",
                  action: NoticeButton302(label: 'Unblock', filled: false, onPressed: () {})),
              label('They blocked me'),
              const ChatNoticeBar302(
                  tone: NoticeTone302.grey, icon: Icons.lock_rounded, title: "You can't message kiran."),
              label('Admin blocked them'),
              ChatNoticeBar302.of(ChatNotice302.peerAdmin('ibrahim')),
              label('Admin blocked me'),
              ChatNoticeBar302.of(ChatNotice302.selfAdmin),
              label('Their LinkUp is old'),
              ChatNoticeBar302.of(ChatNotice302.peerOld('ayesha')),
              label('My LinkUp is old'),
              ChatNoticeBar302.of(ChatNotice302.selfOld,
                  action: NoticeButton302(label: 'Update', onPressed: () {})),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await _shot(tester, key, 'ui302_${dark ? 'dark' : 'light'}');
    });
  }
}

/// The stopped banner on its own (pictures only).
class VersionBannerShot302 extends StatefulWidget {
  const VersionBannerShot302({super.key});

  @override
  State<VersionBannerShot302> createState() => _VersionBannerShot302State();
}

class _VersionBannerShot302State extends State<VersionBannerShot302> {
  @override
  void initState() {
    super.initState();
    VersionGuard.instance.update(rule: null, state: const VersionState(VersionStateKind.stopped));
  }

  @override
  Widget build(BuildContext context) => const VersionBanner(offers: false);
}
