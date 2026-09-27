import 'dart:io';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/locallink_api.dart';

abstract interface class AccountRepositoryContract {
  Future<LocalProfile?> cachedProfile();
  Future<LocalProfile> fetchProfile({bool downloadAvatar = true});
  Future<AccountProfileLoadResult> loadProfile();
  Future<AccountProfileSaveResult> saveProfile({required String displayName, required String username, File? avatarFile, String phoneNumber = '', String phoneVisibility = 'contacts', bool discoverableByPhone = true, bool discoverableByName = true, bool directorySyncEnabled = true});
  Future<bool> syncPendingProfile();
  Future<List<Device>> trustedDevices();
  Future<void> revokeDevice(String deviceId);
  Future<RecoveryCodeStatus> recoveryCodeStatus();
  Future<String> rotateRecoveryCode();
  Future<void> disableRecoveryCode();
}

class AccountProfileLoadResult {
  final LocalProfile? cached; final LocalProfile? remote; final Object? error;
  const AccountProfileLoadResult({this.cached, this.remote, this.error});
  LocalProfile? get bestAvailable => remote ?? cached;
}

class AccountProfileSaveResult {
  final LocalProfile profile; final bool synced;
  const AccountProfileSaveResult({required this.profile, required this.synced});
}
