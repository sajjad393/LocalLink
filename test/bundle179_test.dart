// Bundle 179: notification Accept answers once (saved 60 s), files wait
// during a voice call, STATUS call alerts line, Realme/Oppo tip.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/features/calls/data/models/call_notification_action.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/services/call_notification_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_session_manager.dart';
import 'package:locallink/features/files/data/services/media_progress_hub.dart';
import 'package:locallink/features/files/presentation/widgets/blue_progress_ring.dart';
import 'package:locallink/features/home/domain/background_brand_guide.dart';
import 'package:locallink/features/home/presentation/widgets/background_status_card.dart';

import 'call_handover_176_test.dart'
    show Harness, FakeHandover, installChannelMocks, notificationCalls;
import 'support/phase5_fakes.dart' show pumpEvents;

/// What the Android side has saved for the notification Accept.
Map<String, Object?>? savedAccept;
final List<String> clearedAccepts = <String>[];

void mockSavedAccept() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('locallink/call_notifications'), (call) async {
    notificationCalls.add(call);
    if (call.method == 'acceptedCall') return savedAccept;
    if (call.method == 'clearAcceptedCall') {
      final id = (call.arguments as Map)['call_id']?.toString() ?? '';
      clearedAccepts.add(id);
      if (savedAccept?['call_id'] == id) savedAccept = null;
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    notificationCalls.clear();
    clearedAccepts.clear();
    savedAccept = null;
    installChannelMocks();
    mockSavedAccept();
  });
  tearDown(() {
    CallSessionManager.coldAcceptWindow = const Duration(seconds: 60);
  });

  group('179 (2): Accept answers once', () {
    test('the wait for a late call is now 60 s', () {
      expect(CallSessionManager.coldAcceptWindow, const Duration(seconds: 60));
    });

    test('screen rebuilt (Accept event lost): the saved Accept answers the '
        'handed-over call', () async {
      final slot = FakeHandover();
      final closed = await Harness.create(handover: slot, background: true);
      closed.invite('call-z1');
      await pumpEvents();
      // Accept was tapped; Android saved it, but the event never reached
      // the new app engine (screen rebuilt on a slow phone).
      savedAccept = <String, Object?>{
        'call_id': 'call-z1',
        'caller_id': 'peer-1',
        'remaining_ms': 55000,
      };
      final app = await Harness.create(handover: slot);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(app.manager.session?.id, 'call-z1');
      expect(app.manager.session?.state, isNot(CallState.ringing));
      expect(app.manager.session?.isFinished, isFalse);
      expect(app.sentOfType('call_accept'), hasLength(1));
      expect(clearedAccepts, contains('call-z1'));
      await app.dispose();
      await closed.dispose();
    });

    test('Accept first, the call arrives later (re-sent invite): answered once',
        () async {
      final h = await Harness.create();
      h.notifications.act(CallNotificationActionType.accept, 'call-z2');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(h.manager.session, isNull);
      h.invite('call-z2');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(h.manager.session?.id, 'call-z2');
      expect(h.manager.session?.state, isNot(CallState.ringing));
      expect(h.sentOfType('call_accept'), hasLength(1));
      // A second Accept (event + saved copy) does not answer twice.
      h.notifications.act(CallNotificationActionType.accept, 'call-z2');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(h.sentOfType('call_accept'), hasLength(1));
      await h.dispose();
    });

    test('a saved Accept never answers a different call', () async {
      savedAccept = <String, Object?>{
        'call_id': 'call-old',
        'caller_id': 'peer-1',
        'remaining_ms': 50000,
      };
      final h = await Harness.create();
      h.invite('call-new');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(h.manager.session?.id, 'call-new');
      expect(h.manager.session?.state, CallState.ringing);
      expect(h.sentOfType('call_accept'), isEmpty);
      await h.dispose();
    });

    test('an old finished call on file does not block the Accept for the new '
        'call', () async {
      final h = await Harness.create();
      h.invite('call-a');
      await pumpEvents();
      h.notifications.act(CallNotificationActionType.reject, 'call-a');
      await pumpEvents();
      expect(h.manager.session?.isFinished, isTrue);
      final notices = <String>[];
      final sub = h.manager.callUnavailableNotices.listen(notices.add);
      h.notifications.act(CallNotificationActionType.accept, 'call-b');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      h.invite('call-b');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(h.manager.session?.id, 'call-b');
      expect(h.manager.session?.state, isNot(CallState.ringing));
      expect(notices, isEmpty);
      await sub.cancel();
      await h.dispose();
    });

    test('saved Accept with no call before it runs out: notice + forgotten',
        () async {
      savedAccept = <String, Object?>{
        'call_id': 'call-gone',
        'caller_id': 'peer-1',
        'remaining_ms': 250,
      };
      final h = await Harness.create();
      final notices = <String>[];
      final sub = h.manager.callUnavailableNotices.listen(notices.add);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(notices, contains('call-gone'));
      expect(clearedAccepts, contains('call-gone'));
      await sub.cancel();
      await h.dispose();
    });

    test('Reject forgets the saved Accept', () async {
      final h = await Harness.create();
      h.invite('call-r');
      await pumpEvents();
      h.notifications.act(CallNotificationActionType.reject, 'call-r');
      await pumpEvents();
      expect(clearedAccepts, contains('call-r'));
      await h.dispose();
    });

    test('SavedCallAccept.fromMap', () {
      expect(SavedCallAccept.fromMap(null), isNull);
      expect(
          SavedCallAccept.fromMap(<Object?, Object?>{
            'call_id': 'c',
            'caller_id': 'p',
            'remaining_ms': 0,
          }),
          isNull);
      expect(
          SavedCallAccept.fromMap(
              <Object?, Object?>{'call_id': '', 'caller_id': 'p', 'remaining_ms': 5}),
          isNull);
      final s = SavedCallAccept.fromMap(<Object?, Object?>{
        'call_id': 'c',
        'caller_id': 'p',
        'remaining_ms': 99999,
      })!;
      expect(s.remaining, const Duration(seconds: 60));
      expect(s.action.type, CallNotificationActionType.accept);
      expect(s.action.callId, 'c');
      expect(s.action.callerId, 'p');
    });
  });

  group('179 (1.6): files wait during a voice call', () {
    setUp(() => MediaProgressHub.instance.resetForTest());

    test('paused keeps the numbers; resumed goes on', () {
      final hub = MediaProgressHub.instance;
      hub.update('m1', done: 3, total: 10);
      hub.setPaused('m1', true);
      expect(hub.peek('m1')?.paused, isTrue);
      expect(hub.peek('m1')?.done, 3);
      hub.update('m1', done: 4, total: 10);
      expect(hub.peek('m1')?.paused, isTrue, reason: 'still waiting');
      hub.setPaused('m1', false);
      expect(hub.peek('m1')?.paused, isFalse);
      expect(hub.peek('m1')?.done, 4);
    });

    test('paused before any number, then resumed: back to the turning ring',
        () {
      final hub = MediaProgressHub.instance;
      hub.setPaused('m2', true);
      expect(hub.peek('m2')?.paused, isTrue);
      hub.setPaused('m2', false);
      expect(hub.peek('m2'), isNull);
      hub.setPaused('m3', false);
      expect(hub.peek('m3'), isNull);
    });

    testWidgets('ring shows the pause sign instead of the percent',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: TransferPercentRing(fraction: 0.45, paused: true))),
      ));
      expect(find.byKey(const Key('transfer_paused')), findsOneWidget);
      expect(find.text('45%'), findsNothing);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(child: TransferPercentRing(fraction: 0.45))),
      ));
      expect(find.byKey(const Key('transfer_paused')), findsNothing);
      expect(find.text('45%'), findsOneWidget);
    });
  });

  group('179 (3): STATUS call alerts line', () {
    Future<void> pump(WidgetTester tester, String? state,
        {VoidCallback? onFix}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BackgroundStatusCard(
            running: true,
            notifications: true,
            onStart: () {},
            onAllowNotifications: () {},
            nearby: 'on',
            callAlerts: state,
            onFixCallAlerts: onFix,
          ),
        ),
      ));
    }

    Color edge(WidgetTester tester) {
      final box = tester
          .widget<Container>(
              find.byKey(const ValueKey('background-status-card')))
          .decoration! as BoxDecoration;
      return (box.border! as Border).top.color;
    }

    testWidgets('all good: green "Call alerts on", not tappable',
        (tester) async {
      var taps = 0;
      await pump(tester, 'ok', onFix: () => taps++);
      expect(find.text('Call alerts on'), findsOneWidget);
      expect(find.text('Calls ring with Accept / Reject'), findsOneWidget);
      expect(edge(tester), BackgroundStatusCard.green);
      await tester.tap(find.text('Call alerts on'));
      expect(taps, 0);
    });

    testWidgets('category off: red line, red card, tap opens settings',
        (tester) async {
      var taps = 0;
      await pump(tester, 'category_off', onFix: () => taps++);
      expect(find.text('Call alerts off - tap to turn on'), findsOneWidget);
      expect(find.text('Calls ring, but no Accept button'), findsOneWidget);
      expect(edge(tester), BackgroundStatusCard.red);
      await tester.tap(find.text('Call alerts off - tap to turn on'));
      expect(taps, 1);
    });

    testWidgets('full screen off: orange line, card stays green, tappable',
        (tester) async {
      var taps = 0;
      await pump(tester, 'lockscreen_off', onFix: () => taps++);
      expect(find.text('Lock-screen calls off - turn on'), findsOneWidget);
      expect(edge(tester), BackgroundStatusCard.green);
      await tester.tap(find.text('Lock-screen calls off - turn on'));
      expect(taps, 1);
    });

    testWidgets('no row when unknown or when the Notifications row covers it',
        (tester) async {
      for (final s in <String?>[null, 'permission', 'app_off', 'weird']) {
        await pump(tester, s);
        expect(find.byKey(const ValueKey('background-status-call-alerts')),
            findsNothing,
            reason: '$s');
      }
    });

    testWidgets('row order: Running, Notifications, Nearby, Call alerts',
        (tester) async {
      await pump(tester, 'ok');
      final y = <double>[
        tester.getTopLeft(find.text('Running now')).dy,
        tester.getTopLeft(find.text('Notifications on')).dy,
        tester.getTopLeft(find.text('Nearby while closed: On')).dy,
        tester.getTopLeft(find.text('Call alerts on')).dy,
      ];
      for (var i = 1; i < y.length; i++) {
        expect(y[i], greaterThan(y[i - 1]));
      }
    });
  });

  test('179 (3.6): Realme / Oppo tip mentions notifications', () {
    final oppo = backgroundBrandByKey('oppo');
    expect(
        oppo.steps.any((s) =>
            s.contains('Notifications') &&
            s.contains('Banners') &&
            s.contains('Full-screen')),
        isTrue);
  });
}
