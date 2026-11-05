import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/admin/data/services/admin_role_service.dart';
import 'package:locallink/features/authentication/bloc/authentication_bloc.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/data/repositories/authentication_repository.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

import 'support/b214_fakes.dart';
import 'support/g211_fakes.dart';

String _src(String p) => File(p).readAsStringSync();

/// Real LocalStore over in-memory secure storage; the signed-out flag
/// (a DB setting in the app) is kept in memory here.
class _Store extends LocalStore {
  _Store(MemStorage211 mem) : super(secureStorage: mem);
  bool out = false;
  @override
  Future<void> setSignedOut(bool signedOut) async => out = signedOut;
  @override
  Future<bool> isSignedOut() async => out;
}

/// The real repository; only the server parts are faked.
class _Repo extends AuthenticationRepository {
  _Repo(_Store store) : super(api: Api211(), store: store, connectivity: _NoNet());
  bool serverUp = true;
  int seeds = 0;

  @override
  String generateUniqueDeviceName() => 'My Android Phone (abcd1234)';

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
      account: LocalAccount(id: 'u-saj', username: username, createdAt: '2026-11-01T00:00:00Z'),
      device: const Device(id: 'dev-me', name: 'p', platform: 'android', createdAt: '', lastSeenAt: ''),
      expiresAt: '2026-12-01T00:00:00Z',
      recoveryCode: 'ABCD-EFGH-JKLM',
    );
  }

  @override
  Future<void> ensureOfflineProfileSeed() async => seeds++;
}

class _NoNet extends Fake implements ConnectivityRepositoryContract {}

/// Bundle 214 (G): sign out, then sign in again with no server on the same
/// phone - same account, admin + crown kept.
void main() {
  test('online login → sign out → offline sign in: same account comes back', () async {
    final mem = MemStorage211();
    final store = _Store(mem);
    final repo = _Repo(store);
    final bloc = AuthenticationBloc(repo);
    addTearDown(bloc.close);

    final first = await bloc.submit(username: 'Sajjad', password: 'pass-1234');
    expect(first.offline, isFalse);
    expect(store.offlineLoginAccount?['username'], 'sajjad');

    await repo.signOut();
    expect(await repo.isSignedOut(), isTrue);
    expect(store.offlineLoginAccount, isNotNull); // sign out keeps the mirror

    repo.serverUp = false;
    final again = await bloc.submit(username: 'sajjad', password: 'pass-1234');
    expect(again.offline, isTrue);
    expect(await repo.isSignedOut(), isFalse);
    expect(repo.seeds, 1);

    // Wrong password: plain message, still signed in state untouched.
    await repo.signOut();
    await expectLater(bloc.submit(username: 'sajjad', password: 'nope-9999'), throwsException);
    expect(bloc.state.error, 'That username and password do not match.');
    expect(await repo.isSignedOut(), isTrue);

    // Recovery code typed in the password box works offline too.
    final rec = await bloc.submit(username: 'sajjad', password: 'abcd efgh jklm');
    expect(rec.offline, isTrue);
  });

  test('only the last account is remembered', () async {
    final store = _Store(MemStorage211());
    final repo = _Repo(store);
    final bloc = AuthenticationBloc(repo);
    addTearDown(bloc.close);
    await bloc.submit(username: 'sajjad', password: 'pass-1234');
    await bloc.submit(username: 'sumaira', password: 'pass-5678');
    await repo.signOut();
    repo.serverUp = false;
    await expectLater(bloc.submit(username: 'sajjad', password: 'pass-1234'), throwsException);
    expect((await bloc.submit(username: 'sumaira', password: 'pass-5678')).offline, isTrue);
  });

  group('admin after sign in', () {
    late MemStorage211 mem;
    late Map<String, String> settings;
    late String account;
    late bool out;
    late FakeRoleServer214 server;

    AdminRoleService make() {
      final cap = capability211(mem);
      return AdminRoleService(
        capability: cap,
        read: (k) async => settings[k],
        write: (k, v) async => settings[k] = v,
        accountId: () => account,
        signedOut: () async => out,
        server: server,
      );
    }

    setUp(() async {
      mem = MemStorage211();
      settings = {};
      account = 'u-saj';
      out = false;
      server = FakeRoleServer214()..session = session214(token: 'dev-tok-1');
      final svc = make();
      expect(await svc.refresh(reason: 'test'), AdminRoleResult.admin);
      svc.dispose();
    });
    tearDown(AdminRoleService.resetForTest);

    test('sign out keeps it; no server asks while signed out', () async {
      out = true;
      final svc = make();
      server.tokensSent.clear();
      expect(await svc.refresh(reason: 'tick'), AdminRoleResult.skipped);
      expect(server.tokensSent, isEmpty);
      expect(mem.data['locallink_admin_session_token'], 'dev-tok-1');
      svc.dispose();
    });

    test('offline sign in, same account: admin back at once', () async {
      server.mode = 'down';
      final svc = make();
      await svc.afterSignIn(online: false);
      expect(svc.current.value?.token, 'dev-tok-1');
      expect(svc.current.value?.role, 'owner');
      await svc.afterSignIn(online: true); // server down → kept
      expect(svc.current.value?.token, 'dev-tok-1');
      svc.dispose();
    });

    test('another account on this phone: old admin cleared', () async {
      account = 'u-other';
      server.mode = 'not_admin';
      final svc = make();
      await svc.afterSignIn(online: false);
      expect(svc.current.value, isNull);
      expect(mem.data.containsKey('locallink_admin_session_token'), isFalse);
      svc.dispose();
    });
  });

  test('sources: sign out does not touch admin; reset does; logs', () {
    final app = _src('lib/app/local_link_app.dart');
    expect(app, contains(".afterSignIn(online: true)"));
    final roles = _src('lib/features/admin/data/services/admin_role_service.dart');
    expect(roles, contains("'ADMIN_ROLE_KEPT_AFTER_SIGNIN'"));
    expect(roles, contains("'ADMIN_ROLE_OTHER_ACCOUNT_CLEARED'"));
    expect(_src('lib/features/authentication/bloc/authentication_bloc.dart'),
        contains("'AUTH_OFFLINE_LOGIN'"));
    expect(_src('lib/features/authentication/data/repositories/authentication_repository.dart'),
        contains('Future<void> signOut() => _store.setSignedOut(true);'));
  });
}
