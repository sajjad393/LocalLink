import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/services/admin_live_hint_274.dart';
import 'package:locallink/features/admin/presentation/widgets/link_ways_274.dart';

/// Bundle 274: live admin data (hint -> quiet re-read) and the dashboard
/// ring that counts each phone once.
void main() {
  setUp(AdminLiveHint274.resetForTest);

  test('hint frame bumps the tick; other frames do not', () {
    final t0 = AdminLiveHint274.tick.value;
    expect(AdminLiveHint274.onMessage({'type': 'message'}), isFalse);
    expect(AdminLiveHint274.tick.value, t0);
    expect(AdminLiveHint274.onMessage({'type': 'admin_link_map_changed'}), isTrue);
    expect(AdminLiveHint274.tick.value, t0 + 1);
  });

  test('D-2: each phone once; the row counts links', () {
    final w = LinkWays274.of({
      'nodes': [
        {'device_id': 'a', 'online': true, 'link': 'server'},
        {'device_id': 'b', 'online': true, 'link': 'server'},
        {'device_id': 'c', 'online': false, 'link': 'lan'},
        {'device_id': 'd', 'online': false, 'link': 'wifi_direct'},
        {'device_id': 'e', 'online': false, 'link': 'mesh'},
        {'device_id': 'f', 'online': false, 'link': ''},
      ],
      'edges': [
        {'from': 'server', 'to': 'a', 'link': 'server'},
        {'from': 'server', 'to': 'b', 'link': 'server'},
        {'from': 'a', 'to': 'c', 'link': 'lan'},
        {'from': 'a', 'to': 'd', 'link': 'wifi_direct'},
        {'from': 'b', 'to': 'd', 'link': 'wifi_direct'},
        {'from': 'd', 'to': 'e', 'link': 'mesh'},
      ],
    })!;
    expect([w.server, w.lan, w.wifiDirect, w.mesh, w.offline], [2, 1, 1, 1, 1]);
    expect(w.server + w.lan + w.wifiDirect + w.mesh + w.offline, w.phones);
    expect(w.phones, 6);
    expect(w.online, 5);
    expect([w.serverLinks, w.lanLinks, w.wifiDirectLinks, w.meshLinks], [2, 1, 2, 1]);
    expect(LinkWays274.of(null), isNull);
  });

  test('D-3 / D-4 wiring', () {
    final dash = File('lib/features/admin/presentation/screens/admin_dashboard_screen.dart').readAsStringSync();
    expect(dash, contains('LinkWays274.of(state.linkMapData)'));
    expect(dash, contains('kLinkTagColors[LinkTag.server]'));
    expect(dash, contains('Each phone once, by how it is linked now'));
    final shell = File('lib/features/admin/presentation/screens/admin_shell_screen.dart').readAsStringSync();
    expect(shell, contains('AdminLiveHint274.tick.addListener(_onHint274)'));
    expect(shell, contains('AdminLiveHint274.tick.removeListener(_onHint274)'));
    final role = File('lib/features/admin/data/services/admin_role_service.dart').readAsStringSync();
    expect(role, contains('AdminLiveHint274.onMessage('));
    final presence = File('lib/features/connectivity/data/services/presence_service.dart').readAsStringSync();
    expect(presence, contains('peer_disconnected'));
  });
}
