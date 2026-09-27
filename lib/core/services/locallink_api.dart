import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
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
  const AccountRecoveryResult({required this.account, required this.device, required this.profile, required this.token, required this.expiresAt, required this.revokedDeviceIds});

  factory AccountRecoveryResult.fromJson(Map<String, dynamic> json) => AccountRecoveryResult(
    account: LocalAccount.fromJson(Map<String, dynamic>.from(json['account'] as Map)),
    device: Device.fromJson(Map<String, dynamic>.from(json['device'] as Map)),
    profile: LocalProfile.fromJson(Map<String, dynamic>.from(json['profile'] as Map)),
    token: json['token']?.toString() ?? '',
    expiresAt: json['expires_at']?.toString() ?? '',
    revokedDeviceIds: json['source_device_id']?.toString() ?? '',
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
class GroupKeyEnvelope {
  final String groupId;
  final int keyVersion;
  final String senderId;
  final String recipientId;
  final String envelope;
  final String createdAt;

  const GroupKeyEnvelope({
    required this.groupId,
    required this.keyVersion,
    required this.senderId,
    required this.recipientId,
    required this.envelope,
    required this.createdAt,
  });

  factory GroupKeyEnvelope.fromJson(Map<String, dynamic> json) => GroupKeyEnvelope(
        groupId: json['group_id']?.toString() ?? '',
        keyVersion: int.tryParse(json['key_version']?.toString() ?? '') ?? 0,
        senderId: json['sender_id']?.toString() ?? '',
        recipientId: json['recipient_id']?.toString() ?? '',
        envelope: json['envelope']?.toString() ?? '',
        createdAt: json['created_at']?.toString() ?? '',
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
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/pairing/info')).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception(_error(response));
    return PairingInfo.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<AuthResult> registerAccount({
    required String username,
    required String password,
    required String deviceName,
    String? deviceId,
    String? pairingCode,
  }) async {
    final id = deviceId ?? store.deviceId ?? store.generateDeviceId();
    final response = await httpClient.post(
      Uri.parse('$baseUrl/api/v1/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username.trim().toLowerCase(),
        'password': password,
        'device_id': id,
        'device_name': deviceName.trim(),
        'platform': 'android',
        if (pairingCode != null && pairingCode.trim().isNotEmpty) 'pairing_code': pairingCode.trim(),
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 201) throw Exception(_error(response));
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
    final response = await httpClient.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username.trim().toLowerCase(),
        'password': password,
        'device_id': id,
        'device_name': deviceName.trim(),
        'platform': 'android',
        if (pairingCode != null && pairingCode.trim().isNotEmpty) 'pairing_code': pairingCode.trim(),
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception(_error(response));
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
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/auth/me'), headers: _headers()).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception(_error(response));
    return LocalAccount.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<void> logoutAccount() async {
    final response = await httpClient.post(Uri.parse('$baseUrl/api/v1/auth/logout'), headers: _headers()).timeout(const Duration(seconds: 6));
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
      if (pendingAvatar != null && pendingAvatar.isNotEmpty) {
        final file = File(pendingAvatar);
        if (await file.exists()) {
          profile = await uploadProfileAvatar(file);
          try { await file.delete(); } catch (_) {}
        }
        await store.clearPendingProfileAvatarPath();
        await store.saveProfile(profile);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<LocalProfile> getProfile({bool downloadAvatar = true}) async {
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/profile'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final profile = LocalProfile.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    var result = profile;
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
    if (response.statusCode != 200) throw Exception(_error(response));
    final profile = LocalProfile.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    final cached = await store.profile();
    final result = profile.copyWith(localAvatarPath: cached?.localAvatarPath ?? '');
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
    final response = await httpClient.get(Uri.parse('$baseUrl$path'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw Exception(_error(response));
    return LocalProfile.fromJson(Map<String,dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<List<LocalProfile>> _directoryList(String path) async {
    final response = await httpClient.get(Uri.parse('$baseUrl$path'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final decoded = jsonDecode(response.body);
    final rows = decoded is List ? decoded : (decoded is Map && decoded['profiles'] is List ? decoded['profiles'] as List : const []);
    return rows.map((e) => LocalProfile.fromJson(Map<String,dynamic>.from(e as Map))).toList();
  }

  Future<LocalProfile> uploadProfileAvatar(File file) async {
    if (!await file.exists()) throw Exception('Selected image no longer exists');
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/profile/avatar'));
    request.headers.addAll(_headers());
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) throw Exception(_error(response));
    final profile = LocalProfile.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    final localPath = await store.profileAvatarPath();
    final target = File('$localPath${_avatarExtension(file.path)}');
    await target.parent.create(recursive: true);
    await file.copy(target.path);
    final result = profile.copyWith(localAvatarPath: target.path);
    await store.saveProfile(result);
    return result;
  }

  Future<LocalProfile> _cacheProfileAvatar(LocalProfile profile) async {
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/profile/avatar'), headers: _headers()).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw Exception(_error(response));
    final base = await store.profileAvatarPath();
    final path = '$base${_avatarExtensionFromContentType(response.headers['content-type'])}';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(response.bodyBytes, flush: true);
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

  Future<void> putIdentityKey(String publicKey) async {
    final response = await httpClient.put(
      Uri.parse('$baseUrl/api/v1/device-key'),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({'public_key': publicKey}),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  Future<Map<String, String>> identityKeys() async {
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/device-keys'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final raw = jsonDecode(response.body) as List;
    return {for (final e in raw) if (e is Map && e['peer_id'] != null && e['public_key'] != null) e['peer_id'].toString(): e['public_key'].toString()};
  }

  Future<List<IdentityKeyRecord>> identityKeyRecords() async {
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/device-keys'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final raw = jsonDecode(response.body) as List;
    return raw.whereType<Map>().map((e) => IdentityKeyRecord.fromJson(Map<String, dynamic>.from(e))).where((e) => e.peerId.isNotEmpty && e.publicKey.isNotEmpty).toList();
  }

  Future<List<Map<String, dynamic>>> identityKeyHistory() async {
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/device-key/history'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final raw = jsonDecode(response.body) as List;
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> allIdentityKeyHistory() async {
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/device-keys/history'), headers: _headers()).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception(_error(response));
    final raw = jsonDecode(response.body) as List;
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  Future<Map<String, dynamic>> rotateIdentityKey(String publicKey, {String? idempotencyKey}) async {
    final response = await httpClient.post(
      Uri.parse('$baseUrl/api/v1/device-key/rotate'),
      headers: {..._headers(), 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
      body: jsonEncode({'public_key': publicKey}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception(_error(response));
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<PairingInfo> probePairingInfo(String server) async {
    final normalized = normalizeServerAddress(server);
    final response = await httpClient.get(Uri.parse('$normalized/api/v1/pairing/info')).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw Exception(_error(response));
    return PairingInfo.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  Future<AccountTransferStart> startAccountTransfer({String? idempotencyKey}) async {
    final response = await httpClient.post(
      Uri.parse('$baseUrl/api/v1/account/transfer/start'),
      headers: {..._headers(), 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode != 201) throw Exception(_error(response));
    return AccountTransferStart.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<void> cancelAccountTransfer(String transferId) async {
    final response = await httpClient.post(
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
    final response = await httpClient.post(
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
  Future<AccountRecoveryStart> createAccountRecovery({required String username, String password = '', String recoveryCode = '', required String deviceId, required String deviceName, required String identityPublicKey, String? idempotencyKey}) async {
    final server = normalizeServerAddress(store.serverAddress ?? '');
    final response = await httpClient.post(
      Uri.parse('$server/api/v1/account/recovery/request'),
      headers: {'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
      body: jsonEncode({'username': username.trim().toLowerCase(), if (password.isNotEmpty) 'password': password, if (recoveryCode.isNotEmpty) 'recovery_code': recoveryCode.trim(), 'device_id': deviceId, 'device_name': deviceName.trim(), 'platform': 'android', 'identity_public_key': identityPublicKey}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 202) throw Exception(_error(response));
    return AccountRecoveryStart.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<AccountRecoveryState> accountRecoveryStatus({required String server, required String requestId, required String requestSecret}) async {
    final base = normalizeServerAddress(server);
    final response = await httpClient.post(
      Uri.parse('$base/api/v1/account/recovery/status'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'request_id': requestId, 'request_secret': requestSecret}),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    return AccountRecoveryState.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  Future<AccountRecoveryResult> completeAccountRecovery({required String server, required String requestId, required String requestSecret, required String recoveryCredential, required String deviceId, required String deviceName, required String identityPublicKey, String? idempotencyKey}) async {
    final base = normalizeServerAddress(server);
    final response = await httpClient.post(
      Uri.parse('$base/api/v1/account/recovery/complete'),
      headers: {'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
      body: jsonEncode({'request_id': requestId, 'request_secret': requestSecret, 'recovery_credential': recoveryCredential.trim(), 'device_id': deviceId, 'device_name': deviceName.trim(), 'platform': 'android', 'identity_public_key': identityPublicKey}),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw Exception(_error(response));
    return AccountRecoveryResult.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<RecoveryCodeStatus> recoveryCodeStatus() async {
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/account/recovery-code/status'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    return RecoveryCodeStatus.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<bool> recoveryCodeConfigured() async => (await recoveryCodeStatus()).configured;

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  Future<String> rotateRecoveryCode({String? idempotencyKey}) async {
    final response = await httpClient.post(Uri.parse('$baseUrl/api/v1/account/recovery-code/rotate'), headers: {..._headers(), 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()}).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final code = (jsonDecode(response.body) as Map)['recovery_code']?.toString() ?? '';
    if (code.isEmpty) throw Exception('Server returned no recovery code');
    return code;
  }

  Future<void> disableRecoveryCode() async {
    final response = await httpClient.post(Uri.parse('$baseUrl/api/v1/account/recovery-code/disable'), headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  Future<AccountRestoreManifest> accountRestoreManifest() async {
    final response = await httpClient.get(
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
    final response = await httpClient.get(uri, headers: _headers()).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception(_error(response));
    return AccountRestorePage.fromJson(scope, Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<CryptoBackupEnvelope> getCryptoBackup() async {
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/account/crypto-backup'), headers: _headers()).timeout(const Duration(seconds: 10));
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
    final response = await httpClient.post(
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
          body: jsonEncode(call.toDb()),
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
          final response = await httpClient.get(uri, headers: _headers()).timeout(const Duration(seconds: 5));
          if (response.statusCode != 200) throw Exception(_error(response));
          return _pageJson(response.body);
        },
        readItems: (page) => (page['groups'] as List? ?? []).map((e) => LocalGroup.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );

  /// Reuse [idempotencyKey] when retrying after an unknown network outcome.
  Future<LocalGroup> createGroup(String name, List<String> memberIds, {String? idempotencyKey}) async {
    final response = await httpClient.post(Uri.parse('$baseUrl/api/v1/groups'), headers:{..._headers(),'Content-Type':'application/json','Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()}, body:jsonEncode({'name':name.trim(),'member_ids':memberIds})).timeout(const Duration(seconds:8));
    if (response.statusCode != 201) throw Exception(_error(response));
    return LocalGroup.fromJson(jsonDecode(response.body) as Map<String,dynamic>);
  }

  Future<List<GroupMember>> groupMembers(String groupId) async {
    final uri=Uri.parse('$baseUrl/api/v1/groups/members').replace(queryParameters:{'group_id':groupId});
    final response=await httpClient.get(uri,headers:_headers()).timeout(const Duration(seconds:5));
    if(response.statusCode!=200) throw Exception(_error(response));
    return (jsonDecode(response.body) as List).map((e)=>GroupMember.fromJson(Map<String,dynamic>.from(e as Map))).toList();
  }

  Future<bool> addGroupMember(String groupId, String deviceId) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/members').replace(queryParameters: {'group_id': groupId});
    final response = await httpClient.post(uri, headers: {..._headers(), 'Content-Type': 'application/json'}, body: jsonEncode({'device_id': deviceId})).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(_error(response));
    return response.statusCode == 201;
  }

  Future<void> removeGroupMember(String groupId, String deviceId) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/members').replace(queryParameters: {'group_id': groupId, 'device_id': deviceId});
    final response = await httpClient.delete(uri, headers: _headers()).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) throw Exception(_error(response));
  }

  Future<List<GroupKeyEnvelope>> groupKeyEnvelopes(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty) throw const FormatException('Group ID is required');
    final uri = Uri.parse('$baseUrl/api/v1/groups/keys').replace(queryParameters: {'group_id': id});
    final response = await httpClient.get(uri, headers: _headers()).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_error(response));
    final raw = jsonDecode(response.body) as List;
    return raw.whereType<Map>().map((e) => GroupKeyEnvelope.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> distributeGroupKeyEnvelopes({
    required String groupId,
    required int keyVersion,
    required List<Map<String, String>> envelopes,
    String? idempotencyKey,
  }) async {
    final response = await httpClient.post(
      Uri.parse('$baseUrl/api/v1/groups/keys'),
      headers: {..._headers(), 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey ?? _newIdempotencyKey()},
      body: jsonEncode({
        'group_id': groupId,
        'key_version': keyVersion,
        'envelopes': envelopes,
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(_error(response));
  }

  Future<List<GroupMessage>> groupMessages(String groupId) => _fetchAllPaged<GroupMessage>(
        fetchPage: (cursor, limit) async {
          final params = <String, String>{'group_id': groupId, 'limit': '$limit'};
          if (cursor != null) params['cursor'] = cursor;
          final uri = Uri.parse('$baseUrl/api/v1/group-messages').replace(queryParameters: params);
          final response = await httpClient.get(uri, headers: _headers()).timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) throw Exception(_error(response));
          return _pageJson(response.body);
        },
        readItems: (page) => (page['group_messages'] as List? ?? [])
            .map((e) => GroupMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Future<GroupMessage> createGroupMessage(String groupId, String body, {String? id, String? createdAt, List<String> attachmentIds = const []}) async {
    final effectiveCreatedAt = createdAt ?? DateTime.now().toUtc().toIso8601String();
    final response=await httpClient.post(Uri.parse('$baseUrl/api/v1/group-messages'),headers:{..._headers(),'Content-Type':'application/json'},body:jsonEncode({'id':id,'group_id':groupId,'body':body,'created_at':effectiveCreatedAt, if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds})).timeout(const Duration(seconds:8));
    if(response.statusCode!=200&&response.statusCode!=201) throw Exception(_error(response));
    return GroupMessage.fromJson(jsonDecode(response.body) as Map<String,dynamic>);
  }

  Future<ServerStatus> status() async {
    final response = await httpClient.get(Uri.parse('$baseUrl/api/v1/status'), headers: _headers()).timeout(const Duration(seconds: 4));
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
