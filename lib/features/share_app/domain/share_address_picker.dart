// Bundle 210: which address goes in the download QR.

/// One IPv4 address of this phone.
class ShareAddress {
  final String iface;
  final String ip;

  /// The interface name looks like a hotspot / tethering one.
  final bool hotspot;

  const ShareAddress(
      {required this.iface, required this.ip, this.hotspot = false});

  static List<ShareAddress> listFrom(Object? raw) {
    if (raw is! List) return const <ShareAddress>[];
    final out = <ShareAddress>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final iface = item['iface']?.toString() ?? '';
      final ip = item['ip']?.toString() ?? '';
      if (ip.isEmpty) continue;
      out.add(ShareAddress(
          iface: iface, ip: ip, hotspot: item['hotspot'] == true));
    }
    return out;
  }
}

bool isPrivateV4(String ip) {
  final p = ip.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.any((e) => e == null || e < 0 || e > 255)) {
    return false;
  }
  return p[0] == 10 ||
      (p[0] == 192 && p[1] == 168) ||
      (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31);
}

/// Wi-Fi Direct group (`p2p*`, 192.168.49.x) and the normal Wi-Fi (`wlan0`)
/// are never the hotspot.
bool _hotspotCandidate(ShareAddress a) {
  final n = a.iface.toLowerCase();
  if (!isPrivateV4(a.ip)) return false;
  if (n.startsWith('p2p') || a.ip.startsWith('192.168.49.')) return false;
  if (n == 'wlan0' || n.startsWith('rmnet') || n.startsWith('lo')) {
    return false;
  }
  return true;
}

/// The hotspot address, or null when unsure (the screen then lets the user
/// pick from [list]).
///
/// 1. The address Android-side found (new since the start).
/// 2. A private address on a hotspot-looking interface.
/// 3. The only private address that is not Wi-Fi / Wi-Fi Direct.
String? pickShareIp({String? nativeIp, required List<ShareAddress> list}) {
  if (nativeIp != null &&
      isPrivateV4(nativeIp) &&
      !nativeIp.startsWith('192.168.49.')) {
    return nativeIp;
  }
  final candidates = list.where(_hotspotCandidate).toList();
  final hinted = candidates.where((a) => a.hotspot).toList();
  if (hinted.isNotEmpty) return hinted.first.ip;
  if (candidates.length == 1) return candidates.first.ip;
  return null;
}

/// Own phone hotspot is on: its address (the classic `192.168.43.1` first).
String? pickTetherIp(List<ShareAddress> list) {
  for (final a in list) {
    if (a.ip == '192.168.43.1') return a.ip;
  }
  final picked = pickShareIp(list: list);
  if (picked != null) return picked;
  // Some phones run their hotspot on wlan0 itself; a hotspot owns `x.x.x.1`.
  for (final a in list) {
    if (isPrivateV4(a.ip) &&
        a.ip.endsWith('.1') &&
        !a.iface.toLowerCase().startsWith('p2p') &&
        !a.ip.startsWith('192.168.49.')) {
      return a.ip;
    }
  }
  return null;
}

/// Addresses the user may pick by hand (rare).
List<ShareAddress> shareIpChoices(List<ShareAddress> list) =>
    list.where(_hotspotCandidate).toList();
