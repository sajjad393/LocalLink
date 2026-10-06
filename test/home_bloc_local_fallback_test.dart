import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';

void main() {
  test('starts nearby discovery once when server sync fails', () async {
    var discoveryAttempts = 0;
    final bloc = HomeBloc(
      repository: _OfflineHomeRepository(),
      onServerSyncUnavailable: () async {
        discoveryAttempts++;
      },
    );
    addTearDown(bloc.close);

    await bloc.load();
    await bloc.load();

    expect(discoveryAttempts, 1);
    expect(bloc.state.loading, isFalse);
    expect(bloc.state.error, contains('Server sync failed'));
    expect(bloc.state.error, contains('showing saved conversations'));
  });

  test('clears the discovery guard after server sync recovers', () async {
    final repository = _OfflineHomeRepository();
    var discoveryAttempts = 0;
    final bloc = HomeBloc(
      repository: repository,
      onServerSyncUnavailable: () async {
        discoveryAttempts++;
      },
    );
    addTearDown(bloc.close);

    await bloc.load();
    repository.offline = false;
    await bloc.load();
    repository.offline = true;
    await bloc.load();

    expect(discoveryAttempts, 2);
  });
}

final class _OfflineHomeRepository implements HomeRepositoryContract {
  bool offline = true;

  @override
  String? get localDeviceId => 'local';

  @override
  Stream<Map<String, dynamic>> get presenceEvents => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get directPresenceEvents => const Stream.empty();

  @override
  Future<List<Device>> devices() async {
    if (offline) throw TimeoutException('Future not completed');
    return const [];
  }

  @override
  Future<List<LocalGroup>> groups() async => const [];

  @override
  Future<List<Device>> localDevices() async => const [
        Device(
          id: 'peer',
          name: 'Saved peer',
          platform: 'android',
          createdAt: '',
          lastSeenAt: '',
        ),
      ];

  @override
  Future<List<LocalGroup>> localGroups() async => const [];

  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) {
    throw UnimplementedError();
  }

  @override
  Future<void> cacheDevice(Device device) async {}
}
