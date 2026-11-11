// Bundle 223 (Phase 7, O): clean logs.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/account/presentation/screens/account_center_screen.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';

import 'support/phase5_fakes.dart';

class _NoTokenStore extends FakeStore {
  @override
  String? get deviceToken => null;
  @override
  String? get serverAddress => null;
}

List<String> _log() => AppLogFile.instance.pendingForTest;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppLogFile.instance.resetForTest());

  test('223-32 the stamp is made from kAppVersion + kAppBuild = pubspec', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    expect(pub, contains('version: $kAppVersion+$kAppBuild'));
    expect(kAppVersion, '3.0.77');
    expect(kAppBuild, 148);
    expect(AppBuild.stamp, 'v3 · 3.0.77+148');
    final app = File('lib/app/local_link_app.dart').readAsStringSync();
    expect(app, contains("AppLogger.info('APP_BUILD_STAMP', detail: AppBuild.stamp);"));
    expect(app, isNot(contains('3.0.50')));
  });

  test('223-33 source: normal pair steps are INFO, real problems stay WARN', () {
    final all = File('lib/features/directory/data/services/pairing_service.dart').readAsStringSync() +
        File('lib/features/directory/presentation/nearby_people_section.dart').readAsStringSync();
    final warn = RegExp(r"AppLogger\.warning\('PAIR_(ACCEPT|STAGE|TAP|SHEET|UI)',?[^;]*;")
        .allMatches(all)
        .map((m) => m.group(0)!)
        .toList();
    expect(warn.length, 3);
    expect(warn.where((w) => w.contains('adopt_failed')).length, 1);
    expect(warn.where((w) => w.contains('caught error=')).length, 1);
    expect(warn.where((w) => w.contains('PAIR_AMBIGUOUS')).length, 1);
    expect(RegExp(r"AppLogger\.info\('PAIR_(ACCEPT|STAGE|TAP|SHEET|UI)'").allMatches(all).length,
        greaterThanOrEqualTo(22));
  });

  test('223-34 LogOnce writes once per state, again when it changes', () {
    final once = LogOnce();
    expect(once.info('X_SKIPPED', 'no_token'), isTrue);
    expect(once.info('X_SKIPPED', 'no_token'), isFalse);
    expect(once.info('X_SKIPPED', 'no_server'), isTrue);
    once.clear('X_SKIPPED');
    expect(once.info('X_SKIPPED', 'no_server'), isTrue);
    final lines = _log().where((l) => l.contains('X_SKIPPED')).toList();
    expect(lines.length, 3);
    expect(lines.every((l) => l.contains('|I|')), isTrue);
  });

  test('223-34 phone-only account: sync skip lines once, INFO', () async {
    final store = _NoTokenStore();
    final socket = WebSocketService();
    final service = ReliableMessagingService(store, LocalLinkApi(store, socket), socket,
        FakeFilesRepository(), FakeConnectivity(), FakePeerTransport());
    for (var i = 0; i < 4; i++) {
      await service.synchronize();
    }
    final sync = _log().where((l) => l.contains('MESSAGE_SYNC_SKIPPED')).toList();
    final peers = _log().where((l) => l.contains('KNOWN_PEERS_REFRESH_SKIPPED')).toList();
    expect(sync.length, 1);
    expect(sync.single, contains('|I|'));
    expect(sync.single, contains('no_token'));
    expect(peers.length, 1);
    expect(peers.single, contains('|I|'));
    final src = File('lib/features/messaging/data/services/reliable_messaging_service.dart').readAsStringSync();
    expect(src, contains("_logOnce.info('DIRECT_TRANSPORT_INFO', info);"));
  });

  test('223-34b offline failures are WARN with offline=<type>; other errors stay ERROR', () {
    AppLogger.failure('HTTP_REQUEST_FAILED',
        error: const SocketException('Connection refused'), detail: 'GET /x (12ms)');
    AppLogger.failure('WS_READY_TIMEOUT', error: TimeoutException('ready'));
    AppLogger.failure('MESSAGE_SYNC_FAILED', error: const FormatException('bad json'));
    final l = _log();
    final http = l.firstWhere((x) => x.contains('HTTP_REQUEST_FAILED'));
    expect(http, contains('|W|'));
    expect(http, contains('GET /x (12ms) offline=SocketException'));
    expect(l.firstWhere((x) => x.contains('WS_READY_TIMEOUT')), contains('|W|'));
    expect(l.firstWhere((x) => x.contains('MESSAGE_SYNC_FAILED')), contains('|E|'));
    expect(AppLogger.isOfflineError(Exception('Failed host lookup: x')), isTrue);
    expect(AppLogger.isOfflineError(StateError('x')), isFalse);
  });

  test('223-34b source: the 6 network failures use AppLogger.failure', () {
    String read(String p) => File(p).readAsStringSync();
    final all = read('lib/core/services/websocket_service.dart') +
        read('lib/core/network/api_http_client.dart') +
        read('lib/features/messaging/data/services/reliable_messaging_service.dart');
    for (final e in [
      'WS_STREAM_ERROR',
      'WS_READY_TIMEOUT',
      'HTTP_REQUEST_FAILED',
      'MESSAGE_REALTIME_CONNECT_FAILED',
      'MESSAGE_SYNC_FAILED',
      'MESSAGE_HISTORY_REMOTE_FAILED',
    ]) {
      expect(RegExp("AppLogger\\.failure\\([^']*'$e'").hasMatch(all), isTrue, reason: e);
      expect(RegExp("AppLogger\\.error\\(\\s*'$e'").hasMatch(all), isFalse, reason: e);
    }
  });

  test('223-34c ACCOUNT_OFFLINE_BOX reason', () {
    expect(accountOfflineBoxReason(serverAddress: null), 'phone_only');
    expect(accountOfflineBoxReason(serverAddress: ' '), 'phone_only');
    expect(accountOfflineBoxReason(serverAddress: 'http://x', reachWhy: 'no_network'), 'no_network');
    expect(accountOfflineBoxReason(serverAddress: 'http://x', reachWhy: 'server_down'), 'server_down');
    expect(accountOfflineBoxReason(serverAddress: 'http://x'), 'server_down');
    final src = File('lib/features/account/presentation/screens/account_center_screen.dart').readAsStringSync();
    expect(src, contains("detail: 'reason=\$reason serverConnected="));
  });
}
