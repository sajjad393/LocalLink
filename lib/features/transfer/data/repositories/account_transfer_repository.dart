import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/core/models/account_transfer.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

final class AccountTransferRepository
    implements AccountTransferRepositoryContract {
  final LocalLinkApi api;
  final LocalStore store;
  final IdentityCryptoService crypto;
  final ConnectivityRepositoryContract connectivity;
  const AccountTransferRepository(
      {required this.api,
      required this.store,
      required this.crypto,
      required this.connectivity});
  @override
  Future<AccountTransferStart> start() => api.startAccountTransfer();
  @override
  Future<void> cancel(String transferId) =>
      api.cancelAccountTransfer(transferId);
  @override
  Future<AccountTransferResult> complete(
      {required String server,
      required AccountTransferPayload payload,
      required String deviceName,
      required bool revokeSourceDevice}) async {
    final id = store.generateDeviceId();
    final name =
        deviceName.trim().isEmpty ? 'My Android Phone' : deviceName.trim();
    await store.saveConfiguration(server: server, id: id, name: name);
    await store.trustServer(
        serverId: payload.serverId, fingerprint: payload.fingerprint);
    await crypto.init(id);
    final key = await crypto.publicKey();
    final result = await api.completeAccountTransfer(
        server: server,
        transferId: payload.transferId,
        secret: payload.secret,
        deviceId: id,
        deviceName: name,
        identityPublicKey: key,
        revokeSourceDevice: revokeSourceDevice);
    await store.saveConfiguration(
        server: server,
        id: result.device.id,
        name: result.device.name,
        token: result.token,
        accountId: result.account.id,
        username: result.account.username);
    await store.saveProfile(result.profile);
    return result;
  }

  @override
  Future<List<DiscoveredServer>> discoverServers() =>
      connectivity.discoverServers();
  @override
  Future<PairingInfo> verifyServer(String address) =>
      api.probePairingInfo(address);
  @override
  String normalizeServerAddress(String address) =>
      LocalLinkApi.normalizeServerAddress(address);
}
