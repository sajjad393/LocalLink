import 'package:locallink/core/models/account_restore.dart';

abstract interface class AccountRestorationRepositoryContract {
  Future<AccountRestoreManifest> loadManifest();
  Future<String> createEncryptedCryptoBackup({required String passphrase});
  Future<void> restoreAccountData({
    required void Function(RestoreProgress progress) onProgress,
    bool restoreMessages = true,
    bool restoreGroupMessages = true,
    bool restoreCalls = true,
    bool restoreFiles = true,
    String? cryptoBackupPassphrase,
  });
}

class RestoreProgress {
  final String phase;
  final int completed;
  final int total;
  final String detail;
  const RestoreProgress({required this.phase, required this.completed, required this.total, this.detail = ''});
}
