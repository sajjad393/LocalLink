import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

/// Bundle 308: ONE rule for the lines of BOTH maps (Chats › My links and
/// Admin › Link paths), so they always show the same path:
/// * the way of the PERSON (PresenceHub: best of all their phones);
/// * Mesh goes through the REAL next phone ([PresenceWayInfo.via]): a phone
///   on the map is drawn as that phone, any other one as the LinkUp logo;
/// * no guessed chain, and no second line on a path that has its own line.
class OwnLinks308 {
  const OwnLinks308._();

  static const String relayPrefix = 'relay:';

  /// Lines for the mesh phone [id]. [friendOf] = the node id on this map of
  /// the phone [PresenceWayInfo.via] (null = not on the map: LinkUp logo).
  /// Returns 'self' (own line from You), 'known' (through a phone on the
  /// map), 'logo' (through a new logo) or 'logo_again' (an existing logo).
  static String meshLines({
    required String id,
    required PresenceWayInfo info,
    required String? Function(String via) friendOf,
    required List<LinkEdge> edges,
    required Map<String, LinkNode> relays,
    bool blocked = false,
  }) {
    final via = (info.via ?? '').trim();
    if (info.way != PresenceWay.mesh || via.isEmpty || via == id) {
      edges.add(LinkEdge(LinkEdge.self, id, LinkTag.mesh, blocked: blocked));
      return 'self';
    }
    final friend = friendOf(via);
    if (friend != null && friend != id) {
      edges.add(LinkEdge(friend, id, LinkTag.mesh, blocked: blocked));
      edges.add(LinkEdge(LinkEdge.self, friend, LinkTag.mesh));
      return 'known';
    }
    final between = info.phonesBetween ?? 1;
    final rid = '$relayPrefix$via';
    var kind = 'logo_again';
    if (!relays.containsKey(rid)) {
      kind = 'logo';
      relays[rid] = LinkNode(
          id: rid,
          label: '',
          tag: LinkTag.mesh,
          relay: true,
          noLine: true,
          hiddenMore: between >= 2 ? between - 1 : 0);
      edges.add(LinkEdge(LinkEdge.self, rid, LinkTag.mesh));
    }
    edges.add(LinkEdge(rid, id, LinkTag.mesh, blocked: blocked));
    return kind;
  }

  /// A phone with its own line from You needs no second one; no repeats.
  static List<LinkEdge> clean(List<LinkEdge> edges, Set<String> ownLine) {
    final seen = <String>{};
    return [
      for (final e in edges)
        if (!(e.from == LinkEdge.self && ownLine.contains(e.to)) && seen.add(e.key)) e,
    ];
  }

  /// Admin own view: the admin nodes (one per person) + the same lines as
  /// My links. Mesh nodes get no default line (the map would chain them by
  /// screen distance = a guess); their lines are the returned edges.
  static ({List<LinkNode> nodes, List<LinkEdge> edges}) admin({
    required List<LinkNode> nodes,
    required PresenceWayInfo Function(String deviceId) wayOf,
    String? Function(String deviceId)? userOf,
  }) {
    final byId = {for (final n in nodes) n.id: n};
    final byUser = <String, LinkNode>{
      for (final n in nodes)
        if (n.userId.isNotEmpty) n.userId: n,
    };
    String? friendOf(String via) {
      if (byId.containsKey(via)) return via;
      final u = userOf?.call(via) ?? '';
      return u.isEmpty ? null : byUser[u]?.id;
    }

    final out = <LinkNode>[];
    final edges = <LinkEdge>[];
    final relays = <String, LinkNode>{};
    final ownLine = <String>{};
    for (final n in nodes) {
      if (n.relay || n.offline) {
        out.add(n);
        continue;
      }
      final info = wayOf(n.id);
      if (n.tag == LinkTag.mesh || info.way == PresenceWay.mesh) {
        out.add(_meshNode(n));
        meshLines(
            id: n.id, info: info, friendOf: friendOf, edges: edges, relays: relays, blocked: n.blocked);
        continue;
      }
      if (!n.noLine && (n.tag == LinkTag.localWifi || n.tag == LinkTag.wifiDirect)) ownLine.add(n.id);
      out.add(n);
    }
    out.addAll(relays.values);
    return (nodes: out, edges: clean(edges, ownLine));
  }

  static LinkNode _meshNode(LinkNode n) => LinkNode(
      id: n.id,
      label: n.label,
      tag: LinkTag.mesh,
      blocked: n.blocked,
      userId: n.userId,
      admin: n.admin,
      adminRole: n.adminRole,
      relay: n.relay,
      hiddenMore: n.hiddenMore,
      offline: n.offline,
      noLine: true);
}

/// Bundle 308: the admin map asks about the PERSON (any of their phones),
/// like My links - not only this one phone id.
bool adminPersonNear308(String id, [PresenceHub? hub]) =>
    (hub ?? PresenceHub.instance).statusOf(id) == PresenceStatus.nearby;

LinkTag? adminPersonTag308(String id, [PresenceHub? hub]) {
  final h = hub ?? PresenceHub.instance;
  if (!adminPersonNear308(id, h)) return null;
  return switch (h.wayOf(id)) {
    PresenceWay.wifiDirect => LinkTag.wifiDirect,
    PresenceWay.wifi => LinkTag.localWifi,
    PresenceWay.mesh => LinkTag.mesh,
    _ => null,
  };
}

/// Bundle 308: "last seen" for the duplicate rules. A phone the hub says is
/// near NOW is live (this exact phone wins over the person's other phones),
/// so it is never hidden as a stale duplicate.
DateTime? adminSeenAt308({
  required String presenceLocalAt,
  required bool phoneNear,
  required bool personNear,
  required DateTime now,
}) {
  if (phoneNear) return now;
  if (personNear) return now.subtract(const Duration(seconds: 1));
  return DateTime.tryParse(presenceLocalAt);
}

/// Bundle 308 (TODO 309 G2): the card of each phone id = the same rule as
/// PresenceHub (`directoryProfileByDeviceId`): a server card before an
/// offline one (`offline_...`), then the NEWEST. (Before: the oldest card
/// won, so a phone that had another account before counted as that one.)
Map<String, Map<String, dynamic>> adminCardPerPhone309(List<Map<String, dynamic>> rows) {
  bool offline(Map<String, dynamic> r) => '${r['user_id'] ?? ''}'.startsWith('offline_');
  final out = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final device = '${r['device_id'] ?? ''}'.trim();
    if (device.isEmpty) continue;
    final old = out[device];
    if (old == null) {
      out[device] = r;
      continue;
    }
    final ro = offline(r), oo = offline(old);
    if (ro != oo) {
      if (!ro) out[device] = r;
      continue;
    }
    if ('${r['updated_at'] ?? ''}'.compareTo('${old['updated_at'] ?? ''}') > 0) out[device] = r;
  }
  return out;
}

/// Bundle 308 (TODO 309 G3): the account the duplicate rules use. A phone
/// that is near NOW is merged with another one only on PresenceHub's word
/// (its live owner), never on an old saved card; other rows: hub, then card.
String adminDupeUser309({required bool phoneNear, String? hubUser, String? cardUser}) {
  final hub = (hubUser ?? '').trim();
  if (phoneNear || hub.isNotEmpty) return hub;
  return (cardUser ?? '').trim();
}
