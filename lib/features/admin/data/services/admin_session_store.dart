import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';

final class AdminSessionStore {
  static const _tokenKey = 'locallink_admin_session_token';
  static const _expiresKey = 'locallink_admin_session_expires_at';
  static const _adminIdKey = 'locallink_admin_session_admin_id';
  static const _usernameKey = 'locallink_admin_session_username';
  static const _roleKey = 'locallink_admin_session_role';

  /// Bundle 211 (B6): a token signed out while offline; sent to the server
  /// (POST /admin/logout) on the next connect, then deleted.
  static const _pendingRevokeKey = 'locallink_admin_pending_revoke';

  /// Bundle 214 (G2): the account the saved admin session belongs to. A
  /// session never moves to another account on the same phone.
  static const _accountKey = 'locallink_admin_session_account';

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
    // Bundle 211 (B2): no longer thrown away after 30 minutes or by the
    // phone clock. Only Sign out, or a 401 from the server, clears it.
    return session.usable ? session : null;
  }

  Future<void> saveAccount(String accountId) =>
      storage.write(key: _accountKey, value: accountId);

  Future<String?> readAccount() async {
    final v = await storage.read(key: _accountKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> savePendingRevoke(String token) =>
      storage.write(key: _pendingRevokeKey, value: token);

  Future<String?> pendingRevoke() async {
    final v = await storage.read(key: _pendingRevokeKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> clearPendingRevoke() => storage.delete(key: _pendingRevokeKey);

  Future<void> clear() async {
    await Future.wait([
      storage.delete(key: _tokenKey),
      storage.delete(key: _expiresKey),
      storage.delete(key: _adminIdKey),
      storage.delete(key: _usernameKey),
      storage.delete(key: _roleKey),
      storage.delete(key: _accountKey),
    ]);
  }
}
