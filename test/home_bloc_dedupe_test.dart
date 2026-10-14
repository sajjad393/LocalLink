// Conversation-list identity: several devices that belong to the same
// directory user must produce a single conversation tile, never duplicates.
// See HomeBloc._collapseDeviceDuplicates.

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';

Device _device(
  String id, {
  bool online = false,
  String lastSeen = '2026-01-01T00:00:00Z',
}) =>
    Device(
      id: id,
      name: 'Device $id',
      platform: 'android',
      createdAt: '2026-01-01T00:00:00Z',
      lastSeenAt: lastSeen,
      serverConnected: online,
    );

final class _StubHomeRepository implements HomeRepositoryContract {
  _StubHomeRepository(this.deviceList, this.userByDevice);

  List<Device> deviceList;
  Map<String, String> userByDevice;

  @override
  String? get localDeviceId => 'me';

  @override
  Stream<Map<String, dynamic>> get presenceEvents => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get directPresenceEvents => const Stream.empty();

  @override
  Future<List<Device>> devices() async => deviceList;

  @override
  Future<List<LocalGroup>> groups() async => const <LocalGroup>[];

  @override
  Future<List<Device>> localDevices() async => deviceList;

  @override
  Future<List<LocalGroup>> localGroups() async => const <LocalGroup>[];

  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) =>
      throw UnimplementedError();

  @override
  Future<void> cacheDevice(Device device) async {}

  @override
  Future<String?> userIdForDevice(String deviceId) async =>
      userByDevice[deviceId];

  @override
  Future<String?> labelForDevice(String deviceId) async => null;
}

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  test('two devices of the same user collapse into one conversation', () async {
    final repository = _StubHomeRepository(
      <Device>[
        _device('phone-old', lastSeen: '2026-01-02T00:00:00Z'),
        _device('phone-new', online: true, lastSeen: '2026-03-01T00:00:00Z'),
      ],
      <String, String>{'phone-old': 'user-1', 'phone-new': 'user-1'},
    );
    final bloc = HomeBloc(repository: repository);
    addTearDown(bloc.close);

    await bloc.load();
    await _pump();

    expect(bloc.state.devices, hasLength(1),
        reason: 'one user must never produce two conversation entries');
    expect(bloc.state.devices.single.id, 'phone-new',
        reason: 'the reachable, most recently seen device represents the user');
  });

  test('devices without a directory user stay as individual entries', () async {
    final repository = _StubHomeRepository(
      <Device>[_device('ghost-1'), _device('ghost-2')],
      const <String, String>{},
    );
    final bloc = HomeBloc(repository: repository);
    addTearDown(bloc.close);

    await bloc.load();
    await _pump();

    expect(bloc.state.devices.map((d) => d.id),
        containsAll(<String>['ghost-1', 'ghost-2']));
  });

  test('mixed list keeps one tile per user plus unmapped devices', () async {
    final repository = _StubHomeRepository(
      <Device>[
        _device('a-tablet', lastSeen: '2026-02-01T00:00:00Z'),
        _device('a-phone', lastSeen: '2026-01-01T00:00:00Z'),
        _device('b-phone', lastSeen: '2026-01-05T00:00:00Z'),
        _device('stray', lastSeen: '2026-01-06T00:00:00Z'),
      ],
      <String, String>{
        'a-tablet': 'user-a',
        'a-phone': 'user-a',
        'b-phone': 'user-b',
      },
    );
    final bloc = HomeBloc(repository: repository);
    addTearDown(bloc.close);

    await bloc.load();
    await _pump();

    expect(
      bloc.state.devices.map((d) => d.id),
      containsAll(<String>['a-tablet', 'b-phone', 'stray']),
    );
    expect(bloc.state.devices, hasLength(3));
    expect(
      bloc.state.devices.where((d) => d.id == 'a-phone'),
      isEmpty,
      reason: 'the older device of user-a folds into the single tile',
    );
  });
}
