import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/diagnostics/tap_burst_counter.dart';
import 'package:locallink/core/security/server_proof_231.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/authentication/bloc/authentication_bloc.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/data/repositories/authentication_repository.dart';
import 'package:locallink/features/authentication/data/services/server_hint_256.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/domain/login_problem_321.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

// Bundle 321 Phase 1: the true login reason + a code, the step line, logs
// before sign-in, the address saved only after it passes, Reset keeps the
// last address and the last hour of logs, a second search round, the saved
// address asked while the search runs.

ApiError218 _api(int status, String msg, {String code = '', String minVersion = ''}) =>
    ApiError218(msg, status: status, code: code, minVersion: minVersion);

// ---------------------------------------------------------------- bloc fakes

class _Auth implements AuthenticationRepositoryContract {
  _Auth({this.prepareError, this.loginError});
  Object? prepareError;
  Object? loginError;
  final String address = 'http://192.168.18.27:8080';
  int offlineTries = 0;
  bool offlineOk = false;
  String reason = 'no_copy';
  Completer<void>? gate;

  @override
  String? get serverAddress => address;
  @override
  String generateUniqueDeviceName() => 'Phone';
  @override
  Future<void> prepareForAuthentication({required String deviceName}) async {
    if (gate != null) await gate!.future;
    if (prepareError != null) throw prepareError!;
  }

  @override
  Future<AuthResult> login(
      {required String username,
      required String password,
      required String deviceName,
      String? pairingCode}) async {
    if (loginError != null) throw loginError!;
    throw StateError('not used');
  }

  @override
  bool verifyOfflineLogin(String username, String password) {
    offlineTries++;
    return offlineOk;
  }

  @override
  bool verifyOfflineRecovery(String username, String recoveryCode) => false;
  @override
  Future<void> completeOfflineLogin() async {}
  @override
  Future<void> ensureOfflineProfileSeed() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Auth278 extends _Auth implements OfflineLoginReason278 {
  _Auth278({super.prepareError});
  @override
  Future<String> offlineLoginReason278(String username, String password) async {
    offlineTries++;
    return offlineOk ? 'ok' : reason;
  }
}

Future<AuthenticationBloc> _fail(_Auth auth) async {
  final bloc = AuthenticationBloc(auth);
  try {
    await bloc.submit(username: 'sajjad', password: 'pass-1234');
  } catch (_) {}
  return bloc;
}

// ---------------------------------------------------------- repository fakes

class _Store extends LocalStore {
  _Store({this.saved, this.last = ''});
  String? saved;
  String last;
  final settings = <String, String>{};
  final savedTo = <String>[];
  String? pin;

  @override
  String? get serverAddress => saved;
  @override
  String? get deviceId => 'dev-1';
  @override
  String? get serverFingerprint => pin;
  @override
  String? get serverId => null;
  @override
  Future<String> lastServer321() async => last;
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  Future<void> saveConfiguration(
      {required String server,
      required String id,
      required String name,
      String? token,
      String? accountId,
      String? username}) async {
    savedTo.add(server);
    saved = server;
  }

  @override
  Future<void> trustServer({required String serverId, required String fingerprint}) async =>
      pin = fingerprint;
}

class _ProbeApi implements LocalLinkApi {
  _ProbeApi(this.answers);
  final Map<String, Object> answers; // address -> PairingInfo | error
  final asked = <String>[];
  final askedAt = <String, DateTime>{};

  @override
  Future<PairingInfo> probePairingInfo(String server) async {
    asked.add(server);
    askedAt[server] = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final a = answers[server];
    if (a is PairingInfo) return a;
    if (a != null) throw a;
    throw const SocketException('No route to host', osError: OSError('No route to host', 113));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Net implements ConnectivityRepositoryContract {
  _Net(this.rounds, {this.delay = Duration.zero});
  final List<List<DiscoveredServer>> rounds;
  final Duration delay;
  int calls = 0;
  DateTime? firstAt;

  @override
  Future<List<DiscoveredServer>> discoverServers({Duration timeout = const Duration(seconds: 5)}) async {
    firstAt ??= DateTime.now();
    final i = calls++;
    await Future<void>.delayed(delay);
    return i < rounds.length ? rounds[i] : const [];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PairingInfo _info({String fp = 'FP1'}) => PairingInfo(
    service: 'locallink', version: '3', serverId: 's1', fingerprint: fp, name: 'PC', pairingRequired: false);

DiscoveredServer _found(String host) =>
    DiscoveredServer(host: host, port: 8080, name: 'PC', protocol: 'http');

const _a27 = 'http://192.168.18.27:8080';
const _a30 = 'http://192.168.18.30:8080';

List<String> _logs() => AppLogFile.instance.pendingForTest;

void main() {
  setUp(() {
    AppLogFile.instance.resetForTest();
    ServerHint256.instance.resetForTest();
  });

  group('L1 / L7 / L18 one code per failure (type + status, no word matching)', () {
    test('every HTTP status maps to its own code', () {
      LoginProblem321 of(Object e) => LoginProblem321.of(e, stage: 'login', address: _a27);
      expect(of(_api(401, 'invalid username or password', code: 'BAD_LOGIN')).code, 'L-03');
      expect(of(_api(429, 'account temporarily locked after repeated failed logins')).code, 'L-04');
      expect(of(_api(429, 'authentication rate limit exceeded')).code, 'L-05');
      expect(of(_api(403, 'device pairing is required', code: 'PAIRING_REQUIRED')).code, 'L-07');
      expect(of(_api(403, 'device is revoked and cannot re-authenticate')).code, 'L-08');
      expect(of(_api(403, 'account is not active')).code, 'L-09');
      expect(of(_api(426, 'update_required', minVersion: '3.0.112')).code, 'L-10');
      expect(of(_api(426, 'update_required', minVersion: '3.0.112')).words, contains('3.0.112'));
      expect(of(_api(500, 'failed to create login session')).code, 'L-11');
      expect(of(_api(409, 'device registration conflict')).code, 'L-11');
      expect(of(StateError(ServerProof231.identityChanged)).code, 'L-06');
    });

    test('network errors by type / errno; timeout differs per stage', () {
      LoginProblem321 of(Object e, String stage) => LoginProblem321.of(e, stage: stage, address: _a27);
      expect(of(const SocketException('x', osError: OSError('No route to host', 113)), 'verify').code, 'L-02a');
      expect(of(const SocketException('x', osError: OSError('Network is unreachable', 101)), 'verify').code,
          'L-02a');
      expect(of(const SocketException('x', osError: OSError('Connection refused', 111)), 'verify').code, 'L-02c');
      expect(of(TimeoutException('t'), 'verify').code, 'L-02b');
      expect(of(TimeoutException('t'), 'login').code, 'L-12');
      expect(of(http.ClientException('x'), 'verify').code, 'L-02a');
      expect(of(Exception('Server returned no session token'), 'login').code, 'L-11');
      expect(of(const FormatException('bad'), 'verify').code, 'L-11');
      final p = of(const SocketException('x', osError: OSError('No route', 113)), 'verify');
      expect(p.address, '192.168.18.27');
      expect(p.words, contains('192.168.18.27'));
      expect(p.codeLine, 'Code L-02a · 192.168.18.27');
      expect(const LoginProblem321('L-01').codeLine, 'Code L-01');
    });

    test('only network codes may open offline', () {
      for (final c in ['L-01', 'L-02a', 'L-02b', 'L-02c', 'L-12']) {
        expect(LoginProblem321(c).noServer, isTrue, reason: c);
      }
      for (final c in ['L-03', 'L-04', 'L-05', 'L-06', 'L-07', 'L-08', 'L-09', 'L-10', 'L-11']) {
        expect(LoginProblem321(c).noServer, isFalse, reason: c);
      }
    });
  });

  group('bloc', () {
    test('401: own words + code, never offline', () async {
      final auth = _Auth(loginError: _api(401, 'invalid username or password', code: 'BAD_LOGIN'));
      final bloc = await _fail(auth);
      expect(bloc.state.error, 'Wrong username or password.');
      expect(bloc.state.code, 'Code L-03 · 192.168.18.27');
      expect(auth.offlineTries, 0);
    });

    test('a server that answered 500 never says "could not connect" and never opens offline', () async {
      final auth = _Auth(loginError: _api(500, 'failed to commit login'))..offlineOk = true;
      final bloc = await _fail(auth);
      expect(bloc.state.error, isNot(contains('Could not connect')));
      expect(bloc.state.error, contains('code 500'));
      expect(bloc.state.code, 'Code L-11 · 192.168.18.27');
      expect(auth.offlineTries, 0);
    });

    test('a login timeout never says "retrying"', () async {
      final auth = _Auth(loginError: TimeoutException('t'));
      final bloc = await _fail(auth);
      expect(bloc.state.error!.toLowerCase(), isNot(contains('retrying')));
      expect(bloc.state.error, contains('did not finish signing in'));
      expect(bloc.state.code, startsWith('Code L-12'));
    });

    test('server timeout + saved copy -> offline, with the reason for Home (L-13 once)', () async {
      final auth = _Auth(prepareError: const LoginProblem321('L-02b', address: '192.168.18.27'))
        ..offlineOk = true;
      final bloc = AuthenticationBloc(auth);
      final out = await bloc.submit(username: 'sajjad', password: 'pass-1234');
      expect(out.offline, isTrue);
      expect(out.problem!.code, 'L-02b');
      final store = <String, String>{LoginNote321.key: out.problem!.code};
      Future<String?> read(String k) async => store[k];
      Future<void> write(String k, String v) async => store[k] = v;
      final note = await LoginNote321.take(read: read, write: write);
      expect(note, 'Signed in on this phone only - server not answering (L-02b). It connects by itself later.');
      expect(await LoginNote321.take(read: read, write: write), isNull, reason: 'shown once');
    });

    test('no copy + timeout -> server reason first, never "turn the server on"', () async {
      final auth = _Auth278(prepareError: const LoginProblem321('L-02b', address: '192.168.18.27'));
      final bloc = await _fail(auth);
      expect(bloc.state.error, startsWith('The server PC is not answering.'));
      expect(bloc.state.error, contains('no saved sign-in to open offline'));
      expect(bloc.state.error, isNot(contains('Turn the server on')));
      expect(bloc.state.code, 'Code L-02b · 192.168.18.27');
    });

    test('server down + wrong offline password: server reason first, then the copy', () async {
      final auth = _Auth278(prepareError: const LoginProblem321('L-02a', address: '192.168.18.27'))
        ..reason = 'bad_password';
      final bloc = await _fail(auth);
      expect(bloc.state.error, startsWith("This phone can't reach the server PC (192.168.18.27)"));
      expect(bloc.state.error, contains('do not match the copy saved on this phone'));
    });

    test('server problem (key changed) keeps its words, gets L-06, no offline', () async {
      final auth = _Auth(prepareError: const ServerProblem256('This server is not the one this phone knows.'))
        ..offlineOk = true;
      final bloc = await _fail(auth);
      expect(bloc.state.error, 'This server is not the one this phone knows.');
      expect(bloc.state.code, 'Code L-06');
      expect(auth.offlineTries, 0);
    });

    test('stage words: search, then found with the address; cleared at the end', () async {
      final auth = _Auth(loginError: _api(401, 'x', code: 'BAD_LOGIN'));
      final bloc = AuthenticationBloc(auth);
      final seen = <String>[];
      final sub = bloc.stream.listen((s) => seen.add('${s.stage}|${s.server}'));
      try {
        await bloc.submit(username: 'sajjad', password: 'pass-1234');
      } catch (_) {}
      await Future<void>.delayed(Duration.zero);
      expect(seen.first, 'search|');
      expect(seen, contains('found|192.168.18.27'));
      expect(bloc.state.stage, isNull);
      await sub.cancel();
    });

    test('log line carries code / stage / type and never the password or username', () async {
      final auth = _Auth(loginError: _api(429, 'authentication rate limit exceeded'));
      await _fail(auth);
      final line = _logs().lastWhere((l) => l.contains('AUTH_RESULT'));
      expect(line, contains('code=L-05'));
      expect(line, contains('status=429'));
      expect(line, contains('stage=login'));
      expect(line, contains('err=ApiError218'));
      expect(line, isNot(contains('pass-1234')));
      expect(line, isNot(contains('sajjad')));
    });

    test('regression: a bare StateError from the search (older repositories) still opens offline', () async {
      final auth = _Auth(prepareError: StateError('No LinkUp server is available on the local network.'))
        ..offlineOk = true;
      final out = await AuthenticationBloc(auth).submit(username: 'sajjad', password: 'pass-1234');
      expect(out.offline, isTrue);
    });
  });

  group('repository: search + check', () {
    AuthenticationRepository repo(_Store s, _ProbeApi api, _Net net) =>
        AuthenticationRepository(api: api, store: s, connectivity: net);

    test('L6 a failed try keeps the old address (nothing saved before it passes)', () async {
      final s = _Store(saved: _a27);
      final api = _ProbeApi({});
      final net = _Net([
        [_found('192.168.18.30')]
      ]);
      await expectLater(repo(s, api, net).prepareForAuthentication(deviceName: 'p'),
          throwsA(isA<LoginProblem321>().having((p) => p.code, 'code', 'L-02a')));
      expect(s.savedTo, isEmpty);
      expect(s.saved, _a27);
      expect(api.asked, [_a27, _a30]);
    });

    test('L6 the address is saved once it passes, then trusted and pinned', () async {
      final s = _Store(saved: _a27);
      final api = _ProbeApi({_a30: _info()});
      final net = _Net([
        [_found('192.168.18.30')]
      ]);
      await repo(s, api, net).prepareForAuthentication(deviceName: 'p');
      expect(s.savedTo, [_a30]);
      expect(s.pin, 'FP1');
      expect(_logs().join('\n'), contains('AUTH_VERIFY|addr=192.168.18.30 result=ok'));
      expect(_logs().join('\n'), contains('AUTH_VERIFY|addr=192.168.18.27 result=no_route'));
    });

    test('L8 the saved address is asked while the search runs (not after it)', () async {
      final s = _Store(saved: _a27);
      final api = _ProbeApi({_a27: _info()});
      final net = _Net([
        [_found('192.168.18.30')]
      ], delay: const Duration(milliseconds: 300));
      final t0 = DateTime.now();
      await repo(s, api, net).prepareForAuthentication(deviceName: 'p');
      expect(DateTime.now().difference(t0).inMilliseconds, lessThan(250),
          reason: 'the saved address passed before the search ended');
      expect(net.calls, 1);
      expect(s.savedTo, [_a27]);
    });

    test('L16 no answer -> a second search round, then the log line', () async {
      final s = _Store();
      final api = _ProbeApi({_a30: _info()});
      final net = _Net([
        [],
        [_found('192.168.18.30')]
      ]);
      await repo(s, api, net).prepareForAuthentication(deviceName: 'p');
      expect(net.calls, 2);
      expect(s.savedTo, [_a30]);

      AppLogFile.instance.resetForTest();
      final net2 = _Net([[], []]);
      await expectLater(repo(_Store(), _ProbeApi({}), net2).prepareForAuthentication(deviceName: 'p'),
          throwsA(isA<LoginProblem321>().having((p) => p.code, 'code', 'L-01')));
      expect(net2.calls, 2);
      expect(_logs().join('\n'), contains('SERVER_SEARCH|none reason=no_reply rounds=2'));
    });

    test('L15 after a reset the last address is tried like a search result', () async {
      final s = _Store(last: _a27);
      final api = _ProbeApi({_a27: _info()});
      await repo(s, api, _Net([[], []])).prepareForAuthentication(deviceName: 'p');
      expect(api.asked.first, _a27);
      expect(s.savedTo, [_a27]);
      expect(s.pin, 'FP1', reason: 'trusted again from scratch (pin was cleared)');
    });

    test('a server that answered with an error = L-11 (never "no server")', () async {
      final s = _Store(saved: _a27);
      final api = _ProbeApi({_a27: Exception('Server error (500)')});
      await expectLater(repo(s, api, _Net([[], []])).prepareForAuthentication(deviceName: 'p'),
          throwsA(isA<LoginProblem321>().having((p) => p.noServer, 'noServer', isFalse)));
    });

    test('changed key -> ServerProblem256 (no offline), nothing saved', () async {
      final s = _Store(saved: _a27)..pin = 'OLD';
      final api = _ProbeApi({_a27: _info(fp: 'NEW')});
      await expectLater(repo(s, api, _Net([[], []])).prepareForAuthentication(deviceName: 'p'),
          throwsA(isA<ServerProblem256>()));
      expect(s.savedTo, isEmpty);
    });

    test('hint with a wrong key tail is ignored (256 A3 kept)', () async {
      ServerHint256.instance.take(
          {'addr': 'http://192.168.18.40:8080', 'key_tail': 'zzzzzzzz', 'sender_id': 'x'}, wanted: true);
      final s = _Store();
      final api = _ProbeApi({'http://192.168.18.40:8080': _info()});
      await expectLater(repo(s, api, _Net([[], []])).prepareForAuthentication(deviceName: 'p'),
          throwsA(isA<LoginProblem321>()));
      expect(s.savedTo, isEmpty);
      expect(_logs().join('\n'), contains('SERVER_HINT_IGNORED'));
    });
  });

  group('L4 log share + L17 / L15 reset', () {
    test('5 fast taps open, 4 or slow taps do not', () {
      final t = DateTime(2026, 11, 17, 10);
      final c = TapBurstCounter();
      for (var i = 0; i < 4; i++) {
        expect(c.tap(t.add(Duration(milliseconds: 300 * i))), isFalse);
      }
      expect(c.tap(t.add(const Duration(milliseconds: 1200))), isTrue);
      final slow = TapBurstCounter();
      for (var i = 0; i < 5; i++) {
        expect(slow.tap(t.add(Duration(seconds: i))), isFalse);
      }
    });

    testWidgets('login screen wires the title taps to the log share (source)', (tester) async {
      final s = File('lib/features/authentication/presentation/screens/setup_screen.dart').readAsStringSync();
      expect(s, contains("key: const ValueKey('auth321-title')"));
      expect(s, contains('onTap: _onTitleTap321'));
      expect(s, contains('await runLogShare(context);'));
      expect(s, contains("ValueKey('auth321-step')"));
      expect(s, contains("ValueKey('auth321-code')"));
      expect(const ValueKey('auth321-title'), isNotNull);
    });

    test('Reset keeps the last hour of logs and the last server address', () {
      final app = File('lib/app/local_link_app.dart').readAsStringSync();
      final reset = app.substring(app.indexOf('Future<void> _resetAccount() async {'));
      final body = reset.substring(0, reset.indexOf('\n  }\n'));
      expect(body, contains('AppLogFile.instance.keepLastHour321();'));
      expect(body, isNot(contains('AppLogFile.instance.clearAll()')));
      final store = File('lib/core/services/local_store.dart').readAsStringSync();
      final clear = store.substring(store.indexOf('Future<void> clearConfiguration() async {'));
      expect(clear, contains('final last321 = _serverAddress?.trim()'));
      expect(clear, contains('await writeSetting(lastServerKey321, last321);'));
      expect(clear.indexOf('_serverFingerprint = null;'), greaterThan(0), reason: 'pin still cleared');
    });

    test('keepLastHour321 writes what is waiting and keeps the files', () async {
      final dir = Directory.systemTemp.createTempSync('l321');
      addTearDown(() => dir.deleteSync(recursive: true));
      final log = AppLogFile.instance..useDir(dir.path, engine: 'ui');
      final now = DateTime.now();
      log.add('I', 'AUTH_RESULT', 'code=L-02a', now: now);
      log.keepLastHour321(now: now);
      final files = dir.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(files.single.readAsStringSync(), contains('AUTH_RESULT|code=L-02a'));
    });
  });
}
