import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/bloc/group_members_bloc.dart';

class _FakeGroupRepository implements GroupRepositoryContract {
  List<LocalGroup> groupsValue = const [];
  List<GroupMember> membersValue = const [];
  List<Device> devicesValue = const [];
  final created = <LocalGroup>[];
  final added = <String>[];
  final removed = <String>[];

  @override
  Future<List<LocalGroup>> listGroups() async => List.of(groupsValue);

  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) async {
    final group = LocalGroup(
      id: 'g-${created.length + 1}',
      name: name,
      ownerId: 'local-device',
      createdAt: 'now',
    );
    created.add(group);
    groupsValue = [...groupsValue, group];
    return group;
  }

  @override
  Future<List<GroupMember>> listMembers(String groupId) async =>
      List.of(membersValue);

  @override
  Future<List<Device>> availableMemberDevices() async => List.of(devicesValue);

  @override
  Future<void> addMember(String groupId, String deviceId) async =>
      added.add(deviceId);

  @override
  Future<void> removeMember(String groupId, String deviceId) async =>
      removed.add(deviceId);
}

void main() {
  test('GroupMembersBloc exposes only devices not already in the group',
      () async {
    final repository = _FakeGroupRepository();
    repository.membersValue = const [
      GroupMember(
        groupId: 'g1',
        deviceId: 'peer-1',
        role: 'member',
        joinedAt: 'now',
        name: 'Peer 1',
      ),
      GroupMember(
        groupId: 'g1',
        deviceId: 'local-device',
        role: 'owner',
        joinedAt: 'now',
        name: 'Owner',
      ),
    ];
    repository.devicesValue = [
      const Device(
          id: 'local-device',
          name: 'Owner',
          platform: 'android',
          createdAt: '',
          lastSeenAt: ''),
      const Device(
          id: 'peer-1',
          name: 'Peer 1',
          platform: 'android',
          createdAt: '',
          lastSeenAt: ''),
      const Device(
          id: 'peer-2',
          name: 'Peer 2',
          platform: 'android',
          createdAt: '',
          lastSeenAt: ''),
    ];

    final controller = GroupMembersBloc(
      repository: repository,
      group: const LocalGroup(
          id: 'g1', name: 'Family', ownerId: 'local-device', createdAt: 'now'),
      localDeviceId: 'local-device',
    );
    await controller.load();

    expect(controller.isOwner, isTrue);
    expect(controller.addableDevices.map((d) => d.id), ['peer-2']);

    await controller.addMember(controller.addableDevices.single);
    expect(repository.added, ['peer-2']);

    await controller.removeMember(controller.members.first);
    expect(repository.removed, ['peer-1']);
  });
}
