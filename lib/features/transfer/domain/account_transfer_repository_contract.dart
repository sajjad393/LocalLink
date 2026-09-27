import 'package:locallink/core/models/account_transfer.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

abstract interface class AccountTransferRepositoryContract {
  Future<AccountTransferStart> start();
  Future<void> cancel(String transferId);
  Future<AccountTransferResult> complete(
      {required String server,
      required AccountTransferPayload payload,
      required String deviceName,
      required bool revokeSourceDevice});
  Future<List<DiscoveredServer>> discoverServers();
  Future<PairingInfo> verifyServer(String address);
  String normalizeServerAddress(String address);
}
