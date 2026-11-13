import 'package:flutter/foundation.dart';
import 'package:locallink/core/identity/person_name_276.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

/// Bundle 272 (Option B): the app admin map = this phone's own view + the
/// server's map (`GET /api/v1/admin/link-map`) while the server is
/// connected and the data is fresh (<= 90 s). Server off / stale -> own view
/// only ("Server off - your links only").
class LinkMapNetwork272 {
  const LinkMapNetwork272({required this.nodes, required this.extraEdges, required this.src, required this.ageS});

  final List<LinkNode> nodes;
  final List<LinkEdge> extraEdges;

  /// 'server' (merged) or 'own'.
  final String src;
  final int ageS;

  static const Duration maxAge = Duration(seconds: 90);

  /// Server link word -> map tag (null = unknown / none).
  static LinkTag? tagOfWord(String? w) => switch ((w ?? '').trim()) {
        'server' => LinkTag.server,
        'wifi_direct' => LinkTag.wifiDirect,
        'mesh' => LinkTag.mesh,
        'lan' || 'router' || 'local_net' || 'local_wifi' || 'wifi' => LinkTag.localWifi,
        _ => null,
      };

  /// [own] = nodes this phone sees; [noFlag] = own nodes with no transport
  /// flag of their own (A-3: the server's "online" makes them Server);
  /// [selfIds] = this phone's ids; [hidden] = ids never added (blocked /
  /// duplicates of this phone).
  static LinkMapNetwork272 merge({
    required List<LinkNode> own,
    required Map<String, dynamic>? serverMap,
    required bool serverOnline,
    required DateTime? fetchedAt,
    Set<String> selfIds = const {},
    Set<String> noFlag = const {},
    Set<String> hidden = const {},
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final age = fetchedAt == null ? -1 : t.difference(fetchedAt).inSeconds;
    final raw = serverMap?['nodes'];
    if (!serverOnline || raw is! List || fetchedAt == null || t.difference(fetchedAt) > maxAge) {
      return LinkMapNetwork272(nodes: own, extraEdges: const [], src: 'own', ageS: age);
    }
    final srv = <String, Map>{};
    for (final n in raw) {
      if (n is! Map) continue;
      final id = '${n['device_id'] ?? ''}'.trim();
      if (id.isNotEmpty) srv[id] = n;
    }
    bool onlineOf(String id) => srv[id]?['online'] == true;

    final out = <LinkNode>[];
    final ids = <String>{};
    final users = <String>{};
    for (final n in own) {
      var node = n;
      if (noFlag.contains(n.id) && onlineOf(n.id) && n.tag != LinkTag.server) {
        node = LinkNode(
            id: n.id,
            label: n.label,
            tag: LinkTag.server,
            blocked: n.blocked,
            userId: n.userId,
            admin: n.admin,
            adminRole: n.adminRole,
            relay: n.relay,
            hiddenMore: n.hiddenMore,
            offline: n.offline,
            noLine: n.noLine);
      }
      out.add(node);
      ids.add(n.id);
      if (n.userId.isNotEmpty) users.add(n.userId);
    }
    for (final e in srv.entries) {
      final id = e.key;
      final m = e.value;
      if (m['online'] != true || ids.contains(id) || selfIds.contains(id) || hidden.contains(id)) continue;
      final user = '${m['user_id'] ?? ''}'.trim();
      if (user.isNotEmpty && (users.contains(user) || hidden.contains(user))) continue;
      out.add(LinkNode(
        id: id,
        label: personName276('${m['display_name'] ?? ''}', '${m['username'] ?? ''}'),
        tag: LinkTag.server,
        blocked: m['blocked'] == true,
        userId: user,
        admin: '${m['admin_role'] ?? ''}'.isNotEmpty,
        adminRole: '${m['admin_role'] ?? ''}',
      ));
      ids.add(id);
      if (user.isNotEmpty) users.add(user);
    }
    final edges = <LinkEdge>{};
    // Server -> phone for phones linked another way here but on the server too.
    for (final n in out) {
      if (n.tag != LinkTag.server && onlineOf(n.id)) {
        edges.add(LinkEdge(LinkEdge.server, n.id, LinkTag.server, blocked: n.blocked));
      }
    }
    // Phone <-> phone lines that do not involve this phone.
    final rawEdges = serverMap?['edges'];
    if (rawEdges is List) {
      for (final e in rawEdges) {
        if (e is! Map) continue;
        final from = '${e['from'] ?? ''}', to = '${e['to'] ?? ''}';
        if (from == 'server' || to == 'server' || from == to) continue;
        if (selfIds.contains(from) || selfIds.contains(to)) continue;
        if (!ids.contains(from) || !ids.contains(to)) continue;
        final tag = tagOfWord('${e['link'] ?? ''}');
        if (tag == null || tag == LinkTag.server) continue;
        edges.add(LinkEdge(from, to, tag));
      }
    }
    return LinkMapNetwork272(nodes: out, extraEdges: edges.toList(), src: 'server', ageS: age);
  }

  static String? _last;

  /// `MAP_NET_272 src= nodes= extra= age_s=` once per change.
  void log() {
    final line = 'src=$src nodes=${nodes.length} extra=${extraEdges.length}';
    if (line == _last) return;
    _last = line;
    AppLogger.info('MAP_NET_272', detail: '$line age_s=$ageS');
  }

  @visibleForTesting
  static void resetLogForTest() => _last = null;
}
