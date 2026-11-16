import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/recovery/bloc/account_recovery_bloc.dart';
import 'package:locallink/features/recovery/data/repositories/recovery_repository.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';

// Bundle 321 Phase 2: Forgot password / Confirm account check the server
// for real (saved / last address + search), re-check every 20 s, "Ask the
// admin" searches + sends, the offline reset only after a fresh check.

class _Store implements LocalStore {
  String? saved;
  String last = '';
  final settings = <String, String>{};
  @override
  String? get serverAddress => saved;
  @override
  String? get serverFingerprint => null;
  @override
  Future<String> lastServer321() async => last;
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Api implements LocalLinkApi {
  _Api(this.up);
  final Set<String> up;
  final asked = <String>[];
  @override
  Future<PairingInfo> probePairingInfo(String server) async {
    asked.add(server);
    if (up.contains(server)) {
      return const PairingInfo(
          service: 'locallink', version: '3', serverId: 's', fingerprint: 'F', name: 'PC', pairingRequired: false);
    }
    throw const SocketException('No route to host', osError: OSError('No route to host', 113));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Net implements ConnectivityRepositoryContract {
  _Net(this.found);
  final List<String> found;
  int calls = 0;
  @override
  Future<List<DiscoveredServer>> discoverServers({Duration timeout = const Duration(seconds: 5)}) async {
    calls++;
    return [for (final h in found) DiscoveredServer(host: h, port: 8080, name: 'PC', protocol: 'http')];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Crypto implements IdentityCryptoService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

RecoveryRepository _repo(_Store s, _Api a, _Net n) =>
    RecoveryRepository(api: a, store: s, crypto: _Crypto(), connectivity: n);

class _Repo implements RecoveryRepositoryContract {
  List<bool> answers = [false];
  int checks = 0, onlineResets = 0, offlineResets = 0, sends = 0;
  @override
  Future<bool> serverOnline222() async {
    final a = answers[checks < answers.length ? checks : answers.length - 1];
    checks++;
    return a;
  }

  @override
  Future<AuthResult> resetWithCode222(
      {required String username, required String recoveryCode, required String newPassword}) async {
    onlineResets++;
    return AuthResult(
      account: LocalAccount.fromJson({'id': 'u1', 'username': username}),
      device: Device.fromJson({'id': 'd1', 'name': 'ZTE'}),
      expiresAt: '',
      recoveryCode: 'P3HD8-LKWT6-MZQA2-RX7YB',
    );
  }

  @override
  Future<void> resetOffline222(
      {required String username, required String recoveryCode, required String newPassword}) async {
    offlineResets++;
  }

  @override
  Future<({AccountRecoveryStart start, String server})> createNoCodeRequest222({required String username}) async {
    sends++;
    return (
      start: AccountRecoveryStart.fromJson({
        'request': {'request_id': 'req-1', 'status': 'pending', 'username': username},
        'request_secret': 'sec'
      }),
      server: 'http://192.168.18.27:8080',
    );
  }

  @override
  Future<Map<String, String>?> pendingRequest() async => null;
  @override
  String? get serverAddress => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(AppLogFile.instance.resetForTest);
  String logs() => AppLogFile.instance.pendingForTest.join('\n');

  group('L9 / L12 repository check', () {
    test('no saved address + the search finds the server -> online (was: offline at once)', () async {
      final net = _Net(['192.168.18.27']);
      final ok = await _repo(_Store(), _Api({'http://192.168.18.27:8080'}), net).serverOnline222();
      expect(ok, isTrue);
      expect(net.calls, 1);
      expect(logs(), contains('RECOVERY_SERVER_CHECK|saved=0 found=1 result=ok'));
    });

    test('nothing found -> offline, logged', () async {
      final ok = await _repo(_Store(), _Api({}), _Net([])).serverOnline222();
      expect(ok, isFalse);
      expect(logs(), contains('RECOVERY_SERVER_CHECK|saved=0 found=0 result=none'));
    });

    test('saved address answers -> no search needed; nothing is saved', () async {
      final s = _Store()..saved = 'http://192.168.18.27:8080';
      final net = _Net(['192.168.18.30']);
      expect(await _repo(s, _Api({'http://192.168.18.27:8080'}), net).serverOnline222(), isTrue);
      expect(net.calls, 0);
      expect(s.settings, isEmpty);
    });

    test('the address kept through Reset is asked first', () async {
      final s = _Store()..last = 'http://192.168.18.27:8080';
      final api = _Api({'http://192.168.18.27:8080'});
      expect(await _repo(s, api, _Net([])).serverOnline222(), isTrue);
      expect(api.asked.first, 'http://192.168.18.27:8080');
    });
  });

  group('L9 / L10 bloc', () {
    testWidgets('re-checks every 20 s: Offline flips to online', (tester) async {
      final repo = _Repo()..answers = [false, true];
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.start();
      expect(bloc.state.online, isFalse);
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(bloc.state.online, isTrue);
      expect(repo.checks, 2);
      await bloc.close();
    });

    test('"Ask the admin" sends even after the screen said offline', () async {
      final repo = _Repo()..answers = [false];
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.checkServer();
      expect(bloc.state.online, isFalse);
      await bloc.askAdmin(username: 'sajjad');
      expect(repo.sends, 1);
      expect(bloc.state.hasRequest, isTrue);
      await bloc.close();
    });

    test('reset with a code: a fresh check finds the server -> server reset (not offline)', () async {
      final repo = _Repo()..answers = [false, true];
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.checkServer();
      expect(bloc.state.online, isFalse);
      await bloc.resetWithCode(
          username: 'sajjad',
          recoveryCode: 'K7QM2-XPA9T-RC4WN-E8D3F',
          newPassword: 'newpass-123',
          again: 'newpass-123');
      expect(repo.onlineResets, 1);
      expect(repo.offlineResets, 0);
      await bloc.close();
    });

    test('reset with a code: fresh check finds nothing -> offline reset', () async {
      final repo = _Repo()..answers = [false];
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.resetWithCode(
          username: 'sajjad',
          recoveryCode: 'K7QM2-XPA9T-RC4WN-E8D3F',
          newPassword: 'newpass-123',
          again: 'newpass-123');
      expect(repo.offlineResets, 1);
      await bloc.close();
    });
  });

  test('L11 + L9 screen: one note only under an error; re-check on resume (source)', () {
    final s = File('lib/features/recovery/presentation/screens/account_recovery_screen.dart').readAsStringSync();
    expect(s, contains('if (state.error == null) LinkNote290(L.t.needsTheServer2),'));
    expect(s, contains('if (s == AppLifecycleState.resumed) unawaited(_bloc.checkServer());'));
    expect(s, contains('WidgetsBinding.instance.removeObserver(this);'));
  });
}
