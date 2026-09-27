import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';

final class RecoveryStatusState extends Equatable {
  final Map<String, String>? saved;
  final AccountRecoveryState? recoveryState;
  final bool loading;
  final String? error;
  const RecoveryStatusState(
      {this.saved, this.recoveryState, this.loading = true, this.error});
  bool get hasRequest => saved != null;
  RecoveryStatusState copyWith(
          {Map<String, String>? saved,
          AccountRecoveryState? recoveryState,
          bool? loading,
          String? error,
          bool clearError = false}) =>
      RecoveryStatusState(
          saved: saved ?? this.saved,
          recoveryState: recoveryState ?? this.recoveryState,
          loading: loading ?? this.loading,
          error: clearError ? null : (error ?? this.error));
  @override
  List<Object?> get props => [saved, recoveryState, loading, error];
}

final class RecoveryStatusBloc extends Cubit<RecoveryStatusState> {
  final RecoveryRepositoryContract repository;
  Timer? _timer;
  RecoveryStatusBloc(this.repository) : super(const RecoveryStatusState());
  Map<String, String>? get saved => state.saved;
  AccountRecoveryState? get recoveryState => state.recoveryState;
  bool get loading => state.loading;
  String? get error => state.error;
  bool get hasRequest => state.hasRequest;
  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final saved = await repository.pendingRequest();
      emit(state.copyWith(saved: saved));
      if (saved != null) {
        await poll();
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 4), (_) => poll());
      }
    } catch (e) {
      emit(state.copyWith(error: cleanBlocError(e)));
    }
    emit(state.copyWith(loading: false));
  }

  Future<void> poll() async {
    final server = repository.serverAddress,
        id = state.saved?['request_id'],
        secret = state.saved?['request_secret'];
    if (server == null || id == null || secret == null) {
      emit(state.copyWith(loading: false));
      return;
    }
    try {
      final s = await repository.recoveryStatus(
          server: server, requestId: id, requestSecret: secret);
      emit(state.copyWith(recoveryState: s, loading: false, clearError: true));
      if ({'completed', 'rejected', 'expired'}.contains(s.status))
        _timer?.cancel();
    } catch (_) {
      emit(state.copyWith(
          error:
              'Could not refresh the request. The local network may be temporarily unavailable.',
          loading: false));
    }
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    return super.close();
  }
}
