import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/identity/display_label.dart';
import 'package:locallink/core/identity/person_name_258.dart';
import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/network/session_dead_262.dart';
import 'package:locallink/core/network/tls_pin_243.dart';
import 'package:locallink/core/security/security_policy.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/core/widgets/session_dead_banner_262.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/p2p_pause_262.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';

/// Bundle 262 (11 Nov 19:57 logs): B (Wi-Fi Direct switched off by the
/// phone), C (HTTP only: "Keep http not https"), D (the server ended this
/// phone's sign-in: "Sign in again"), E (no "My LinkUp phone" as a name).
/// A (2.4 GHz groups) is in the Kotlin test Band262Test.
String _logs() => AppLogFile.instance.pendingForTest.join('\n');
String _src(String path) => File(path).readAsStringSync();

// ------------------------------------------------------ Wi-Fi Direct fakes

const _now = 1000000000;
final _me = NearbyTag.idFor('me');
const _a = 'aa:bb:cc:dd:ee:01';

NearbyTag _t(String address, String deviceId, {String? group, int seenAt = _now}) => NearbyTag(
      address: address,
      idHash: NearbyTag.idFor(deviceId),
      host: true,
      member: false,
      members: 0,
      full: false,
      groupAware: true,
      group: group ?? 'DIRECT-LL-$deviceId',
      key: 'pass-$deviceId-1234',
      wanted: const <String>[],
      seenAt: seenAt,
    );

Map<String, Object?> _event(NearbyTag t) => {
      'address': t.address,
      'id': t.idHash,
      'host': t.host,
      'member': t.member,
      'members': t.members,
      'full': t.full,
      'seen_at': t.seenAt,
      'gv': t.groupAware,
      if (t.group != null) 'group': t.group,
      if (t.key != null) 'key': t.key,
    };

class _WdRepo implements ConnectivityRepositoryContract, NearbyGroupControl {
  final StreamController<dynamic> events = StreamController.broadcast();
  WifiDirectConnection connection = const WifiDirectConnection(connected: false, groupOwner: false);
  final List<Map<String, Object?>> joins = [];
  int creates = 0;
  int searches = 0;

  @override
  Stream<dynamic> get wifiDirectEvents => events.stream;
  @override
  Future<void> connectWifiDirect(String address, {bool wantHost = false, bool allowLeaveGroup = true}) async {}
  @override
  Future<void> setNearbyIdentity(String tagId) async {}
  @override
  Future<WifiDirectConnection> wifiDirectConnectionInfo() async => connection;
  @override
  Future<List<WifiDirectPeer>> wifiDirectPeers() async => const [];
  @override
  Future<void> startWifiDirectDiscovery() async => searches += 1;
  @override
  Future<bool> isWifiDirectPermissionGranted() async => true;
  @override
  Future<bool> isWifiDirectSupported() async => true;
  @override
  Future<void> disconnectWifiDirect() async {}
  @override
  Future<void> setNearbyWanted(List<String> ids) async {}
  @override
  Future<void> createNearbyGroup() async => creates += 1;
  @override
  Future<void> joinNearbyGroup({String? name, String? key, required String address, bool leave = false}) async {
    joins.add({'name': name, 'address': address, 'leave': leave});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _tok = 'tok-mine-1';
Map<String, String> _mine() => {'Authorization': 'Bearer $_tok', 'X-Device-ID': 'd1'};

void main() {
  setUp(() {
    AppLogFile.instance.resetForTest();
    NameBook258.instance.resetForTest();
    NearbyTagRegistry.instance.resetForTest();
    SessionDead262.instance.resetForTest();
  });

  tearDown(() {
    TlsPin243.httpOnly262 = false;
    TlsPin243.setForTest();
    SessionDead262.instance.resetForTest();
  });

  // ============================================================ B
  group('B Wi-Fi Direct switched off by the phone', () {
    test('B-0 the pause rule', () {
      final p = P2pPause262();
      expect(p.apply(true, 0), '', reason: 'first ON is no change');
      expect(p.isOff(0), isFalse);
      expect(p.apply(false, 1000), 'off');
      expect(p.apply(false, 2000), '', reason: 'still off');
      expect(p.isOff(2000), isTrue);
      expect(p.waitLogOnce(), isTrue);
      expect(p.waitLogOnce(), isFalse, reason: 'one line per off time');
      expect(p.isOff(1000 + P2pPause262.maxOffMs), isFalse, reason: 'a missed ON never blocks for long');
      expect(p.apply(true, 43000), 'on');
      expect(p.offSeconds(43000), 42);
      expect(p.isOff(43000), isFalse);
    });

    late int now;
    late _WdRepo wd;
    late WifiDirectFallbackService service;

    Future<void> myGroup(String role, {String? name}) async {
      wd.events.add({'type': 'my_group', 'role': role, 'name': name, 'members': 0});
      await _settle();
    }

    Future<void> tags(List<NearbyTag> list) async {
      wd.events.add({'type': 'services', 'peers': [for (final t in list) _event(t)]});
      await _settle();
    }

    Future<void> p2p(bool on) async {
      wd.events.add({'type': 'state', 'enabled': on});
      await _settle();
    }

    setUp(() async {
      now = _now;
      wd = _WdRepo();
      service = WifiDirectFallbackService(wd,
          clock: () => now, random: _ZeroRandom(), groupTick: const Duration(hours: 1));
      service.groupPeerIds = () => const <String>[];
      await service.start();
      service.selfIdHash = _me;
    });

    tearDown(() => service.dispose());

    test('B-1 off: no join and no create while Wi-Fi Direct is off', () async {
      await myGroup('none');
      await p2p(false);
      expect(service.p2pOff262, isTrue);
      expect(_logs(), contains('group wait why=p2p_off'));
      final searches = wd.searches;
      for (var i = 0; i < 4; i++) {
        now += 20 * 1000;
        await tags([_t(_a, 'c71', seenAt: now)]);
      }
      expect(wd.joins, isEmpty, reason: 'every try would fail busy (TECNO 19:54)');
      expect(wd.creates, 0);
      expect(wd.searches, searches);
      expect('group wait why=p2p_off'.allMatches(_logs()).length, 1);
    });

    test('B-2 on: old marks cleared, the group is decided at once', () async {
      await myGroup('none');
      await tags([_t(_a, 'c71', group: 'DIRECT-LL-old', seenAt: now)]);
      expect(wd.joins.length, 1);
      // two failed joins = that host is "full" for 10 min
      now += 26 * 1000;
      await myGroup('none');
      for (var i = 0; i < 12 && wd.joins.length < 2; i++) {
        now += 10 * 1000;
        await tags([_t(_a, 'c71', group: 'DIRECT-LL-old', seenAt: now)]);
      }
      now += 26 * 1000;
      await myGroup('none');
      expect(service.joinCooling261, contains(_a));
      final joins = wd.joins.length;
      await p2p(false);
      now += 30 * 1000;
      await tags([_t(_a, 'c71', group: 'DIRECT-LL-old', seenAt: now)]);
      expect(wd.joins.length, joins);
      final searches = wd.searches;
      await p2p(true);
      expect(service.p2pOff262, isFalse);
      expect(_logs(), contains('group resume why=p2p_on off_s=30 cool_cleared n=1'));
      expect(service.joinCooling261, isEmpty);
      expect(wd.searches, greaterThan(searches), reason: 'a search starts at once');
      expect(wd.joins.length, joins + 1, reason: 'joined right away, not on the next tick');
    });

    test('B-3 the first ON report changes nothing', () async {
      await myGroup('none');
      await p2p(true);
      expect(_logs(), isNot(contains('group resume')));
      await tags([_t(_a, 'c71', seenAt: now)]);
      expect(wd.joins.length, 1);
    });
  });

  // ============================================================ C
  group('C HTTP only ("Keep http not https")', () {
    final sha = 'ab' * 32;

    test('C-1 a saved pin is never used: http and ws:// stay', () {
      TlsPin243.setForTest(host: '192.168.18.27', port: 8443, sha: sha, active: true, httpPort: 8080);
      expect(TlsPin243.active, isTrue, reason: 'bundle 243 rule without the switch');
      TlsPin243.httpOnly262 = true;
      expect(TlsPin243.active, isFalse);
      final u = SecurityPolicy.normalizeServerUri('192.168.18.27:8080');
      expect(u.toString(), 'http://192.168.18.27:8080');
      expect(TlsPin243.upgrade(Uri.parse('http://192.168.18.27:8080')).scheme, 'http');
      expect(TlsPin243.accepts([1, 2, 3], '192.168.18.27', 8443), isFalse);
      // a saved https address still goes back to the plain one
      expect(TlsPin243.downgrade('https://192.168.18.27:8443'), 'http://192.168.18.27:8080');
    });

    test('C-2 the app sets HTTP only before the pin loads, and never starts the HTTPS checks', () {
      final d = _src('lib/app/app_dependencies.dart');
      final bind = d.substring(d.indexOf('void bindServerReach()'));
      final on = bind.indexOf('TlsPin243.httpOnly262 = true;');
      expect(on, greaterThan(0));
      expect(on, lessThan(bind.indexOf('TlsPin243.load(store.readSetting)')));
      final start = d.substring(d.indexOf('void _startTls243()'), d.indexOf('/// Bundle 255 D1: HTTPS is on'));
      final early = start.indexOf('if (TlsPin243.httpOnly262) {');
      expect(early, greaterThan(0));
      expect(early, lessThan(start.indexOf('TlsUpgrade243(')));
      expect(start, contains("AppLogger.info('TLS_262', detail: 'mode=http_only');"));
      expect(start, contains('_wsPlainSwitch262();'));
      final sw = d.substring(d.indexOf('void _wsPlainSwitch262()'), d.indexOf('void _wssSwitch255()'));
      expect(sw, contains("now.startsWith('wss://')"));
      expect(sw, contains("next.startsWith('ws://')"));
      expect(sw, contains('callService.session != null'));
      expect(sw, contains("'from=wss to=ws'"));
      expect(sw, contains('api.connectRealtime()'));
      // background engine binds it too
      expect(_src('lib/app/background_runner.dart'), contains('deps.bindServerReach();'));
    });
  });

  // ============================================================ D
  group('D the server ended my sign-in', () {
    late DateTime clock;
    setUp(() {
      clock = DateTime(2026, 11, 11, 19, 43);
      SessionDead262.instance
        ..ownToken = (() => _tok)
        ..clock = (() => clock);
    });

    test('D-1 three 401s in a row for my token -> dead, logged once', () {
      final s = SessionDead262.instance;
      s.onHttp('/api/v1/contacts/sync', 401, _mine(), body: '{"error":"unauthorized"}');
      s.onHttp('/api/v1/sync', 401, _mine(), body: '{"error":"invalid device token"}');
      expect(s.dead, isFalse);
      s.fail('ws');
      expect(s.dead, isTrue);
      expect(_logs(), contains('SESSION_DEAD_262|n=3 first=/api/v1/contacts/sync'));
      s.fail('ws');
      expect('SESSION_DEAD_262|n='.allMatches(_logs()).length, 1);
    });

    test('D-2 a success between clears the count', () {
      final s = SessionDead262.instance;
      s.onHttp('/a', 401, _mine());
      s.onHttp('/a', 401, _mine());
      s.onHttp('/b', 200, _mine());
      s.onHttp('/a', 401, _mine());
      s.onHttp('/a', 401, _mine());
      expect(s.dead, isFalse);
    });

    test('D-3 admin keys, other tokens and a wrong password never count', () {
      final s = SessionDead262.instance;
      for (var i = 0; i < 5; i++) {
        s.onHttp('/api/v1/admin/x', 401, {'Authorization': 'Bearer admin-key'});
        s.onHttp('/api/v1/auth/login', 401, {'Content-Type': 'application/json'});
        s.onHttp('/api/v1/profile/rename', 401, _mine(),
            body: '{"code":"BAD_LOGIN","error":"invalid username or password"}');
        s.onHttp('/api/v1/x', 401, _mine(), body: '{"error":"invalid admin credentials"}');
      }
      expect(s.dead, isFalse);
      expect(SessionDead262.sessionWords('{"error":"device authentication required"}'), isTrue);
      expect(SessionDead262.sessionWords(''), isTrue);
      expect(SessionDead262.sessionWords('{"error":"username or recovery code is wrong"}'), isFalse);
    });

    test('D-4 while dead: one try per 10 min; a new token (sign in) ends it', () {
      final s = SessionDead262.instance;
      for (var i = 0; i < 3; i++) {
        s.onHttp('/a', 401, _mine());
      }
      expect(s.dead, isTrue);
      expect(() => s.check(_mine()), throwsA(isA<SessionDeadError262>()));
      s.check({'Authorization': 'Bearer admin-key'}); // not mine: goes out
      s.check(const {'Content-Type': 'application/json'}); // login: goes out
      clock = clock.add(const Duration(minutes: 10));
      s.check(_mine()); // the try
      expect(() => s.check(_mine()), throwsA(isA<SessionDeadError262>()));
      expect('${const SessionDeadError262()}', contains('unauthorized'));
      // signed in again (by the card or the login screen): a new token
      s.ownToken = () => 'tok-new-2';
      expect(s.dead, isFalse);
      s.check({'Authorization': 'Bearer tok-new-2'});
      expect(s.count, 0);
    });

    test('D-5 the HTTP client stops calling the server while dead', () async {
      var sent = 0;
      final client = ApiHttpClient(
          client: MockClient((r) async {
        sent++;
        return http.Response('{"error":"unauthorized"}', 401);
      }));
      final uri = Uri.parse('http://192.168.18.27:8080/api/v1/contacts/sync');
      for (var i = 0; i < 3; i++) {
        final r = await client.get(uri, headers: _mine());
        expect(r.statusCode, 401);
      }
      expect(SessionDead262.instance.dead, isTrue);
      await expectLater(client.get(uri, headers: _mine()), throwsA(isA<SessionDeadError262>()));
      expect(sent, 3, reason: 'no 4th call every 30 s (ZTE 19:43-19:57)');
    });

    test('D-6 the socket: 401 upgrade counts, ready clears, 10 min reconnect while dead', () {
      expect(
          wsUnauthorized262("WebSocketChannelException: WebSocketException: Connection to "
              "'https://192.168.18.27:8443/ws#' was not upgraded to websocket, HTTP status code: 401"),
          isTrue);
      expect(wsUnauthorized262('SocketException: Connection refused'), isFalse);
      final ws = _src('lib/core/services/websocket_service.dart');
      expect(ws, contains("if (error != null && wsUnauthorized262('\$error')) {"));
      expect(ws, contains("SessionDead262.instance.fail('ws');"));
      expect(ws, contains('SessionDead262.instance.ok(); // Bundle 262 (D)'));
      expect(ws, contains('final delay = SessionDead262.instance.dead\n        ? SessionDead262.backoff'));
      final b = _src('lib/core/network/build_http.dart');
      expect(b, contains('SessionDead262.instance.check(headers);'));
      expect(b, contains('SessionDead262.instance.check(request.headers); // Bundle 262 (D)'));
    });

    testWidgets('D-7 the card: Sign in again -> password -> normal login', (tester) async {
      final s = SessionDead262.instance;
      final tries = <String>[];
      var token = _tok;
      s
        ..ownToken = (() => token)
        ..signIn = (pwd) async {
          tries.add(pwd);
          if (pwd != 'right-pass') throw Exception('invalid username or password');
          token = 'tok-new';
          s.reset();
        };
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SessionDeadBanner262())));
      expect(find.byKey(const ValueKey('session_dead_banner_262')), findsNothing);
      for (var i = 0; i < 3; i++) {
        s.onHttp('/a', 401, {'Authorization': 'Bearer $token'});
      }
      await tester.pump();
      expect(find.byKey(const ValueKey('session_dead_banner_262')), findsOneWidget);
      expect(find.text(SessionDeadBanner262.text), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('session_dead_sign_in_262')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session_dead_go_262')));
      await tester.pump();
      expect(find.text('Type your password.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('session_dead_password_262')), 'wrong');
      await tester.tap(find.byKey(const ValueKey('session_dead_go_262')));
      await tester.pump();
      await tester.pump();
      expect(tries, ['wrong']);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'stays open on a wrong password');
      await tester.enterText(find.byKey(const ValueKey('session_dead_password_262')), 'right-pass');
      await tester.tap(find.byKey(const ValueKey('session_dead_go_262')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('session_dead_banner_262')), findsNothing);
    });

    test('D-8 the app binds my token + the sign-in, and the card is on the Chats tab', () {
      final d = _src('lib/app/app_dependencies.dart');
      expect(d, contains('..ownToken = (() => store.deviceToken)'));
      expect(d, contains('..signIn = _signInAgain262;'));
      final fn = d.substring(d.indexOf('Future<void> _signInAgain262('));
      expect(fn.substring(0, 900), contains('await api.loginAccount('));
      expect(fn.substring(0, 900), contains('SessionDead262.instance.reset();'));
      final home = _src('lib/features/home/presentation/screens/home_screen.dart');
      expect(home.indexOf('const SessionDeadBanner262(),'), greaterThan(home.indexOf('const AdminBlockedBanner(),')));
    });
  });

  // ============================================================ E
  group('E no "My LinkUp phone" as a person name', () {
    test('E-1 a default phone name -> the username', () {
      expect(displayNameFromProfile({'display_name': 'My LinkUp phone', 'username': 'alex'}), 'alex');
      expect(displayNameFromProfile({'display_name': 'My Android Phone (ed16a834)', 'username': 'alex'}), 'alex');
      expect(displayNameFromProfile({'display_name': 'My LinkUp phone', 'username': ''}), isNull);
      expect(displayNameFromProfile({'display_name': 'Alex Khan', 'username': 'alex'}), 'Alex Khan');
    });

    test('E-2 the name book never keeps a default label; a custom name wins', () {
      final book = NameBook258.instance;
      book.remember('My LinkUp phone', ['d-zte']);
      expect(book.lastKnown('d-zte'), isNull);
      book.debugNames['d-old'] = 'My LinkUp phone'; // kept by an older version
      expect(book.lastKnown('d-old'), isNull);
      expect(book.pick(profile: {'display_name': 'My LinkUp phone', 'username': 'alex', 'device_id': 'd-zte'}),
          'alex');
      expect(book.lastKnown('d-zte'), 'alex');
      expect(
          book.pick(custom: 'Alex ZTE', profile: {'display_name': 'My LinkUp phone', 'username': 'alex'}),
          'Alex ZTE');
    });
  });
}
