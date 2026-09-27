import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_session_store.dart';

/// Reads the locally retained elevated administrator session.
///
/// This is a capability hint for presentation. Backend authorization remains
/// mandatory for every administrative operation.
final class AdminCapabilityService {
  final AdminSessionStore store;

  AdminCapabilityService({AdminSessionStore? store}) : store = store ?? AdminSessionStore();

  Future<AdminSession?> readValidSession() async => store.read();

  Future<bool> isAdminCapable() async => (await readValidSession()) != null;

  Future<void> clear() => store.clear();
}
