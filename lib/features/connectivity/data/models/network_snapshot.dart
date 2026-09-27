/// Snapshot of local IPv4 interfaces used to detect network changes.
class NetworkSnapshot {
  final List<String> interfaceNames;
  final List<String> ipv4Addresses;

  /// Only private, link-local, or loopback IPv4 addresses count as local.
  List<String> get localIpv4Addresses => ipv4Addresses.where(_isLocalIpv4).toList(growable: false);

  bool get connected => localIpv4Addresses.isNotEmpty;

  static bool _isLocalIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null || part < 0 || part > 255)) return false;
    final a = parts[0]!, b = parts[1]!;
    return a == 10 || a == 127 ||
        (a == 169 && b == 254) ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }

  const NetworkSnapshot({
    required this.interfaceNames,
    required this.ipv4Addresses,
  });

  const NetworkSnapshot.empty()
      : interfaceNames = const [],
        ipv4Addresses = const [];

  String get fingerprint =>
      [...interfaceNames, '|', ...ipv4Addresses].join('|');

  bool sameNetworkAs(NetworkSnapshot other) => fingerprint == other.fingerprint;
}
