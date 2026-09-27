import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';

void main() {
  test('pairing info parses and identifies a server', () {
    const fp = 'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789';
    final info = PairingInfo.fromJson({
      'service': 'locallink',
      'version': '1',
      'server_id': 'server-1',
      'fingerprint': fp,
      'name': 'Office LocalLink',
      'pairing_required': true,
    });
    expect(info.serverId, 'server-1');
    expect(info.fingerprint, fp);
    expect(info.pairingRequired, isTrue);
  });
}
