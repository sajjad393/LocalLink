import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/core/state/server_status_321.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/connectivity/data/services/server_group_repair_321.dart';

// Bundle 321 Phase 4: websocket ping, 8 s list limit, one server status,
// Wi-Fi Direct self-repair.

void main() {
  setUp(AppLogFile.instance.resetForTest);

  group('F4', () {
    test('the socket pings every 20 s', () {
      expect(WebSocketService.pingInterval321, const Duration(seconds: 20));
      final s = File('lib/core/services/websocket_service.dart').readAsStringSync();
      final connect = s.substring(s.indexOf('IOWebSocketChannel.connect('));
      expect(connect.substring(0, 200), contains('pingInterval: pingInterval321,'));
    });

    test('Conversations lists give up after 8 s (writes keep 30 s)', () {
      expect(HttpChatAdminServer.listTimeout, const Duration(seconds: 8));
      final s = File('lib/features/admin/data/actions/chat_answer_reader.dart').readAsStringSync();
      expect(s, contains("_uri('/api/v1/admin/conversations'), headers: _h(token)).timeout(listTimeout)"));
      expect(s, contains("_uri('/api/v1/admin/chat-requests'), headers: _h(token)).timeout(listTimeout)"));
      // Bundle 332: assert the code, not the indentation (it drifted once).
      final flat = s.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat, contains("_uri('/api/v1/admin/chat-requests'), headers: _h(token), body: jsonEncode(body)) .timeout(_timeout)"));
    });
  });

  group('F11 one status', () {
    testWidgets('on at once; off only after 15 s without the server; no flip-flop', (tester) async {
      var shown = false;
      var up = false;
      final st = ServerStatus321(set: (v) => shown = v, current: () => shown, socketUp: () => up);
      up = true;
      st.onSocket(true);
      expect(shown, isTrue);
      up = false;
      st.onSocket(false);
      await tester.pump(const Duration(seconds: 10));
      expect(shown, isTrue, reason: 'still within 15 s');
      up = true;
      st.onSocket(true); // came back: no "off" at all
      await tester.pump(const Duration(seconds: 10));
      expect(shown, isTrue);
      up = false;
      st.onSocket(false);
      await tester.pump(const Duration(seconds: 15));
      expect(shown, isFalse);
      expect(AppLogFile.instance.pendingForTest.join('\n'), contains('SERVER_STATUS_OFF|after_s=15'));
      st.reset();
    });

    test('every admin screen source reads the same status', () {
      final s = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect('serverOnline: () => viewMode.state.serverConnected'.allMatches(s).length, 5);
      expect(s, isNot(contains('serverOnline: () => socket.isConnected')));
      expect(s, contains('serverStatus321(connected); // Bundle 321 (F11)'));
      final conv = File('lib/features/admin/presentation/screens/admin_conversations_screen.dart').readAsStringSync();
      expect(conv, contains('widget.viewMode?.state.serverConnected'));
    });
  });

  group('L19b self-repair', () {
    const min = 60 * 1000;
    test('2 min no server while in a group on Wi-Fi -> leave ONCE, no own group for 15 min', () {
      final r = ServerGroupRepair321();
      const down = 1000000;
      expect(r.shouldDrop(now: down + min, serverDownSince: down, inGroup: true, onWifi: true), isFalse);
      expect(r.shouldDrop(now: down + 2 * min, serverDownSince: down, inGroup: true, onWifi: true), isTrue);
      expect(r.shouldDrop(now: down + 3 * min, serverDownSince: down, inGroup: true, onWifi: true), isFalse,
          reason: 'once per server loss');
      expect(r.hostHeld(now: down + 10 * min, onWifi: true), isTrue);
      expect(r.hostHeld(now: down + 10 * min, onWifi: false), isFalse, reason: 'only on this Wi-Fi');
      expect(r.hostHeld(now: down + 18 * min, onWifi: true), isFalse);
      // A new loss later acts again.
      const again = down + 60 * min;
      expect(r.shouldDrop(now: again + 2 * min, serverDownSince: again, inGroup: true, onWifi: true), isTrue);
    });

    test('server answers / no group / not on Wi-Fi -> group untouched', () {
      final r = ServerGroupRepair321();
      expect(r.shouldDrop(now: 9 * min, serverDownSince: 0, inGroup: true, onWifi: true), isFalse);
      expect(r.shouldDrop(now: 9 * min, serverDownSince: 1, inGroup: false, onWifi: true), isFalse);
      expect(r.shouldDrop(now: 9 * min, serverDownSince: 1, inGroup: true, onWifi: false), isFalse);
      expect(r.hostHeld(now: 9 * min, onWifi: true), isFalse);
    });

    test('wired: leave + log + retry before the plan; create held; never turns Wi-Fi off', () {
      final s = File('lib/features/connectivity/data/services/wifi_direct_fallback_service.dart').readAsStringSync();
      final at = s.indexOf("AppLogger.info('WD_GROUP_DROP',");
      expect(at, greaterThan(0));
      expect(at, lessThan(s.indexOf('final planned = planNearbyGroup(NearbyGroupInput(')));
      final block = s.substring(at, at + 500);
      expect(block, contains('await connectivity.disconnectWifiDirect();'));
      expect(block, contains('serverRetry321?.call();'));
      expect(s, contains("why=server_repair"));
      expect(s.toLowerCase(), isNot(contains('setwifienabled')));
      final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(deps, contains('wifiDirectFallback.serverDownSince321 = () => _serverDownAt321;'));
    });
  });
}
