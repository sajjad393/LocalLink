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

/// Wi-Fi Direct group (`p2p*`, 192.168.49.x) is never the hotspot.
///
/// Bundle 223 (E): `wlan0` was always skipped (taken as the home Wi-Fi), but
/// single-radio phones (ZTE Blade A35) run LinkUp's Wi-Fi on wlan0 itself,
/// so the list was empty. wlan0 counts when the phone is NOT on a router
/// ([noRouter]) and it holds `x.x.x.1` (a hotspot owns .1). The "new
/// address" case is decided on the Android side (it knows the address from
/// before the start) and arrives as `nativeIp`.
bool _hotspotCandidate(ShareAddress a, {bool noRouter = false}) {
  final n = a.iface.toLowerCase();
  if (!_notDirect(a)) return false;
  if (n == 'wlan0') return noRouter && a.ip.endsWith('.1');
  if (n.startsWith('rmnet') || n.startsWith('lo')) return false;
  return true;
}

bool _notDirect(ShareAddress a) =>
    isPrivateV4(a.ip) &&
    !a.iface.toLowerCase().startsWith('p2p') &&
    !a.ip.startsWith('192.168.49.');

/// The hotspot address, or null when unsure (the screen then lets the user
/// pick from [list]).
///
/// 1. The address Android-side found (new since the start).
/// 2. A private address on a hotspot-looking interface.
/// 3. The only private address that is not Wi-Fi / Wi-Fi Direct.
/// 4. (223) No router and wlan0 holds x.x.x.1: that one.
String? pickShareIp(
    {String? nativeIp,
    required List<ShareAddress> list,
    bool noRouter = false}) {
  if (nativeIp != null &&
      isPrivateV4(nativeIp) &&
      !nativeIp.startsWith('192.168.49.')) {
    return nativeIp;
  }
  final candidates =
      list.where((a) => _hotspotCandidate(a, noRouter: noRouter)).toList();
  final hinted = candidates.where((a) => a.hotspot).toList();
  if (hinted.isNotEmpty) return hinted.first.ip;
  if (candidates.length == 1) return candidates.first.ip;
  for (final a in candidates) {
    if (a.iface.toLowerCase() == 'wlan0') return a.ip;
  }
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
List<ShareAddress> shareIpChoices(List<ShareAddress> list,
        {bool noRouter = false}) =>
    list.where((a) => _hotspotCandidate(a, noRouter: noRouter)).toList();

/// Bundle 223 (E): after 10 s with nothing found - EVERY private address
/// (also wlan0) with its interface name, so there is always something to
/// tap. Only Wi-Fi Direct (never reachable from the hotspot) is left out.
List<ShareAddress> shareIpAll(List<ShareAddress> list) {
  final seen = <String>{};
  return [
    for (final a in list)
      if (_notDirect(a) && seen.add(a.ip)) a
  ];
}

/// Bundle 223 (E): `iface=ip,iface=ip` for the `SHARE_APP ip_none` line.
String shareIpListForLog(List<ShareAddress> list) => list.isEmpty
    ? 'none'
    : list.map((a) => '${a.iface}=${a.ip}').join(',');
