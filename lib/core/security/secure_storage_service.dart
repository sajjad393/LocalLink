import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Application-owned boundary around platform secure storage.
///
/// Credential names remain defined by the feature that owns them, while the
/// concrete secure-storage plugin stays isolated to this core adapter.
class SecureStorageService {
  final FlutterSecureStorage _storage;

  const SecureStorageService({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  Future<String?> read({required String key}) => _storage.read(key: key);

  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  Future<void> delete({required String key}) => _storage.delete(key: key);

  Future<Map<String, String>> readAll() => _storage.readAll();
}
