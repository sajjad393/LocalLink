import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';

abstract interface class HomeRepositoryContract {
  String? get localDeviceId;
  Stream<Map<String, dynamic>> get presenceEvents;
  Stream<Map<String, dynamic>> get directPresenceEvents;
  Future<List<Device>> devices();
  Future<List<LocalGroup>> groups();
  Future<List<Device>> localDevices();
  Future<List<LocalGroup>> localGroups();
  Future<LocalGroup> createGroup(String name, List<String> memberIds);
  Future<void> cacheDevice(Device device);
}
