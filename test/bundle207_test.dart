// Bundle 207: no gray press overlay on the floating buttons (shrink to 95 %
// instead), the video player closes when a video plays to the end, and a
// tap on an emoji chip adds / removes my reaction.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/core/widgets/brand_gradient_fab.dart';
import 'package:locallink/core/widgets/no_gray_press.dart';
import 'package:locallink/core/widgets/reaction_chips.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_hub.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_player.dart';
import 'package:locallink/features/groups/presentation/screens/new_group_screen.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';

import 'support/chat_video_fakes.dart';
import 'support/phase5_fakes.dart';

String _read(String path) => File(path).readAsStringSync();

MessageReaction _r(String who, String emoji) => MessageReaction(
    messageId: 'm1', reactorId: who, emoji: emoji, createdAt: DateTime(2026));

class _ReactStore extends FakeStore {
  final saved = <String>[];
  final deleted = <String>[];

  @override
  Future<void> saveMessageReaction(
      {required String messageId,
      required String reactorId,
      required String emoji,
      required String createdAt}) async {
    saved.add('$messageId:$reactorId:$emoji');
  }

  @override
  Future<void> deleteMessageReaction(
      {required String messageId, required String reactorId}) async {
    deleted.add('$messageId:$reactorId');
  }
}

double _scale(WidgetTester t) => t
    .widget<AnimatedScale>(find.byKey(const Key('no_gray_press_scale')).first)
    .scale;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('207 P1 no gray overlay, shrink to 95 %', () {
    test('the theme has no splash and see-through press colours', () {
      final t = NoGrayPress.themeOf(ThemeData.light());
      expect(t.splashFactory, NoSplash.splashFactory);
      expect(t.highlightColor, Colors.transparent);
      expect(t.splashColor, Colors.transparent);
      expect(t.hoverColor, Colors.transparent);
      expect(t.focusColor, Colors.transparent);
      expect(t.floatingActionButtonTheme.splashColor, Colors.transparent);
      expect(NoGrayPress.pressedScaleDefault, 0.95);
    });

    testWidgets('round button: shrinks while pressed, a tap still works',
        (t) async {
      var taps = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: BrandGradientFab(
              heroTag: 'x',
              tooltip: 'New conversation',
              icon: Icons.add,
              onPressed: () => taps++,
            ),
          ),
        ),
      ));
      expect(_scale(t), 1.0);
      final g = await t.startGesture(t.getCenter(find.byType(FloatingActionButton)));
      await t.pump();
      expect(_scale(t), 0.95);
      // No ink while held: the InkWell inside uses the see-through theme.
      final ink = t.widget<InkWell>(find.descendant(
          of: find.byType(FloatingActionButton), matching: find.byType(InkWell)));
      final theme = Theme.of(t.element(find.byWidget(ink)));
      expect(theme.highlightColor, Colors.transparent);
      expect(theme.splashFactory, NoSplash.splashFactory);
      await g.up();
      await t.pump();
      expect(_scale(t), 1.0);
      expect(taps, 1);
    });

    testWidgets('square group button: shrinks; grey (off) one does not',
        (t) async {
      var taps = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            SquareGradientFab(
                key: const Key('on'),
                icon: Icons.arrow_forward,
                tooltip: 'Next',
                onPressed: () => taps++),
            const SquareGradientFab(
                key: Key('off'),
                icon: Icons.arrow_forward,
                tooltip: 'Next',
                onPressed: null),
          ]),
        ),
      ));
      final on = find.descendant(
          of: find.byKey(const Key('on')),
          matching: find.byKey(const Key('no_gray_press_scale')));
      final off = find.descendant(
          of: find.byKey(const Key('off')),
          matching: find.byKey(const Key('no_gray_press_scale')));
      var g = await t.startGesture(t.getCenter(find.byKey(const Key('on'))));
      await t.pump();
      expect(t.widget<AnimatedScale>(on).scale, 0.95);
      await g.up();
      await t.pump();
      expect(taps, 1);
      g = await t.startGesture(t.getCenter(find.byKey(const Key('off'))));
      await t.pump();
      expect(t.widget<AnimatedScale>(off).scale, 1.0);
      await g.up();
    });

    test('used by all floating buttons (round, square, Jump to latest)', () {
      expect(_read('lib/core/widgets/brand_gradient_fab.dart'),
          contains('return NoGrayPress('));
      final sq = _read('lib/features/groups/presentation/screens/new_group_screen.dart');
      expect(sq, contains('return NoGrayPress(\n      enabled: onPressed != null && !busy,'));
      final chat = _read('lib/features/messaging/presentation/screens/chat_screen.dart');
      final i = chat.indexOf("tooltip: 'Jump to latest'");
      expect(i, greaterThan(0));
      expect(chat.substring(i - 300, i), contains('NoGrayPress('));
      // Chats / Calls / People all use BrandGradientFab (bundle 206).
      for (final f in [
        'lib/features/home/presentation/screens/home_screen.dart',
        'lib/features/calls/presentation/screens/calls_screen.dart',
        'lib/features/directory/presentation/contacts_screen.dart',
      ]) {
        expect(_read(f), contains('BrandGradientFab('), reason: f);
      }
    });
  });

  group('207 P2 the player closes when the video ends', () {
    test('only a video that was playing counts (not a paused drag to the end)',
        () {
      const end = ChatVideoState(
          initialized: true,
          playing: false,
          position: Duration(seconds: 31),
          duration: Duration(seconds: 31));
      const completedPlaying = ChatVideoState(
          initialized: true,
          playing: true,
          completed: true,
          position: Duration(seconds: 31),
          duration: Duration(seconds: 31));
      const middle = ChatVideoState(
          initialized: true,
          playing: false,
          position: Duration(seconds: 10),
          duration: Duration(seconds: 31));
      expect(ChatVideoHub.playedToEnd(end, wasPlaying: true), isTrue);
      expect(ChatVideoHub.playedToEnd(end, wasPlaying: false), isFalse);
      expect(ChatVideoHub.playedToEnd(completedPlaying, wasPlaying: false),
          isTrue);
      expect(ChatVideoHub.playedToEnd(middle, wasPlaying: true), isFalse);
    });

    testWidgets('full player: played to the end -> closes, bubble shows preview',
        (t) async {
      final r = Rig();
      await t.pumpWidget(host([r.player('/v/a.mp4')], hub: r.hub));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      await tapKey(t, 'chat_video_fullscreen');
      await t.pumpAndSettle();
      expect(find.byType(ChatVideoFullscreen), findsOneWidget);
      await c.finish();
      await t.pumpAndSettle();
      expect(find.byType(ChatVideoFullscreen), findsNothing);
      expect(c.closed, isTrue);
      expect(find.byKey(const Key('chat_video_play_big')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('full player: paused, dragged to the end -> stays open',
        (t) async {
      final r = Rig();
      await t.pumpWidget(host([r.player('/v/a.mp4')], hub: r.hub));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      await tapKey(t, 'chat_video_fullscreen');
      await t.pumpAndSettle();
      await c.pause();
      await t.pump();
      await c.seekTo(const Duration(seconds: 31));
      await t.pumpAndSettle();
      expect(find.byType(ChatVideoFullscreen), findsOneWidget);
      expect(c.closed, isFalse);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('small floating player: closes at once at the end', (t) async {
      final r = Rig();
      await t.pumpWidget(host([r.player('/v/a.mp4')], hub: r.hub));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      r.hub.showMini(r.hub.current!);
      await t.pump();
      expect(find.byKey(const Key('mini_video')), findsOneWidget);
      await c.finish();
      await t.pump();
      await t.pump();
      expect(r.hub.mini, isNull);
      expect(c.closed, isTrue);
      expect(find.byKey(const Key('mini_video')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Android floating window: video ends -> window closed',
        (t) async {
      final r = Rig();
      r.hub.attach(navigatorKey: GlobalKey<NavigatorState>());
      addTearDown(r.hub.detachForTest);
      await t.pumpWidget(host([r.player('/v/a.mp4')], hub: r.hub));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      r.hub.didChangeAppLifecycleState(AppLifecycleState.inactive);
      r.pip.events$.add({'type': 'pip', 'active': true, 'dismissed': false});
      await t.pump(const Duration(milliseconds: 800));
      expect(find.byType(PipVideoView), findsOneWidget);
      await c.finish();
      await t.pump();
      await t.pump();
      expect(c.closed, isTrue);
      expect(r.pip.calls, contains('close'));
      await t.pumpWidget(const SizedBox());
    });

    test('native: close leaves the floating window; log line', () {
      final kt = _read(
          'android/app/src/main/kotlin/com/sajjad/locallink/ChatVideoPip.kt');
      expect(kt, contains('"close" -> {'));
      expect(kt, contains('activity.moveTaskToBack(true)'));
      final hub = _read(
          'lib/features/files/presentation/widgets/chat_video_hub.dart');
      expect(hub, contains("'VIDEO_END_CLOSE', detail: 'where=\$where'"));
      expect(hub, isNot(contains('Duration(seconds: 5)')),
          reason: 'no 5 s wait in the mini player any more');
    });
  });

  group('207 P3 tap an emoji chip', () {
    test('add / remove / change (one reaction per person)', () {
      final list = [_r('d2', '❤️')];
      expect(reactionTapKind(list, 'me', '❤️'), ReactionTapKind.add);
      expect(reactionTapKind([...list, _r('me', '❤️')], 'me', '❤️'),
          ReactionTapKind.remove);
      expect(reactionTapKind([...list, _r('me', '👍')], 'me', '❤️'),
          ReactionTapKind.change);
      expect(reactionTapKind(const [], 'me', '❤️'), ReactionTapKind.add);
    });

    testWidgets('chips: counts, my own has a border, tap and hold', (t) async {
      final taps = <String>[];
      final holds = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Row(
              children: reactionChips(context,
                  reactions: [_r('d2', '❤️'), _r('d3', '❤️'), _r('me', '👍')],
                  myId: 'me',
                  keyPrefix: 'reaction_chip',
                  onTap: taps.add,
                  onLongPress: holds.add),
            ),
          ),
        ),
      ));
      expect(find.text('❤️ 2'), findsOneWidget);
      expect(find.text('👍 1'), findsOneWidget);
      final heart = t.widget<ReactionChip>(
          find.byKey(const ValueKey('reaction_chip_❤️')));
      final thumb = t.widget<ReactionChip>(
          find.byKey(const ValueKey('reaction_chip_👍')));
      expect(heart.mine, isFalse);
      expect(thumb.mine, isTrue);
      await t.tap(find.byKey(const ValueKey('reaction_chip_❤️')));
      await t.longPress(find.byKey(const ValueKey('reaction_chip_👍')));
      expect(taps, ['❤️']);
      expect(holds, ['👍']);
    });

    test('1:1 remove is sent as an empty emoji and deleted here', () async {
      final store = _ReactStore();
      final service = ReliableMessagingService(
        store,
        LocalLinkApi(store, WebSocketService()),
        WebSocketService(),
        FakeFilesRepository(),
        FakeConnectivity(),
        FakePeerTransport(),
      );
      final seen = <MessageReaction>[];
      final sub = service.reactionIncoming.listen(seen.add);
      await service.sendReaction('peer', 'm1', '❤️');
      await service.sendReaction('peer', 'm1', '');
      await Future<void>.delayed(Duration.zero);
      expect(store.saved, ['m1:self-device:❤️']);
      expect(store.deleted, ['m1:self-device']);
      final bodies = store.outboxItems.map((e) => e['body'] as String).toList();
      expect(bodies.length, 2);
      expect(bodies.last, startsWith('llrx:v1:'));
      expect(bodies.last, contains('"emoji":""'));
      expect(seen.map((e) => e.emoji).toList(), ['❤️', '']);
      await sub.cancel();
    });

    test('wired in 1:1 and groups; receive side removes; hold = who reacted',
        () {
      final svc = _read(
          'lib/features/messaging/data/services/reliable_messaging_service.dart');
      expect(svc, contains('// Bundle 207: the friend removed their reaction.'));
      final bloc = _read('lib/features/messaging/bloc/chat_bloc.dart');
      expect(bloc, contains('Future<void> removeReaction(String messageId)'));
      expect(bloc, contains('if (index >= 0) current.removeAt(index);'));
      final chat = _read(
          'lib/features/messaging/presentation/screens/chat_screen.dart');
      expect(chat, contains('(emoji) => _tapReaction(message, emoji)'));
      expect(chat, contains("'REACTION_TAP'"));
      final group = _read(
          'lib/features/groups/presentation/screens/group_chat_screen.dart');
      expect(group, contains('(emoji) => _tapReaction(message, emoji)'));
      expect(group, contains("'REACTION_TAP'"));
      final gb = _read(
          'lib/features/groups/presentation/widgets/group_message_bubble.dart');
      expect(gb, contains('onLongPress: onReactionsTap == null'));
    });
  });

  group('207 I viewer video page', () {
    Widget pageHost(Rig r, {bool active = true}) => MaterialApp(
          home: Scaffold(body: r.player('/v/p.mp4', page: true, active: active)),
          builder: (context, child) => ChatVideoShell(hub: r.hub, child: child!),
        );

    testWidgets('fills the screen and plays by itself; no full-screen button', (t) async {
      final r = Rig();
      await t.pumpWidget(pageHost(r));
      await t.pump();
      await t.pump();
      await t.pump();
      expect(r.controllers, hasLength(1));
      expect(r.controllers.single.state.playing, isTrue);
      final box = t.getSize(find.byKey(const Key('chat_video_page')));
      expect(box, const Size(800, 600));
      expect(find.byKey(const Key('chat_video_fullscreen')), findsNothing);
      expect(find.byKey(const Key('chat_video_back10')), findsOneWidget);
      expect(find.byKey(const Key('chat_video_fwd10')), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('swiped away -> pauses; back -> plays', (t) async {
      final r = Rig();
      await t.pumpWidget(pageHost(r));
      await t.pump();
      await t.pump();
      await t.pump();
      final c = r.controllers.single;
      await t.pumpWidget(pageHost(r, active: false));
      await t.pump();
      expect(c.state.playing, isFalse);
      await t.pumpWidget(pageHost(r, active: true));
      await t.pump();
      expect(c.state.playing, isTrue);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('at the end it stays on the last frame (viewer open); play = from 0', (t) async {
      final r = Rig();
      await t.pumpWidget(pageHost(r));
      await t.pump();
      await t.pump();
      await t.pump();
      final c = r.controllers.single;
      await c.finish();
      await t.pump();
      await t.pump();
      expect(c.closed, isFalse);
      expect(find.byKey(const Key('fake_view')), findsOneWidget);
      expect(find.byKey(const Key('chat_video_play')), findsOneWidget);
      await t.tap(find.byKey(const Key('chat_video_play')));
      await t.pump();
      await t.pump();
      expect(c.seeks.last, Duration.zero);
      expect(c.state.playing, isTrue);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('leaving the viewer stops it (no mini player)', (t) async {
      final r = Rig();
      await t.pumpWidget(pageHost(r));
      await t.pump();
      await t.pump();
      await t.pump();
      final c = r.controllers.single;
      await t.pumpWidget(MaterialApp(
          home: const Scaffold(body: SizedBox()),
          builder: (context, child) => ChatVideoShell(hub: r.hub, child: child!)));
      await t.pump();
      expect(c.closed, isTrue);
      expect(r.hub.mini, isNull);
    });
  });
}
