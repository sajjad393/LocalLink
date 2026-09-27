import 'dart:convert';

class DirectoryProfile {
  final String userId;
  final String deviceId;
  final String username;
  final String displayName;
  final String phoneNumber;
  final String avatarUrl;
  final String updatedAt;
  final String signingPublicKey;
  final String identityPublicKey;
  final String signature;
  final String phoneVisibility;
  final String source;
  final String syncedAt;
  final int profileVersion;
  final bool discoverableByPhone;
  final bool discoverableByName;
  final bool directorySyncEnabled;

  const DirectoryProfile({
    required this.userId,
    this.deviceId = '',
    this.username = '',
    this.displayName = '',
    this.phoneNumber = '',
    this.avatarUrl = '',
    this.updatedAt = '',
    this.signingPublicKey = '',
    this.identityPublicKey = '',
    this.signature = '',
    this.phoneVisibility = 'contacts',
    this.source = 'mesh',
    this.syncedAt = '',
    this.profileVersion = 0,
    this.discoverableByPhone = true,
    this.discoverableByName = true,
    this.directorySyncEnabled = true,
  });

  factory DirectoryProfile.fromMap(Map<String, dynamic> m) => DirectoryProfile(
        userId: m['user_id']?.toString() ?? '',
        deviceId: m['device_id']?.toString() ?? '',
        username: m['username']?.toString() ?? '',
        displayName: m['display_name']?.toString() ?? '',
        phoneNumber: m['phone_number']?.toString() ?? '',
        avatarUrl: m['avatar_url']?.toString() ?? '',
        updatedAt: m['updated_at']?.toString() ?? '',
        signingPublicKey: m['signing_public_key']?.toString() ?? '',
        identityPublicKey: m['identity_public_key']?.toString() ?? '',
        signature: m['signature']?.toString() ?? '',
        phoneVisibility: m['phone_visibility']?.toString() ?? 'contacts',
        source: m['source']?.toString() ?? 'mesh',
        syncedAt: m['synced_at']?.toString() ?? '',
        profileVersion: int.tryParse(m['profile_version']?.toString() ?? '') ?? 0,
        discoverableByPhone:
            m['discoverable_by_phone'] == true || m['discoverable_by_phone']?.toString() == '1',
        discoverableByName:
            m['discoverable_by_name'] == true || m['discoverable_by_name']?.toString() == '1',
        directorySyncEnabled:
            m['directory_sync_enabled'] != false && m['directory_sync_enabled']?.toString() != '0',
      );

  bool get isSigned =>
      signature.isNotEmpty && signingPublicKey.isNotEmpty && identityPublicKey.isNotEmpty;

  Map<String, dynamic> canonicalMap() => {
        'user_id': userId,
        'device_id': deviceId,
        'username': username,
        'display_name': displayName,
        'phone_number': phoneNumber,
        'avatar_url': avatarUrl,
        'profile_version': profileVersion,
        'updated_at': updatedAt,
        'signing_public_key': signingPublicKey,
        'identity_public_key': identityPublicKey,
        'phone_visibility': phoneVisibility,
        'discoverable_by_phone': discoverableByPhone,
        'discoverable_by_name': discoverableByName,
        'directory_sync_enabled': directorySyncEnabled,
      };

  String canonical() => jsonEncode(canonicalMap());

  Map<String, dynamic> toMap() => {
        ...canonicalMap(),
        'signature': signature,
        'source': source,
        'synced_at': syncedAt,
      };

  DirectoryProfile copyWith({
    String? userId,
    String? deviceId,
    String? username,
    String? displayName,
    String? phoneNumber,
    String? avatarUrl,
    String? updatedAt,
    String? signingPublicKey,
    String? identityPublicKey,
    String? signature,
    String? phoneVisibility,
    String? source,
    String? syncedAt,
    int? profileVersion,
    bool? discoverableByPhone,
    bool? discoverableByName,
    bool? directorySyncEnabled,
  }) => DirectoryProfile(
        userId: userId ?? this.userId,
        deviceId: deviceId ?? this.deviceId,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        updatedAt: updatedAt ?? this.updatedAt,
        signingPublicKey: signingPublicKey ?? this.signingPublicKey,
        identityPublicKey: identityPublicKey ?? this.identityPublicKey,
        signature: signature ?? this.signature,
        phoneVisibility: phoneVisibility ?? this.phoneVisibility,
        source: source ?? this.source,
        syncedAt: syncedAt ?? this.syncedAt,
        profileVersion: profileVersion ?? this.profileVersion,
        discoverableByPhone: discoverableByPhone ?? this.discoverableByPhone,
        discoverableByName: discoverableByName ?? this.discoverableByName,
        directorySyncEnabled: directorySyncEnabled ?? this.directorySyncEnabled,
      );
}
