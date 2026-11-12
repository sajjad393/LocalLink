/// Bundle 274 (D-2 / D-3): the dashboard "Live network" ring counts each
/// phone ONCE by how it is linked now (server, else the way it is reached,
/// else offline), so the slices add up to the phones. The row under it
/// counts LINKS by kind. Same data and colours as the maps.
class LinkWays274 {
  const LinkWays274({
    required this.phones,
    required this.server,
    required this.lan,
    required this.wifiDirect,
    required this.mesh,
    required this.offline,
    required this.serverLinks,
    required this.lanLinks,
    required this.wifiDirectLinks,
    required this.meshLinks,
  });

  final int phones, server, lan, wifiDirect, mesh, offline;
  final int serverLinks, lanLinks, wifiDirectLinks, meshLinks;

  int get online => phones - offline;

  static LinkWays274? of(Map<String, dynamic>? linkMap) {
    final nodes = linkMap?['nodes'];
    if (nodes is! List) return null;
    var server = 0, lan = 0, wd = 0, mesh = 0, off = 0, phones = 0;
    for (final n in nodes) {
      if (n is! Map) continue;
      phones++;
      final link = '${n['link'] ?? ''}';
      if (n['online'] == true) {
        server++;
      } else if (link == 'lan' || link == 'router') {
        lan++;
      } else if (link == 'wifi_direct') {
        wd++;
      } else if (link == 'mesh') {
        mesh++;
      } else {
        off++;
      }
    }
    var sl = 0, ll = 0, wl = 0, ml = 0;
    final edges = linkMap?['edges'];
    if (edges is List) {
      for (final e in edges) {
        if (e is! Map) continue;
        switch ('${e['link'] ?? ''}') {
          case 'server':
            sl++;
          case 'lan' || 'router':
            ll++;
          case 'wifi_direct':
            wl++;
          case 'mesh':
            ml++;
        }
      }
    }
    return LinkWays274(
        phones: phones,
        server: server,
        lan: lan,
        wifiDirect: wd,
        mesh: mesh,
        offline: off,
        serverLinks: sl,
        lanLinks: ll,
        wifiDirectLinks: wl,
        meshLinks: ml);
  }
}
