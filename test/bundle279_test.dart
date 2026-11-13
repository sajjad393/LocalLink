import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/admin/data/services/admin_offline_users_222.dart';

import 'support/g211_fakes.dart';

// Bundle 279 (A-1): the phone does not report an old offline card to the
// server ("Not on server yet") when the same phone already has a server card.

class _Store extends LocalStore {
  _Store(this.offline, this.all, this.devices) : super(secureStorage: MemStorage211());
  final List<Map<String, Object?>> offline;
  final List<Map<String, dynamic>> all;
  final List<Device> devices;
  String moves = '[]';

  @override
  Future<List<Map<String, Object?>>> offlineDirectoryAccounts222() async => offline;
  @override
  Future<List<Map<String, dynamic>>> directoryProfiles() async => all;
  @override
  Future<List<Device>> localDevices() async => devices;
  @override
  Future<String?> readSetting(String key) async =>
      key == AdminOfflineUsers222.idMovesKey ? moves : null;
}

void main() {
  final seen = DateTime.now().toUtc().subtract(const Duration(minutes: 2)).toIso8601String();
  Device dev(String id) =>
      Device.fromJson({'id': id, 'name': 'Phone', 'mesh_available': true, 'last_seen_at': seen});

  setUp(AdminOfflineUsers222.resetForTest);
  tearDown(AdminOfflineUsers222.resetForTest);

  test('a phone with a server card: its old offline card is not reported', () async {
    final offline = [
      {'user_id': 'offline_457370aaaaaa', 'device_id': 'd-kiran', 'username': 'kiran'},
      {'user_id': 'offline_b6d2d4aaaaaa', 'device_id': 'd-sum', 'username': 'sumaira'},
      {'user_id': 'offline_cccccc000000', 'device_id': 'd-zara', 'username': 'zara'},
    ];
    final all = <Map<String, dynamic>>[
      ...offline,
      {'user_id': 'u-kiran-server', 'device_id': 'd-kiran'},
    ];
    final store = _Store(offline, all, [dev('d-kiran'), dev('d-sum'), dev('d-zara')])
      ..moves = '[{"old":"offline_b6d2d4aaaaaa","new":"u-sum-server"}]';
    AdminOfflineUsers222.init(store);
    final sent = await AdminOfflineUsers222.reportList();
    expect(sent.map((e) => e['username']), ['zara'],
        reason: 'kiran: same phone has a server card; sumaira: id moved; zara is really offline');
  });

  test('a real offline account is still reported', () async {
    final offline = [
      {'user_id': 'offline_cccccc000000', 'device_id': 'd-zara', 'username': 'zara'},
    ];
    AdminOfflineUsers222.init(_Store(offline, [...offline], [dev('d-zara')]));
    final sent = await AdminOfflineUsers222.reportList();
    expect(sent, hasLength(1));
    expect(sent.single['device_id'], 'd-zara');
    expect(sent.single['user_id'], 'offline_cccccc000000');
  });
}
