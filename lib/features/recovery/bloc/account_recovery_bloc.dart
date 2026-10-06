import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/errors/error_message.dart';
import 'package:locallink/core/services/locallink_api.dart' as api;
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';

typedef CoreRecoveryState = api.AccountRecoveryState;

final class AccountRecoveryState extends Equatable {
  final String? server;
  final String? requestId;
  final String? requestSecret;
  final CoreRecoveryState? recoveryState;
  final bool busy;
  final String? error;
  final String? statusMessage;

  const AccountRecoveryState({
    this.server,
    this.requestId,
    this.requestSecret,
    this.recoveryState,
    this.busy = false,
    this.error,
    this.statusMessage,
  });

  bool get hasActiveRequest =>
      requestId != null && requestSecret != null && recoveryState != null;

  AccountRecoveryState copyWith({
    String? server,
    String? requestId,
    String? requestSecret,
    CoreRecoveryState? recoveryState,
    bool clearRecoveryState = false,
    bool? busy,
    String? error,
    bool clearError = false,
    String? statusMessage,
    bool clearStatusMessage = false,
  }) {
    return AccountRecoveryState(
      server: server ?? this.server,
      requestId: requestId ?? this.requestId,
      requestSecret: requestSecret ?? this.requestSecret,
      recoveryState: clearRecoveryState
          ? null
          : (recoveryState ?? this.recoveryState),
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
    );
  }

  @override
  List<Object?> get props => [
        server,
        requestId,
        requestSecret,
        recoveryState,
        busy,
        error,
        statusMessage,
      ];
}

final class AccountRecoveryBloc extends Cubit<AccountRecoveryState> {
  final RecoveryRepositoryContract repository;
  Timer? _timer;

  AccountRecoveryBloc(this.repository) : super(const AccountRecoveryState());

  String? get server => state.server;
  String? get requestId => state.requestId;
  String? get requestSecret => state.requestSecret;
  CoreRecoveryState? get recoveryState => state.recoveryState;
  bool get busy => state.busy;
  String? get error => state.error;
  String? get statusMessage => state.statusMessage;
  bool get hasActiveRequest => state.hasActiveRequest;

  Future<void> resumePending() async {
    final saved = await repository.pendingRequest();
    if (saved == null) return;
    final savedServer = repository.serverAddress;
    if (savedServer == null || savedServer.isEmpty) return;
    emit(state.copyWith(
      requestId: saved['request_id'],
      requestSecret: saved['request_secret'],
      server: savedServer,
      statusMessage: 'Resuming your recovery request…',
    ));
    await pollOnce();
    startPolling();
  }

  Future<void> startRecovery({required String username}) async {
    if (state.busy) return;

    final user = username.trim().toLowerCase();
    if (user.isEmpty) {
      emit(state.copyWith(error: 'Enter your username.'));
      return;
    }

    emit(state.copyWith(
      busy: true,
      clearError: true,
      statusMessage: 'Connecting securely…',
    ));

    try {
      const deviceName = 'My Android Phone';
      final selectedServer = await repository.prepareForRecovery(
        deviceName: deviceName,
      );
      final id = repository.deviceId ?? repository.generateDeviceId();
      await repository.saveConfiguration(
        server: selectedServer,
        id: id,
        name: deviceName,
      );
      await repository.initCrypto(id);
      final key = await repository.publicKey();
      final result = await repository.createRecovery(
        username: user,
        password: '',
        deviceId: id,
        deviceName: deviceName,
        identityPublicKey: key,
      );

      await repository.savePendingRequest(
        requestId: result.requestId,
        requestSecret: result.requestSecret,
        deviceId: result.targetDeviceId,
      );

      final recoveryState = CoreRecoveryState(
        requestId: result.requestId,
        status: result.status,
        username: result.username,
        expiresAt: result.expiresAt,
        approvedAt: '',
        recoveryExpiresAt: '',
        rejectedReason: '',
        serverId: result.serverId,
        fingerprint: result.fingerprint,
        targetDeviceId: result.targetDeviceId,
      );

      emit(state.copyWith(
        server: selectedServer,
        requestId: result.requestId,
        requestSecret: result.requestSecret,
        recoveryState: recoveryState,
        busy: false,
        statusMessage:
            'Request submitted. Ask the LocalLink administrator to approve it and provide the recovery code.',
      ));
      startPolling();
    } catch (e) {
      emit(state.copyWith(
        busy: false,
        error: _cleanRecoveryError(errorMessage(e)),
        clearStatusMessage: true,
      ));
    }
  }

  String _cleanRecoveryError(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('server') ||
        lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('socket')) {
      return 'Could not connect to LocalLink. Make sure the LocalLink server is available on your private network.';
    }
    return value;
  }

  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => pollOnce());
  }

  Future<void> pollOnce() async {
    final selectedServer = state.server;
    final id = state.requestId;
    final secret = state.requestSecret;
    if (selectedServer == null || id == null || secret == null) return;

    try {
      final current = await repository.recoveryStatus(
        server: selectedServer,
        requestId: id,
        requestSecret: secret,
      );
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
          targetDeviceId: current.targetDeviceId,
        ),
        statusMessage: message,
        clearError: true,
      ));
      if ({'approved', 'rejected', 'expired', 'completed'}
          .contains(current.status)) {
        _timer?.cancel();
      }
    } catch (_) {}
  }

  Future<api.AccountRecoveryResult?> complete({
    required String recoveryCode,
  }) async {
    if (state.busy ||
        state.server == null ||
        state.requestId == null ||
        state.requestSecret == null) {
      return null;
    }

    final code = recoveryCode.trim();
    if (code.isEmpty) {
      emit(state.copyWith(error: 'Enter the recovery code.'));
      return null;
    }

    emit(state.copyWith(
      busy: true,
      clearError: true,
      statusMessage: 'Completing secure account recovery…',
    ));

    try {
      final id = repository.deviceId;
      if (id == null || id.isEmpty) {
        throw StateError('New device identity is not initialized.');
      }
      const deviceName = 'My Android Phone';
      final key = await repository.publicKey();
      final result = await repository.completeRecovery(
        server: state.server!,
        requestId: state.requestId!,
        requestSecret: state.requestSecret!,
        recoveryCredential: code,
        deviceId: id,
        deviceName: deviceName,
        identityPublicKey: key,
      );
      await repository.saveConfiguration(
        server: state.server!,
        id: result.device.id,
        name: result.device.name,
        token: result.token,
        accountId: result.account.id,
        username: result.account.username,
      );
      await repository.saveProfile(result.profile);
      await repository.clearPendingRequest();
      _timer?.cancel();
      emit(state.copyWith(
        busy: false,
        statusMessage: 'Account recovered successfully.',
      ));
      return result;
    } catch (e) {
      emit(state.copyWith(
        busy: false,
        error: _cleanRecoveryError(errorMessage(e)),
      ));
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
