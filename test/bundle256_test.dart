import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/utils/phone_rule_256.dart';
import 'package:locallink/features/authentication/bloc/authentication_bloc.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/data/services/offline_publish_ticker_256.dart';
import 'package:locallink/features/authentication/data/services/server_hint_256.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/connectivity/data/services/discovery_service.dart';
import 'package:locallink/features/directory/presentation/add_friend_256.dart';
import 'package:locallink/features/directory/presentation/nearby_status_256.dart';

class _Sock implements DiscoverySocket {
  _Sock(this.at, this.answer);
  final InternetAddress at;
  final bool answer;
  final sent = <String>[];
  final _out = StreamController<(List<int>, InternetAddress)>.broadcast();
  bool closed = false;

  @override
  void send(List<int> data, InternetAddress to, int port) {
    sent.add('${to.address}:$port');
    if (answer) {
      scheduleMicrotask(() => _out.add((
            utf8.encode(jsonEncode({'name': 'LinkUp', 'port': 8080})),
            InternetAddress('192.168.18.27')
          )));
    }
  }

  @override
  Stream<(List<int>, InternetAddress)> get replies => _out.stream;

  @override
  void close() => closed = true;
}

class _Auth implements AuthenticationRepositoryContract {
  _Auth(this.prepareError);
  final Object? prepareError;
  final offline = <String>[];

  @override
  String generateUniqueDeviceName() => 'Phone';
  @override
  Future<void> prepareForAuthentication({required String deviceName}) async {
    if (prepareError != null) throw prepareError!;
  }

  @override
  Future<String> registerOffline(
      {required String username, required String password, String? pairingCode}) async {
    offline.add(username);
    return 'ABCDE-FGHIJ';
  }

  @override
  Future<void> completeOfflineLogin() async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('256 A1/A2 server search', () {
    test('no answer: 3 asks to the broadcast + the Wi-Fi subnet, from 2 sockets', () async {
      final socks = <_Sock>[];
      final d = DiscoveryService(
        localAddresses: () async => ['192.168.18.88'],
        wifiOn: () => true,
        bind: (at) async => (socks..add(_Sock(at, false))).last,
      );
      final out = await d.discover(timeout: const Duration(seconds: 3));
      expect(out, isEmpty);
      expect(socks.map((s) => s.at.address), ['0.0.0.0', '192.168.18.88']);
      for (final s in socks) {
        expect(s.sent.where((t) => t == '255.255.255.255:45454').length, 3);
        expect(s.sent.where((t) => t == '192.168.18.255:45454').length, 3);
        expect(s.closed, isTrue);
      }
    });

    test('stops right after the first answer', () async {
      final socks = <_Sock>[];
      final d = DiscoveryService(
        localAddresses: () async => ['10.0.0.5'],
        wifiOn: () => true,
        bind: (at) async => (socks..add(_Sock(at, true))).last,
      );
      final watch = Stopwatch()..start();
      final out = await d.discover();
      expect(out.single.address, 'http://192.168.18.27:8080');
      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(socks.first.sent.length, 2); // one ask only
    });

    test('Wi-Fi off: no wait and no socket', () async {
      var binds = 0;
      final d = DiscoveryService(
        localAddresses: () async => ['192.168.1.2'],
        wifiOn: () => false,
        bind: (at) async {
          binds++;
          return _Sock(at, true);
        },
      );
      final watch = Stopwatch()..start();
      expect(await d.discover(), isEmpty);
      expect(watch.elapsedMilliseconds, lessThan(200));
      expect(binds, 0);
    });

    test('no Wi-Fi address yet: waits, then searches when it comes', () async {
      var calls = 0;
      final socks = <_Sock>[];
      final d = DiscoveryService(
        localAddresses: () async => ++calls < 3 ? <String>[] : ['192.168.18.40'],
        wifiOn: () => true,
        bind: (at) async => (socks..add(_Sock(at, true))).last,
        wifiPoll: const Duration(milliseconds: 50),
      );
      final out = await d.discover();
      expect(out, hasLength(1));
      expect(calls, 3);
    });

    test('no Wi-Fi address at all: gives up after the wait', () async {
      final d = DiscoveryService(
        localAddresses: () async => <String>[],
        wifiOn: () => null,
        bind: (at) async => throw StateError('no bind'),
        wifiWait: const Duration(milliseconds: 300),
        wifiPoll: const Duration(milliseconds: 50),
      );
      final watch = Stopwatch()..start();
      expect(await d.discover(), isEmpty);
      expect(watch.elapsedMilliseconds, lessThan(1500));
    });

    test('helpers', () {
      expect(DiscoveryService.subnetBroadcast('192.168.18.88'), '192.168.18.255');
      expect(DiscoveryService.isPrivateIpv4('172.20.1.1'), isTrue);
      expect(DiscoveryService.isPrivateIpv4('8.8.8.8'), isFalse);
      expect(DiscoveryService.isPrivateIpv4('100.64.0.1'), isFalse);
    });
  });

  group('256 A4/A5 sign-up result', () {
    test('no server: phone-only account, and the screen is told', () async {
      final auth = _Auth(StateError('No LinkUp server is available on the local network.'));
      final bloc = AuthenticationBloc(auth, registerMode: true);
      final stages = <String?>[];
      final sub = bloc.stream.listen((s) => stages.add(s.stage));
      final out = await bloc.submit(username: 'ibrahim', password: 'password1');
      await Future<void>.delayed(Duration.zero);
      expect(out.offline, isTrue);
      expect(out.madeOffline, isTrue);
      expect(auth.offline, ['ibrahim']);
      expect(stages.first, 'search');
      expect(bloc.state.stage, isNull);
      await sub.cancel();
    });

    test('server answered with a problem: NO phone-only account', () async {
      final auth = _Auth(const ServerProblem256('This server is not the one this phone knows.'));
      final bloc = AuthenticationBloc(auth, registerMode: true);
      await expectLater(
          bloc.submit(username: 'ibrahim', password: 'password1'), throwsA(isA<ServerProblem256>()));
      expect(auth.offline, isEmpty);
      expect(bloc.state.error, 'This server is not the one this phone knows.');
      expect(bloc.state.busy, isFalse);
    });

    test('sign-in offline is not "made offline"', () {
      expect(const AuthOutcome.offline().madeOffline, isFalse);
      expect(const AuthOutcome.offline(madeOffline: true).madeOffline, isTrue);
    });
  });

  group('256 A3 server hint', () {
    setUp(ServerHint256.instance.resetForTest);

    test('sent once per 10 min per phone, only with a server + key', () {
      final h = ServerHint256.instance;
      final t = DateTime(2026, 11, 10, 13, 36);
      expect(h.payloadFor('p1', server: '', key: 'k', self: 'me', now: t), isNull);
      expect(h.payloadFor('p1', server: 'http://192.168.18.27:8080', key: '', self: 'me', now: t), isNull);
      final p = h.payloadFor('p1',
          server: 'http://192.168.18.27:8080', key: 'abcdefghijklmnop', self: 'me', now: t)!;
      expect(p['type'], 'server_hint_256');
      expect(p['key_tail'], 'ijklmnop');
      expect(h.payloadFor('p1', server: 'http://192.168.18.27:8080', key: 'k', self: 'me',
          now: t.add(const Duration(minutes: 5))), isNull);
      expect(h.payloadFor('p2', server: 'http://192.168.18.27:8080', key: 'k', self: 'me', now: t),
          isNotNull);
      expect(h.payloadFor('p1', server: 'http://192.168.18.27:8080', key: 'k', self: 'me',
          now: t.add(const Duration(minutes: 11))), isNotNull);
    });

    test('kept only when wanted and only a LAN address', () {
      final h = ServerHint256.instance;
      expect(h.take({'addr': 'http://192.168.18.27:8080'}, wanted: false), isFalse);
      expect(h.take({'addr': 'http://evil.example.com:8080'}, wanted: true), isFalse);
      expect(h.take({'addr': 'http://8.8.8.8:8080'}, wanted: true), isFalse);
      expect(h.address, isNull);
      expect(h.take({'addr': 'http://192.168.18.27:8080', 'key_tail': 'ijklmnop'}, wanted: true),
          isTrue);
      expect(h.take({'addr': 'http://192.168.18.27:8080', 'key_tail': 'ijklmnop'}, wanted: true),
          isFalse, reason: 'same address again is not new');
      expect(h.keyMatches('abcdefghijklmnop'), isTrue);
      expect(h.keyMatches('zzzz'), isFalse);
    });
  });

  group('256 B ticker', () {
    test('60 s for 10 min, then 5 min', () {
      var now = DateTime(2026, 11, 10, 13, 36);
      final t = OfflinePublishTicker256(clock: () => now);
      t.start((_) async {}, listenLifecycle: false);
      expect(t.gapSeconds, 60);
      expect(t.nextInSeconds, 60);
      now = now.add(const Duration(minutes: 11));
      expect(t.gapSeconds, 300);
      t.stop();
      expect(t.active, isFalse);
      expect(t.nextInSeconds, isNull);
    });

    test('nudges run the try; two close nudges run once', () async {
      final whys = <String>[];
      final t = OfflinePublishTicker256();
      t.start((why) async => whys.add(why), listenLifecycle: false);
      t.nudge('wifi_up');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      t.nudge('resume');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(whys, ['wifi_up']);
      expect(await t.tryNow(), isTrue);
      expect(whys, ['wifi_up', 'find_now']);
      t.stop();
      expect(await t.tryNow(), isFalse);
    });
  });

  group('256 D profile', () {
    test('same phone rule as the server', () {
      expect(normalizePhone256('0300 1234567'), '+923001234567');
      expect(normalizePhone256('923001234567'), '+923001234567');
      expect(normalizePhone256('+92 300 1234567'), '+923001234567');
      expect(normalizePhone256('0092-300-1234567'), '+923001234567');
      expect(normalizePhone256('3001234567'), isNull);
      expect(normalizePhone256('03001234'), isNull);
      expect(normalizePhone256('+92abc'), isNull);
      expect(phoneOk256(''), isTrue);
      expect(phoneOk256('12345'), isFalse);
    });

    test('server error words in the log', () {
      expect(serverErrorText256('{"error":"invalid phone number","ok":false}\n'),
          ' error="invalid phone number"');
      expect(serverErrorText256('<html>'), '');
      expect(serverErrorText256(''), '');
    });
  });

  group('256 E add friend', () {
    test('chips say why the list is empty (TECNO: Wi-Fi off, BT not allowed)', () {
      final chips = nearbyChips256(wifi: false, wifiDirectOn: true, ble: 'no_permission');
      expect(chips.map((c) => c.label), ['Wi-Fi off', 'Wi-Fi Direct on', 'Bluetooth not allowed']);
      expect(chips.map((c) => c.good), [false, true, false]);
      expect(nearbyChips256(wifi: null, wifiDirectOn: false, ble: 'unknown').map((c) => c.id), ['wd']);
    });

    test('phones stay 2 min after they leave', () {
      final kept = NearbyKept256<String>();
      kept.saw([(id: 'c71', name: 'Sajjad', peer: 'p')], 0);
      expect(kept.kept(10000, {'c71'}), isEmpty, reason: 'still shown');
      final k = kept.kept(40000, {});
      expect(k.single.name, 'Sajjad');
      expect(nearbySeenLabel256(k.single.ageMs), 'Seen 40 s ago');
      expect(kept.kept(40000, {'c71'}), isEmpty, reason: 'a friend now');
      expect(kept.kept(120000, {}), isEmpty);
      expect(kept.isEmpty, isTrue);
    });

    test('NEARBY_LIST line', () {
      expect(
          nearbyListLog256(shown: 0, lan: 0, wd: 0, ble: 0, kept: 2, wifi: false, bleState: 'on'),
          'shown=0 lan=0 wd=0 ble=0 kept=2 why_empty=wifi_off');
      expect(nearbyWhyEmpty256(shown: 0, wifi: true, ble: 'no_permission'), 'no_perm');
      expect(nearbyWhyEmpty256(shown: 1, wifi: false, ble: 'off'), '-');
    });

    test('status line and plain failure words', () {
      expect(addStatusText256(addStatus256(serverConnected: true, wifi: false)), 'Server connected');
      expect(addStatusText256(addStatus256(serverConnected: false, wifi: false)),
          'Wi-Fi off - using Wi-Fi Direct');
      expect(addStatusText256(addStatus256(serverConnected: false, wifi: null)),
          'No server - searching nearby phones');
      expect(friendAddFailText256(Exception('Contact has no active device')), contains('not known yet'));
      expect(friendAddFailText256(Exception('boom')), 'Could not add this person. Try again.');
    });
  });

  test('AuthResult import stays used', () => expect(AuthResult, isNotNull));
}
