import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/features/account/data/models/identity_key_history.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';

final class IdentityState extends Equatable {
  final int currentVersion;
  final String currentPublicKey;
  final List<IdentityKeyHistoryEntry> history;
  final bool isLoading;
  final bool isRotating;
  final String? errorMessage;

  const IdentityState({
    this.currentVersion = 1,
    this.currentPublicKey = '',
    this.history = const [],
    this.isLoading = true,
    this.isRotating = false,
    this.errorMessage,
  });

  IdentityState copyWith({
    int? currentVersion,
    String? currentPublicKey,
    List<IdentityKeyHistoryEntry>? history,
    bool? isLoading,
    bool? isRotating,
    String? errorMessage,
    bool clearError = false,
  }) =>
      IdentityState(
        currentVersion: currentVersion ?? this.currentVersion,
        currentPublicKey: currentPublicKey ?? this.currentPublicKey,
        history: history ?? this.history,
        isLoading: isLoading ?? this.isLoading,
        isRotating: isRotating ?? this.isRotating,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );

  @override
  List<Object?> get props => [
        currentVersion,
        currentPublicKey,
        history,
        isLoading,
        isRotating,
        errorMessage,
      ];
}

final class IdentityBloc extends Cubit<IdentityState> {
  final IdentityRepositoryContract repository;

  IdentityBloc(this.repository) : super(const IdentityState());

  int get currentVersion => state.currentVersion;
  String get currentPublicKey => state.currentPublicKey;
  List<IdentityKeyHistoryEntry> get history => state.history;
  bool get isLoading => state.isLoading;
  bool get isRotating => state.isRotating;
  String? get errorMessage => state.errorMessage;

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final result = await repository.load();
      if (isClosed) return;
      emit(state.copyWith(
        currentVersion: result.keyVersion,
        currentPublicKey: result.publicKey,
        history: result.history,
        isLoading: false,
      ));
    } catch (error) {
      if (isClosed) return;
      emit(state.copyWith(errorMessage: cleanBlocError(error), isLoading: false));
    }
  }

  Future<void> rotate() async {
    if (isClosed) return;
    emit(state.copyWith(isRotating: true, clearError: true));
    try {
      final result = await repository.rotate();
      if (isClosed) return;
      emit(state.copyWith(
        currentVersion: result.keyVersion,
        currentPublicKey: result.publicKey,
        history: result.history,
        isRotating: false,
      ));
    } catch (error) {
      if (isClosed) return;
      emit(state.copyWith(errorMessage: cleanBlocError(error), isRotating: false));
      rethrow;
    }
  }
}
