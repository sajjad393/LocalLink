// Bundle 265: small safety fixes from the 12 Nov review.
// R1 the server-search reply can only point at itself or a private address,
// C1 a UDP send of 0 bytes is an error, C2 a left-over background lease is
// taken over by the app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/connectivity/data/services/discovery_service.dart';

class _Sock implements DiscoverySocket {
  _Sock(this.at, {this.throwOnSend = false, this.replyHost});
  final InternetAddress at;
  final bool throwOnSend;
  final String? replyHost;
  final _out = StreamController<(List<int>, InternetAddress)>.broadcast();

  @override
  void send(List<int> data, InternetAddress to, int port) {
    if (throwOnSend) throw const SocketException('not sent');
    if (replyHost != null) {
      scheduleMicrotask(() => _out.add((
            utf8.encode(jsonEncode({'name': 'LinkUp', 'port': 8080, 'host': replyHost})),
            InternetAddress('192.168.1.22')
          )));
    }
  }

  @override
  Stream<(List<int>, InternetAddress)> get replies => _out.stream;

  @override
  void close() {}
}

class _Store implements LocalStore {
  final settings = <String, String>{};
  bool waiting = true;
  @override
  bool get isOfflinePending => waiting;
  @override
  Map<String, dynamic>? get offlinePending => waiting ? {'username': 'sumaira'} : null;
  @override
  String? get deviceName => 'ZTE';
  @override
  Future<String?> readOfflinePublishSecret() async => 'one-time-secret';
  @override
  Future<void> markAccountSynced() async => waiting = false;
  @override
  Future<LocalProfile?> profile() async => null;
  @override
  Future<void> writeRenamedAccountNotice(String username) async {}
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Result implements AuthResult {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Auth implements AuthenticationRepositoryContract {
  final tried = <String>[];
  Completer<void>? hold;
  @override
  Future<void> prepareForAuthentication({required String deviceName}) async {}
  @override
  Future<AuthResult> register({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) async {
    tried.add(username);
    if (hold != null) await hold!.future;
    return _Result();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

String _logs() => AppLogFile.instance.pendingForTest.join('\n');

void main() {
  group('A R1 reply host', () {
    final sender = InternetAddress('192.168.1.22');
    test('1 a public host -> the sender, marked ignored', () {
      final s = DiscoveredServer.fromJson({'host': '203.0.113.5', 'port': 8080}, sender);
      expect(s.host, '192.168.1.22');
      expect(s.hostIgnored, isTrue);
    });
    test('2 a private host and the same-as-sender host are kept', () {
      final a = DiscoveredServer.fromJson(
          {'host': '192.168.18.27', 'port': 8080}, InternetAddress('192.168.18.30'));
      expect(a.host, '192.168.18.27');
      expect(a.hostIgnored, isFalse);
      final b = DiscoveredServer.fromJson({'host': '192.168.1.22'}, sender);
      expect(b.host, '192.168.1.22');
      expect(b.hostIgnored, isFalse);
      final c = DiscoveredServer.fromJson({'host': '10.0.2.2'}, sender);
      expect(c.host, '10.0.2.2');
      final d = DiscoveredServer.fromJson({'host': '172.20.1.1'}, sender);
      expect(d.host, '172.20.1.1');
    });
    test('3 no host -> the sender, not ignored', () {
      final s = DiscoveredServer.fromJson({'port': 9000}, sender);
      expect(s.address, 'http://192.168.1.22:9000');
      expect(s.hostIgnored, isFalse);
    });
    test('4 a host name -> the sender', () {
      final s = DiscoveredServer.fromJson({'host': 'evil.example'}, sender);
      expect(s.host, '192.168.1.22');
      expect(s.hostIgnored, isTrue);
      expect(DiscoveredServer.privateIpv4('172.32.0.1'), isFalse);
      expect(DiscoveredServer.privateIpv4('192.168.1'), isFalse);
      expect(DiscoveredServer.privateIpv4('192.168.1.300'), isFalse);
    });
  });

  group('B C1 send count', () {
    test('5 checkSent', () {
      expect(() => DiscoveryService.checkSent(0), throwsA(isA<SocketException>()));
      expect(() => DiscoveryService.checkSent(-1), throwsA(isA<SocketException>()));
      DiscoveryService.checkSent(19);
    });
    test('6 every send fails -> sent=0, reason=socket_error', () async {
      AppLogFile.instance.resetForTest();
      final d = DiscoveryService(
        localAddresses: () async => ['192.168.18.88'],
        wifiOn: () => true,
        bind: (at) async => _Sock(at, throwOnSend: true),
      );
      final out = await d.discover(timeout: const Duration(milliseconds: 1200));
      expect(out, isEmpty);
      final l = _logs();
      expect(l, contains('try n=1 sent=0'));
      expect(l, contains('none reason=socket_error'));
    });
    test('7 public host in a reply -> one host_ignored line, the sender is used', () async {
      AppLogFile.instance.resetForTest();
      final d = DiscoveryService(
        localAddresses: () async => ['192.168.1.30'],
        wifiOn: () => true,
        bind: (at) async => _Sock(at, replyHost: '8.8.8.8'),
      );
      final out = await d.discover();
      expect(out.single.address, 'http://192.168.1.22:8080');
      expect(_logs(), contains('host_ignored from=192.168.1.22'));
      expect(_logs(), isNot(contains('8.8.8.8')));
    });
  });

  group('C C2 left-over background lease', () {
    late _Store store;
    late _Auth auth;
    late List<String> log;
    setUp(() {
      OfflineAccountSyncService.resetForTest();
      store = _Store();
      auth = _Auth();
      log = [];
      offlineAccountLogHook216 = (step, detail) => log.add('$step $detail');
    });
    tearDown(() {
      offlineAccountLogHook216 = null;
      OfflineAccountSyncService.resetForTest();
    });
    OfflineAccountSyncService svc() => OfflineAccountSyncService(store: store, auth: auth);
    String soon() => '${DateTime.now().add(const Duration(seconds: 60)).millisecondsSinceEpoch}';

    test('8 a |bg lease is taken over by the app', () async {
      store.settings[OfflineAccountSyncService.leaseKey] = '${soon()}|bg';
      await svc().autoPublish(from: 'home');
      expect(auth.tried, ['sumaira']);
      expect(log, contains('LEASE cleared=bg'));
      expect(log.any((l) => l.startsWith('BUSY')), isFalse);
    });
    test('9 a |bg lease still blocks the background engine', () async {
      store.settings[OfflineAccountSyncService.leaseKey] = '${soon()}|bg';
      await svc().autoPublish(from: 'background');
      expect(auth.tried, isEmpty);
      expect(log.any((l) => l.startsWith('BUSY')), isTrue);
    });
    test('10 an untagged lease blocks the app (unchanged)', () async {
      store.settings[OfflineAccountSyncService.leaseKey] = soon();
      await svc().autoPublish();
      expect(auth.tried, isEmpty);
      expect(log.any((l) => l.startsWith('BUSY')), isTrue);
      expect(log.any((l) => l.startsWith('LEASE')), isFalse);
    });
    test('11 background writes |bg while running, the app writes no tag', () async {
      auth.hold = Completer<void>();
      final a = svc().autoPublish(from: 'background');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.settings[OfflineAccountSyncService.leaseKey], endsWith('|bg'));
      auth.hold!.complete();
      await a;
      expect(store.settings[OfflineAccountSyncService.leaseKey], '0');
      OfflineAccountSyncService.resetForTest();
      store.waiting = true;
      auth.hold = Completer<void>();
      final b = svc().autoPublish(from: 'home');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final v = store.settings[OfflineAccountSyncService.leaseKey]!;
      expect(v.contains('|'), isFalse);
      expect(int.parse(v), greaterThan(DateTime.now().millisecondsSinceEpoch));
      auth.hold!.complete();
      await b;
    });
  });

  test('12 source: first-trust log before the single trust call, order kept', () {
    final s = File('lib/features/authentication/data/repositories/authentication_repository.dart')
        .readAsStringSync();
    final log = s.indexOf("AppLogger.info('SERVER_FIRST_TRUST'");
    final trust = s.indexOf('await trustServer(info);');
    expect(log, greaterThan(0));
    expect(trust, greaterThan(log));
    expect('await trustServer(info);'.allMatches(s).length, 1);
    final check = s.indexOf('ServerProof231.check(');
    final pin = s.indexOf('ServerProof231.pin(');
    expect(check, lessThan(trust));
    expect(trust, lessThan(pin));
  });
}
