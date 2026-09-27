import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/models/account_transfer.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';

final class AccountTransferState extends Equatable {
  final AccountTransferStart? transfer;
  final bool loading, cancelling;
  final String? error;
  final Duration remaining;
  const AccountTransferState(
      {this.transfer,
      this.loading = true,
      this.cancelling = false,
      this.error,
      this.remaining = Duration.zero});
  AccountTransferState copyWith(
          {AccountTransferStart? transfer,
          bool? loading,
          bool? cancelling,
          String? error,
          bool clearError = false,
          Duration? remaining}) =>
      AccountTransferState(
          transfer: transfer ?? this.transfer,
          loading: loading ?? this.loading,
          cancelling: cancelling ?? this.cancelling,
          error: clearError ? null : (error ?? this.error),
          remaining: remaining ?? this.remaining);
  @override
  List<Object?> get props => [transfer, loading, cancelling, error, remaining];
}

final class AccountTransferBloc extends Cubit<AccountTransferState> {
  final AccountTransferRepositoryContract repository;
  Timer? _timer;
  AccountTransferBloc(this.repository) : super(const AccountTransferState());
  AccountTransferStart? get transfer => state.transfer;
  bool get loading => state.loading;
  bool get cancelling => state.cancelling;
  String? get error => state.error;
  Duration get remaining => state.remaining;
  Future<void> start() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final t = await repository.start();
      emit(state.copyWith(transfer: t, remaining: _until(t.expiresAt)));
      _startTicker();
    } catch (e) {
      emit(state.copyWith(error: cleanBlocError(e)));
    } finally {
      emit(state.copyWith(loading: false));
    }
  }

  Duration _until(String value) {
    final d = DateTime.tryParse(value)?.toLocal();
    return d == null ? Duration.zero : d.difference(DateTime.now());
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final t = state.transfer;
      if (t == null) return;
      final r = _until(t.expiresAt);
      emit(state.copyWith(remaining: r));
      if (r <= Duration.zero) _timer?.cancel();
    });
  }

  Future<bool> cancel() async {
    final t = state.transfer;
    if (t == null || state.cancelling) return false;
    emit(state.copyWith(cancelling: true));
    try {
      await repository.cancel(t.transferId);
      return true;
    } catch (e) {
      emit(state.copyWith(error: cleanBlocError(e)));
      return false;
    } finally {
      emit(state.copyWith(cancelling: false));
    }
  }

  String remainingLabel() => state.remaining <= Duration.zero
      ? 'Expired'
      : '${state.remaining.inMinutes.toString().padLeft(2, '0')}:${(state.remaining.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Future<void> close() async {
    _timer?.cancel();
    return super.close();
  }
}
