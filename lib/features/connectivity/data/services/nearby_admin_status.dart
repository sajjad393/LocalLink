/// Bundle 159.3: read-only nearby network status for the admin view.
///
/// Shows how THIS phone sees the nearby network: its group (host, members,
/// bridge), its links, its routes (hops) and what it passes on for others.
/// Never message text, keys or call sound.
library;

class NearbyAdminRoute {
  final String destination;
  final String nextHop;
  final int hops;
  final String state;

  const NearbyAdminRoute({
    required this.destination,
    required this.nextHop,
    required this.hops,
    required this.state,
  });
}

class NearbyAdminSnapshot {
  final String role;
  final String? group;
  final int members;
  final bool bridge;
  final bool charging;
  final int nearbyTags;
  final int waiting;
  final int directLinks;
  final int relayLinks;
  final int relayVoiceCalls;
  final int forwardedPackets;
  final int forwardedVoiceFrames;
  final List<NearbyAdminRoute> routes;

  /// Bundle 160: this Wi-Fi blocks phones from seeing each other.
  final bool wifiBlocked;

  /// Bundle 160: links whose device id was proven (signed id).
  final int verifiedLinks;

  /// Bundle 161 (tests): `off` / `joining` / `linked`, and `group` /
  /// `hotspot`.
  final String localNet;
  final String? localNetKind;
  final bool hotspot;

  /// Bundle 161: phones linked to this phone over a linked group / hotspot.
  final int localNetPeers;

  /// Bundle 161 (3.3): this member keeps only its group + contacts.
  final bool compactMap;

  const NearbyAdminSnapshot({
    this.role = 'none',
    this.group,
    this.members = 0,
    this.bridge = false,
    this.charging = false,
    this.nearbyTags = 0,
    this.waiting = 0,
    this.directLinks = 0,
    this.relayLinks = 0,
    this.relayVoiceCalls = 0,
    this.forwardedPackets = 0,
    this.forwardedVoiceFrames = 0,
    this.routes = const <NearbyAdminRoute>[],
    this.wifiBlocked = false,
    this.verifiedLinks = 0,
    this.localNet = 'off',
    this.localNetKind,
    this.hotspot = false,
    this.localNetPeers = 0,
    this.compactMap = false,
  });

  /// Short id for display (first 8 characters).
  static String shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  /// [group] from WifiDirectFallbackService.nearbyStatus(), [topology]
  /// from the native transport. Missing parts read as empty.
  factory NearbyAdminSnapshot.from({
    Map<String, Object?>? group,
    Map<String, dynamic>? topology,
  }) {
    final g = group ?? const <String, Object?>{};
    final t = topology ?? const <String, dynamic>{};
    final routes = <NearbyAdminRoute>[];
    final raw = t['routes'];
    if (raw is List) {
      for (final r in raw) {
        if (r is! Map) continue;
        final dest = r['destination']?.toString() ?? '';
        if (dest.isEmpty) continue;
        routes.add(NearbyAdminRoute(
          destination: shortId(dest),
          nextHop: shortId(r['next_hop']?.toString() ?? ''),
          hops: _int(r['hop_count']),
          state: r['state']?.toString() ?? '',
        ));
      }
    }
    routes.sort((a, b) => a.hops != b.hops
        ? a.hops.compareTo(b.hops)
        : a.destination.compareTo(b.destination));
    final groupName = g['group']?.toString();
    return NearbyAdminSnapshot(
      role: g['role']?.toString() ?? 'none',
      group: (groupName == null || groupName.isEmpty) ? null : groupName,
      members: _int(g['members']),
      bridge: g['bridge'] == true,
      charging: g['charging'] == true,
      nearbyTags: _int(g['nearby_tags']),
      waiting: _int(g['waiting']),
      directLinks: _int(t['peer_count']),
      relayLinks: _int(t['relay_links']),
      relayVoiceCalls: _int(t['relay_voice_calls']),
      forwardedPackets: _int(t['forwarded_packets']),
      forwardedVoiceFrames: _int(t['forwarded_voice_frames']),
      routes: List.unmodifiable(routes),
      wifiBlocked: g['wifi_blocked'] == true,
      verifiedLinks: _int(t['verified_links']),
      localNet: g['local_net']?.toString() ?? 'off',
      localNetKind: g['local_net_kind']?.toString(),
      hotspot: g['hotspot'] == true,
      localNetPeers: _int(t['local_net_peers']),
      compactMap: t['compact_map'] == true,
    );
  }
}

/// Wired in app_dependencies (null in tests and before start).
abstract final class NearbyAdminStatus {
  static Future<NearbyAdminSnapshot> Function()? loader;
}
