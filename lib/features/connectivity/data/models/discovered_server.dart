import 'dart:io';

/// A LocalLink server discovered through the LAN broadcast protocol.
class DiscoveredServer {
  final String host;
  final int port;
  final String name;
  final String protocol;

  /// Bundle 265 (R1): the reply named a host that is neither the sender nor
  /// a private IPv4 address, so the sender address is used instead.
  final bool hostIgnored;

  const DiscoveredServer({
    required this.host,
    required this.port,
    required this.name,
    required this.protocol,
    this.hostIgnored = false,
  });

  /// Bundle 265 (R1): 10/8, 172.16/12, 192.168/16 IPv4 literals only.
  static bool privateIpv4(String raw) {
    final parts = raw.trim().split('.');
    if (parts.length != 4) return false;
    final n = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255 || p.isEmpty) return false;
      n.add(v);
    }
    if (n[0] == 10) return true;
    if (n[0] == 172 && n[1] >= 16 && n[1] <= 31) return true;
    return n[0] == 192 && n[1] == 168;
  }

  String get address => '${protocol.toLowerCase()}://$host:$port';

  factory DiscoveredServer.fromJson(
    Map<String, dynamic> json,
    InternetAddress fallback,
  ) {
    final rawHost = json['host']?.toString().trim() ?? '';
    final rawProtocol = json['protocol']?.toString().trim().toLowerCase();
    final protocol = rawProtocol == 'https' ? 'https' : 'http';
    // Bundle 265 (R1): a reply may only point at itself or at a private
    // address; anything else (internet host, name) -> the sender.
    final hostOk = rawHost.isNotEmpty &&
        (rawHost == fallback.address || privateIpv4(rawHost));
    return DiscoveredServer(
      host: hostOk ? rawHost : fallback.address,
      hostIgnored: rawHost.isNotEmpty && !hostOk,
      port: int.tryParse(json['port']?.toString() ?? '') ?? 8080,
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : 'LinkUp Server',
      protocol: protocol,
    );
  }
}
