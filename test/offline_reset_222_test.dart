// Bundle 222: Forgot password with no server (same phone, last account),
// and the later sync of the new password to the server.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/recovery/data/repositories/recovery_repository.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';

class _Store implements LocalStore {
  String? user = 'sajjad';
  String? code = 'K7QM2-XPA9T-RC4WN-E8D3F';
  Map<String, dynamic>? pending; // phone-only account
  Map<String, dynamic>? mirror = {'username': 'sajjad', 'pwd_hash': 'x', 'pwd_salt': 'y'};
  Map<String, dynamic>? resetPending;
  String? secret;
  bool? signedOut = true;
  final settings = <String, String>{};

  @override
  String? get username => user;
  @override
  String? get deviceName => 'ZTE';
  @override
  String? get localRecoveryCode => code;
  @override
  Map<String, dynamic>? get offlinePending => pending == null ? null : Map.of(pending!);
  @override
  Map<String, dynamic>? get offlineLoginAccount => mirror == null ? null : Map.of(mirror!);
  @override
  Future<void> updateOfflinePendingPassword222({required String pwdHash, required String pwdSalt}) async {
    pending!['pwd_hash'] = pwdHash;
    pending!['pwd_salt'] = pwdSalt;
  }

  @override
  Future<String?> readOfflinePublishSecret() async => secret;
  @override
  Future<void> writeOfflinePublishSecret(String value) async => secret = value;
  @override
  Future<void> saveOfflineLoginAccount({required String username, required String pwdHash, required String pwdSalt, required String recoveryCode}) async {
    mirror = {'username': username, 'pwd_hash': pwdHash, 'pwd_salt': pwdSalt};
  }

  @override
  Future<Map<String, dynamic>?> pwdResetPending222() async => resetPending;
  @override
  Future<void> savePwdResetPending222(Map<String, dynamic> value) async => resetPending = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  @override
  Future<void> clearPwdResetPending222() async => resetPending = null;
  @override
  Future<void> setSignedOut(bool value) async => signedOut = value;
  @override
  Future<void> updateLocalRecoveryCode(String value) async => code = value;
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements LocalLinkApi {
  Object? failWith;
  final sent = <Map<String, Object>>[];
  @override
  Future<AuthResult> resetPasswordWithCode222({
    required String username,
    required String recoveryCode,
    String newPassword = '',
    String newPasswordHash = '',
    String newPasswordSalt = '',
    int iterations = 0,
    required String deviceName,
    String identityPublicKey = '',
    String? pairingCode,
  }) async {
    sent.add({'username': username, 'code': recoveryCode, 'password': newPassword, 'hash': newPasswordHash, 'salt': newPasswordSalt, 'iterations': iterations});
    if (failWith != null) throw failWith!;
    return AuthResult(
      account: LocalAccount.fromJson({'id': 'u1', 'username': username}),
      device: Device.fromJson({'id': 'd1', 'name': 'ZTE'}),
      expiresAt: '',
      recoveryCode: 'NEWCO-DEFRO-MSERV-ER222',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Crypto implements IdentityCryptoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conn implements ConnectivityRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RecoveryRepository _repo(_Store store, [_Api? api]) =>
    RecoveryRepository(api: api ?? _Api(), store: store, crypto: _Crypto(), connectivity: _Conn());

void main() {
  test('offline: only the last account on this phone, only its saved code', () {
    final store = _Store();
    final repo = _repo(store);
    expect(repo.offlineResetProblem222(username: 'ali', recoveryCode: store.code!), 'not_last');
    expect(repo.offlineResetProblem222(username: 'sajjad', recoveryCode: 'AAAAA-BBBBB-CCCCC-DDDDD'), 'bad_code');
    expect(repo.offlineResetProblem222(username: ' Sajjad ', recoveryCode: 'k7qm2 xpa9t rc4wn e8d3f'), isNull);
    store.mirror = null;
    expect(repo.offlineResetProblem222(username: 'sajjad', recoveryCode: store.code!), 'not_last',
        reason: 'the account must be saved on this phone');
  });

  test('offline reset: new password works here, waits for the server as a hash', () async {
    final store = _Store();
    await _repo(store).resetOffline222(username: 'sajjad', recoveryCode: store.code!, newPassword: 'new-pass-1');
    expect(store.signedOut, isFalse);
    expect(PasswordKdf.verify('new-pass-1', store.mirror!['pwd_salt'] as String, store.mirror!['pwd_hash'] as String), isTrue);
    final p = store.resetPending!;
    expect(p['username'], 'sajjad');
    expect(p['iterations'], PasswordKdf.iterations);
    expect(p['code_hash'], sha256.convert(utf8.encode('K7QM2-XPA9T-RC4WN-E8D3F')).toString());
    expect(jsonEncode(p), isNot(contains('new-pass-1')), reason: 'the plain password is never kept');
  });

  test('offline reset refused: nothing changes', () async {
    final store = _Store();
    await expectLater(
      _repo(store).resetOffline222(username: 'sajjad', recoveryCode: 'AAAAA-BBBBB-CCCCC-DDDDD', newPassword: 'new-pass-1'),
      throwsA(isA<ResetProblem222>()),
    );
    expect(store.resetPending, isNull);
    expect(store.mirror!['pwd_hash'], 'x');
    expect(store.signedOut, isTrue);
  });

  test('phone-only account (never on the server): its waiting registration gets the new password', () async {
    final store = _Store()
      ..mirror = null
      ..pending = {'username': 'sajjad', 'pwd_hash': 'old', 'pwd_salt': 'old'}
      ..secret = 'old-password';
    await _repo(store).resetOffline222(username: 'sajjad', recoveryCode: store.code!, newPassword: 'new-pass-1');
    expect(PasswordKdf.verify('new-pass-1', store.pending!['pwd_salt'] as String, store.pending!['pwd_hash'] as String), isTrue);
    expect(store.secret, 'new-pass-1', reason: 'the first publish must use the new password');
    expect(store.resetPending, isNull, reason: 'nothing to reset on the server');
  });

  test('sync when the server is back: hash only, new code shown once on Home', () async {
    final store = _Store();
    await _repo(store).resetOffline222(username: 'sajjad', recoveryCode: store.code!, newPassword: 'new-pass-1');
    final api = _Api();
    expect(await OfflineAccountSyncService.syncPwdReset222(store: store, api: api), 'ok');
    expect(api.sent.single['password'], '');
    expect(api.sent.single['hash'], isNotEmpty);
    expect(api.sent.single['iterations'], PasswordKdf.iterations);
    expect(api.sent.single['code'], 'K7QM2-XPA9T-RC4WN-E8D3F');
    expect(store.resetPending, isNull);
    expect(store.code, 'NEWCO-DEFRO-MSERV-ER222');
    expect(store.settings[OfflineAccountSyncService.joinRecoveryKey], 'NEWCO-DEFRO-MSERV-ER222');
    expect(await OfflineAccountSyncService.syncPwdReset222(store: store, api: api), 'none');
  });

  test('sync refused (code changed on the server): note on Home, no loop', () async {
    final store = _Store();
    await _repo(store).resetOffline222(username: 'sajjad', recoveryCode: store.code!, newPassword: 'new-pass-1');
    final api = _Api()..failWith = const ApiError218('wrong', code: 'BAD_RECOVERY_CODE', status: 401);
    expect(await OfflineAccountSyncService.syncPwdReset222(store: store, api: api), 'refused');
    expect(store.settings[OfflineAccountSyncService.pwdResetBannerKey222], '1');
    expect(store.resetPending, isNull);
    expect(await OfflineAccountSyncService.syncPwdReset222(store: store, api: api), 'none');
    expect(api.sent.length, 1);
  });

  test('sync with no network: kept for the next time', () async {
    final store = _Store();
    await _repo(store).resetOffline222(username: 'sajjad', recoveryCode: store.code!, newPassword: 'new-pass-1');
    final api = _Api()..failWith = Exception('SocketException: Connection refused');
    expect(await OfflineAccountSyncService.syncPwdReset222(store: store, api: api), 'later');
    expect(store.resetPending, isNotNull);
    expect(store.settings[OfflineAccountSyncService.pwdResetBannerKey222], isNull);
  });

  test('the code was changed on this phone meanwhile: refused without asking the server', () async {
    final store = _Store();
    await _repo(store).resetOffline222(username: 'sajjad', recoveryCode: store.code!, newPassword: 'new-pass-1');
    store.code = 'OTHER-CODE2-ONTHI-SPHON';
    final api = _Api();
    expect(await OfflineAccountSyncService.syncPwdReset222(store: store, api: api), 'refused');
    expect(api.sent, isEmpty);
  });

  test('after an online reset the phone keeps the new code and the new password', () async {
    final store = _Store()..resetPending = {'username': 'sajjad'};
    await _repo(store).afterReset222(username: 'sajjad', newPassword: 'new-pass-2', newRecoveryCode: 'P3HD8-LKWT6-MZQA2-RX7YB');
    expect(store.code, 'P3HD8-LKWT6-MZQA2-RX7YB');
    expect(PasswordKdf.verify('new-pass-2', store.mirror!['pwd_salt'] as String, store.mirror!['pwd_hash'] as String), isTrue);
    expect(store.resetPending, isNull);
    expect(store.signedOut, isFalse);
  });
}
