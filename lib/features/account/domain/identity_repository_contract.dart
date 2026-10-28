import 'package:locallink/features/account/data/models/identity_key_history.dart';

abstract interface class IdentityRepositoryContract {
  Future<IdentitySnapshot> load();
  Future<IdentityRotationResult> rotate();
}

class IdentitySnapshot {
  final int keyVersion; final String publicKey; final List<IdentityKeyHistoryEntry> history;
  /// Bundle 133: true when the local key loaded fine but the server history
  /// fetch failed (offline). The screen shows the local key + a calm note
  /// instead of failing the whole load.
  final bool historyUnavailable;
  const IdentitySnapshot({required this.keyVersion, required this.publicKey, required this.history, this.historyUnavailable = false});
}

class IdentityRotationResult {
  final int keyVersion; final String publicKey; final List<IdentityKeyHistoryEntry> history;
  const IdentityRotationResult({required this.keyVersion, required this.publicKey, required this.history});
}
