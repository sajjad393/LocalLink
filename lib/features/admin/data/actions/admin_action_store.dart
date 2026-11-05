import 'package:locallink/core/services/local_store.dart';

/// Bundle 220: where cards and receipts are kept. The SQL one uses the two
/// new tables in [LocalStore]; tests use [MemoryAdminActionStore].
abstract class AdminActionStore {
  Future<List<Map<String, Object?>>> actions();
  Future<List<Map<String, Object?>>> receipts();
  Future<void> putAction(Map<String, Object?> row);
  Future<void> putReceipt(Map<String, Object?> row);
  Future<void> deleteActions(List<String> ids);

  /// A phone's keys from its signed profile (empty when unknown).
  Future<({String userId, String signingKey, String identityKey})> keysOf(String deviceId);

  /// The phones this phone knows for a person (newest profile).
  Future<List<String>> phonesOf(String userId);

  Future<String?> readSetting(String key);
  Future<void> writeSetting(String key, String value);
}

class SqlAdminActionStore implements AdminActionStore {
  SqlAdminActionStore(this.store);
  final LocalStore store;

  @override
  Future<List<Map<String, Object?>>> actions() => store.adminActionRows();
  @override
  Future<List<Map<String, Object?>>> receipts() => store.adminActionReceiptRows();
  @override
  Future<void> putAction(Map<String, Object?> row) => store.putAdminActionRow(row);
  @override
  Future<void> putReceipt(Map<String, Object?> row) => store.putAdminActionReceiptRow(row);
  @override
  Future<void> deleteActions(List<String> ids) => store.deleteAdminActionRows(ids);
  @override
  Future<({String userId, String signingKey, String identityKey})> keysOf(String deviceId) =>
      store.directoryKeysForDevice(deviceId);
  @override
  Future<List<String>> phonesOf(String userId) async =>
      (await store.devicesOfUsers({userId})).keys.toList();
  @override
  Future<String?> readSetting(String key) => store.readSetting(key);
  @override
  Future<void> writeSetting(String key, String value) => store.writeSetting(key, value);
}

class MemoryAdminActionStore implements AdminActionStore {
  final Map<String, Map<String, Object?>> rows = {};
  final Map<String, Map<String, Object?>> receiptRows = {};
  final Map<String, ({String userId, String signingKey, String identityKey})> keys = {};
  final Map<String, String> settings = {};

  @override
  Future<List<Map<String, Object?>>> actions() async => rows.values.toList();
  @override
  Future<List<Map<String, Object?>>> receipts() async => receiptRows.values.toList();
  @override
  Future<void> putAction(Map<String, Object?> row) async =>
      rows[row['id'].toString()] = Map.of(row);
  @override
  Future<void> putReceipt(Map<String, Object?> row) async =>
      receiptRows['${row['action_id']}|${row['device_id']}'] = Map.of(row);
  @override
  Future<void> deleteActions(List<String> ids) async {
    for (final id in ids) {
      rows.remove(id);
      receiptRows.removeWhere((k, _) => k.startsWith('$id|'));
    }
  }

  @override
  Future<({String userId, String signingKey, String identityKey})> keysOf(String deviceId) async =>
      keys[deviceId] ?? (userId: '', signingKey: '', identityKey: '');
  @override
  Future<List<String>> phonesOf(String userId) async => [
        for (final e in keys.entries)
          if (e.value.userId == userId) e.key,
      ];
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
}
