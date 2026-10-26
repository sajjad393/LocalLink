import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';

/// Bundle 110: submit() outcome — either a server-authenticated session or a
/// silent offline reopen of a locally known account. No message is emitted on
/// either success path.
final class AuthOutcome {
  final AuthResult? result;
  final bool offline;

  const AuthOutcome.online(this.result) : offline = false;

  const AuthOutcome.offline()
      : result = null,
        offline = true;

  bool get online => result != null;
}

final class AuthenticationState extends Equatable {
  final bool registerMode;
  final bool busy;
  final String? error;

  /// Bundle 102: the last submit failed because no server was reachable —
  /// the register screen may now offer the offline account path.
  final bool offlineRegisterAvailable;

  const AuthenticationState({
    this.registerMode = false,
    this.busy = false,
    this.error,
    this.offlineRegisterAvailable = false,
  });

  AuthenticationState copyWith({
    bool? registerMode,
    bool? busy,
    String? error,
    bool clearError = false,
    bool? offlineRegisterAvailable,
  }) {
    return AuthenticationState(
      registerMode: registerMode ?? this.registerMode,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      offlineRegisterAvailable:
          offlineRegisterAvailable ?? this.offlineRegisterAvailable,
    );
  }

  @override
  List<Object?> get props =>
      [registerMode, busy, error, offlineRegisterAvailable];
}

final class AuthenticationBloc extends Cubit<AuthenticationState> {
  final AuthenticationRepositoryContract repository;

  AuthenticationBloc(
    this.repository, {
    bool registerMode = false,
  }) : super(AuthenticationState(registerMode: registerMode));

  bool get registerMode => state.registerMode;
  bool get busy => state.busy;
  String? get error => state.error;

  void clearError() {
    if (state.error != null) emit(state.copyWith(clearError: true));
  }

  Future<AuthOutcome> submit({
    required String username,
    required String password,
  }) async {
    final user = username.trim().toLowerCase();
    if (user.isEmpty || password.isEmpty) {
      throw _validation('Enter your username and password.');
    }
    if (!RegExp(r'^[a-z0-9_][a-z0-9_.-]{2,31}$').hasMatch(user)) {
      throw _validation(
        'Username must be 3–32 characters and use letters, numbers, dot, dash, or underscore.',
      );
    }
    if (state.registerMode && password.length < 8) {
      throw _validation('Password must be at least 8 characters.');
    }

    emit(state.copyWith(busy: true, clearError: true));
    try {
      final deviceName = repository.generateUniqueDeviceName();
      await repository.prepareForAuthentication(deviceName: deviceName);
      if (state.registerMode) {
        final result = await repository.register(
          username: user,
          password: password,
          deviceName: deviceName,
        );
        await _mirror(user, password, result);
        await repository.completeOfflineLogin(); // clears any prior sign-out gate
        return AuthOutcome.online(result);
      }
      final result = await repository.login(
        username: user,
        password: password,
        deviceName: deviceName,
      );
      await _mirror(user, password, result);
      await repository.completeOfflineLogin();
      return AuthOutcome.online(result);
    } catch (error) {
      if (_isOfflineEligible(error)) {
        // Bundle 110: invisible server-first → offline fallback.
        final offline = await _offlineFallback(user, password);
        if (offline != null) return offline;
      }
      final message = cleanBlocError(error);
      emit(state.copyWith(
        error: _cleanAuthenticationError(message),
        offlineRegisterAvailable: false,
      ));
      rethrow;
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  /// Bundle 110: after an ONLINE success, mirror the credentials into secure
  /// storage so the account can be reopened later without any server. A
  /// mirror failure never fails the login itself.
  Future<void> _mirror(String user, String password, AuthResult result) async {
    try {
      await repository.mirrorOfflineLogin(
        username: user,
        password: password,
        recoveryCode: result.recoveryCode,
      );
    } catch (_) {}
  }

  /// Silent offline path (Bundle 110). Registering while offline creates a
  /// fully local account; logging in reopens a locally known account via its
  /// password, or via its recovery code typed in the password field.
  Future<AuthOutcome?> _offlineFallback(String user, String password) async {
    if (state.registerMode) {
      if (password.length < 8) {
        throw _validation('Password must be at least 8 characters.');
      }
      await repository.registerOffline(username: user, password: password);
      await repository.completeOfflineLogin();
      return const AuthOutcome.offline();
    }
    if (repository.verifyOfflineLogin(user, password) ||
        repository.verifyOfflineRecovery(user, password)) {
      await repository.completeOfflineLogin();
      return const AuthOutcome.offline();
    }
    // Known receiver: the credential simply did not match — say so plainly,
    // with a single fixed message and no connectivity chatter.
    emit(state.copyWith(error: 'That username and password do not match.'));
    throw Exception('That username and password do not match.');
  }

  /// Register without a reachable server (Bundle 102). Returns the recovery
  /// code to display once; the account publishes later when the configured
  /// server answers.
  Future<String> registerOffline({
    required String username,
    required String password,
  }) async {
    final user = username.trim().toLowerCase();
    if (user.isEmpty || password.isEmpty) {
      throw _validation('Enter your username and password.');
    }
    if (!RegExp(r'^[a-z0-9_][a-z0-9_.-]{2,31}$').hasMatch(user)) {
      throw _validation(
        'Username must be 3–32 characters and use letters, numbers, dot, dash, or underscore.',
      );
    }
    if (password.length < 8) {
      throw _validation('Password must be at least 8 characters.');
    }
    emit(state.copyWith(
        busy: true, clearError: true, offlineRegisterAvailable: false));
    try {
      final recovery = await repository.registerOffline(
          username: user, password: password);
      emit(state.copyWith(busy: false));
      return recovery;
    } catch (error) {
      emit(state.copyWith(busy: false, error: cleanBlocError(error)));
      rethrow;
    }
  }

  bool _isOfflineEligible(Object error) {
    if (error is StateError) return true; // prepareForAuthentication failures
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('timeout') ||
        text.contains('clientexception') ||
        text.contains('connection refused') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('no route to host');
  }

  String _cleanAuthenticationError(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('server') ||
        lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('socket')) {
      return 'Could not connect to LocalLink. Make sure the LocalLink server is available on your private network.';
    }
    return value;
  }

  Exception _validation(String message) {
    emit(state.copyWith(error: message));
    return Exception(message);
  }
}
