import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/account/bloc/devices_bloc.dart';

class _FakeAccountRepository implements AccountRepositoryContract {
  LocalProfile? profileValue;
  List<Device> devicesValue = const [];
  Object? loadError;
  bool synced = true;
  int revokeCalls = 0;

  @override
  Future<LocalProfile?> cachedProfile() async => profileValue;

  @override
  Future<LocalProfile> fetchProfile({bool downloadAvatar = true}) async =>
      profileValue!;

  @override
  Future<AccountProfileLoadResult> loadProfile() async =>
      AccountProfileLoadResult(cached: profileValue, error: loadError);

  @override
  Future<AccountProfileSaveResult> saveProfile(
      {required String displayName,
      required String username,
      String phoneNumber = '',
      String phoneVisibility = 'contacts',
      bool discoverableByPhone = true,
      bool discoverableByName = true,
      bool directorySyncEnabled = true,
      File? avatarFile}) async {
    profileValue = LocalProfile(
        userId: 'account-1',
        username: username,
        displayName: displayName,
        phoneNumber: phoneNumber,
        phoneVisibility: phoneVisibility,
        discoverableByPhone: discoverableByPhone,
        discoverableByName: discoverableByName,
        directorySyncEnabled: directorySyncEnabled);
    return AccountProfileSaveResult(profile: profileValue!, synced: synced);
  }

  @override
  Future<bool> syncPendingProfile() async => synced;

  @override
  Future<List<Device>> trustedDevices() async => devicesValue;

  @override
  Future<void> revokeDevice(String deviceId) async {
    revokeCalls++;
    devicesValue = devicesValue.where((d) => d.id != deviceId).toList();
  }

  @override
  Future<RecoveryCodeStatus> recoveryCodeStatus() async =>
      const RecoveryCodeStatus(configured: false, createdAt: '', rotatedAt: '');

  @override
  Future<String> rotateRecoveryCode() async => 'test-code';

  @override
  Future<void> disableRecoveryCode() async {}
}

void main() {
  test('AccountBloc loads cached profile and preserves offline error state',
      () async {
    final repo = _FakeAccountRepository()
      ..profileValue = const LocalProfile(
          userId: '1', username: 'sajjad', displayName: 'Sajjad')
      ..loadError = StateError('offline');
    final controller = AccountBloc(repo);

    await controller.load();

    expect(controller.profile?.username, 'sajjad');
    expect(controller.errorMessage, contains('offline'));
    expect(controller.isLoading, isFalse);
  });

  test('AccountBloc saves profile through repository', () async {
    final repo = _FakeAccountRepository();
    final controller = AccountBloc(repo);

    final synced = await controller.saveProfile(
        displayName: 'New Name', username: 'newname', avatarFile: null);

    expect(synced, isTrue);
    expect(controller.profile?.displayName, 'New Name');
    expect(controller.profile?.username, 'newname');
    expect(controller.isSaving, isFalse);
  });

  test('DevicesBloc revokes a non-current device and refreshes', () async {
    final repo = _FakeAccountRepository()
      ..devicesValue = [
        const Device(
            id: 'current',
            name: 'This phone',
            platform: 'android',
            createdAt: '',
            lastSeenAt: '',
            current: true),
        const Device(
            id: 'old',
            name: 'Old phone',
            platform: 'android',
            createdAt: '',
            lastSeenAt: ''),
      ];
    final controller = DevicesBloc(repo);

    await controller.load();
    await controller.revoke(controller.devices.last);

    expect(repo.revokeCalls, 1);
    expect(controller.devices.map((d) => d.id), ['current']);
  });
}
