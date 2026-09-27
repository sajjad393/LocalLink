class LocalProfile {
  final String userId;
  final String username;
  final String deviceId;
  final String displayName;
  final String phoneNumber;
  final String avatarUrl;
  final String localAvatarPath;
  final String avatarUpdatedAt;
  final String updatedAt;
  final int profileVersion;
  final String phoneVisibility;
  final bool discoverableByPhone;
  final bool discoverableByName;
  final bool directorySyncEnabled;

  const LocalProfile({
    required this.userId,
    required this.username,
    this.deviceId = '',
    required this.displayName,
    this.phoneNumber = '',
    this.avatarUrl = '',
    this.localAvatarPath = '',
    this.avatarUpdatedAt = '',
    this.updatedAt = '',
    this.profileVersion = 0,
    this.phoneVisibility = 'contacts',
    this.discoverableByPhone = true,
    this.discoverableByName = true,
    this.directorySyncEnabled = true,
  });

  factory LocalProfile.fromJson(Map<String, dynamic> json) => LocalProfile(
        userId: json['user_id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        deviceId: json['device_id']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
        phoneNumber: json['phone_number']?.toString() ?? '',
        avatarUrl: json['avatar_url']?.toString() ?? '',
        localAvatarPath: json['local_avatar_path']?.toString() ?? '',
        avatarUpdatedAt: json['avatar_updated_at']?.toString() ?? '',
        updatedAt: json['updated_at']?.toString() ?? '',
        profileVersion: int.tryParse(json['profile_version']?.toString() ?? '') ?? 0,
        phoneVisibility: json['phone_visibility']?.toString() ?? 'contacts',
        discoverableByPhone: json['discoverable_by_phone'] == true || json['discoverable_by_phone']?.toString() == '1',
        discoverableByName: json['discoverable_by_name'] == true || json['discoverable_by_name']?.toString() == '1',
        directorySyncEnabled: json['directory_sync_enabled'] != false && json['directory_sync_enabled']?.toString() != '0',
      );

  Map<String, dynamic> toMap() => {
        'user_id': userId,
        'username': username,
        'display_name': displayName,
        'phone_number': phoneNumber,
        'avatar_url': avatarUrl,
        'local_avatar_path': localAvatarPath,
        'avatar_updated_at': avatarUpdatedAt,
        'updated_at': updatedAt,
        'profile_version': profileVersion,
        'phone_visibility': phoneVisibility,
        'discoverable_by_phone': discoverableByPhone ? 1 : 0,
        'discoverable_by_name': discoverableByName ? 1 : 0,
        'directory_sync_enabled': directorySyncEnabled ? 1 : 0,
      };

  LocalProfile copyWith({
    String? userId, String? username, String? deviceId, String? displayName,
    String? phoneNumber, String? avatarUrl, String? localAvatarPath, String? avatarUpdatedAt, String? updatedAt,
    int? profileVersion, String? phoneVisibility, bool? discoverableByPhone,
    bool? discoverableByName, bool? directorySyncEnabled,
  }) => LocalProfile(
        userId: userId ?? this.userId, username: username ?? this.username, deviceId: deviceId ?? this.deviceId, displayName: displayName ?? this.displayName,
        phoneNumber: phoneNumber ?? this.phoneNumber, avatarUrl: avatarUrl ?? this.avatarUrl,
        localAvatarPath: localAvatarPath ?? this.localAvatarPath, avatarUpdatedAt: avatarUpdatedAt ?? this.avatarUpdatedAt,
        updatedAt: updatedAt ?? this.updatedAt, profileVersion: profileVersion ?? this.profileVersion,
        phoneVisibility: phoneVisibility ?? this.phoneVisibility, discoverableByPhone: discoverableByPhone ?? this.discoverableByPhone,
        discoverableByName: discoverableByName ?? this.discoverableByName, directorySyncEnabled: directorySyncEnabled ?? this.directorySyncEnabled,
      );
}
