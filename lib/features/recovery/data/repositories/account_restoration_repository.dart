import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/features/recovery/data/services/account_restoration_service.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';

final class AccountRestorationRepository implements AccountRestorationRepositoryContract {
  final AccountRestorationService _service;
  const AccountRestorationRepository({required AccountRestorationService service}) : _service = service;

  @override
  Future<AccountRestoreManifest> loadManifest() => _service.loadManifest();

  @override
  Future<String> createEncryptedCryptoBackup({required String passphrase}) =>
      _service.createEncryptedCryptoBackup(passphrase: passphrase);

  @override
  Future<void> restoreAccountData({
    required void Function(RestoreProgress progress) onProgress,
    bool restoreMessages = true,
    bool restoreGroupMessages = true,
    bool restoreCalls = true,
    bool restoreFiles = true,
    String? cryptoBackupPassphrase,
  }) => _service.restoreAccountData(
        cryptoBackupPassphrase: cryptoBackupPassphrase,
        restoreMessages: restoreMessages,
        restoreGroupMessages: restoreGroupMessages,
        restoreCalls: restoreCalls,
        restoreFiles: restoreFiles,
        onProgress: (p) => onProgress(RestoreProgress(
          phase: p.phase,
          completed: p.completed,
          total: p.total,
          detail: p.detail,
        )),
      );
}
