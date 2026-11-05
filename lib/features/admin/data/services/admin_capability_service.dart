import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_service.dart';
import 'package:locallink/features/admin/data/services/admin_session_store.dart';

/// Sends `POST /api/v1/admin/logout` for [token] (throws on failure).
typedef AdminServerLogout = Future<void> Function(String token);

/// Reads the locally retained elevated administrator session.
///
/// This is a capability hint for presentation. Backend authorization remains
/// mandatory for every administrative operation.
final class AdminCapabilityService {
  final AdminSessionStore store;

  AdminCapabilityService({AdminSessionStore? store}) : store = store ?? AdminSessionStore();

  /// Bundle 211 (B3): the saved sign-in while it is usable. It stays until
  /// Sign out, a revoke, or a password reset (the server answers 401).
  Future<AdminSession?> readValidSession() async => store.read();

  Future<bool> isAdminCapable() async => (await readValidSession()) != null;

  Future<void> clear() => store.clear();

  /// Bundle 211 (B6): called when the server connects. Sends a sign-out
  /// that was made offline; deleted once the server has it (or says the
  /// sign-in is already gone). Bundle 214: also ends an old 211 web
  /// sign-in found on this phone (there is no admin login any more).
  Future<void> sendPendingRevoke(AdminServerLogout serverLogout) async {
    final token = await store.pendingRevoke();
    if (token == null) return;
    try {
      await serverLogout(token);
      await store.clearPendingRevoke();
      AppLogger.info('ADMIN_SIGN_OUT', detail: 'pending=sent');
    } on AdminRequestException catch (e) {
      if (e.unauthorized) await store.clearPendingRevoke();
    } catch (_) {/* try again on the next connect */}
  }
}
