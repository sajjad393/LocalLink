import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';

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

  Future<AuthResult> submit({
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
        return await repository.register(
          username: user,
          password: password,
          deviceName: deviceName,
        );
      }
      return await repository.login(
        username: user,
        password: password,
        deviceName: deviceName,
      );
    } catch (error) {
      final message = cleanBlocError(error);
      emit(state.copyWith(
        error: _cleanAuthenticationError(message),
        offlineRegisterAvailable:
            state.registerMode && _isOfflineEligible(error),
      ));
      rethrow;
    } finally {
      emit(state.copyWith(busy: false));
    }
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
