import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/errors/error_message.dart';
import 'package:locallink/core/services/locallink_api.dart' as api;
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';

typedef CoreRecoveryState = api.AccountRecoveryState;

final class AccountRecoveryState extends Equatable {
  final PairingInfo? pairingInfo;
  final String? server, requestId, requestSecret;
  final CoreRecoveryState? recoveryState;
  final bool serverTrusted, busy, discovering;
  final String? error, statusMessage;
  const AccountRecoveryState(
      {this.pairingInfo,
      this.server,
      this.requestId,
      this.requestSecret,
      this.recoveryState,
      this.serverTrusted = false,
      this.busy = false,
      this.discovering = false,
      this.error,
      this.statusMessage});
  bool get hasActiveRequest =>
      requestId != null && requestSecret != null && recoveryState != null;
  AccountRecoveryState copyWith(
          {PairingInfo? pairingInfo,
          bool clearPairingInfo = false,
          String? server,
          String? requestId,
          String? requestSecret,
          CoreRecoveryState? recoveryState,
          bool clearRecoveryState = false,
          bool? serverTrusted,
          bool? busy,
          bool? discovering,
          String? error,
          bool clearError = false,
          String? statusMessage,
          bool clearStatusMessage = false}) =>
      AccountRecoveryState(
          pairingInfo:
              clearPairingInfo ? null : (pairingInfo ?? this.pairingInfo),
          server: server ?? this.server,
          requestId: requestId ?? this.requestId,
          requestSecret: requestSecret ?? this.requestSecret,
          recoveryState:
              clearRecoveryState ? null : (recoveryState ?? this.recoveryState),
          serverTrusted: serverTrusted ?? this.serverTrusted,
          busy: busy ?? this.busy,
          discovering: discovering ?? this.discovering,
          error: clearError ? null : (error ?? this.error),
          statusMessage: clearStatusMessage
              ? null
              : (statusMessage ?? this.statusMessage));
  @override
  List<Object?> get props => [
        pairingInfo,
        server,
        requestId,
        requestSecret,
        recoveryState,
        serverTrusted,
        busy,
        discovering,
        error,
        statusMessage
      ];
}

final class AccountRecoveryBloc extends Cubit<AccountRecoveryState> {
  final RecoveryRepositoryContract repository;
  Timer? _timer;
  AccountRecoveryBloc(this.repository) : super(const AccountRecoveryState());
  PairingInfo? get pairingInfo => state.pairingInfo;
  String? get server => state.server;
  String? get requestId => state.requestId;
  String? get requestSecret => state.requestSecret;
  CoreRecoveryState? get recoveryState => state.recoveryState;
  bool get serverTrusted => state.serverTrusted;
  bool get busy => state.busy;
  bool get discovering => state.discovering;
  String? get error => state.error;
  String? get statusMessage => state.statusMessage;
  bool get hasActiveRequest => state.hasActiveRequest;
  Future<void> resumePending() async {
    final saved = await repository.pendingRequest();
    if (saved == null) return;
    emit(state.copyWith(
        requestId: saved['request_id'],
        requestSecret: saved['request_secret'],
        server: repository.serverAddress,
        statusMessage: 'Resuming your recovery request…'));
    await pollOnce();
    startPolling();
  }

  Future<void> discoverServers(
      {required String manualAddress, required String deviceName}) async {
    if (state.discovering) return;
    emit(state.copyWith(discovering: true, clearError: true));
    try {
      final found = await repository.discoverServers();
      final candidates = <String>{
        ...found.map((DiscoveredServer e) => e.address),
        if (manualAddress.trim().isNotEmpty) manualAddress.trim()
      };
      String? selected;
      for (final c in candidates) {
        try {
          final info = await repository.verifyServer(c);
          selected = repository.normalizeServerAddress(c);
          emit(state.copyWith(
              pairingInfo: info,
              serverTrusted: repository.isServerTrusted(info)));
          break;
        } catch (_) {}
      }
      if (selected == null)
        throw Exception('No LocalLink server was found on the local network.');
      emit(state.copyWith(server: selected, statusMessage: 'Server found.'));
    } catch (error) {
      emit(state.copyWith(error: errorMessage(error)));
    } finally {
      emit(state.copyWith(discovering: false));
    }
  }

  Future<void> trustServer() async {
    final info = state.pairingInfo;
    if (info == null) return;
    await repository.trustServer(info);
    emit(state.copyWith(serverTrusted: true, clearError: true));
  }

  Future<void> loadServer(String address, String deviceName) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(error: 'Enter a LocalLink server address first.'));
      return;
    }
    try {
      final info = await repository.verifyServer(trimmed);
      emit(state.copyWith(
          pairingInfo: info,
          server: repository.normalizeServerAddress(trimmed),
          serverTrusted: repository.isServerTrusted(info),
          clearError: true));
    } catch (e) {
      emit(state.copyWith(
          clearPairingInfo: true,
          serverTrusted: false,
          error:
              'Could not verify LocalLink server identity: ${errorMessage(e)}'));
    }
  }

  Future<void> startRecovery(
      {required String username,
      required String password,
      required String deviceName}) async {
    if (state.busy) return;
    if (state.server == null)
      await discoverServers(manualAddress: '', deviceName: deviceName);
    if (state.server == null) return;
    if (!state.serverTrusted) {
      emit(state.copyWith(
          error:
              'Verify and trust the LocalLink server before submitting recovery.'));
      return;
    }
    final user = username.trim().toLowerCase();
    if (user.isEmpty || password.isEmpty) {
      emit(state.copyWith(error: 'Enter your username and password.'));
      return;
    }
    emit(state.copyWith(
        busy: true,
        clearError: true,
        statusMessage: 'Creating recovery request…'));
    try {
      final id = repository.deviceId ?? repository.generateDeviceId();
      final name =
          deviceName.trim().isEmpty ? 'My Android Phone' : deviceName.trim();
      await repository.saveConfiguration(
          server: state.server!, id: id, name: name);
      await repository.initCrypto(id);
      final key = await repository.publicKey();
      final r = await repository.createRecovery(
          username: user,
          password: password,
          deviceId: id,
          deviceName: name,
          identityPublicKey: key);
      await repository.savePendingRequest(
          requestId: r.requestId,
          requestSecret: r.requestSecret,
          deviceId: r.targetDeviceId);
      final s = CoreRecoveryState(
          requestId: r.requestId,
          status: r.status,
          username: r.username,
          expiresAt: r.expiresAt,
          approvedAt: '',
          recoveryExpiresAt: '',
          rejectedReason: '',
          serverId: r.serverId,
          fingerprint: r.fingerprint,
          targetDeviceId: r.targetDeviceId);
      emit(state.copyWith(
          requestId: r.requestId,
          requestSecret: r.requestSecret,
          recoveryState: s,
          busy: false,
          statusMessage:
              'Request submitted. Ask the LocalLink administrator to approve it and give you the recovery code.'));
      startPolling();
    } catch (e) {
      emit(state.copyWith(
          busy: false, error: errorMessage(e), clearStatusMessage: true));
    }
  }

  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => pollOnce());
  }

  Future<void> pollOnce() async {
    final s = state.server, id = state.requestId, secret = state.requestSecret;
    if (s == null || id == null || secret == null) return;
    try {
      final current = await repository.recoveryStatus(
          server: s, requestId: id, requestSecret: secret);
      final message = switch (current.status) {
        'pending' => 'Waiting for administrator approval…',
        'approved' =>
          'Approved. Enter the recovery code provided by the administrator.',
        'rejected' => 'The administrator rejected this recovery request.',
        'expired' => 'This recovery request has expired. Start a new request.',
        'completed' => 'Recovery completed.',
        _ => 'Recovery status: ${current.status}'
      };
      emit(state.copyWith(
          recoveryState: CoreRecoveryState(
              requestId: current.requestId,
              status: current.status,
              username: current.username,
              expiresAt: current.expiresAt,
              approvedAt: current.approvedAt,
              recoveryExpiresAt: current.recoveryExpiresAt,
              rejectedReason: current.rejectedReason,
              serverId: current.serverId,
              fingerprint: current.fingerprint,
              targetDeviceId: current.targetDeviceId),
          statusMessage: message,
          clearError: true));
      if ({'approved', 'rejected', 'expired', 'completed'}
          .contains(current.status)) _timer?.cancel();
    } catch (_) {}
  }

  Future<api.AccountRecoveryResult?> complete(
      {required String recoveryCode, required String deviceName}) async {
    if (state.busy ||
        state.server == null ||
        state.requestId == null ||
        state.requestSecret == null) return null;
    final code = recoveryCode.trim();
    if (code.isEmpty) {
      emit(state.copyWith(
          error: 'Enter the recovery code from the administrator.'));
      return null;
    }
    emit(state.copyWith(
        busy: true,
        clearError: true,
        statusMessage: 'Completing secure account recovery…'));
    try {
      final id = repository.deviceId;
      if (id == null || id.isEmpty)
        throw StateError('New device identity is not initialized.');
      final key = await repository.publicKey();
      final name =
          deviceName.trim().isEmpty ? 'My Android Phone' : deviceName.trim();
      final r = await repository.completeRecovery(
          server: state.server!,
          requestId: state.requestId!,
          requestSecret: state.requestSecret!,
          recoveryCredential: code,
          deviceId: id,
          deviceName: name,
          identityPublicKey: key);
      await repository.saveConfiguration(
          server: state.server!,
          id: r.device.id,
          name: r.device.name,
          token: r.token,
          accountId: r.account.id,
          username: r.account.username);
      await repository.saveProfile(r.profile);
      await repository.clearPendingRequest();
      _timer?.cancel();
      emit(state.copyWith(
          busy: false, statusMessage: 'Account recovered successfully.'));
      return r;
    } catch (e) {
      emit(state.copyWith(busy: false, error: errorMessage(e)));
      return null;
    }
  }

  Future<void> resetRequest() async {
    _timer?.cancel();
    await repository.clearPendingRequest();
    emit(const AccountRecoveryState());
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    return super.close();
  }
}
