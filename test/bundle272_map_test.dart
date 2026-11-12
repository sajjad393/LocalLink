import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/presentation/theme/admin_ui216.dart';
import 'package:locallink/features/admin/presentation/widgets/link_map_network_272.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

/// Bundle 272: the app admin map = this phone's links + the server's live
/// map (option B) while the server is connected; server lines are blue.
void main() {
  final now = DateTime(2026, 11, 14, 12);
  Map<String, dynamic> map() => {
        'server': 'server',
        'nodes': [
          {
            'device_id': 'a',
            'user_id': 'ua',
            'username': 'ali',
            'display_name': 'My Android Phone (1a2b)',
            'online': true,
            'link': 'server'
          },
          {
            'device_id': 'b',
            'user_id': 'ub',
            'username': '@bina',
            'display_name': 'Bina',
            'online': true,
            'link': 'server'
          },
          {'device_id': 'me', 'user_id': 'um', 'username': 'me', 'online': true, 'link': 'server'},
          {'device_id': 'c', 'user_id': 'uc', 'username': 'chan', 'online': false, 'link': 'mesh'},
          {'device_id': 'w', 'user_id': 'uw', 'username': 'wifi', 'online': true, 'link': 'server'},
          {'device_id': 'a2', 'user_id': 'ua', 'username': 'ali', 'online': true, 'link': 'server'},
          {'device_id': 'x', 'user_id': 'ux', 'username': 'blocked', 'online': true, 'link': 'server'},
        ],
        'edges': [
          {'from': 'server', 'to': 'a', 'link': 'server'},
          {'from': 'a', 'to': 'b', 'link': 'wifi_direct'},
          {'from': 'me', 'to': 'b', 'link': 'lan'},
          {'from': 'a', 'to': 'c', 'link': 'mesh'},
        ],
      };
  final own = [
    const LinkNode(id: 'w', label: 'Wafa', tag: LinkTag.localWifi, userId: 'uw'),
    const LinkNode(id: 'n', label: 'Noor', tag: LinkTag.mesh, userId: 'un'),
  ];

  test('server off / stale / no map: only my links', () {
    for (final r in [
      LinkMapNetwork272.merge(own: own, serverMap: map(), serverOnline: false, fetchedAt: now, now: now),
      LinkMapNetwork272.merge(
          own: own,
          serverMap: map(),
          serverOnline: true,
          fetchedAt: now.subtract(const Duration(seconds: 91)),
          now: now),
      LinkMapNetwork272.merge(own: own, serverMap: null, serverOnline: true, fetchedAt: now, now: now),
    ]) {
      expect(r.src, 'own');
      expect(r.nodes.map((n) => n.id), ['w', 'n']);
      expect(r.extraEdges, isEmpty);
    }
  });

  test('server on: online phones added once per person, never me / hidden', () {
    final r = LinkMapNetwork272.merge(
        own: own, serverMap: map(), serverOnline: true, fetchedAt: now, selfIds: {'me'}, hidden: {'x'}, now: now);
    expect(r.src, 'server');
    expect(r.nodes.map((n) => n.id).toList(), ['w', 'n', 'a', 'b']);
    final a = r.nodes.firstWhere((n) => n.id == 'a');
    expect(a.label, 'ali'); // 276: default phone name never shown
    expect(a.tag, LinkTag.server);
    expect(r.nodes.firstWhere((n) => n.id == 'b').label, 'Bina');
    expect(r.nodes.any((n) => n.id == 'c'), isFalse); // offline on the server
  });

  test('blue server line to a phone I see another way; phone lines without me', () {
    final r = LinkMapNetwork272.merge(
        own: own, serverMap: map(), serverOnline: true, fetchedAt: now, selfIds: {'me'}, hidden: {'x'}, now: now);
    expect(r.extraEdges, contains(const LinkEdge(LinkEdge.server, 'w', LinkTag.server)));
    expect(r.extraEdges, contains(const LinkEdge('a', 'b', LinkTag.wifiDirect)));
    expect(r.extraEdges.any((e) => e.from == 'me' || e.to == 'me'), isFalse);
    expect(r.extraEdges.any((e) => e.to == 'c' || e.from == 'c'), isFalse);
  });

  test('A-3: a phone with no flag of its own that is on the server = Server', () {
    final r = LinkMapNetwork272.merge(
        own: [const LinkNode(id: 'w', label: 'Wafa', tag: LinkTag.mesh, userId: 'uw')],
        serverMap: map(),
        serverOnline: true,
        fetchedAt: now,
        noFlag: {'w'},
        now: now);
    expect(r.nodes.first.tag, LinkTag.server);
  });

  test('link words', () {
    expect(LinkMapNetwork272.tagOfWord('server'), LinkTag.server);
    expect(LinkMapNetwork272.tagOfWord('wifi_direct'), LinkTag.wifiDirect);
    expect(LinkMapNetwork272.tagOfWord('mesh'), LinkTag.mesh);
    for (final w in ['lan', 'router', 'local_wifi', 'wifi']) {
      expect(LinkMapNetwork272.tagOfWord(w), LinkTag.localWifi, reason: w);
    }
    expect(LinkMapNetwork272.tagOfWord('?'), isNull);
  });

  test('server = blue everywhere; panel says when the server is off', () {
    expect(A216.linkServer.toARGB32(), 0xFF3B82C4);
    expect(kLinkTagColors[LinkTag.server]!.toARGB32(), 0xFF3B82C4);
    final panel = File('lib/features/admin/presentation/screens/admin_panel_screen.dart').readAsStringSync();
    expect(panel, contains('Server off - your links only'));
    expect(panel, contains('linkMapData'));
  });
}
