import 'package:locallink/features/account/data/models/identity_key_history.dart';

abstract interface class IdentityRepositoryContract {
  Future<IdentitySnapshot> load();
  Future<IdentityRotationResult> rotate();
}

class IdentitySnapshot {
  final int keyVersion; final String publicKey; final List<IdentityKeyHistoryEntry> history;
  const IdentitySnapshot({required this.keyVersion, required this.publicKey, required this.history});
}

class IdentityRotationResult {
  final int keyVersion; final String publicKey; final List<IdentityKeyHistoryEntry> history;
  const IdentityRotationResult({required this.keyVersion, required this.publicKey, required this.history});
}
