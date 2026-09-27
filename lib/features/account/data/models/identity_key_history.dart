class IdentityKeyHistoryEntry {
  final int keyVersion;
  final String publicKey;
  final bool active;
  final String createdAt;
  final String retiredAt;

  const IdentityKeyHistoryEntry({
    required this.keyVersion,
    required this.publicKey,
    required this.active,
    required this.createdAt,
    required this.retiredAt,
  });

  factory IdentityKeyHistoryEntry.fromJson(Map<String, dynamic> json) => IdentityKeyHistoryEntry(
        keyVersion: int.tryParse(json['key_version']?.toString() ?? '') ?? 0,
        publicKey: json['public_key']?.toString() ?? '',
        active: json['active'] == true,
        createdAt: json['created_at']?.toString() ?? '',
        retiredAt: json['retired_at']?.toString() ?? '',
      );
}
