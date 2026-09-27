import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/account/data/models/identity_key_history.dart';

class IdentityRepository implements IdentityRepositoryContract {
  final LocalLinkApi _api;
  final LocalStore _store;
  final IdentityCryptoService _crypto;

  const IdentityRepository({required LocalLinkApi api, required LocalStore store, required IdentityCryptoService crypto})
      : _api = api,
        _store = store,
        _crypto = crypto;

  @override
  Future<IdentitySnapshot> load() async {
    final deviceId = _store.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw StateError('Device identity is not configured');
    }
    await _crypto.init(deviceId);
    final history = (await _api.identityKeyHistory())
        .map(IdentityKeyHistoryEntry.fromJson)
        .toList(growable: false);
    final publicKey = await _crypto.publicKey();
    return IdentitySnapshot(
      keyVersion: _crypto.keyVersion,
      publicKey: publicKey,
      history: history,
    );
  }

  @override
  Future<IdentityRotationResult> rotate() async {
    final prepared = await _crypto.prepareIdentityRotation();
    try {
      final response = await _api.rotateIdentityKey(prepared.publicKey);
      final serverVersion = int.tryParse(response['key_version']?.toString() ?? '') ?? prepared.keyVersion;
      if (serverVersion != prepared.keyVersion) {
        throw StateError('server returned an unexpected identity-key version');
      }
      await _crypto.commitIdentityRotation(prepared.keyVersion);
      await _store.resetDerivedEncryptionState();
      final history = (await _api.identityKeyHistory())
          .map(IdentityKeyHistoryEntry.fromJson)
          .toList(growable: false);
      return IdentityRotationResult(keyVersion: _crypto.keyVersion, publicKey: await _crypto.publicKey(), history: history);
    } catch (_) {
      await _crypto.discardPendingIdentityRotation(prepared.keyVersion);
      rethrow;
    }
  }
}
