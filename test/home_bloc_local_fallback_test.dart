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
    // A failing BACKGROUND sync must stay silent: no red error banner and no
    // chatty notice at all - saved conversations keep rendering and sync
    // retries itself. Never a raw exception, anywhere.
    expect(bloc.state.error, isNull);
    expect(bloc.state.syncNotice, isNull,
        reason:
            'background sync failures stay silent; only an explicit retry earns one calm line');
  });

  test('an explicit user refresh earns one calm friendly notice', () async {
    final bloc = HomeBloc(repository: _OfflineHomeRepository());
    addTearDown(bloc.close);

    await bloc.load(userInitiated: true);

    expect(bloc.state.loading, isFalse);
    // Standing design rule: an explicit retry earns ONE short friendly
    // sentence as a calm neutral notice - never a red banner, never raw
    // error text (no exception names, no technical detail).
    expect(bloc.state.error, isNull);
    expect(bloc.state.syncNotice,
        "Couldn't sync right now — showing your saved conversations.");
    expect(bloc.state.syncNotice, isNot(contains('TimeoutException')));
    expect(bloc.state.syncNotice, isNot(contains('took too long')));
    expect(bloc.state.syncNotice, isNot(contains('Server sync failed')));
  });

  test('conversation titles prefer the directory person over the device name', () async {
    final repository = _OfflineHomeRepository()..offline = false;
    final bloc = HomeBloc(repository: repository);
    addTearDown(bloc.close);

    await bloc.load();

    expect(bloc.state.deviceLabels['peer'], 'sana.oz');
    expect(bloc.state.deviceLabels.containsKey('unresolved'), isFalse);
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
    return const [
      Device(
        id: 'peer',
        name: 'My Android Phone',
        platform: 'android',
        createdAt: '',
        lastSeenAt: '',
      ),
      Device(
        id: 'unresolved',
        name: 'My Android Phone',
        platform: 'android',
        createdAt: '',
        lastSeenAt: '',
      ),
    ];
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

  @override
  Future<void> markDeviceSeen(String deviceId) async {}

  @override
  Future<String?> userIdForDevice(String deviceId) async => null;

  @override
  Future<String?> labelForDevice(String deviceId) async =>
      deviceId == 'peer' ? 'sana.oz' : null;
}
