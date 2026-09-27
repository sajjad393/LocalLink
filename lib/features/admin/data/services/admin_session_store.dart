import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';

final class AdminSessionStore {
  static const _tokenKey = 'locallink_admin_session_token';
  static const _expiresKey = 'locallink_admin_session_expires_at';
  static const _adminIdKey = 'locallink_admin_session_admin_id';
  static const _usernameKey = 'locallink_admin_session_username';
  static const _roleKey = 'locallink_admin_session_role';

  final SecureStorageService storage;
  AdminSessionStore({SecureStorageService? storage}) : storage = storage ?? const SecureStorageService();

  Future<void> save(AdminSession session) async {
    await storage.write(key: _tokenKey, value: session.token);
    await storage.write(key: _expiresKey, value: session.expiresAt);
    await storage.write(key: _adminIdKey, value: session.adminId);
    await storage.write(key: _usernameKey, value: session.username);
    await storage.write(key: _roleKey, value: session.role);
  }

  Future<AdminSession?> read() async {
    final token = await storage.read(key: _tokenKey);
    final expiresAt = await storage.read(key: _expiresKey);
    final adminId = await storage.read(key: _adminIdKey);
    final username = await storage.read(key: _usernameKey);
    final role = await storage.read(key: _roleKey);
    if ([token, expiresAt, adminId, username, role].any((value) => value == null || value.isEmpty)) {
      return null;
    }
    final session = AdminSession(
      token: token!,
      expiresAt: expiresAt!,
      adminId: adminId!,
      username: username!,
      role: role!,
    );
    if (session.expired) {
      await clear();
      return null;
    }
    return session;
  }

  Future<void> clear() async {
    await Future.wait([
      storage.delete(key: _tokenKey),
      storage.delete(key: _expiresKey),
      storage.delete(key: _adminIdKey),
      storage.delete(key: _usernameKey),
      storage.delete(key: _roleKey),
    ]);
  }
}
