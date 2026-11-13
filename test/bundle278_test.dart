import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/authentication/bloc/authentication_bloc.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/data/repositories/authentication_repository.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

import 'support/g211_fakes.dart';

// Bundle 278: offline sign-in says WHY it did not work (nothing saved on
// this phone / this phone saved another account / wrong password).

class _Store extends LocalStore {
  _Store(MemStorage211 mem) : super(secureStorage: mem);
  bool out = false;
  @override
  Future<void> setSignedOut(bool signedOut) async => out = signedOut;
  @override
  Future<bool> isSignedOut() async => out;
}

class _Repo extends AuthenticationRepository {
  _Repo(_Store store) : super(api: Api211(), store: store, connectivity: _NoNet());
  bool serverUp = true;

  @override
  String generateUniqueDeviceName() => 'p';

  @override
  Future<void> prepareForAuthentication({required String deviceName}) async {
    if (!serverUp) throw StateError('LinkUp server not found');
  }

  @override
  Future<AuthResult> login({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) async {
    if (!serverUp) throw StateError('LinkUp server not found');
    return AuthResult(
      account:
          LocalAccount(id: 'u-$username', username: username, createdAt: '2026-11-01T00:00:00Z'),
      device:
          const Device(id: 'dev-me', name: 'p', platform: 'android', createdAt: '', lastSeenAt: ''),
      expiresAt: '2026-12-01T00:00:00Z',
      recoveryCode: 'ABCD-EFGH-JKLM',
    );
  }

  @override
  Future<void> ensureOfflineProfileSeed() async {}
}

/// A store holding the copy a phone-only account saves at sign-up
/// (`saveOfflineAccount` needs the database, which tests do not have).
class _Pending extends _Store {
  _Pending(this.copy) : super(MemStorage211());
  final Map<String, dynamic> copy;
  @override
  Map<String, dynamic>? get offlinePending => copy;
}

class _NoNet extends Fake implements ConnectivityRepositoryContract {}

const _noCopy = 'This phone has no saved sign-in yet. Turn the server on and sign in once.';
const _other = 'This phone can sign in offline only with the last account used on it.';
const _bad = 'That username and password do not match.';

void main() {
  test('nothing saved on this phone: says so (not "do not match")', () async {
    final store = _Store(MemStorage211());
    final repo = _Repo(store)..serverUp = false;
    final bloc = AuthenticationBloc(repo);
    addTearDown(bloc.close);
    expect(await repo.offlineLoginReason278('sajjad', 'pass-1234'), 'no_copy');
    await expectLater(bloc.submit(username: 'sajjad', password: 'pass-1234'), throwsException);
    expect(bloc.state.error, _noCopy);
  });

  test('another account saved here: says only the last account works', () async {
    final store = _Store(MemStorage211());
    final repo = _Repo(store);
    final bloc = AuthenticationBloc(repo);
    addTearDown(bloc.close);
    await bloc.submit(username: 'sumaira', password: 'pass-5678');
    await repo.signOut();
    repo.serverUp = false;
    expect(await repo.offlineLoginReason278('sajjad', 'pass-1234'), 'other_user');
    await expectLater(bloc.submit(username: 'sajjad', password: 'pass-1234'), throwsException);
    expect(bloc.state.error, _other);
    expect(bloc.state.error, isNot(contains('sumaira')), reason: 'no names shown');
  });

  test('wrong password: same words as before; right password and recovery code still work',
      () async {
    final store = _Store(MemStorage211());
    final repo = _Repo(store);
    final bloc = AuthenticationBloc(repo);
    addTearDown(bloc.close);
    await bloc.submit(username: 'sajjad', password: 'pass-1234');
    await repo.signOut();
    repo.serverUp = false;
    expect(await repo.offlineLoginReason278('Sajjad ', 'nope-9999'), 'bad_password');
    await expectLater(bloc.submit(username: 'sajjad', password: 'nope-9999'), throwsException);
    expect(bloc.state.error, _bad);
    expect(await repo.offlineLoginReason278('sajjad', 'pass-1234'), 'ok');
    expect((await bloc.submit(username: 'sajjad', password: 'pass-1234')).offline, isTrue);
    await repo.signOut();
    expect((await bloc.submit(username: 'sajjad', password: 'abcd efgh jklm')).offline, isTrue);
  });

  test('a phone-only account (made offline) checks its own saved password', () async {
    final salt = Uint8List.fromList(List<int>.generate(PasswordKdf.saltLength, (i) => i));
    final hash = await PasswordKdf.deriveAsync('pass-0000', salt);
    final store = _Pending({
      'username': 'kiran',
      'pwd_hash': PasswordKdf.b64(hash),
      'pwd_salt': PasswordKdf.b64(salt),
    });
    final repo = _Repo(store)..serverUp = false;
    expect(await repo.offlineLoginReason278('kiran', 'pass-0000'), 'ok');
    expect(await repo.verifyOfflineLoginAsync('kiran', 'pass-0000'), isTrue);
    expect(await repo.offlineLoginReason278('kiran', 'pass-1111'), 'bad_password');
    expect(await repo.offlineLoginReason278('ayesha', 'pass-0000'), 'other_user');
  });

  test('words per reason; log has the reason and no name', () {
    expect(offlineLoginText278('no_copy'), _noCopy);
    expect(offlineLoginText278('other_user'), _other);
    expect(offlineLoginText278('bad_password'), _bad);
    expect(offlineLoginText278('anything'), _bad);
    final src =
        File('lib/features/authentication/bloc/authentication_bloc.dart').readAsStringSync();
    expect(src, contains("AppLogger.info('AUTH_OFFLINE_LOGIN', detail: 'bad reason=\$why278');"));
  });
}
