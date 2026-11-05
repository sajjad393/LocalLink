import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/data/services/admin_session_store.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';

/// Bundle 211 test helpers.
class MemStorage211 extends SecureStorageService {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read({required String key}) async => data[key];

  @override
  Future<void> write({required String key, required String value}) async =>
      data[key] = value;

  @override
  Future<void> delete({required String key}) async => data.remove(key);

  @override
  Future<Map<String, String>> readAll() async => Map.of(data);
}

class Store211 extends LocalStore {
  String? server;
  Store211({this.server});

  @override
  String? get username => 'sajjad';
  @override
  String? get deviceName => 'My LinkUp phone';
  @override
  Map<String, dynamic>? get offlinePending => null;
  @override
  String? get serverAddress => server;
}

class Api211 implements LocalLinkApi {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class AdminFactory211 implements AdminRepositoryFactory {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// An admin sign-in whose old 30-minute end has long passed.
AdminSession oldSession211({String token = 'tok-1'}) => AdminSession(
      token: token,
      expiresAt: '2026-01-01T10:30:00Z',
      adminId: 'adm-1',
      username: 'sajjad-admin',
      role: 'owner',
    );

AdminCapabilityService capability211(MemStorage211 mem) =>
    AdminCapabilityService(store: AdminSessionStore(storage: mem));
