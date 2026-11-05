import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/errors/error_message.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/locallink_api.dart' as api;
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
            'Request submitted. Ask the LinkUp administrator to approve it and provide the recovery code.',
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
      return 'Could not connect to LinkUp. Make sure the LinkUp server is available on your private network.';
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

// ---------------------------------------------------------------- Bundle 222

/// Which tab of "Forgot password" is open (mocks R-2 / R-3 / R-5).
enum ForgotTab222 { haveCode, noCode }

final class ForgotPasswordState222 extends Equatable {
  final ForgotTab222 tab;
  /// null = still checking the server.
  final bool? online;
  final bool busy;
  final String? error;
  /// Set when the password is changed: the NEW recovery code (R-4), or ''
  /// when it was changed with no server (the new code comes after sync).
  final String? doneCode;
  final bool doneOffline;
  // "I don't have it" request (R-5).
  final String? server;
  final String? requestId;
  final String? requestSecret;
  final String requestUsername;
  final String requestStatus;
  final String rejectedReason;

  const ForgotPasswordState222({
    this.tab = ForgotTab222.haveCode,
    this.online,
    this.busy = false,
    this.error,
    this.doneCode,
    this.doneOffline = false,
    this.server,
    this.requestId,
    this.requestSecret,
    this.requestUsername = '',
    this.requestStatus = '',
    this.rejectedReason = '',
  });

  bool get hasRequest => requestId != null && requestSecret != null;

  ForgotPasswordState222 copyWith({
    ForgotTab222? tab,
    bool? online,
    bool? busy,
    String? error,
    bool clearError = false,
    String? doneCode,
    bool? doneOffline,
    String? server,
    String? requestId,
    String? requestSecret,
    String? requestUsername,
    String? requestStatus,
    String? rejectedReason,
    bool clearRequest = false,
  }) {
    return ForgotPasswordState222(
      tab: tab ?? this.tab,
      online: online ?? this.online,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      doneCode: doneCode ?? this.doneCode,
      doneOffline: doneOffline ?? this.doneOffline,
      server: clearRequest ? null : (server ?? this.server),
      requestId: clearRequest ? null : (requestId ?? this.requestId),
      requestSecret: clearRequest ? null : (requestSecret ?? this.requestSecret),
      requestUsername: clearRequest ? '' : (requestUsername ?? this.requestUsername),
      requestStatus: clearRequest ? '' : (requestStatus ?? this.requestStatus),
      rejectedReason: clearRequest ? '' : (rejectedReason ?? this.rejectedReason),
    );
  }

  @override
  List<Object?> get props => [tab, online, busy, error, doneCode, doneOffline, server, requestId, requestSecret, requestUsername, requestStatus, rejectedReason];
}

/// Bundle 222: "Forgot password" — recovery code + new password (online or,
/// on the same phone, with no server), or a no-code request to the admin.
final class ForgotPasswordBloc222 extends Cubit<ForgotPasswordState222> {
  final RecoveryRepositoryContract repository;
  Timer? _poll;

  /// The no-code request is checked this often while the screen is open.
  static const pollEvery = Duration(seconds: 30);

  ForgotPasswordBloc222(this.repository) : super(const ForgotPasswordState222());

  Future<void> start() async {
    await checkServer();
    final saved = await repository.pendingRequest();
    final server = repository.serverAddress ?? '';
    if (saved != null && server.isNotEmpty) {
      emit(state.copyWith(
        tab: ForgotTab222.noCode,
        server: server,
        requestId: saved['request_id'],
        requestSecret: saved['request_secret'],
        requestStatus: 'pending',
      ));
      await pollOnce();
      _startPolling();
    }
  }

  Future<void> checkServer() async {
    final online = await repository.serverOnline222();
    if (!isClosed) emit(state.copyWith(online: online));
  }

  void selectTab(ForgotTab222 tab) {
    if (state.busy) return;
    emit(state.copyWith(tab: tab, clearError: true));
  }

  void clearError() {
    if (state.error != null) emit(state.copyWith(clearError: true));
  }

  /// Same rules as register: 8..128, typed the same twice, no control
  /// characters. Returns the text to show, or null when fine.
  static String? passwordProblem(String password, String again) {
    if (password.length < 8) return 'Password must be at least 8 characters.';
    if (password.length > 128) return 'Password is too long.';
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(password)) return 'Password has a character that is not allowed.';
    if (password != again) return 'The two passwords are not the same.';
    return null;
  }

  static bool codeLooksRight(String code) =>
      code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length == 20;

  /// R-2 / R-3 "Set new password".
  Future<void> resetWithCode({
    required String username,
    required String recoveryCode,
    required String newPassword,
    required String again,
  }) async {
    if (state.busy) return;
    final user = username.trim().toLowerCase();
    if (user.isEmpty) return _fail('Enter your username.');
    if (!codeLooksRight(recoveryCode)) return _fail('Enter your recovery code (like K7QM2-XPA9T-RC4WN-E8D3F).');
    final problem = passwordProblem(newPassword, again);
    if (problem != null) return _fail(problem);
    emit(state.copyWith(busy: true, clearError: true));
    final online = state.online ?? await repository.serverOnline222();
    try {
      if (online) {
        final result = await repository.resetWithCode222(username: user, recoveryCode: recoveryCode, newPassword: newPassword);
        emit(state.copyWith(busy: false, online: true, doneCode: result.recoveryCode, doneOffline: false));
      } else {
        await repository.resetOffline222(username: user, recoveryCode: recoveryCode, newPassword: newPassword);
        emit(state.copyWith(busy: false, online: false, doneCode: '', doneOffline: true));
      }
    } catch (error) {
      if (online && _isNetwork(error)) {
        // The server went away between the check and the send.
        emit(state.copyWith(busy: false, online: false, error: 'Could not reach the server. Try again.'));
        AppLogger.info('RESET_CODE_FAIL', detail: 'reason=net');
        return;
      }
      AppLogger.info('RESET_CODE_FAIL', detail: 'reason=${_reasonOf(error)}');
      emit(state.copyWith(busy: false, error: textFor222(error)));
    }
  }

  /// R-5: username only → request to the admin (needs the server).
  Future<void> askAdmin({required String username}) async {
    if (state.busy) return;
    final user = username.trim().toLowerCase();
    if (user.isEmpty) return _fail('Enter your username.');
    if (state.online == false) return _fail('This needs the server. Try again when the server is back.');
    emit(state.copyWith(busy: true, clearError: true));
    try {
      final out = await repository.createNoCodeRequest222(username: user);
      emit(state.copyWith(
        busy: false,
        server: out.server,
        requestId: out.start.requestId,
        requestSecret: out.start.requestSecret,
        requestUsername: out.start.username.isEmpty ? user : out.start.username,
        requestStatus: out.start.status.isEmpty ? 'pending' : out.start.status,
      ));
      _startPolling();
    } catch (error) {
      emit(state.copyWith(busy: false, error: _isNetwork(error) ? 'This needs the server. Try again when the server is back.' : textFor222(error)));
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollEvery, (_) => pollOnce());
  }

  Future<void> pollOnce() async {
    final server = state.server;
    final id = state.requestId;
    final secret = state.requestSecret;
    if (server == null || id == null || secret == null) return;
    try {
      final now = await repository.recoveryStatus(server: server, requestId: id, requestSecret: secret);
      if (isClosed) return;
      if (now.status == 'approved' && state.requestStatus != 'approved') {
        AppLogger.info('RECOVERY_NOCODE_APPROVED');
      }
      emit(state.copyWith(
        requestUsername: now.username.isEmpty ? state.requestUsername : now.username,
        requestStatus: now.status,
        rejectedReason: now.rejectedReason,
      ));
      if (now.status == 'rejected' || now.status == 'completed') _poll?.cancel();
    } catch (_) {}
  }

  /// R-5 "Set new password" with the admin's one-time code.
  Future<void> completeNoCode({
    required String oneTimeCode,
    required String newPassword,
    required String again,
  }) async {
    if (state.busy || !state.hasRequest) return;
    final digits = oneTimeCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 12) return _fail('Enter the 12-digit code from the admin.');
    final problem = passwordProblem(newPassword, again);
    if (problem != null) return _fail(problem);
    emit(state.copyWith(busy: true, clearError: true));
    try {
      final code = await repository.completeNoCode222(
        server: state.server!,
        requestId: state.requestId!,
        requestSecret: state.requestSecret!,
        oneTimeCode: digits,
        newPassword: newPassword,
      );
      _poll?.cancel();
      emit(state.copyWith(busy: false, doneCode: code, doneOffline: false));
    } catch (error) {
      final lower = error.toString().toLowerCase();
      final text = lower.contains('not approved') || lower.contains('pending')
          ? 'The admin has not approved it yet.'
          : (lower.contains('credential') || lower.contains('invalid recovery') || lower.contains('expired'))
              ? 'The code is wrong or too old. Ask the admin for a new code.'
              : textFor222(error);
      emit(state.copyWith(busy: false, error: text));
    }
  }

  /// "Cancel request": forget it on this phone (the admin's list keeps it).
  Future<void> cancelRequest() async {
    _poll?.cancel();
    await repository.clearPendingRequest();
    emit(state.copyWith(clearRequest: true, clearError: true));
  }

  void _fail(String text) => emit(state.copyWith(error: text));

  static bool _isNetwork(Object error) {
    if (error is StateError) return true;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('timeout') ||
        text.contains('clientexception') ||
        text.contains('connection refused') ||
        text.contains('no route to host') ||
        text.contains('network is unreachable');
  }

  static String _reasonOf(Object error) {
    if (error is api.ApiError218) return '${error.status}';
    if (error is ResetProblem222) return error.reason;
    return 'other';
  }

  /// The plain words for every answer (EN; UR in the screen's word list).
  static String textFor222(Object error) {
    if (error is ResetProblem222) {
      return error.reason == 'not_last'
          ? 'Without the server this works only for the last account on this phone.'
          : 'Username or recovery code is wrong.';
    }
    if (error is api.ApiError218) {
      switch (error.code) {
        case 'BAD_RECOVERY_CODE':
          return 'Username or recovery code is wrong.';
        case 'RATE_LIMIT':
          return 'Too many tries. Try again in 1 minute.';
        case 'NOT_ACTIVE':
          return 'This account is not active. Ask the admin.';
        case 'PAIRING_REQUIRED':
          return 'This phone is not paired with the server yet. Ask the admin for the pairing code.';
        case 'NO_ACCOUNT':
          return 'No account with this username.';
        case 'BAD_RESET_DATA':
          return 'Check the new password and try again.';
      }
      if (error.status == 429) return 'Too many tries. Try again in 1 minute.';
    }
    final text = errorMessage(error);
    if (text.toLowerCase().contains('too many')) return 'Too many tries. Try again in 1 minute.';
    return text;
  }

  @override
  Future<void> close() async {
    _poll?.cancel();
    return super.close();
  }
}
