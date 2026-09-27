import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/locallink_api.dart';

void main() {
  test('preserves HTTPS server addresses for WSS', () {
    expect(LocalLinkApi.normalizeServerAddress('https://192.168.1.20:8443'), 'https://192.168.1.20:8443');
  });

  test('adds HTTP scheme when omitted', () {
    expect(LocalLinkApi.normalizeServerAddress('192.168.1.20:8080'), 'http://192.168.1.20:8080');
  });

  test('rejects URLs with query, credentials, or path', () {
    expect(() => LocalLinkApi.normalizeServerAddress('https://user:pass@192.168.1.20:8443'), throwsFormatException);
    expect(() => LocalLinkApi.normalizeServerAddress('https://192.168.1.20:8443?token=x'), throwsFormatException);
    expect(() => LocalLinkApi.normalizeServerAddress('https://192.168.1.20:8443/api'), throwsFormatException);
  });
}
