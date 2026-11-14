import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' show CallBloc;
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/domain/call_gateway.dart';
import 'package:locallink/features/calls/domain/call_repository_contract.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/features/calls/presentation/widgets/call_strip_303.dart';

import 'support/b216_fonts.dart';

/// Bundle 303: the ring screen opens while LinkUp is on screen (also when
/// Android says "inactive"), skips are logged, ONE call card (style C)
/// shows on every screen instead of the Chats / Calls bars + chat chip,
/// calls start on the earpiece and the proximity result is logged.
final String? _out = Platform.environment['UI_CHECK_OUT'];

String _src(String p) => File(p).readAsStringSync();

class _Gw implements CallGateway {
  final ctrl = StreamController<CallSession?>.broadcast();
  CallSession? current;
  void set(CallSession? s) {
    current = s;
    ctrl.add(s);
  }

  @override
  Stream<CallSession?> get sessionStream => ctrl.stream;
  @override
  Stream<List<CallRecord>> get historyStream => const Stream.empty();
  @override
  CallSession? get session => current;
  @override
  String? get selfDeviceId => 'me';
  @override
  void start() {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<String> get callScreenRequests => const Stream.empty();
  @override
  String? get requestedCallScreenId => null;
  @override
  Stream<String> get callUnavailableNotices => const Stream.empty();
  int accepted = 0;
  int rejected = 0;
  @override
  Future<void> acceptIncoming() async => accepted++;
  @override
  Future<void> rejectIncoming({String reason = 'rejected'}) async => rejected++;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('not used: $invocation');
}

class _Repo implements CallRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('not used: $invocation');
}

CallSession _s(CallDirection d, CallState st, {DateTime? answered, String name = 'ayesha'}) => CallSession(
      id: 'c1',
      peerId: 'dev-a',
      peerName: name,
      direction: d,
      state: st,
      startedAt: DateTime(2026, 11, 15, 10),
      answeredAt: answered,
    );

Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final f = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(f.readAsBytesSync()))));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await loadRoboto216();
    await _loadIcons();
  });
  tearDown(() {
    CallStrip303.detachForTest();
    CallScreen.visibleCallId = null;
  });

  group('words', () {
    final now = DateTime(2026, 11, 15, 10, 5);
    test('ringing to me / calling / answered / reconnecting / ended', () {
      expect(CallStrip303.wordsFor(_s(CallDirection.incoming, CallState.ringing)), ('ayesha', 'Incoming call'));
      expect(CallStrip303.wordsFor(_s(CallDirection.outgoing, CallState.ringing)), ('ayesha', 'Calling…'));
      expect(CallStrip303.wordsFor(_s(CallDirection.outgoing, CallState.connecting)), ('ayesha', 'Calling…'));
      expect(
          CallStrip303.wordsFor(
              _s(CallDirection.incoming, CallState.connected, answered: DateTime(2026, 11, 15, 10, 3, 37)),
              now: now),
          ('ayesha', '01:23'));
      expect(
          CallStrip303.wordsFor(
              _s(CallDirection.outgoing, CallState.reconnecting, answered: DateTime(2026, 11, 15, 10, 4)),
              now: now),
          ('ayesha', 'Reconnecting…'));
      expect(CallStrip303.wordsFor(_s(CallDirection.incoming, CallState.missed)), isNull);
      expect(CallStrip303.wordsFor(null), isNull);
      expect(CallStrip303.wordsFor(_s(CallDirection.incoming, CallState.ringing, name: ' ')),
          ('LinkUp user', 'Incoming call'));
    });
  });

  group('card on every screen (style C)', () {
    late _Gw gw;
    late CallBloc calls;
    late int opened;
    final nav = GlobalKey<NavigatorState>();

    Future<void> pumpApp(WidgetTester tester, {bool dark = false}) async {
      gw = _Gw();
      calls = CallBloc(service: gw, repository: _Repo());
      opened = 0;
      CallStrip303.attach(calls, () => opened++);
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        theme: dark ? LocalLinkTheme.dark() : LocalLinkTheme.light(),
        navigatorObservers: [CallStrip303.observer],
        builder: (context, child) => CallStrip303.wrap(child!),
        home: Scaffold(appBar: AppBar(title: const Text('Chats')), body: const SizedBox()),
      ));
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('ayesha chat'), toolbarHeight: 68), body: const TextField())));
      await tester.pumpAndSettle();
    }

    Future<void> two(WidgetTester tester) async {
      // The stream event lands after the first frame; the card measures the
      // top bar after the next one.
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('ringing: card with Decline + Answer on a chat; the chat stays', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const ValueKey('call_strip_303')), findsNothing);
      await tester.enterText(find.byType(TextField), 'hello');
      gw.set(_s(CallDirection.incoming, CallState.ringing));
      await two(tester);
      expect(find.text('ayesha'), findsWidgets);
      expect(find.text('Incoming call'), findsOneWidget);
      expect(find.byKey(const ValueKey('call_strip_303_decline')), findsOneWidget);
      expect(find.byKey(const ValueKey('call_strip_303_answer')), findsOneWidget);
      expect(find.byKey(const ValueKey('call_strip_303_return')), findsNothing);
      // Same navigator + same chat (typed text kept): no rebuild of screens.
      expect(find.text('ayesha chat'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('call_strip_303_title')));
      expect(opened, 1);
      gw.set(null);
      await two(tester);
      expect(find.byKey(const ValueKey('call_strip_303')), findsNothing);
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('Answer answers right in the card, then opens the call screen; Decline declines', (tester) async {
      await pumpApp(tester);
      gw.set(_s(CallDirection.incoming, CallState.ringing));
      await two(tester);
      await tester.tap(find.byKey(const ValueKey('call_strip_303_answer')));
      await tester.pump();
      expect(gw.accepted, 1);
      expect(opened, 1);
      gw.set(_s(CallDirection.incoming, CallState.ringing));
      await two(tester);
      await tester.tap(find.byKey(const ValueKey('call_strip_303_decline')));
      await tester.pump();
      expect(gw.rejected, 1);
      expect(opened, 1);
    });

    testWidgets('answered: green line with the clock + Return; tap Return opens', (tester) async {
      await pumpApp(tester);
      gw.set(_s(CallDirection.outgoing, CallState.connected, answered: DateTime.now().subtract(const Duration(seconds: 83))));
      await two(tester);
      expect(find.byKey(const ValueKey('call_strip_303_return')), findsOneWidget);
      expect(find.text('01:23'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('call_strip_303_return')));
      expect(opened, 1);
    });

    testWidgets('floats just under the top bar of the screen in front', (tester) async {
      await pumpApp(tester);
      gw.set(_s(CallDirection.outgoing, CallState.connecting));
      await two(tester);
      final bar = tester.getBottomLeft(find.byType(AppBar).last).dy;
      expect(bar, 68);
      expect(tester.getTopLeft(find.byKey(const ValueKey('call_strip_303'))).dy, bar + 6);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      await two(tester);
      expect(tester.getTopLeft(find.byKey(const ValueKey('call_strip_303'))).dy, kToolbarHeight + 6);
    });

    testWidgets('hidden while the call screen is open, back after it closes', (tester) async {
      await pumpApp(tester);
      gw.set(_s(CallDirection.outgoing, CallState.connecting));
      await two(tester);
      expect(find.text('Calling…'), findsOneWidget);
      CallScreen.visibleCallId = 'c1';
      await tester.pump();
      expect(find.byKey(const ValueKey('call_strip_303')), findsNothing);
      CallScreen.visibleCallId = null;
      await tester.pump();
      expect(find.byKey(const ValueKey('call_strip_303')), findsOneWidget);
    });

    testWidgets('not attached = no card (widget tests, old bars stay)', (tester) async {
      CallStrip303.detachForTest();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => CallStrip303.wrap(child!),
        home: const Scaffold(body: Text('Chats')),
      ));
      expect(CallStrip303.attached, isFalse);
      expect(find.byKey(const ValueKey('call_strip_303')), findsNothing);
    });

    for (final dark in [false, true]) {
      testWidgets('picture ${dark ? 'dark' : 'light'}', (tester) async {
        if (_out == null) return;
        tester.view.physicalSize = const Size(360, 230);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final st in [
          _s(CallDirection.incoming, CallState.ringing),
          _s(CallDirection.outgoing, CallState.connected, answered: DateTime.now().subtract(const Duration(seconds: 83))),
        ]) {
          final key = GlobalKey();
          gw = _Gw();
          calls = CallBloc(service: gw, repository: _Repo());
          CallStrip303.attach(calls, () {});
          await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? LocalLinkTheme.dark() : LocalLinkTheme.light(),
              builder: (context, child) => CallStrip303.wrap(child!),
              home: Scaffold(
                  appBar: AppBar(title: const Text('ayesha')),
                  body: const Align(alignment: Alignment.bottomCenter, child: Text('are you free?'))),
            ),
          ));
          gw.set(st);
          await two(tester);
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final name = st.answeredAt == null ? 'ring' : 'live';
          await tester.runAsync(() async {
            final img = await boundary.toImage(pixelRatio: 2);
            final png = await img.toByteData(format: ui.ImageByteFormat.png);
            File('$_out/strip303_${name}_${dark ? 'dark' : 'light'}.png').writeAsBytesSync(png!.buffer.asUint8List());
          });
          CallStrip303.detachForTest();
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  });

  group('speaker + proximity (D, E)', () {
    test('both calls start on the earpiece; the sensor follows the speaker', () {
      final m = _src('lib/features/calls/data/services/call_session_manager.dart');
      expect('speakerOn: false,'.allMatches(m).length, 2);
      expect(m, isNot(contains('      speakerOn: true,\n      directMode: true,')));
      // Sensor only at the ear (speaker off, no video) - Bundle 143 rule kept.
      expect(m, contains('!s.videoEnabled &&\n        !s.peerVideoActive &&\n        !s.speakerOn;'));
      // The route at call start follows the session (earpiece / headset).
      expect(_src('lib/features/calls/data/transport/native_mesh_call_transport.dart'),
          contains('audio.setSpeakerphoneOn(session.speakerOn),'));
    });

    test('the sensor result is logged; unsupported phones show it', () {
      final dart = _src('lib/features/calls/data/platform/call_audio_platform_service.dart');
      expect(dart, contains("AppLogger.info('CALL_PROXIMITY',"));
      final kt = _src('android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt');
      expect(kt, contains('result.success(setCallProximity(inCall && proximity))'));
      expect(kt, contains('PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return "unsupported"'));
    });
  });

  group('ring screen rules (source)', () {
    final app = _src('lib/app/local_link_app.dart');
    test('A: opens when resumed OR inactive; skip reasons are logged', () {
      expect(app, contains('_lifecycleState == AppLifecycleState.resumed ||\n      _lifecycleState == AppLifecycleState.inactive;'));
      expect(app, contains("_skip303('app_\${_lifecycleState.name}', session.id);"));
      expect(app, contains("AppLogger.info('CALL_SCREEN_SKIP', detail: 'reason=\$reason call=\$callId');"));
      // The old hard "resumed only" gate is gone from the ring screen path.
      final body = app.substring(app.indexOf('void _maybeShowIncomingCall() {'), app.indexOf('Bundle 303: the ring screen always opens'));
      expect(body, isNot(contains('_lifecycleState != AppLifecycleState.resumed')));
    });

    test('A: a leftover id is cleared; retry every second while ringing', () {
      expect(app, contains('if (CallScreen.visibleCallId != _shownIncomingCallId) {'));
      expect(app, contains('reason=leftover_cleared'));
      expect(app, contains('_ringRetry303 ??= Timer.periodic(const Duration(seconds: 1), (_) {'));
      expect(app, contains('_ringRetry303?.cancel();\n    unawaited(_callSub?.cancel());'));
    });

    test('B: the strip is in the app builder and replaces the old bars + chip', () {
      expect(app, contains('CallStrip303.wrap(\n            CrownTapScope290(child: child ?? const SizedBox.shrink())),'));
      expect(app, contains('CallStrip303.attach(_deps.calls, _openCallFromStrip303);'));
      expect(_src('lib/features/home/presentation/screens/home_screen.dart'),
          contains('if (session == null || session.isFinished || CallStrip303.attached) {'));
      expect(_src('lib/features/calls/presentation/screens/calls_screen.dart'),
          contains('if (session == null || session.isFinished || CallStrip303.attached) {'));
      expect(_src('lib/features/messaging/presentation/screens/chat_screen.dart'), contains('CallStrip303.attached) {'));
    });

    test('C: inactive counts as on screen for the call notification', () {
      expect(_src('lib/features/calls/data/services/call_session_manager.dart'),
          contains('_appInForeground = state == AppLifecycleState.resumed ||\n        state == AppLifecycleState.inactive;'));
    });
  });
}
