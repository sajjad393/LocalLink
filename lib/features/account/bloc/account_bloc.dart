import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
final class AccountState extends Equatable{final LocalProfile? profile;final bool isLoading,isSaving;final String? errorMessage;const AccountState({this.profile,this.isLoading=false,this.isSaving=false,this.errorMessage});AccountState copyWith({LocalProfile? profile,bool? isLoading,bool? isSaving,String? errorMessage,bool clearError=false})=>AccountState(profile:profile??this.profile,isLoading:isLoading??this.isLoading,isSaving:isSaving??this.isSaving,errorMessage:clearError?null:(errorMessage??this.errorMessage));@override List<Object?> get props=>[profile,isLoading,isSaving,errorMessage];}
final class AccountBloc extends Cubit<AccountState> {
  final AccountRepositoryContract repository;

  AccountBloc(this.repository) : super(const AccountState());

  LocalProfile? get profile => state.profile;
  bool get isLoading => state.isLoading;
  bool get isSaving => state.isSaving;
  String? get errorMessage => state.errorMessage;

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final result = await repository.loadProfile();
      if (isClosed) return;
      emit(state.copyWith(
        profile: result.bestAvailable,
        errorMessage: result.error == null ? null : cleanBlocError(result.error!),
        isLoading: false,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(errorMessage: cleanBlocError(e), isLoading: false));
    }
  }

  Future<bool> saveProfile({
    required String displayName,
    required String username,
    File? avatarFile,
    String phoneNumber = '',
    String phoneVisibility = 'contacts',
    bool discoverableByPhone = true,
    bool discoverableByName = true,
    bool directorySyncEnabled = true,
  }) async {
    if (isClosed) return false;
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      final result = await repository.saveProfile(
        displayName: displayName,
        username: username,
        avatarFile: avatarFile,
        phoneNumber: phoneNumber,
        phoneVisibility: phoneVisibility,
        discoverableByPhone: discoverableByPhone,
        discoverableByName: discoverableByName,
        directorySyncEnabled: directorySyncEnabled,
      );
      if (isClosed) return result.synced;
      emit(state.copyWith(profile: result.profile, isSaving: false));
      return result.synced;
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(errorMessage: cleanBlocError(e), isSaving: false));
      }
      rethrow;
    }
  }
}
