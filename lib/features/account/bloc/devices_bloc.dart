import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';

final class DevicesState extends Equatable {
  final List<Device> devices;
  final bool isLoading;
  final String? errorMessage;

  const DevicesState({
    this.devices = const [],
    this.isLoading = true,
    this.errorMessage,
  });

  DevicesState copyWith({
    List<Device>? devices,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) =>
      DevicesState(
        devices: devices ?? this.devices,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );

  @override
  List<Object?> get props => [devices, isLoading, errorMessage];
}

final class DevicesBloc extends Cubit<DevicesState> {
  final AccountRepositoryContract repository;

  DevicesBloc(this.repository) : super(const DevicesState());

  List<Device> get devices => state.devices;
  bool get isLoading => state.isLoading;
  String? get errorMessage => state.errorMessage;

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final devices = await repository.trustedDevices();
      if (isClosed) return;
      emit(state.copyWith(devices: devices, isLoading: false));
    } catch (error) {
      if (isClosed) return;
      emit(state.copyWith(errorMessage: cleanBlocError(error), isLoading: false));
    }
  }

  Future<void> revoke(Device device) async {
    if (isClosed || device.current) return;
    await repository.revokeDevice(device.id);
    if (!isClosed) await load();
  }
}
