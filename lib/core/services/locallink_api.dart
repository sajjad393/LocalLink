import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:locallink/core/widgets/error_toast.dart' show FriendlyError;
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/network/build_http.dart' as http; // Bundle 213: build header
import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/security/security_policy.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/core/services/websocket_service.dart';

class AccountTransferStart {
  final String transferId;
  final String payload;
  final String expiresAt;
  const AccountTransferStart({required this.transferId, required this.payload, required this.expiresAt});
  factory AccountTransferStart.fromJson(Map<String, dynamic> json) => AccountTransferStart(
    transferId: json['transfer_id']?.toString() ?? '',
    payload: json['payload']?.toString() ?? '',
    expiresAt: json['expires_at']?.toString() ?? '',
  );
}

class AccountRecoveryStart {
  final String requestId;
  final String requestSecret;
  final String status;
  final String username;
  final String expiresAt;
  final String serverId;
  final String fingerprint;
  final String targetDeviceId;

  const AccountRecoveryStart({required this.requestId, required this.requestSecret, required this.status, required this.username, required this.expiresAt, required this.serverId, required this.fingerprint, required this.targetDeviceId});

  factory AccountRecoveryStart.fromJson(Map<String, dynamic> json) {
    final request = Map<String, dynamic>.from(json['request'] as Map);
    return AccountRecoveryStart(
      requestId: request['request_id']?.toString() ?? '',
      requestSecret: json['request_secret']?.toString() ?? '',
      status: request['status']?.toString() ?? 'pending',
      username: request['username']?.toString() ?? '',
      expiresAt: request['expires_at']?.toString() ?? '',
      serverId: request['server_id']?.toString() ?? '',
      fingerprint: request['fingerprint']?.toString() ?? '',
      targetDeviceId: request['target_device_id']?.toString() ?? '',
    );
  }
}

class AccountRecoveryState {
  final String requestId;
  final String status;
  final String username;
  final String expiresAt;
  final String approvedAt;
  final String recoveryExpiresAt;
  final String rejectedReason;
  final String serverId;
  final String fingerprint;
  final String targetDeviceId;

  const AccountRecoveryState({required this.requestId, required this.status, required this.username, required this.expiresAt, required this.approvedAt, required this.recoveryExpiresAt, required this.rejectedReason, required this.serverId, required this.fingerprint, required this.targetDeviceId});

  factory AccountRecoveryState.fromJson(Map<String, dynamic> json) => AccountRecoveryState(
    requestId: json['request_id']?.toString() ?? '',
    status: json['status']?.toString() ?? 'pending',
    username: json['username']?.toString() ?? '',
    expiresAt: json['expires_at']?.toString() ?? '',
    approvedAt: json['approved_at']?.toString() ?? '',
    recoveryExpiresAt: json['recovery_expires_at']?.toString() ?? '',
    rejectedReason: json['rejected_reason']?.toString() ?? '',
    serverId: json['server_id']?.toString() ?? '',
    fingerprint: json['fingerprint']?.toString() ?? '',
    targetDeviceId: json['target_device_id']?.toString() ?? '',
  );
}

class AccountRecoveryResult {
  final LocalAccount account;
  final Device device;
  final LocalProfile profile;
  final String token;
  final String expiresAt;
  final String revokedDeviceIds;
  /// Bundle 222: a no-code reset returns a new recovery code (shown once).
  final String recoveryCode;
  const AccountRecoveryResult({required this.account, required this.device, required this.profile, required this.token, required this.expiresAt, required this.revokedDeviceIds, this.recoveryCode = ''});

  factory AccountRecoveryResult.fromJson(Map<String, dynamic> json) => AccountRecoveryResult(
    account: LocalAccount.fromJson(Map<String, dynamic>.from(json['account'] as Map)),
    device: Device.fromJson(Map<String, dynamic>.from(json['device'] as Map)),
    profile: LocalProfile.fromJson(Map<String, dynamic>.from(json['profile'] as Map)),
    token: json['token']?.toString() ?? '',
    expiresAt: json['expires_at']?.toString() ?? '',
    revokedDeviceIds: json['source_device_id']?.toString() ?? '',
    recoveryCode: json['recovery_code']?.toString() ?? '',
  );
}

class AccountTransferResult {
  final LocalAccount account;
  final Device device;
  final LocalProfile profile;
  final String token;
  final String expiresAt;
  final String sourceDeviceId;
  final bool sourceDeviceRevoked;
  const AccountTransferResult({required this.account, required this.device, required this.profile, required this.token, required this.expiresAt, required this.sourceDeviceId, required this.sourceDeviceRevoked});
  factory AccountTransferResult.fromJson(Map<String, dynamic> json) => AccountTransferResult(
    account: LocalAccount.fromJson(Map<String, dynamic>.from(json['account'] as Map)),
    device: Device.fromJson(Map<String, dynamic>.from(json['device'] as Map)),
    profile: LocalProfile.fromJson(Map<String, dynamic>.from(json['profile'] as Map)),
    token: json['token']?.toString() ?? '',
    expiresAt: json['expires_at']?.toString() ?? '',
    sourceDeviceId: json['source_device_id']?.toString() ?? '',
    sourceDeviceRevoked: json['source_device_revoked'] == true,
  );
}


class SyncPage {
  final List<Message> messages;
  final List<GroupMessage> groupMessages;
  final List<LocalGroup> groups;
  final List<GroupMember> groupMembers;
  final List<String> removedGroupIds;
  final String? nextCursor;
  final bool hasMore;
  const SyncPage({required this.messages, this.groupMessages = const [], this.groups = const [], this.groupMembers = const [], this.removedGroupIds = const [], this.nextCursor, required this.hasMore});

  factory SyncPage.fromJson(Map<String, dynamic> json) => SyncPage(
        messages: (json['messages'] as List? ?? [])
            .map((e) => Message.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        groupMessages: (json['group_messages'] as List? ?? [])
            .map((e) => GroupMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        groups: (json['groups'] as List? ?? [])
            .map((e) => LocalGroup.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        groupMembers: (json['group_members'] as List? ?? [])
            .map((e) => GroupMember.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        removedGroupIds: (json['removed_group_ids'] as List? ?? []).map((e) => e.toString()).toList(),
        nextCursor: json['next_cursor']?.toString(),
        hasMore: json['has_more'] == true,
      );
}


Future<List<T>> _fetchAllPaged<T>({
  required Future<Map<String, dynamic>> Function(String? cursor, int limit) fetchPage,
  required List<T> Function(Map<String, dynamic> page) readItems,
}) async {
  final all = <T>[];
  String? cursor;
  for (var pageIndex = 0; pageIndex < 10000; pageIndex++) {
    final page = await fetchPage(cursor, 200);
    all.addAll(readItems(page));
    final hasMore = page['has_more'] == true;
    final next = page['next_cursor']?.toString();
    if (!hasMore) return all;
    if (next == null || next.isEmpty || next == cursor) {
      throw StateError('server returned a non-progressing pagination cursor');
    }
    cursor = next;
  }
  throw StateError('pagination exceeded safety limit');
}

Map<String, dynamic> _pageJson(String body) {
  final value = jsonDecode(body);
  if (value is! Map) throw const FormatException('invalid paginated response');
  return Map<String, dynamic>.from(value);
}

class IdentityKeyRecord {
  final String peerId;
  final String publicKey;
  final int keyVersion;
  const IdentityKeyRecord({required this.peerId, required this.publicKey, required this.keyVersion});
  factory IdentityKeyRecord.fromJson(Map<String, dynamic> json) => IdentityKeyRecord(
    peerId: json['peer_id']?.toString() ?? '',
    publicKey: json['public_key']?.toString() ?? '',
    keyVersion: int.tryParse(json['key_version']?.toString() ?? '') ?? 1,
  );
}
class LocalLinkApi {
  String _newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  final LocalStore store;
  final WebSocketService socket;
  final ApiHttpClient httpClient;

  LocalLinkApi(this.store, this.socket, {ApiHttpClient? httpClient})
      : httpClient = httpClient ?? ApiHttpClient();

  static String normalizeServerAddress(String value) =>
      SecurityPolicy.normalizeServerAddress(value);

  String get baseUrl => normalizeServerAddress(store.serverAddress ?? '');

  String get wsUrl {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/ws',
    ).toString();
  }

  Map<String, String> get wsHeaders => {
        'Authorization': 'Bearer ${store.deviceToken!}',
        'X-Device-ID': store.deviceId!,
      };


  Future<PairingInfo> pairingInfo() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/pairing/info')).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception(_error(response));
    return PairingInfo.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<AuthResult> reEnrollDevice({
  required String username,
  required String password,
  required String deviceName,
  required String pairingCode,
}) async {
  final newDeviceId = store.generateDeviceId();

  final response = await http
      .post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username.trim().toLowerCase(),
          'password': password,
          'device_id': newDeviceId,
          'device_name': deviceName.trim(),
          'platform': 'android',
          'pairing_code': pairingCode.trim(),
        }),
      )
      .timeout(const Duration(seconds: 10));

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(_error(response));
  }

  final payload =
      Map<String, dynamic>.from(jsonDecode(response.body) as Map);

  final account = LocalAccount.fromJson(
    Map<String, dynamic>.from(payload['account'] as Map),
  );

  final device = Device.fromJson(
    Map<String, dynamic>.from(payload['device'] as Map),
  );

  final token = payload['token']?.toString() ?? '';

  if (token.isEmpty) {
    throw Exception('Server returned an empty authentication token.');
  }

  final expiresAt = payload['expires_at']?.toString() ?? '';

  if (expiresAt.isEmpty) {
    throw Exception('Server returned no token expiry.');
  }

  final server = store.serverAddress;

  if (server == null || server.trim().isEmpty) {
    throw Exception('Server address is not configured.');
  }

  await store.saveConfiguration(
    server: server,
    id: device.id,
    name: device.name,
    token: token,
    accountId: account.id,
    username: account.username,
  );

  return AuthResult(
    account: account,
    device: device,
    expiresAt: expiresAt,
    recoveryCode: '',
  );
}
  

  Future<AuthResult> registerAccount({
    required String username,
    required String password,
    required String deviceName,
    String? deviceId,
    String? pairingCode,
  }) async {
    final id = deviceId ?? store.deviceId ?? store.generateDeviceId();
    // Bundle 218: the phone-only account this comes from + its recovery code.
    final extra = await _offlineJoinFields218(withRecovery: true);
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username.trim().toLowerCase(),
        'password': password,
        'device_id': id,
        'hardware_fp': store.hardwareFp,
        'device_name': deviceName.trim(),
        'platform': 'android',
        if (pairingCode != null && pairingCode.trim().isNotEmpty) 'pairing_code': pairingCode.trim(),
        ...extra,
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 201) throw _fail218(response);
    final payload = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final account = LocalAccount.fromJson(Map<String, dynamic>.from(payload['account'] as Map));
    final device = Device.fromJson(Map<String, dynamic>.from(payload['device'] as Map));
    final token = payload['token']?.toString();
    if (token == null || token.isEmpty) throw Exception('Server returned no session token');
    await store.saveConfiguration(
      server: store.serverAddress!,
      id: device.id,
      name: device.name,
      token: token,
      accountId: account.id,
      username: account.username,
    );
    return AuthResult(account: account, device: device, expiresAt: payload['expires_at']?.toString() ?? '', recoveryCode: payload['recovery_code']?.toString() ?? '');
  }

  Future<AuthResult> loginAccount({
    required String username,
    required String password,
    required String deviceName,
    String? deviceId,
    String? pairingCode,
  }) async {
    final id = deviceId ?? store.deviceId ?? store.generateDeviceId();
    // Bundle 218: joining her own account keeps that account's recovery code.
    final extra = await _offlineJoinFields218(withRecovery: false);
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username.trim().toLowerCase(),
        'password': password,
        'device_id': id,
        'hardware_fp': store.hardwareFp,
        'device_name': deviceName.trim(),
        'platform': 'android',
        if (pairingCode != null && pairingCode.trim().isNotEmpty) 'pairing_code': pairingCode.trim(),
        ...extra,
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw _fail218(response);
    final payload = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final account = LocalAccount.fromJson(Map<String, dynamic>.from(payload['account'] as Map));
    final device = Device.fromJson(Map<String, dynamic>.from(payload['device'] as Map));
    final token = payload['token']?.toString();
    if (token == null || token.isEmpty) throw Exception('Server returned no session token');
    await store.saveConfiguration(
      server: store.serverAddress!,
      id: device.id,
      name: device.name,
      token: token,
      accountId: account.id,
      username: account.username,
    );
    return AuthResult(account: account, device: device, expiresAt: payload['expires_at']?.toString() ?? '', recoveryCode: '');
  }

  Future<LocalAccount> authMe() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/auth/me'), headers: _headers()).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception(_error(response));
    return LocalAccount.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<void> logoutAccount() async {
    final response = await http.post(Uri.parse('$baseUrl/api/v1/auth/logout'), headers: _headers()).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  Future<bool> syncPendingProfile() async {
    final pending = await store.pendingProfileUpdate();
    final pendingAvatar = await store.pendingProfileAvatarPath();
    if (pending == null && (pendingAvatar == null || pendingAvatar.isEmpty)) return true;
    try {
      LocalProfile profile;
      if (pending != null) {
        profile = await updateProfile(
          displayName: pending['display_name']?.toString() ?? '',
          username: pending['username']?.toString() ?? '',
          phoneNumber: pending['phone_number']?.toString() ?? '',
          phoneVisibility: pending['phone_visibility']?.toString() ?? 'contacts',
          discoverableByPhone: pending['discoverable_by_phone'] != false,
          discoverableByName: pending['discoverable_by_name'] != false,
          directorySyncEnabled: pending['directory_sync_enabled'] != false,
        );
        await store.clearPendingProfileUpdate();
      } else {
        profile = await getProfile(downloadAvatar: false);
      }
      if (pendingAvatar == removeAvatarMark) {
        // Bundle 204: "Remove photo" made with no internet.
        profile = await deleteProfileAvatar();
        await store.clearPendingProfileAvatarPath();
      } else if (pendingAvatar != null && pendingAvatar.isNotEmpty) {
        final file = File(pendingAvatar);
        if (await file.exists()) {
          profile = await uploadProfileAvatar(file);
          try { await file.delete(); } catch (_) {}
        }
        await store.clearPendingProfileAvatarPath();
        await store.saveProfile(profile);
      }
      return true;
    } catch (error) {
      if (pending != null && !_retried218) {
        // Bundle 218: number used by another account → save the rest; the
        // number stays on this phone only (with a note).
        final number = (pending['phone_number'] ?? '').toString().trim();
        if (number.isNotEmpty && _isPhoneTaken218(error)) {
          try {
            await store.writeSetting(phoneLocalOnlyKey218, number);
            await _rewritePending218(pending, phoneNumber: '');
            await _markJoinPhoneLine218();
            AppLogger.info('OFFLINE_ACCOUNT_PHONE_LOCAL_ONLY');
            return await _retryOnce218();
          } catch (_) {}
        }
        // The pending name is old (renamed on join): send the current one.
        final current = (store.username ?? '').trim();
        final wanted = (pending['username'] ?? '').toString().trim();
        if (_isUsernameTaken218(error) && current.isNotEmpty && current != wanted) {
          try {
            await _rewritePending218(pending, username: current);
            return await _retryOnce218();
          } catch (_) {}
        }
      }
      return false;
    }
  }

  // ------------------------------------------------------------- Bundle 218
  static const phoneLocalOnlyKey218 = 'phone_local_only_218';
  bool _retried218 = false;

  Future<bool> _retryOnce218() async {
    _retried218 = true;
    try {
      return await syncPendingProfile();
    } finally {
      _retried218 = false;
    }
  }

  Future<void> _rewritePending218(Map<String, dynamic> pending,
      {String? username, String? phoneNumber}) {
    return store.setPendingProfileUpdate(
        pending['display_name']?.toString() ?? '',
        username ?? pending['username']?.toString() ?? '',
        phoneNumber: phoneNumber ?? pending['phone_number']?.toString() ?? '',
        phoneVisibility: pending['phone_visibility']?.toString() ?? 'contacts',
        discoverableByPhone: pending['discoverable_by_phone'] != false,
        discoverableByName: pending['discoverable_by_name'] != false,
        directorySyncEnabled: pending['directory_sync_enabled'] != false);
  }

  static bool _isPhoneTaken218(Object error) =>
      (error is ApiError218 && error.code == 'PHONE_TAKEN') ||
      error.toString().toLowerCase().contains('phone number is already registered');

  static bool _isUsernameTaken218(Object error) =>
      (error is ApiError218 && error.code == 'USERNAME_TAKEN') ||
      error.toString().toLowerCase().contains('username is already registered');

  /// The join card (U-1) gets the orange "number stays on this phone" line.
  Future<void> _markJoinPhoneLine218() async {
    try {
      final raw = await store.readSetting('join_notice_218');
      if (raw == null || raw.isEmpty) return;
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      map['phone'] = true;
      await store.writeSetting('join_notice_218', jsonEncode(map));
    } catch (_) {}
  }

  /// Extra register / login fields while a phone-only account is waiting.
  Future<Map<String, String>> _offlineJoinFields218({required bool withRecovery}) async {
    if (!store.isOfflinePending) return const {};
    final out = <String, String>{};
    try {
      final id = (await store.profile())?.userId ?? '';
      if (id.startsWith('offline_')) out['offline_user_id'] = id;
    } catch (_) {}
    if (withRecovery) {
      final code = store.localRecoveryCode ?? '';
      if (code.isNotEmpty) out['recovery_code'] = code;
    }
    return out;
  }

  /// Which of these ids (offline ids or phone ids) are on the server now.
  /// Never throws: [] on any problem.
  Future<List<Map<String, String>>> resolveIds218(List<String> ids) async {
    final list = [for (final id in ids) if (id.trim().isNotEmpty) id.trim()].take(100).toList();
    if (list.isEmpty || baseUrl.isEmpty) return const [];
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/users/resolve'),
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: jsonEncode({'ids': list}),
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body);
      final found = body is Map ? body['found'] : null;
      if (found is! List) return const [];
      return [
        for (final f in found)
          if (f is Map)
            {
              'id': f['id']?.toString() ?? '',
              'user_id': f['user_id']?.toString() ?? '',
              'username': f['username']?.toString() ?? '',
              'device_id': f['device_id']?.toString() ?? '',
            }
      ];
    } catch (_) {
      return const [];
    }
  }

  ApiError218 _fail218(http.Response response) {
    var code = '';
    var owner = '';
    try {
      final json = jsonDecode(response.body);
      if (json is Map) {
        code = json['error_code']?.toString() ?? '';
        owner = json['owner']?.toString() ?? '';
      }
    } catch (_) {}
    return ApiError218(_error(response), code: code, owner: owner, status: response.statusCode);
  }

  Future<LocalProfile> getProfile({bool downloadAvatar = true}) async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/profile'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final profile = LocalProfile.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    var result = profile;
    // Bundle 218: the number another account uses stays on this phone.
    try {
      final localOnly = (await store.readSetting(phoneLocalOnlyKey218)) ?? '';
      if (localOnly.isNotEmpty && profile.phoneNumber.trim().isEmpty) {
        result = result.copyWith(phoneNumber: localOnly);
      }
    } catch (_) {}
    if (downloadAvatar && profile.avatarUrl.isNotEmpty) {
      try {
        result = await _cacheProfileAvatar(profile);
      } catch (_) {
        final cached = await store.profile();
        if (cached != null && cached.userId == profile.userId) result = profile.copyWith(localAvatarPath: cached.localAvatarPath);
      }
    }
    await store.saveProfile(result);
    return result;
  }

  Future<LocalProfile> updateProfile({required String displayName, required String username, String phoneNumber = '', String phoneVisibility = 'contacts', bool discoverableByPhone = true, bool discoverableByName = true, bool directorySyncEnabled = true}) async {
    final response = await httpClient.put(
      Uri.parse('$baseUrl/api/v1/profile'),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({'display_name': displayName.trim(), 'username': username.trim().toLowerCase(), 'phone_number': phoneNumber.trim(), 'phone_visibility': phoneVisibility, 'discoverable_by_phone': discoverableByPhone, 'discoverable_by_name': discoverableByName, 'directory_sync_enabled': directorySyncEnabled}),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw _fail218(response);
    final profile = LocalProfile.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    final cached = await store.profile();
    var result = profile.copyWith(localAvatarPath: cached?.localAvatarPath ?? '');
    // Bundle 218: the number used by another account stays on this phone.
    try {
      final localOnly = (await store.readSetting(phoneLocalOnlyKey218)) ?? '';
      if (localOnly.isNotEmpty && result.phoneNumber.trim().isEmpty) {
        result = result.copyWith(phoneNumber: localOnly);
      }
    } catch (_) {}
    await store.saveConfiguration(
      server: store.serverAddress!,
      id: store.deviceId!,
      name: store.deviceName!,
      token: store.deviceToken,
      accountId: store.accountId,
      username: result.username,
    );
    await store.saveProfile(result);
    return result;
  }

  Future<List<LocalProfile>> directoryByName(String query) async => _directoryList('/api/v1/directory/name?q=${Uri.encodeQueryComponent(query.trim())}');
  Future<LocalProfile?> directoryByPhone(String phone) async => _directorySingle('/api/v1/directory/phone?phone=${Uri.encodeQueryComponent(phone)}');
  Future<LocalProfile?> directoryByUserId(String userId) async => _directorySingle('/api/v1/directory/user/${Uri.encodeComponent(userId)}');

  Future<LocalProfile?> _directorySingle(String path) async {
    final response = await http.get(Uri.parse('$baseUrl$path'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw Exception(_error(response));
    return LocalProfile.fromJson(Map<String,dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<List<LocalProfile>> _directoryList(String path) async {
    final response = await http.get(Uri.parse('$baseUrl$path'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final decoded = jsonDecode(response.body);
    final rows = decoded is List ? decoded : (decoded is Map && decoded['profiles'] is List ? decoded['profiles'] as List : const []);
    return rows.map((e) => LocalProfile.fromJson(Map<String,dynamic>.from(e as Map))).toList();
  }

  Future<LocalProfile> uploadProfileAvatar(File file) async {
    if (!await file.exists()) throw Exception('Selected image no longer exists');
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/profile/avatar'));
    request.headers.addAll(AppBuild.withHeader(null)); // Bundle 213
    request.headers.addAll(_headers());
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) throw Exception(_error(response));
    final profile = LocalProfile.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    // Bundle 204: named by the picture (a new name when it changes).
    final bytes = await file.readAsBytes();
    final target = File(await store.profileAvatarFilePath(
        ProfilePhotoCode.hashOf(bytes), _avatarExtension(file.path)));
    await target.parent.create(recursive: true);
    if (target.path != file.path) await file.copy(target.path);
    final result = profile.copyWith(localAvatarPath: target.path);
    await store.saveProfile(result);
    await store.sweepProfileAvatars({target.path, file.path});
    return result;
  }

  /// Bundle 204: "Remove photo" -> the letter avatar again.
  static const String removeAvatarMark = 'remove';

  Future<LocalProfile> deleteProfileAvatar() async {
    final response = await httpClient
        .delete(Uri.parse('$baseUrl/api/v1/profile/avatar'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw Exception(_error(response));
    final profile = LocalProfile.fromJson(
            Map<String, dynamic>.from(jsonDecode(response.body) as Map))
        .copyWith(localAvatarPath: '');
    await store.saveProfile(profile);
    await store.sweepProfileAvatars(const <String>{});
    return profile;
  }

  /// Bundle 204: a friend's picture from the server (friends only; null =
  /// none / not a friend there).
  Future<List<int>?> friendAvatar(String userId) async {
    final response = await httpClient
        .get(
            Uri.parse(
                '$baseUrl/api/v1/directory/user/${Uri.encodeComponent(userId)}/avatar'),
            headers: _headers())
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw Exception(_error(response));
    if (response.bodyBytes.length > ProfilePhotoCode.maxServerBytes) return null;
    return response.bodyBytes;
  }

  Future<LocalProfile> _cacheProfileAvatar(LocalProfile profile) async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/profile/avatar'), headers: _headers()).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw Exception(_error(response));
    // Bundle 204: named by the picture; the same picture is not written again.
    final path = await store.profileAvatarFilePath(
        ProfilePhotoCode.hashOf(response.bodyBytes),
        _avatarExtensionFromContentType(response.headers['content-type']));
    final file = File(path);
    await file.parent.create(recursive: true);
    if (!await file.exists() || await file.length() != response.bodyBytes.length) {
      await file.writeAsBytes(response.bodyBytes, flush: true);
    }
    final pending = await store.pendingProfileAvatarPath() ?? '';
    await store.sweepProfileAvatars({file.path, if (pending.isNotEmpty) pending});
    return profile.copyWith(localAvatarPath: file.path);
  }

  String _avatarExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.gif')) return '.gif';
    return '.jpg';
  }

  String _avatarExtensionFromContentType(String? value) {
    final content = (value ?? '').split(';').first.trim().toLowerCase();
    if (content == 'image/png') return '.png';
    if (content == 'image/gif') return '.gif';
    return '.jpg';
  }

  Future<Device> registerDevice(
    String name, {
    String? id,
    String? pairingCode,
  }) async {
    final deviceId = id ?? store.deviceId ?? store.generateDeviceId();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/devices'),
          headers: {
            'Content-Type': 'application/json',
            if (store.deviceToken != null)
              'Authorization': 'Bearer ${store.deviceToken}',
            if (store.deviceToken != null)
              'X-Device-ID': store.deviceId ?? '',
          },
          body: jsonEncode({
            'id': deviceId,
            'name': name.trim(),
            'platform': 'android',
            if (pairingCode != null && pairingCode.trim().isNotEmpty)
              'pairing_code': pairingCode.trim(),
            if (store.deviceToken != null) 'token': store.deviceToken,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_error(response));
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final device = Device.fromJson(payload['device'] as Map<String, dynamic>);
    await store.saveConfiguration(
      server: store.serverAddress!,
      id: device.id,
      name: device.name,
      token: payload['token'] as String?,
    );
    return device;
  }

  Future<void> registerWithServer(
    String server,
    String name, {
    String? pairingCode,
  }) async {
    final normalized = normalizeServerAddress(server);
    await store.saveConfiguration(
      server: normalized,
      id: store.deviceId ?? store.generateDeviceId(),
      name: name.trim(),
    );
    await registerDevice(name, pairingCode: pairingCode);
  }

  Future<Map<String, String>> identityKeys() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/device-keys'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final raw = jsonDecode(response.body) as List;
    return {for (final e in raw) if (e is Map && e['peer_id'] != null && e['public_key'] != null) e['peer_id'].toString(): e['public_key'].toString()};
  }

  Future<List<Map<String, dynamic>>> identityKeyHistory() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/device-key/history'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final raw = jsonDecode(response.body) as List;
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  Future<Map<String, dynamic>> rotateIdentityKey(String publicKey, {String? idempotencyKey}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/device-key/rotate'),
      headers: {..._headers(), 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
      body: jsonEncode({'public_key': publicKey}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception(_error(response));
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<PairingInfo> probePairingInfo(String server) async {
    final normalized = normalizeServerAddress(server);
    final response = await http.get(Uri.parse('$normalized/api/v1/pairing/info')).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception(_error(response));
    return PairingInfo.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  Future<AccountTransferStart> startAccountTransfer({String? idempotencyKey}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/account/transfer/start'),
      headers: {..._headers(), 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode != 201) throw Exception(_error(response));
    return AccountTransferStart.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<void> cancelAccountTransfer(String transferId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/account/transfer/cancel'),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({'transfer_id': transferId}),
    ).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  Future<AccountTransferResult> completeAccountTransfer({
    required String server,
    required String transferId,
    required String secret,
    required String deviceId,
    required String deviceName,
    required String identityPublicKey,
    bool revokeSourceDevice = true,
    String? idempotencyKey,
  }) async {
    final response = await http.post(
      Uri.parse('${normalizeServerAddress(server)}/api/v1/account/transfer/complete'),
      headers: {'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
      body: jsonEncode({
        'transfer_id': transferId,
        'secret': secret,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': 'android',
        'identity_public_key': identityPublicKey,
        'revoke_source_device': revokeSourceDevice,
      }),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw Exception(_error(response));
    return AccountTransferResult.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  Future<AccountRecoveryStart> createAccountRecovery({required String username, String password = '', String recoveryCode = '', required String deviceId, required String deviceName, required String identityPublicKey, String? idempotencyKey, bool noCode = false}) async {
    final server = normalizeServerAddress(store.serverAddress ?? '');
    final response = await http.post(
      Uri.parse('$server/api/v1/account/recovery/request'),
      headers: {'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
      body: jsonEncode({'username': username.trim().toLowerCase(), if (password.isNotEmpty) 'password': password, if (recoveryCode.isNotEmpty) 'recovery_code': recoveryCode.trim(), 'device_id': deviceId, 'device_name': deviceName.trim(), 'platform': 'android', 'identity_public_key': identityPublicKey, if (noCode) 'no_code': true}),
    ).timeout(const Duration(seconds: 10));
    // Bundle 222: no-code requests keep the error code (NO_ACCOUNT, RATE_LIMIT).
    if (response.statusCode != 202) throw noCode ? _fail218(response) : Exception(_error(response));
    return AccountRecoveryStart.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<AccountRecoveryState> accountRecoveryStatus({required String server, required String requestId, required String requestSecret}) async {
    final base = normalizeServerAddress(server);
    final response = await http.post(
      Uri.parse('$base/api/v1/account/recovery/status'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'request_id': requestId, 'request_secret': requestSecret}),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    return AccountRecoveryState.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  Future<AccountRecoveryResult> completeAccountRecovery({required String server, required String requestId, required String requestSecret, required String recoveryCredential, required String deviceId, required String deviceName, required String identityPublicKey, String? idempotencyKey, String newPassword = ''}) async {
    final base = normalizeServerAddress(server);
    final response = await http.post(
      Uri.parse('$base/api/v1/account/recovery/complete'),
      headers: {'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
      body: jsonEncode({'request_id': requestId, 'request_secret': requestSecret, 'recovery_credential': recoveryCredential.trim(), 'device_id': deviceId, 'device_name': deviceName.trim(), 'platform': 'android', 'identity_public_key': identityPublicKey, if (newPassword.isNotEmpty) 'new_password': newPassword}),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw newPassword.isNotEmpty ? _fail218(response) : Exception(_error(response));
    return AccountRecoveryResult.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  /// Bundle 222: "Forgot password" with the user's own recovery code. Sends
  /// either [newPassword] (online) or the hash made on this phone while the
  /// server was away (never the plain password then). Signs this phone in
  /// like a normal login; the account's other phones stay signed in. The
  /// server answers with a NEW recovery code (shown once).
  Future<AuthResult> resetPasswordWithCode222({
    required String username,
    required String recoveryCode,
    String newPassword = '',
    String newPasswordHash = '',
    String newPasswordSalt = '',
    int iterations = 0,
    required String deviceName,
    String identityPublicKey = '',
    String? pairingCode,
  }) async {
    final server = normalizeServerAddress(store.serverAddress ?? '');
    final id = store.deviceId ?? store.generateDeviceId();
    final response = await http.post(
      Uri.parse('$server/api/v1/account/recovery/reset'),
      headers: {'Content-Type': 'application/json', 'Idempotency-Key': _newIdempotencyKey()},
      body: jsonEncode({
        'username': username.trim().toLowerCase(),
        'recovery_code': recoveryCode.trim(),
        if (newPassword.isNotEmpty) 'new_password': newPassword,
        if (newPasswordHash.isNotEmpty) 'new_password_hash': newPasswordHash,
        if (newPasswordSalt.isNotEmpty) 'new_password_salt': newPasswordSalt,
        if (iterations > 0) 'iterations': iterations,
        'device_id': id,
        'device_name': deviceName.trim(),
        'platform': 'android',
        'hardware_fp': store.hardwareFp,
        if (identityPublicKey.isNotEmpty) 'identity_public_key': identityPublicKey,
        if (pairingCode != null && pairingCode.trim().isNotEmpty) 'pairing_code': pairingCode.trim(),
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw _fail218(response);
    final payload = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final account = LocalAccount.fromJson(Map<String, dynamic>.from(payload['account'] as Map));
    final device = Device.fromJson(Map<String, dynamic>.from(payload['device'] as Map));
    final token = payload['token']?.toString();
    if (token == null || token.isEmpty) throw Exception('Server returned no session token');
    await store.saveConfiguration(
      server: server,
      id: device.id,
      name: device.name,
      token: token,
      accountId: account.id,
      username: account.username,
    );
    return AuthResult(account: account, device: device, expiresAt: payload['expires_at']?.toString() ?? '', recoveryCode: payload['recovery_code']?.toString() ?? '');
  }

  Future<RecoveryCodeStatus> recoveryCodeStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/account/recovery-code/status'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    return RecoveryCodeStatus.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<bool> recoveryCodeConfigured() async => (await recoveryCodeStatus()).configured;

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  Future<String> rotateRecoveryCode({String? idempotencyKey}) async {
    final response = await http.post(Uri.parse('$baseUrl/api/v1/account/recovery-code/rotate'), headers: {..._headers(), 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()}).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final code = (jsonDecode(response.body) as Map)['recovery_code']?.toString() ?? '';
    if (code.isEmpty) throw Exception('Server returned no recovery code');
    return code;
  }

  Future<void> disableRecoveryCode() async {
    final response = await http.post(Uri.parse('$baseUrl/api/v1/account/recovery-code/disable'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  // Mirrors contact list changes to the account on the server so contacts
  // survive reinstalls (they were previously stored locally only). Failures
  // are non-fatal for the local action; the next successful sync/restore
  // reconciles the server list.
  Future<List<AccountContact>> listAccountContacts() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/account/contacts'),
      headers: _headers(),
    ).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception(_error(response));
    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    return (body['contacts'] as List? ?? [])
        .map((e) => AccountContact.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> addAccountContact(String userId, {bool? isPrivate}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/account/contacts'),
      headers: _headers(),
      // is_private omitted when null → server upsert keeps the existing flag
      // (old clients stay byte-compatible; bundle 90 toggles send it).
      body: jsonEncode({
        'user_id': userId.trim(),
        if (isPrivate != null) 'is_private': isPrivate,
      }),
    ).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw _fail218(response);
  }

  Future<void> removeAccountContact(String userId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/account/contacts/${Uri.encodeComponent(userId.trim())}'),
      headers: _headers(),
    ).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  Future<AccountRestoreManifest> accountRestoreManifest() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/account/restore/manifest'),
      headers: _headers(),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception(_error(response));
    return AccountRestoreManifest.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<AccountRestorePage> accountRestoreData({required String scope, String? cursor, int limit = 200}) async {
    final params = <String, String>{'scope': scope, 'limit': '$limit'};
    if (cursor != null && cursor.isNotEmpty) params['cursor'] = cursor;
    final uri = Uri.parse('$baseUrl/api/v1/account/restore/data').replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception(_error(response));
    return AccountRestorePage.fromJson(scope, Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<CryptoBackupEnvelope> getCryptoBackup() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/account/crypto-backup'), headers: _headers()).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception(_error(response));
    return CryptoBackupEnvelope.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<void> putCryptoBackup(String envelope) async {
    final response = await httpClient.put(
      Uri.parse('$baseUrl/api/v1/account/crypto-backup'),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({'envelope': envelope}),
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  Future<void> deleteCryptoBackup() async {
    final response = await httpClient.delete(Uri.parse('$baseUrl/api/v1/account/crypto-backup'), headers: _headers()).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  Future<List<Device>> accountDevices() => _fetchAllPaged<Device>(
        fetchPage: (cursor, limit) async {
          final params = <String, String>{'limit': '$limit'};
          if (cursor != null) params['cursor'] = cursor;
          final uri = Uri.parse('$baseUrl/api/v1/account/devices').replace(queryParameters: params);
          final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) throw Exception(_error(response));
          return _pageJson(response.body);
        },
        readItems: (page) => (page['devices'] as List? ?? []).map((e) => Device.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );

  Future<void> revokeAccountDevice(String deviceId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/account/devices/revoke'),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId}),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  Future<List<Device>> devices() => _fetchAllPaged<Device>(
        fetchPage: (cursor, limit) async {
          final params = <String, String>{'limit': '$limit'};
          if (cursor != null) params['cursor'] = cursor;
          final uri = Uri.parse('$baseUrl/api/v1/devices').replace(queryParameters: params);
          final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 5));
          if (response.statusCode != 200) throw Exception(_error(response));
          return _pageJson(response.body);
        },
        readItems: (page) => (page['devices'] as List? ?? []).map((e) => Device.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );

  Future<CallRecord> reconcileCall(CallRecord call, {String? idempotencyKey}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/calls/reconcile'),
          headers: {..._headers(), 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
          // Bundle 130: peer_name is a LOCAL display cache — strip it from
          // the reconcile payload so the server contract stays unchanged.
          body: jsonEncode(Map<String, dynamic>.from(call.toDb())
            ..remove('peer_name')),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(_error(response));
    return CallRecord.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<List<CallRecord>> calls() => _fetchAllPaged<CallRecord>(
        fetchPage: (cursor, limit) async {
          final params = <String, String>{'limit': '$limit'};
          if (cursor != null) params['cursor'] = cursor;
          final uri = Uri.parse('$baseUrl/api/v1/calls').replace(queryParameters: params);
          final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) throw Exception(_error(response));
          return _pageJson(response.body);
        },
        readItems: (page) => (page['calls'] as List? ?? []).map((e) => CallRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );

  Future<List<Message>> messages(String otherId) => _fetchAllPaged<Message>(
        fetchPage: (cursor, limit) async {
          final params = <String, String>{'a': store.deviceId!, 'b': otherId, 'limit': '$limit'};
          if (cursor != null) params['cursor'] = cursor;
          final uri = Uri.parse('$baseUrl/api/v1/messages').replace(queryParameters: params);
          final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) throw Exception(_error(response));
          return _pageJson(response.body);
        },
        readItems: (page) => (page['messages'] as List? ?? []).map((e) => Message.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );

  Future<SyncPage> sync({String? cursor, int limit = 200}) async {
    final params = <String, String>{'limit': '$limit'};
    if (cursor != null && cursor.isNotEmpty) params['cursor'] = cursor;
    final uri = Uri.parse('$baseUrl/api/v1/sync').replace(queryParameters: params);
    final response = await http
        .get(uri, headers: _headers())
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception(_error(response));
    return SyncPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Message> acknowledgeMessage(String id) async {
    final uri = Uri.parse('$baseUrl/api/v1/messages/ack').replace(queryParameters: {'id': id});
    final response = await http
        .post(uri, headers: _headers())
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) throw Exception(_error(response));
    return Message.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<LocalGroup>> groups() => _fetchAllPaged<LocalGroup>(
        fetchPage: (cursor, limit) async {
          final params = <String, String>{'limit': '$limit'};
          if (cursor != null) params['cursor'] = cursor;
          final uri = Uri.parse('$baseUrl/api/v1/groups').replace(queryParameters: params);
          final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 5));
          if (response.statusCode != 200) throw Exception(_error(response));
          return _pageJson(response.body);
        },
        readItems: (page) => (page['groups'] as List? ?? []).map((e) => LocalGroup.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  /// Bundle G2: [description] and settings are sent only when they are not
  /// the defaults, so the request stays the same as before for old servers.
  /// Bundle G3: [id] = the group id made on the phone (Nearby groups keep
  /// the same id on the server); the server answers 200 when it already has
  /// it from me.
  Future<LocalGroup> createGroup(String name, List<String> memberIds, {String? idempotencyKey, String description = '', String editInfo = 'admins', String sendMessages = 'all', String addMembers = 'admins', String? id, bool bridge = false}) async {
    final response = await http.post(Uri.parse('$baseUrl/api/v1/groups'), headers:{..._headers(),'Content-Type':'application/json','Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()}, body:jsonEncode({'name':name.trim(),'member_ids':memberIds,
      if (id != null && id.isNotEmpty) 'id': id,
      if (bridge) 'bridge': true,
      if (description.trim().isNotEmpty) 'description': description.trim(),
      if (editInfo != 'admins') 'edit_info': editInfo,
      if (sendMessages != 'all') 'send_messages': sendMessages,
      if (addMembers != 'admins') 'add_members': addMembers,
    })).timeout(const Duration(seconds:8));
    if (response.statusCode != 201 && !(id != null && response.statusCode == 200)) throw Exception(_error(response));
    return LocalGroup.fromJson(jsonDecode(response.body) as Map<String,dynamic>);
  }

  Future<List<GroupMember>> groupMembers(String groupId) async {
    final uri=Uri.parse('$baseUrl/api/v1/groups/members').replace(queryParameters:{'group_id':groupId});
    final response=await http.get(uri,headers:_headers()).timeout(const Duration(seconds:5));
    if(response.statusCode!=200) throw Exception(_error(response));
    return (jsonDecode(response.body) as List).map((e)=>GroupMember.fromJson(Map<String,dynamic>.from(e as Map))).toList();
  }

  Future<bool> addGroupMember(String groupId, String deviceId) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/members').replace(queryParameters: {'group_id': groupId});
    final response = await http.post(uri, headers: {..._headers(), 'Content-Type': 'application/json'}, body: jsonEncode({'device_id': deviceId})).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(_error(response));
    return response.statusCode == 201;
  }

  Future<void> removeGroupMember(String groupId, String deviceId) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/members').replace(queryParameters: {'group_id': groupId, 'device_id': deviceId});
    final response = await httpClient.delete(uri, headers: _headers()).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  // ---- Bundle G2: admins, info, photo, leave --------------------------

  Never _groupError(http.Response response) {
    var code = '';
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      code = json['error_code']?.toString() ?? '';
    } catch (_) {}
    throw GroupActionException(code, _error(response), response.statusCode);
  }

  /// Bundle G5: "got it" / "read" rows for MY messages in a group,
  /// changed after [since] (server time text, '' = all).
  Future<List<Map<String, dynamic>>> groupReceipts(String groupId,
      {String since = ''}) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/receipts').replace(
        queryParameters: {'group_id': groupId, if (since.isNotEmpty) 'since': since});
    final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) _groupError(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final list = json['receipts'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  // ---- Bundle G6: invite link ------------------------------------------

  /// Admins: the group's link token (made the first time; [reset] = new).
  Future<String> groupInviteToken(String groupId,
      {bool approve = false, bool reset = false}) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/invite')
        .replace(queryParameters: {'group_id': groupId});
    final response = await http
        .post(uri,
            headers: {..._headers(), 'Content-Type': 'application/json'},
            body: jsonEncode({'approve': approve, 'reset': reset}))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) _groupError(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['token']?.toString() ?? '';
  }

  /// Anyone signed in: what the link opens (name, members, my status).
  Future<Map<String, dynamic>> groupJoinPreview(String token) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/join')
        .replace(queryParameters: {'token': token});
    final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) _groupError(response);
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  /// Join (or ask to join). Returns {status: member|joined|requested, group_id}.
  Future<Map<String, dynamic>> joinGroupByLink(String token,
      {String seal = '', String sign = ''}) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/join')
        .replace(queryParameters: {'token': token});
    final response = await http
        .post(uri,
            headers: {..._headers(), 'Content-Type': 'application/json'},
            body: jsonEncode({'seal': seal, 'sign': sign}))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) _groupError(response);
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  /// Admins: people who asked to join with the link (last 24 h).
  Future<List<Map<String, dynamic>>> groupLinkRequests(String groupId) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/join-requests')
        .replace(queryParameters: {'group_id': groupId});
    final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) _groupError(response);
    final list = (jsonDecode(response.body) as Map)['requests'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// Admins: "Ignore" a link request (the asker is not told).
  Future<void> declineGroupLinkRequest(String groupId, String deviceId) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/join-requests')
        .replace(queryParameters: {'group_id': groupId, 'device_id': deviceId});
    final response = await http.delete(uri, headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) _groupError(response);
  }

  Future<LocalGroup> groupInfo(String groupId) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/info').replace(queryParameters: {'group_id': groupId});
    final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) _groupError(response);
    return LocalGroup.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<LocalGroup> updateGroup(String groupId, {String? name, String? description, String? editInfo, String? sendMessages, String? addMembers}) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups').replace(queryParameters: {'group_id': groupId});
    final response = await http.patch(uri, headers: {..._headers(), 'Content-Type': 'application/json'}, body: jsonEncode({
      if (name != null) 'name': name.trim(),
      if (description != null) 'description': description.trim(),
      if (editInfo != null) 'edit_info': editInfo,
      if (sendMessages != null) 'send_messages': sendMessages,
      if (addMembers != null) 'add_members': addMembers,
    })).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) _groupError(response);
    return LocalGroup.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// A small JPEG (max 256 KB). Returns the new photo version.
  Future<int> setGroupPhoto(String groupId, List<int> jpeg) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/photo').replace(queryParameters: {'group_id': groupId});
    final response = await http.put(uri, headers: {..._headers(), 'Content-Type': 'image/jpeg'}, body: jpeg).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) _groupError(response);
    return int.tryParse((jsonDecode(response.body) as Map)['photo_version']?.toString() ?? '') ?? 0;
  }

  Future<int> removeGroupPhoto(String groupId) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/photo').replace(queryParameters: {'group_id': groupId});
    final response = await http.delete(uri, headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) _groupError(response);
    return int.tryParse((jsonDecode(response.body) as Map)['photo_version']?.toString() ?? '') ?? 0;
  }

  /// Null = the group has no photo.
  Future<List<int>?> groupPhoto(String groupId) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/photo').replace(queryParameters: {'group_id': groupId});
    final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) _groupError(response);
    return response.bodyBytes;
  }

  Future<void> leaveGroup(String groupId) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/leave').replace(queryParameters: {'group_id': groupId});
    final response = await http.post(uri, headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) _groupError(response);
  }

  Future<void> setGroupRole(String groupId, String deviceId, {required bool admin}) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/role').replace(queryParameters: {'group_id': groupId});
    final response = await http.post(uri, headers: {..._headers(), 'Content-Type': 'application/json'}, body: jsonEncode({'device_id': deviceId, 'role': admin ? 'admin' : 'member'})).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) _groupError(response);
  }

  Future<List<GroupMessage>> groupMessages(String groupId) => _fetchAllPaged<GroupMessage>(
        fetchPage: (cursor, limit) async {
          final params = <String, String>{'group_id': groupId, 'limit': '$limit'};
          if (cursor != null) params['cursor'] = cursor;
          final uri = Uri.parse('$baseUrl/api/v1/group-messages').replace(queryParameters: params);
          final response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) throw Exception(_error(response));
          return _pageJson(response.body);
        },
        readItems: (page) => (page['group_messages'] as List? ?? [])
            .map((e) => GroupMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Future<GroupMessage> createGroupMessage(String groupId, String body, {String? id, String? createdAt, List<String> attachmentIds = const []}) async {
    final effectiveCreatedAt = createdAt ?? DateTime.now().toUtc().toIso8601String();
    final response=await http.post(Uri.parse('$baseUrl/api/v1/group-messages'),headers:{..._headers(),'Content-Type':'application/json'},body:jsonEncode({'id':id,'group_id':groupId,'body':body,'created_at':effectiveCreatedAt, if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds})).timeout(const Duration(seconds:8));
    if(response.statusCode!=200&&response.statusCode!=201) throw Exception(_error(response));
    return GroupMessage.fromJson(jsonDecode(response.body) as Map<String,dynamic>);
  }

  Future<ServerStatus> status() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/status'), headers: _headers()).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) throw Exception(_error(response));
    return ServerStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> connectRealtime() => socket.connect(wsUrl, headers: wsHeaders);

  Map<String, String> _headers() => {
        'Authorization': 'Bearer ${store.deviceToken ?? ''}',
        'X-Device-ID': store.deviceId ?? '',
      };

  String _error(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['error']?.toString() ?? 'Server error (${response.statusCode})';
    } catch (_) {
      return 'Server error (${response.statusCode})';
    }
  }
}


class RecoveryCodeStatus {
  final bool configured;
  final String createdAt;
  final String rotatedAt;

  const RecoveryCodeStatus({required this.configured, required this.createdAt, required this.rotatedAt});

  factory RecoveryCodeStatus.fromJson(Map<String, dynamic> json) => RecoveryCodeStatus(
        configured: json['configured'] == true,
        createdAt: json['created_at']?.toString() ?? '',
        rotatedAt: json['rotated_at']?.toString() ?? '',
      );
}

class ServerStatus {
  final int devices;
  final int messages;
  const ServerStatus({this.devices = 0, this.messages = 0});
  factory ServerStatus.fromJson(Map<String, dynamic> json) => ServerStatus(
    devices: int.tryParse(json['devices']?.toString() ?? '') ?? 0,
    messages: int.tryParse(json['messages']?.toString() ?? '') ?? 0,
  );
}


/// Bundle G2: a group action the server refused. [code] e.g.
/// GROUP_ADMINS_ONLY, GROUP_NOT_MEMBER, GROUP_NOT_CONTACT.
class GroupActionException implements Exception, FriendlyError {
  const GroupActionException(this.code, this.message, [this.status = 0]);
  final String code;
  final String message;
  final int status;

  /// Plain words for a toast.
  @override
  String get friendly => switch (code) {
        'GROUP_ADMINS_ONLY' => 'Only admins can do this.',
        'GROUP_NOT_MEMBER' => "You're no longer a participant in this group.",
        'GROUP_NOT_CONTACT' => 'You can only add your friends.',
        'GROUP_LINK_INVALID' => "This invite link doesn't work any more.",
        'GROUP_FULL' => 'This group is full (100 people).',
        _ => message,
      };

  @override
  String toString() => friendly;
}

/// Bundle 218: a server error with its stable code. `toString()` is the same
/// as `Exception(text)`, so every old text check and every message shown to
/// the user stay exactly as before.
class ApiError218 implements Exception {
  final String message;
  final String code;
  final String owner;
  final int status;

  const ApiError218(this.message, {this.code = '', this.owner = '', this.status = 0});

  @override
  String toString() => 'Exception: $message';
}
