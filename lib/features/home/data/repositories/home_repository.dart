import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';

final class HomeRepository implements HomeRepositoryContract {
  final LocalLinkApi _api;
  final LocalStore _store;
  final WebSocketService _socket;
  final PeerTransportContract _directTransport;
  final GroupRepositoryContract _groups;

  const HomeRepository({
    required LocalLinkApi api,
    required LocalStore store,
    required WebSocketService socket,
    required PeerTransportContract directTransport,
    required GroupRepositoryContract groups,
  })  : _api = api,
        _store = store,
        _socket = socket,
        _directTransport = directTransport,
        _groups = groups;

  @override
  String? get localDeviceId => _store.deviceId;

  @override
  Stream<Map<String, dynamic>> get presenceEvents =>
      _socket.messages.where((m) => m['type'] == 'presence_update');

  @override
  Stream<Map<String, dynamic>> get directPresenceEvents =>
      _directTransport.events.where((m) => m['type'] == 'message');

  @override
  Future<List<Device>> devices() => _api.devices();

  @override
  Future<List<LocalGroup>> groups() => _groups.listGroups();

  @override
  Future<List<Device>> localDevices() => _store.localDevices();

  @override
  Future<List<LocalGroup>> localGroups() => _store.localGroups();

  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) =>
      _groups.createGroup(name, memberIds);

  @override
  Future<void> cacheDevice(Device device) => _store.saveDevice(device);
}
