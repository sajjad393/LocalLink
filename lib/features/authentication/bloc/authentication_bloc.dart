import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';

final class AuthenticationState extends Equatable {
  final bool registerMode;
  final bool busy;
  final String? error;

  const AuthenticationState({
    this.registerMode = false,
    this.busy = false,
    this.error,
  });

  AuthenticationState copyWith({
    bool? registerMode,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return AuthenticationState(
      registerMode: registerMode ?? this.registerMode,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [registerMode, busy, error];
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
      emit(state.copyWith(error: _cleanAuthenticationError(message)));
      rethrow;
    } finally {
      emit(state.copyWith(busy: false));
    }
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
