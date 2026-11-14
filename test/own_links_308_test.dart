// Bundle 308: both maps (Chats › My links, Admin › Link paths) show the same
// true path: the person's way, Mesh through the real next phone, and a
// down server marked with a red X + "Off".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/features/admin/presentation/screens/admin_panel_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/link_map_network_272.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';
import 'package:locallink/features/admin/presentation/widgets/own_links_308.dart';
import 'package:locallink/features/contacts/presentation/widgets/my_links_map_273.dart';

typedef _R1 = ({String id, String user, String name, String at, bool phone, bool person});
typedef _R2 = ({String id, String at, bool phone});

Set<String> _keys(List<LinkEdge> e) => {for (final x in e) x.key};

void main() {
  // The 15 Nov screens: kiran + ayesha on Wi-Fi, sumaira on Mesh via ayesha.
  const ways = <String, PresenceWayInfo>{
    'd-kiran': PresenceWayInfo(PresenceWay.wifi),
    'd-ayesha': PresenceWayInfo(PresenceWay.wifi),
    'd-sumaira': PresenceWayInfo(PresenceWay.mesh, hops: 2, via: 'd-ayesha'),
  };
  PresenceWayInfo wayOf(String id) => ways[id] ?? const PresenceWayInfo(PresenceWay.offline);

  group('one rule for both maps', () {
    test('Mesh via a phone on the map: ayesha -> sumaira, never You -> sumaira', () {
      final r = OwnLinks308.admin(
        nodes: const [
          LinkNode(id: 'd-kiran', label: 'kiran', tag: LinkTag.localWifi, userId: 'u-kiran'),
          LinkNode(id: 'd-ayesha', label: 'ayesha', tag: LinkTag.localWifi, userId: 'u-ayesha'),
          LinkNode(id: 'd-sumaira', label: 'sumaira', tag: LinkTag.mesh, userId: 'u-sumaira'),
        ],
        wayOf: wayOf,
      );
      final sum = r.nodes.firstWhere((n) => n.id == 'd-sumaira');
      expect(sum.noLine, isTrue); // no guessed chain line
      expect(sum.tag, LinkTag.mesh);
      expect(_keys(r.edges), {const LinkEdge('d-ayesha', 'd-sumaira', LinkTag.mesh).key});
      expect(r.nodes.where((n) => n.relay), isEmpty);
      expect(r.nodes.firstWhere((n) => n.id == 'd-ayesha').noLine, isFalse); // own teal line
    });

    test('admin and My links give the SAME lines for the same people', () {
      final admin = OwnLinks308.admin(
        nodes: const [
          LinkNode(id: 'd-kiran', label: 'kiran', tag: LinkTag.localWifi, userId: 'u-kiran'),
          LinkNode(id: 'd-ayesha', label: 'ayesha', tag: LinkTag.localWifi, userId: 'u-ayesha'),
          LinkNode(id: 'd-sumaira', label: 'sumaira', tag: LinkTag.mesh, userId: 'u-sumaira'),
        ],
        wayOf: wayOf,
      );
      final mine = MyLinks273.build(
        contacts: const [
          MyLinkContact273(deviceId: 'd-kiran', userId: 'u-kiran', name: 'kiran'),
          MyLinkContact273(deviceId: 'd-ayesha', userId: 'u-ayesha', name: 'ayesha'),
          MyLinkContact273(deviceId: 'd-sumaira', userId: 'u-sumaira', name: 'sumaira'),
        ],
        wayOf: wayOf,
      );
      expect(_keys(admin.edges), _keys(mine.edges));
      String lines(List<LinkNode> n) =>
          ([for (final x in n) '${x.id}:${x.tag.name}:${x.noLine}']..sort()).join(',');
      expect(lines(admin.nodes), lines(mine.nodes));
      expect(mine.relaysKnown, 1);
    });

    test('via a phone that is not on the map = LinkUp logo in the middle', () {
      final r = OwnLinks308.admin(
        nodes: const [LinkNode(id: 'd-sumaira', label: 'sumaira', tag: LinkTag.mesh)],
        wayOf: (_) => const PresenceWayInfo(PresenceWay.mesh, hops: 3, via: 'd-far'),
      );
      final relay = r.nodes.singleWhere((n) => n.relay);
      expect(relay.id, '${OwnLinks308.relayPrefix}d-far');
      expect(relay.hiddenMore, 1);
      expect(_keys(r.edges), {
        const LinkEdge(LinkEdge.self, 'relay:d-far', LinkTag.mesh).key,
        const LinkEdge('relay:d-far', 'd-sumaira', LinkTag.mesh).key,
      });
    });

    test('via a second phone of a person on the map = that person', () {
      final r = OwnLinks308.admin(
        nodes: const [
          LinkNode(id: 'd-ayesha', label: 'ayesha', tag: LinkTag.localWifi, userId: 'u-ayesha'),
          LinkNode(id: 'd-sumaira', label: 'sumaira', tag: LinkTag.mesh, userId: 'u-sumaira'),
        ],
        wayOf: (id) => id == 'd-sumaira'
            ? const PresenceWayInfo(PresenceWay.mesh, hops: 2, via: 'd-ayesha-old')
            : const PresenceWayInfo(PresenceWay.wifi),
        userOf: (id) => id == 'd-ayesha-old' ? 'u-ayesha' : null,
      );
      expect(_keys(r.edges), {const LinkEdge('d-ayesha', 'd-sumaira', LinkTag.mesh).key});
    });

    test('Mesh with no known next phone: its own line from You (no chain)', () {
      final r = OwnLinks308.admin(
        nodes: const [
          LinkNode(id: 'a', label: 'a', tag: LinkTag.mesh),
          LinkNode(id: 'b', label: 'b', tag: LinkTag.mesh, blocked: true),
        ],
        wayOf: (_) => const PresenceWayInfo(PresenceWay.offline), // saved flag only
      );
      expect(r.nodes.every((n) => n.noLine), isTrue);
      expect(_keys(r.edges), {
        const LinkEdge(LinkEdge.self, 'a', LinkTag.mesh).key,
        const LinkEdge(LinkEdge.self, 'b', LinkTag.mesh, blocked: true).key,
      });
    });

    test('Wi-Fi Direct / server / offline nodes are left as they were', () {
      const nodes = [
        LinkNode(id: 'w', label: 'w', tag: LinkTag.wifiDirect),
        LinkNode(id: 's', label: 's', tag: LinkTag.server),
        LinkNode(id: 'o', label: 'o', tag: LinkTag.mesh, offline: true, noLine: true),
      ];
      final r = OwnLinks308.admin(nodes: nodes, wayOf: (_) => const PresenceWayInfo(PresenceWay.online));
      expect(r.nodes, nodes);
      expect(r.edges, isEmpty);
    });
  });

  group('kiran is not dropped from the admin map', () {
    test('the person is near on another phone id -> the admin row counts', () {
      final t = DateTime(2026, 11, 15, 11, 11);
      final hub = PresenceHub(clock: () => t);
      hub.linkUser('d-kiran-old', 'u-kiran');
      hub.linkUser('d-kiran-new', 'u-kiran');
      hub.notePath('d-kiran-new', up: true);
      hub.noteRoute(const PresenceRoute('d-kiran-new', 'lan'));
      // Old rule (this phone id only) dropped the saved row:
      expect(adminHubNearby254('d-kiran-old', hub), isFalse);
      // 308: the person is near -> shown, with the same way as My links.
      expect(adminPersonNear308('d-kiran-old', hub), isTrue);
      expect(adminPersonTag308('d-kiran-old', hub), LinkTag.localWifi);
      expect(adminPersonTag308('d-kiran-new', hub), LinkTag.localWifi);
      expect(adminPersonNear308('d-nobody', hub), isFalse);
      expect(adminPersonTag308('d-nobody', hub), isNull);
    });

    test('a phone near now is live: not hidden as a stale twin (same model name)', () {
      final now = DateTime.utc(2026, 11, 15, 6, 11);
      final stale = now.subtract(const Duration(minutes: 30)).toIso8601String();
      final fresh = now.subtract(const Duration(minutes: 1)).toIso8601String();
      final rows = <_R1>[
        (id: 'd-ayesha', user: 'u-ayesha', name: 'realme Note 60x', at: fresh, phone: true, person: true),
        (id: 'd-kiran', user: 'u-kiran', name: 'realme Note 60x', at: stale, phone: true, person: true),
      ];
      List<String> kept(bool use308) => dedupeNodes<_R1>(rows,
              deviceId: (r) => r.id,
              userId: (r) => r.user,
              phoneName: (r) => r.name,
              seenAt: (r) => use308
                  ? adminSeenAt308(presenceLocalAt: r.at, phoneNear: r.phone, personNear: r.person, now: now)
                  : DateTime.tryParse(r.at),
              now: now)
          .kept
          .map((r) => r.id)
          .toList();
      expect(kept(false), ['d-ayesha']); // the old way: kiran hidden
      expect(kept(true), ['d-ayesha', 'd-kiran']);
    });

    test('two phones of one person: the phone near now wins', () {
      final now = DateTime.utc(2026, 11, 15, 6, 11);
      final newer = now.subtract(const Duration(seconds: 10)).toIso8601String();
      final rows = <_R2>[
        (id: 'd-old', at: newer, phone: false),
        (id: 'd-new', at: '', phone: true),
      ];
      final r = dedupeNodes<_R2>(rows,
          deviceId: (r) => r.id,
          userId: (_) => 'u-kiran',
          phoneName: (_) => '',
          seenAt: (r) => adminSeenAt308(presenceLocalAt: r.at, phoneNear: r.phone, personNear: true, now: now),
          now: now);
      expect(r.kept.single.id, 'd-new');
      expect(adminSeenAt308(presenceLocalAt: newer, phoneNear: false, personNear: false, now: now),
          DateTime.parse(newer));
    });

    test('admin screen uses the person rule, the 308 lines and the same list for "Phones near"', () {
      final src = File('lib/features/admin/presentation/screens/admin_panel_screen.dart').readAsStringSync();
      expect(src, contains('static bool _hubNearby(String id) => adminPersonNear308(id);'));
      expect(src, contains('static LinkTag? _hubTag(String id) => adminPersonTag308(id);'));
      expect(src, contains('seenAt: (d) => adminSeenAt308('));
      expect(src, contains('final mine = OwnLinks308.admin('));
      expect(src, contains('ownEdges: mine.edges,'));
      expect(src, contains("near: '\${_check ? 3 : onLink.length}',"));
      expect(src, contains('final devices = onLink;'));
      final my = File('lib/features/contacts/presentation/widgets/my_links_map_273.dart').readAsStringSync();
      expect(my, contains('OwnLinks308.meshLines('));
      expect(my, contains('OwnLinks308.clean(edges, ownLine)'));
    });
  });

  group('309 G2/G3: right owner per phone, a near phone is never hidden', () {
    test('one phone, an old and a new card -> the NEWEST card (was: the oldest)', () {
      final rows = <Map<String, dynamic>>[
        {'user_id': 'u-kiran', 'device_id': 'd-tecno', 'updated_at': '2026-11-14T10:00:00Z'}, // newest first
        {'user_id': 'u-ibrahim', 'device_id': 'd-tecno', 'updated_at': '2026-11-01T10:00:00Z'},
        {'user_id': 'u-ayesha', 'device_id': 'd-ayesha', 'updated_at': '2026-11-10T10:00:00Z'},
        {'user_id': 'u-none', 'device_id': '', 'updated_at': '2026-11-10T10:00:00Z'},
      ];
      final cards = adminCardPerPhone309(rows);
      expect(cards.keys.toSet(), {'d-tecno', 'd-ayesha'});
      expect(cards['d-tecno']!['user_id'], 'u-kiran');
      // Order does not matter.
      expect(adminCardPerPhone309(rows.reversed.toList())['d-tecno']!['user_id'], 'u-kiran');
    });

    test('a server card wins over a newer offline card (same rule as PresenceHub)', () {
      final cards = adminCardPerPhone309([
        {'user_id': 'offline_abc', 'device_id': 'd-z', 'updated_at': '2026-11-15T10:00:00Z'},
        {'user_id': 'u-sumaira', 'device_id': 'd-z', 'updated_at': '2026-11-01T10:00:00Z'},
      ]);
      expect(cards['d-z']!['user_id'], 'u-sumaira');
    });

    test('near phone: merged only on the hub owner, never on an old card', () {
      expect(adminDupeUser309(phoneNear: true, hubUser: null, cardUser: 'u-old'), '');
      expect(adminDupeUser309(phoneNear: true, hubUser: 'u-kiran', cardUser: 'u-old'), 'u-kiran');
      expect(adminDupeUser309(phoneNear: false, hubUser: 'u-kiran', cardUser: 'u-old'), 'u-kiran');
      expect(adminDupeUser309(phoneNear: false, hubUser: null, cardUser: 'u-old'), 'u-old');
      expect(adminDupeUser309(phoneNear: false), '');
    });

    test('the 11:51 case: kiran near, his phone has an old card of a near friend -> both stay', () {
      final now = DateTime.utc(2026, 11, 15, 6, 51);
      final fresh = now.toIso8601String();
      // Old card on kiran's phone says "u-ayesha"; the hub knows kiran's phone only as near.
      final rows = <({String id, String card, String? hub})>[
        (id: 'd-ayesha', card: 'u-ayesha', hub: 'u-ayesha'),
        (id: 'd-kiran', card: 'u-ayesha', hub: null),
      ];
      List<String> kept({required bool use309}) => dedupeNodes<({String id, String card, String? hub})>(rows,
              deviceId: (r) => r.id,
              userId: (r) => use309 ? adminDupeUser309(phoneNear: true, hubUser: r.hub, cardUser: r.card) : r.card,
              phoneName: (r) => r.id,
              seenAt: (r) => adminSeenAt308(presenceLocalAt: fresh, phoneNear: true, personNear: true, now: now),
              now: now)
          .kept
          .map((r) => r.id)
          .toList();
      expect(kept(use309: false), hasLength(1)); // before: one of them hidden as a "duplicate"
      expect(kept(use309: true), ['d-ayesha', 'd-kiran']);
    });

    test('the admin screen uses both rules', () {
      final src = File('lib/features/admin/presentation/screens/admin_panel_screen.dart').readAsStringSync();
      expect(src, contains('final cards = adminCardPerPhone309(await widget.store.directoryProfiles());'));
      expect(src, contains('userId: (d) => adminDupeUser309('));
      expect(src, isNot(contains('for (final p in await widget.store.directoryProfiles()) {')));
    });
  });

  group('admin network keeps the own lines', () {
    test('server off: own lines are the map lines', () {
      final r = LinkMapNetwork272.merge(
        own: const [LinkNode(id: 'b', label: 'b', tag: LinkTag.mesh, noLine: true)],
        ownEdges: const [LinkEdge('a', 'b', LinkTag.mesh)],
        serverMap: null,
        serverOnline: false,
        fetchedAt: null,
      );
      expect(r.src, 'own');
      expect(_keys(r.extraEdges), {const LinkEdge('a', 'b', LinkTag.mesh).key});
    });

    test('server on: own lines stay; a phone turned Server gets the server line back', () {
      final now = DateTime(2026, 11, 15, 11);
      final r = LinkMapNetwork272.merge(
        own: const [
          LinkNode(id: 'a', label: 'a', tag: LinkTag.localWifi),
          LinkNode(id: 'b', label: 'b', tag: LinkTag.mesh, noLine: true),
          LinkNode(id: 'c', label: 'c', tag: LinkTag.mesh, noLine: true),
        ],
        ownEdges: const [
          LinkEdge('a', 'b', LinkTag.mesh),
          LinkEdge(LinkEdge.self, 'c', LinkTag.mesh),
        ],
        serverMap: {
          'nodes': [
            {'device_id': 'c', 'online': true},
          ],
        },
        serverOnline: true,
        fetchedAt: now,
        noFlag: {'c'},
        now: now,
      );
      expect(r.src, 'server');
      final c = r.nodes.firstWhere((n) => n.id == 'c');
      expect(c.tag, LinkTag.server);
      expect(c.noLine, isFalse);
      expect(_keys(r.extraEdges), contains(const LinkEdge('a', 'b', LinkTag.mesh).key));
      expect(_keys(r.extraEdges), isNot(contains(const LinkEdge(LinkEdge.self, 'c', LinkTag.mesh).key)));
    });
  });

  group('server off mark', () {
    for (final dark in [false, true]) {
      testWidgets('small + big map paint the red X + "Off" (dark=$dark)', (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: const Scaffold(
            body: Column(children: [
              SizedBox(
                height: 200,
                child: LinkPathsMap(
                  title: 'Link paths',
                  height: 104,
                  serverOnline: false,
                  selfName: 'Sajjad',
                  selfId: 'd-me',
                  nodes: [
                    LinkNode(id: 'd-ayesha', label: 'ayesha', tag: LinkTag.localWifi),
                    LinkNode(id: 'd-sumaira', label: 'sumaira', tag: LinkTag.mesh, noLine: true),
                  ],
                  extraEdges: [LinkEdge('d-ayesha', 'd-sumaira', LinkTag.mesh)],
                ),
              ),
              SizedBox(
                height: 300,
                child: LinkPathsCanvas(
                  serverOnline: false,
                  selfName: 'Sajjad',
                  selfId: 'd-me',
                  nodes: [LinkNode(id: 'd-ayesha', label: 'ayesha', tag: LinkTag.localWifi)],
                ),
              ),
            ]),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        final src = File('lib/features/admin/presentation/widgets/link_paths_map.dart').readAsStringSync();
        expect(src, contains("if (mid != null) _serverOffMark(canvas, mid.position, mid.vector);"));
        expect(src, contains("text: L.en('Off'),"));
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
