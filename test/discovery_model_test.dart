import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/services/discovery_service.dart';

void main() {
  test('discovered server falls back to datagram source address', () {
    final server = DiscoveredServer.fromJson(
      {'name': 'LocalLink', 'port': 8080, 'protocol': 'http'},
      InternetAddress('192.168.1.22'),
    );
    expect(server.host, '192.168.1.22');
    expect(server.address, 'http://192.168.1.22:8080');
  });

  test('discovered HTTPS server keeps the advertised secure protocol', () {
    final server = DiscoveredServer.fromJson(
      {'name': 'LocalLink', 'port': 8443, 'protocol': 'https'},
      InternetAddress('192.168.1.22'),
    );
    expect(server.address, 'https://192.168.1.22:8443');
  });
}
