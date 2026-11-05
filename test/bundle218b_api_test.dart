// Bundle 218b: LocalLinkApi — join fields, error codes, phone number taken,
// old pending name, local-only number kept, resolve.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';

class _Store implements LocalStore {
  bool waiting = true;
  final settings = <String, String>{};
  Map<String, dynamic>? pendingUpdate;
  LocalProfile? me = const LocalProfile(
      userId: 'offline_0123456789ab', username: 'sumaira', displayName: 'Sumaira');
  String? user = 'sumaira37';

  @override
  String? get serverAddress => 'http://192.168.1.10:8080';
  @override
  String? get deviceId => 'dev-zte';
  @override
  String? get deviceName => 'ZTE';
  @override
  String? get deviceToken => 'tok';
  @override
  String? get accountId => 'u-real-1';
  @override
  String? get username => user;
  @override
  String get hardwareFp => 'hw-1';
  @override
  bool get isOfflinePending => waiting;
  @override
  String? get localRecoveryCode => 'ABCDE-FGHIJ-KLMNO-PQRS2';
  @override
  Future<LocalProfile?> profile() async => me;
  @override
  Future<void> saveProfile(LocalProfile profile) async => me = profile;
  @override
  Future<void> saveConfiguration(
      {required String server,
      required String id,
      required String name,
      String? token,
      String? accountId,
      String? username}) async {}
  @override
  Future<Map<String, dynamic>?> pendingProfileUpdate() async => pendingUpdate;
  @override
  Future<void> setPendingProfileUpdate(String displayName, String username,
      {String phoneNumber = '',
      String phoneVisibility = 'contacts',
      bool discoverableByPhone = true,
      bool discoverableByName = true,
      bool directorySyncEnabled = true}) async {
    pendingUpdate = {
      'display_name': displayName,
      'username': username,
      'phone_number': phoneNumber,
      'phone_visibility': phoneVisibility,
    };
  }

  @override
  Future<void> clearPendingProfileUpdate() async => pendingUpdate = null;
  @override
  Future<String?> pendingProfileAvatarPath() async => null;
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

String _authBody() => jsonEncode({
      'account': {'id': 'u-real-1', 'username': 'sumaira', 'created_at': ''},
      'device': {'id': 'dev-zte', 'name': 'ZTE', 'platform': 'android', 'created_at': '', 'last_seen_at': ''},
      'token': 'tok2',
      'expires_at': '',
      'recovery_code': 'ABCDE-FGHIJ-KLMNO-PQRS2',
    });

String _profileBody({String phone = '', String name = 'sumaira'}) => jsonEncode({
      'user_id': 'u-real-1',
      'username': name,
      'display_name': 'Sumaira',
      'phone_number': phone,
      'phone_visibility': 'private',
      'profile_version': 2,
    });

void main() {
  late _Store store;
  final sent = <http.Request>[];

  setUp(() {
    store = _Store();
    sent.clear();
  });

  LocalLinkApi api(Future<http.Response> Function(http.Request r) handler) => LocalLinkApi(
      store, WebSocketService(),
      httpClient: ApiHttpClient(client: MockClient((r) async {
        sent.add(r);
        return handler(r);
      })));

  Future<T> zone<T>(Future<http.Response> Function(http.Request r) handler, Future<T> Function() body) =>
      http.runWithClient(body, () => MockClient((r) async {
            sent.add(r);
            return handler(r);
          }));

  test('register sends offline_user_id + recovery_code only while waiting', () async {
    final a = api((_) async => http.Response('', 500));
    await zone((_) async => http.Response(_authBody(), 201),
        () => a.registerAccount(username: 'Sumaira', password: 'pw-123456', deviceName: 'ZTE'));
    final body = jsonDecode(sent.single.body) as Map;
    expect(body['offline_user_id'], 'offline_0123456789ab');
    expect(body['recovery_code'], 'ABCDE-FGHIJ-KLMNO-PQRS2');

    sent.clear();
    store.waiting = false;
    await zone((_) async => http.Response(_authBody(), 201),
        () => a.registerAccount(username: 'Sumaira', password: 'pw-123456', deviceName: 'ZTE'));
    final plain = jsonDecode(sent.single.body) as Map;
    expect(plain.containsKey('offline_user_id'), isFalse);
    expect(plain.containsKey('recovery_code'), isFalse);
  });

  test('login sends offline_user_id only (her account keeps its code)', () async {
    final a = api((_) async => http.Response('', 500));
    await zone((_) async => http.Response(_authBody(), 200),
        () => a.loginAccount(username: 'sumaira', password: 'pw-123456', deviceName: 'ZTE'));
    final body = jsonDecode(sent.single.body) as Map;
    expect(body['offline_user_id'], 'offline_0123456789ab');
    expect(body.containsKey('recovery_code'), isFalse);
  });

  test('errors carry the code; the text is unchanged', () async {
    final a = api((_) async => http.Response('', 500));
    Object? caught;
    try {
      await zone(
          (_) async => http.Response(
              jsonEncode({'ok': false, 'error': 'device id is already registered', 'error_code': 'DEVICE_TAKEN', 'owner': 'oldname'}),
              409),
          () => a.registerAccount(username: 'sumaira', password: 'pw-123456', deviceName: 'ZTE'));
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<ApiError218>());
    expect((caught! as ApiError218).code, 'DEVICE_TAKEN');
    expect((caught as ApiError218).owner, 'oldname');
    expect(caught.toString(), 'Exception: device id is already registered');
  });

  test('PHONE_TAKEN: second PUT without the number, kept on this phone', () async {
    store.pendingUpdate = {'display_name': 'Sumaira', 'username': 'sumaira', 'phone_number': '03001234567'};
    store.settings['join_notice_218'] = jsonEncode({'kind': 'plain', 'name': 'sumaira'});
    final a = api((r) async {
      final b = jsonDecode(r.body) as Map;
      if ((b['phone_number'] as String).isNotEmpty) {
        return http.Response(
            jsonEncode({'ok': false, 'error': 'phone number is already registered', 'error_code': 'PHONE_TAKEN'}), 409);
      }
      return http.Response(_profileBody(), 200);
    });
    expect(await a.syncPendingProfile(), isTrue);
    final puts = sent.where((r) => r.method == 'PUT').toList();
    expect(puts.length, 2);
    expect((jsonDecode(puts.last.body) as Map)['phone_number'], '');
    expect(store.settings['phone_local_only_218'], '03001234567');
    expect(store.pendingUpdate, isNull);
    expect(store.me!.phoneNumber, '03001234567', reason: 'her number stays on her phone');
    expect((jsonDecode(store.settings['join_notice_218']!) as Map)['phone'], isTrue);
  });

  test('USERNAME_TAKEN with an old pending name → PUT with the current name', () async {
    store.pendingUpdate = {'display_name': 'Sumaira', 'username': 'sumaira', 'phone_number': ''};
    final a = api((r) async {
      final b = jsonDecode(r.body) as Map;
      if (b['username'] == 'sumaira') {
        return http.Response(
            jsonEncode({'ok': false, 'error': 'username is already registered', 'error_code': 'USERNAME_TAKEN'}), 409);
      }
      return http.Response(_profileBody(name: 'sumaira37'), 200);
    });
    expect(await a.syncPendingProfile(), isTrue);
    final puts = sent.where((r) => r.method == 'PUT').toList();
    expect([for (final p in puts) (jsonDecode(p.body) as Map)['username']], ['sumaira', 'sumaira37']);
  });

  test('a failing PUT for another reason is not retried in a loop', () async {
    store.pendingUpdate = {'display_name': 'Sumaira', 'username': 'sumaira37', 'phone_number': '0300'};
    final a = api((_) async => http.Response(
        jsonEncode({'ok': false, 'error': 'phone number is already registered', 'error_code': 'PHONE_TAKEN'}), 409));
    expect(await a.syncPendingProfile(), isFalse);
    expect(sent.where((r) => r.method == 'PUT').length, 2);
  });

  test('getProfile: empty server number + local-only flag → local number kept', () async {
    store.settings['phone_local_only_218'] = '03001234567';
    final a = api((_) async => http.Response('', 500));
    final p = await zone((_) async => http.Response(_profileBody(), 200), () => a.getProfile(downloadAvatar: false));
    expect(p.phoneNumber, '03001234567');
    expect(store.me!.phoneNumber, '03001234567');
    final other = await zone((_) async => http.Response(_profileBody(phone: '0321'), 200),
        () => a.getProfile(downloadAvatar: false));
    expect(other.phoneNumber, '0321', reason: 'a server number wins');
  });

  test('resolveIds218 posts the ids and never throws', () async {
    final a = api((_) async => http.Response('', 500));
    final found = await zone(
        (_) async => http.Response(
            jsonEncode({
              'found': [
                {'id': 'offline_0123456789ab', 'user_id': 'u-real-1', 'username': 'sumaira', 'device_id': 'dev-zte'}
              ]
            }),
            200),
        () => a.resolveIds218(['offline_0123456789ab', '', 'dev-x']));
    expect(found.single['user_id'], 'u-real-1');
    expect(sent.single.url.path, '/api/v1/users/resolve');
    expect((jsonDecode(sent.single.body) as Map)['ids'], ['offline_0123456789ab', 'dev-x']);
    final none = await zone((_) async => throw Exception('down'), () => a.resolveIds218(['x']));
    expect(none, isEmpty);
  });
}
