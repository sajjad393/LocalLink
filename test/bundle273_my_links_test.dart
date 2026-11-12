import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';
import 'package:locallink/features/contacts/presentation/widgets/my_links_map_273.dart';

/// Bundle 273: "My links" - only my contacts, a line by how each is reached;
/// a relay that is not a contact = LinkUp logo, no name.
void main() {
  const contacts = [
    MyLinkContact273(deviceId: 'a', userId: 'ua', name: 'Ali'),
    MyLinkContact273(deviceId: 'b', userId: 'ub', name: 'Bina'),
    MyLinkContact273(deviceId: 'c', userId: 'uc', name: 'Chan'),
    MyLinkContact273(deviceId: 'd', userId: 'ud', name: 'Dua'),
    MyLinkContact273(deviceId: 'e', userId: 'ue', name: 'Eman'),
    MyLinkContact273(deviceId: 'f', userId: 'uf', name: 'My Android Phone (1a2b)'),
    MyLinkContact273(deviceId: 'a2', userId: 'ua', name: 'Ali again'), // same person
  ];
  final ways = <String, PresenceWayInfo>{
    'a': const PresenceWayInfo(PresenceWay.wifi),
    'b': const PresenceWayInfo(PresenceWay.mesh, hops: 2, via: 'a'), // via a contact
    'c': const PresenceWayInfo(PresenceWay.mesh, hops: 4, via: 'zz'), // 3 phones between
    'd': const PresenceWayInfo(PresenceWay.online),
    'e': const PresenceWayInfo(PresenceWay.offline),
    'f': const PresenceWayInfo(PresenceWay.wifiDirect),
  };
  MyLinks273 build() =>
      MyLinks273.build(contacts: contacts, wayOf: (id) => ways[id] ?? const PresenceWayInfo(PresenceWay.offline));

  test('one node per contact; offline grey with no line; summary', () {
    final m = build();
    final ids = m.nodes.map((n) => n.id).toList();
    expect(ids.where((i) => i == 'a2'), isEmpty);
    expect(m.nodes.firstWhere((n) => n.id == 'e').offline, isTrue);
    expect(m.nodes.firstWhere((n) => n.id == 'e').noLine, isTrue);
    expect(m.nodes.firstWhere((n) => n.id == 'd').tag, LinkTag.server);
    expect(m.nodes.firstWhere((n) => n.id == 'a').tag, LinkTag.localWifi);
    expect(m.nodes.firstWhere((n) => n.id == 'f').tag, LinkTag.wifiDirect);
    expect(m.nodes.firstWhere((n) => n.id == 'f').label, 'LinkUp user'); // 276
    expect(m.summary, '5 live · 1 offline');
  });

  test('mesh via a contact: You -> Ali -> Bina', () {
    final m = build();
    expect(m.edges, contains(const LinkEdge('a', 'b', LinkTag.mesh)));
    expect(m.relaysKnown, 1);
    // Ali already has his own Wi-Fi line: no second self line.
    expect(m.edges.where((e) => e.from == LinkEdge.self && e.to == 'a'), isEmpty);
  });

  test('mesh via a stranger: logo node, no name, "+N"', () {
    final m = build();
    final relay = m.nodes.firstWhere((n) => n.relay);
    expect(relay.id, '${MyLinks273.relayPrefix}zz');
    expect(relay.label, '');
    expect(relay.hiddenMore, 2);
    expect(m.edges, contains(LinkEdge(LinkEdge.self, relay.id, LinkTag.mesh)));
    expect(m.edges, contains(LinkEdge(relay.id, 'c', LinkTag.mesh)));
    expect(m.relaysLogo, 1);
  });

  test('setting: on by default, can be hidden', () async {
    final s = MyLinksSetting273.instance;
    final store = <String, String>{};
    await s.load(read: (k) async => store[k], write: (k, v) async => store[k] = v);
    expect(s.on, isTrue);
    await s.set(false);
    expect(store[MyLinksSetting273.key], '0');
    expect(s.on, isFalse);
    s.debugSet(true);
  });

  test('wiring: card on Chats, row in Settings, setting loaded', () {
    expect(File('lib/features/home/presentation/screens/home_screen.dart').readAsStringSync(),
        contains('MyLinksCard273('));
    expect(File('lib/features/home/presentation/screens/messenger_settings_screen.dart').readAsStringSync(),
        contains('const MyLinksRow273()'));
    expect(File('lib/app/app_dependencies.dart').readAsStringSync(), contains('MyLinksSetting273.instance'));
  });
}
