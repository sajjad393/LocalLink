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

  /// Resolves a device id to the owning directory user id, if known. Used to
  /// collapse multiple devices of one user into a single conversation entry.
  Future<String?> userIdForDevice(String deviceId);

  /// Resolves a device id to the best human-readable label from the local
  /// directory profile (display name first, then username), if known. Used so
  /// the conversation list shows the person instead of the raw device name.
  Future<String?> labelForDevice(String deviceId);
}
