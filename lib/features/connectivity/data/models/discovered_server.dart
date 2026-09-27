import 'dart:io';

/// A LocalLink server discovered through the LAN broadcast protocol.
class DiscoveredServer {
  final String host;
  final int port;
  final String name;
  final String protocol;

  const DiscoveredServer({
    required this.host,
    required this.port,
    required this.name,
    required this.protocol,
  });

  String get address => '${protocol.toLowerCase()}://$host:$port';

  factory DiscoveredServer.fromJson(
    Map<String, dynamic> json,
    InternetAddress fallback,
  ) {
    final rawHost = json['host']?.toString().trim() ?? '';
    final rawProtocol = json['protocol']?.toString().trim().toLowerCase();
    final protocol = rawProtocol == 'https' ? 'https' : 'http';
    return DiscoveredServer(
      host: rawHost.isNotEmpty ? rawHost : fallback.address,
      port: int.tryParse(json['port']?.toString() ?? '') ?? 8080,
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : 'LocalLink Server',
      protocol: protocol,
    );
  }
}
