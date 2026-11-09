// Bundle 227: the app jumped to the Welcome screen while logged in.
// F1 one start screen, F2 sign-out opens Welcome on purpose, F3 "back to
// Home first" stops at Home, F4 the call screen closes once and only itself.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/routing/app_router.dart';
import 'package:locallink/core/routing/app_routes.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' as call_bloc;
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/domain/call_gateway.dart';
import 'package:locallink/features/calls/domain/call_repository_contract.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';

Route<dynamic> _gen(RouteSettings s) => MaterialPageRoute<void>(
      settings: s,
      builder: (_) => s.name == AppRoutes.home
          ? const PopScope(canPop: false, child: Scaffold(body: Text('HOME')))
          : const Scaffold(body: Text('WELCOME')),
    );

Widget _app(GlobalKey<NavigatorState> key, {bool fixed = true}) => MaterialApp(
      navigatorKey: key,
      initialRoute: AppRoutes.home,
      onGenerateInitialRoutes:
          fixed ? (name) => AppRouter.oneStartScreen(name, _gen) : null,
      onGenerateRoute: _gen,
    );

Route<void> _page(String text) =>
    MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(text)));

class _Gateway implements CallGateway {
  final StreamController<CallSession?> sessionCtl =
      StreamController<CallSession?>.broadcast();
  final StreamController<List<CallRecord>> historyCtl =
      StreamController<List<CallRecord>>.broadcast();
  @override
  Stream<CallSession?> get sessionStream => sessionCtl.stream;
  @override
  Stream<List<CallRecord>> get historyStream => historyCtl.stream;
  @override
  CallSession? session;
  @override
  String? get selfDeviceId => 'me';
  @override
  void start() {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CallRepo implements CallRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _start = DateTime(2026, 11, 9, 10);

CallSession _call(CallState state, {String reason = '', DateTime? endedAt}) =>
    CallSession(
      id: 'call-1',
      peerId: 'peer-b',
      peerName: 'B',
      direction: CallDirection.outgoing,
      state: state,
      startedAt: _start,
      endedAt: endedAt,
      reason: reason,
    );

void main() {
  group('227-F1 one start screen', () {
    testWidgets('before: /home built a hidden Welcome under Home', (t) async {
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(_app(key, fixed: false));
      key.currentState!.popUntil((r) => r.isFirst);
      await t.pumpAndSettle();
      expect(find.text('WELCOME'), findsOneWidget, reason: 'the old bug');
    });

    testWidgets('now: only Home; popUntil(isFirst) stays on Home', (t) async {
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(_app(key));
      expect(find.text('HOME'), findsOneWidget);
      expect(key.currentState!.canPop(), isFalse, reason: 'Home is the root');
      key.currentState!.popUntil((r) => r.isFirst);
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('WELCOME'), findsNothing);
    });

    testWidgets('not logged in: only Welcome', (t) async {
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
        navigatorKey: key,
        initialRoute: AppRoutes.welcome,
        onGenerateInitialRoutes: (name) => AppRouter.oneStartScreen(name, _gen),
        onGenerateRoute: _gen,
      ));
      expect(find.text('WELCOME'), findsOneWidget);
      expect(key.currentState!.canPop(), isFalse);
    });
  });

  group('227-F3 notification tap / new friend chat', () {
    testWidgets('chat -> another chat from a tap -> back = Home', (t) async {
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(_app(key));
      key.currentState!.push(_page('CHAT A'));
      await t.pumpAndSettle();
      key.currentState!.popUntil(AppRouter.isHomeOrFirst);
      key.currentState!.push(_page('CHAT B'));
      await t.pumpAndSettle();
      expect(find.text('CHAT B'), findsOneWidget);
      key.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('WELCOME'), findsNothing);
    });

    testWidgets('after a fresh login (Home pushed by name) it stops at Home',
        (t) async {
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
        navigatorKey: key,
        initialRoute: AppRoutes.welcome,
        onGenerateInitialRoutes: (name) => AppRouter.oneStartScreen(name, _gen),
        onGenerateRoute: _gen,
      ));
      key.currentState!.pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
      await t.pumpAndSettle();
      key.currentState!.push(_page('CHAT'));
      key.currentState!.push(_page('PHOTO'));
      await t.pumpAndSettle();
      key.currentState!.popUntil(AppRouter.isHomeOrFirst);
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('227-F4 the call screen closes once, only itself', () {
    late _Gateway gateway;
    late call_bloc.CallBloc bloc;


    Future<GlobalKey<NavigatorState>> openCall(WidgetTester t,
        {bool fromNotification = false}) async {
      gateway = _Gateway();
      bloc = call_bloc.CallBloc(service: gateway, repository: _CallRepo())
        ..start();
      addTearDown(() async {
        await gateway.sessionCtl.close();
        await gateway.historyCtl.close();
      });
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(_app(key));
      if (fromNotification) key.currentState!.popUntil(AppRouter.isHomeOrFirst);
      key.currentState!.push(_page('CHAT'));
      await t.pumpAndSettle();
      final live = _call(CallState.connecting);
      gateway.session = live;
      key.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => CallScreen(controller: bloc, initialSession: live)));
      await t.pumpAndSettle();
      expect(find.byType(CallScreen), findsOneWidget);
      return key;
    }

    Future<void> hangUp(WidgetTester t) async {
      // What a real hang-up sends: ended, then saved (new end time), then
      // cleared - one update per frame.
      gateway.sessionCtl.add(_call(CallState.canceled));
      await t.pump(const Duration(milliseconds: 16));
      gateway.sessionCtl.add(
          _call(CallState.canceled, endedAt: _start.add(const Duration(seconds: 3))));
      await t.pump(const Duration(milliseconds: 16));
      gateway.sessionCtl.add(null);
      await t.pump(const Duration(milliseconds: 16));
      await t.pump(const Duration(seconds: 1)); // the 1 s ticker
      await t.pumpAndSettle();
    }

    testWidgets('A calls B from a chat and cuts: the chat stays', (t) async {
      await openCall(t);
      await hangUp(t);
      expect(find.byType(CallScreen), findsNothing);
      expect(find.text('CHAT'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      expect(find.text('Press back again to exit'), findsNothing);
    });

    testWidgets('chat opened from a notification: never Welcome', (t) async {
      await openCall(t, fromNotification: true);
      await hangUp(t);
      expect(find.text('CHAT'), findsOneWidget);
      expect(find.text('WELCOME'), findsNothing);
    });

    testWidgets('call ends while a box is open on top: both go, chat stays',
        (t) async {
      final key = await openCall(t);
      unawaited(showDialog<void>(
        context: key.currentState!.overlay!.context,
        builder: (_) => const AlertDialog(title: Text('Switch to video call?')),
      ));
      await t.pumpAndSettle();
      expect(find.text('Switch to video call?'), findsOneWidget);
      await hangUp(t);
      expect(find.text('Switch to video call?'), findsNothing);
      expect(find.byType(CallScreen), findsNothing);
      expect(find.text('CHAT'), findsOneWidget);
    });

    testWidgets('minimized call screen: the end closes nothing else',
        (t) async {
      final key = await openCall(t);
      key.currentState!.pop(); // Minimize
      await t.pumpAndSettle();
      expect(find.text('CHAT'), findsOneWidget);
      await hangUp(t);
      expect(find.text('CHAT'), findsOneWidget);
    });

    testWidgets('"no nearby connection" end: text held 2 s, then one close',
        (t) async {
      await openCall(t);
      gateway.sessionCtl.add(_call(CallState.ended, reason: 'no_nearby_connection'));
      await t.pump(const Duration(milliseconds: 16));
      gateway.sessionCtl.add(null);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(CallScreen), findsOneWidget, reason: 'still held');
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(find.byType(CallScreen), findsNothing);
      expect(find.text('CHAT'), findsOneWidget);
    });
  });

  group('227 source checks', () {
    final app = File('lib/app/local_link_app.dart').readAsStringSync();
    test('F1: one start screen in the real app', () {
      expect(app, contains('AppRouter.oneStartScreen(name, _router.onGenerateRoute)'));
    });
    test('F2: sign-out opens Welcome on purpose', () {
      final i = app.indexOf('Future<void> _signedOut() async {');
      final body = app.substring(i, app.indexOf('Future<void> _resetAccount()'));
      expect(body, contains('pushNamedAndRemoveUntil('));
      expect(body, contains('AppRoutes.welcome'));
      expect(body, contains('if (!mounted || _configured) return;'));
    });
    test('F3: no "popUntil(isFirst)" left in the app shell', () {
      expect(app, isNot(contains('popUntil((route) => route.isFirst)')));
      expect('popUntil(AppRouter.isHomeOrFirst)'.allMatches(app).length, 3);
    });
    test('F4: the call screen never uses maybePop to close at the end', () {
      final src = File('lib/features/calls/presentation/screens/call_screen.dart')
          .readAsStringSync();
      final b = src.substring(src.indexOf('if (session.isFinished && session.id'),
          src.indexOf('// Bundle 93: peer turned their camera on'));
      expect(b, isNot(contains('maybePop')));
      expect(b, contains('_closeOnce'));
    });
  });
}
