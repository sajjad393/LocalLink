import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/security/security_policy.dart';

void main() {
  test('normalizes a valid HTTPS server address', () {
    expect(
      SecurityPolicy.normalizeServerAddress('https://192.168.1.20:8443/'),
      'https://192.168.1.20:8443',
    );
  });

  test('rejects credentials, paths, queries, and fragments', () {
    expect(
      () => SecurityPolicy.normalizeServerAddress('https://user:pass@192.168.1.20:8443'),
      throwsFormatException,
    );
    expect(
      () => SecurityPolicy.normalizeServerAddress('https://192.168.1.20:8443/api'),
      throwsFormatException,
    );
    expect(
      () => SecurityPolicy.normalizeServerAddress('https://192.168.1.20:8443?secret=x'),
      throwsFormatException,
    );
    expect(
      () => SecurityPolicy.normalizeServerAddress('https://192.168.1.20:8443#secret'),
      throwsFormatException,
    );
  });

  test('normalizes a development HTTP address on the LAN', () {
    expect(
      SecurityPolicy.normalizeServerAddress('192.168.1.20:8080'),
      'http://192.168.1.20:8080',
    );
  });

  test('rejects public Internet server addresses', () {
    expect(
      () => SecurityPolicy.normalizeServerAddress('https://8.8.8.8:443'),
      throwsFormatException,
    );
    expect(
      () => SecurityPolicy.normalizeServerAddress('https://example.com:443'),
      throwsFormatException,
    );
  });

  test('accepts loopback and local hostnames', () {
    expect(SecurityPolicy.normalizeServerAddress('https://127.0.0.1:8443'), 'https://127.0.0.1:8443');
    expect(SecurityPolicy.normalizeServerAddress('https://server.local:8443'), 'https://server.local:8443');
  });

  test('keeps attachment resources on the configured LocalLink server', () {
    expect(
      SecurityPolicy.resolveLocalResource('/api/v1/files/1', baseAddress: 'https://192.168.1.20:8443').toString(),
      'https://192.168.1.20:8443/api/v1/files/1',
    );
    expect(
      () => SecurityPolicy.resolveLocalResource('https://192.168.1.21:8443/api/v1/files/1', baseAddress: 'https://192.168.1.20:8443'),
      throwsFormatException,
    );
    expect(
      () => SecurityPolicy.resolveLocalResource('https://example.com/file', baseAddress: 'https://192.168.1.20:8443'),
      throwsFormatException,
    );
  });
}
