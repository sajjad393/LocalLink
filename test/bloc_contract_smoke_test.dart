import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/locallink_api.dart';

class _Repository implements AccountRepositoryContract {
  @override
  Future<LocalProfile?> cachedProfile() async =>
      const LocalProfile(userId: '1', username: 'demo', displayName: 'Demo');
  @override
  Future<LocalProfile> fetchProfile({bool downloadAvatar = true}) async =>
      (await cachedProfile())!;
  @override
  Future<AccountProfileLoadResult> loadProfile() async =>
      AccountProfileLoadResult(cached: await cachedProfile());
  @override
  Future<AccountProfileSaveResult> saveProfile(
          {required String displayName,
          required String username,
          String phoneNumber = '',
          String phoneVisibility = 'contacts',
          bool discoverableByPhone = true,
          bool discoverableByName = true,
          bool directorySyncEnabled = true,
          File? avatarFile}) async =>
      AccountProfileSaveResult(
          profile: LocalProfile(
              userId: '1',
              username: username,
              displayName: displayName,
              phoneNumber: phoneNumber,
              phoneVisibility: phoneVisibility,
              discoverableByPhone: discoverableByPhone,
              discoverableByName: discoverableByName,
              directorySyncEnabled: directorySyncEnabled),
          synced: true);
  @override
  Future<bool> syncPendingProfile() async => true;
  @override
  Future<List<Device>> trustedDevices() async => const [];
  @override
  Future<void> revokeDevice(String deviceId) async {}
  @override
  Future<RecoveryCodeStatus> recoveryCodeStatus() async =>
      const RecoveryCodeStatus(configured: false, createdAt: '', rotatedAt: '');
  @override
  Future<String> rotateRecoveryCode() async => 'code';
  @override
  Future<void> disableRecoveryCode() async {}
}

void main() {
  blocTest<AccountBloc, AccountState>(
    'emits loaded account state',
    build: () => AccountBloc(_Repository()),
    act: (bloc) => bloc.load(),
    expect: () => [
      isA<AccountState>().having((s) => s.isLoading, 'loading', true),
      isA<AccountState>()
          .having((s) => s.profile?.username, 'username', 'demo'),
    ],
  );
}
