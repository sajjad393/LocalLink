/// Typed in-memory representation for portable identity backups. This avoids
/// passing raw dynamic maps containing private seed material through layers.
class SensitiveIdentityKeyRecord {
  final int version;
  final String seed;
  final String publicKey;

  const SensitiveIdentityKeyRecord({required this.version, required this.seed, required this.publicKey});

  Map<String, String> toMap() => {
    'version': version.toString(),
    'seed': seed,
    'public_key': publicKey,
  };
}

class SensitiveIdentityBundle {
  final String deviceId;
  final List<SensitiveIdentityKeyRecord> keyVersions;

  const SensitiveIdentityBundle({required this.deviceId, required this.keyVersions});

  Map<String, Object> toJson() => {
    'v': 1,
    'device_id': deviceId,
    'key_versions': keyVersions.map((e) => e.toMap()).toList(growable: false),
  };

  static SensitiveIdentityBundle fromJson(Map<String, dynamic> json) {
    final deviceId = json['device_id']?.toString() ?? '';
    final raw = json['key_versions'];
    if (deviceId.isEmpty || raw is! List) throw const FormatException('invalid identity backup bundle');
    final records = <SensitiveIdentityKeyRecord>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final version = int.tryParse(item['version']?.toString() ?? '') ?? 0;
      final seed = item['seed']?.toString() ?? '';
      final publicKey = item['public_key']?.toString() ?? '';
      if (version < 1 || seed.isEmpty) continue;
      records.add(SensitiveIdentityKeyRecord(version: version, seed: seed, publicKey: publicKey));
    }
    if (records.isEmpty) throw const FormatException('identity backup contains no valid keys');
    return SensitiveIdentityBundle(deviceId: deviceId, keyVersions: List.unmodifiable(records));
  }
}
