import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// UI mode for an already-authenticated LocalLink identity.
///
/// The mode changes presentation only. Administrative authorization continues
/// to come from the authenticated backend admin session.
enum AppViewMode { user, admin }

final class AppViewModeState extends Equatable {
  final AppViewMode mode;
  final bool adminCapable;
  final bool serverConnected;

  const AppViewModeState({
    this.mode = AppViewMode.user,
    this.adminCapable = false,
    this.serverConnected = false,
  });

  AppViewModeState copyWith({
    AppViewMode? mode,
    bool? adminCapable,
    bool? serverConnected,
  }) =>
      AppViewModeState(
        mode: mode ?? this.mode,
        adminCapable: adminCapable ?? this.adminCapable,
        serverConnected: serverConnected ?? this.serverConnected,
      );

  @override
  List<Object?> get props => [mode, adminCapable, serverConnected];
}

final class AppViewModeCubit extends Cubit<AppViewModeState> {
  AppViewModeCubit() : super(const AppViewModeState());

  /// Bundle 134: an admin opens the panel even when the server is unreachable —
  /// the panel itself locks its server-only modules while offline.
  bool get canEnterAdminView => state.adminCapable;

  /// Bundle 162 (6.1): a server drop no longer throws the admin out of the
  /// admin view — it stays, and the panel locks its server-only parts
  /// (same rule as entering offline, Bundle 134).
  void setServerConnected(bool connected) {
    emit(state.copyWith(serverConnected: connected));
  }

  void setAdminCapability(bool capable) {
    if (!capable && state.mode == AppViewMode.admin) {
      emit(state.copyWith(mode: AppViewMode.user, adminCapable: false));
      return;
    }
    emit(state.copyWith(adminCapable: capable));
  }

  bool enterAdminView() {
    if (!canEnterAdminView) return false;
    emit(state.copyWith(mode: AppViewMode.admin));
    return true;
  }

  void enterUserView() {
    emit(state.copyWith(mode: AppViewMode.user));
  }

  /// Security-safe reset. View mode is deliberately not persisted.
  void reset() => emit(const AppViewModeState());
}
