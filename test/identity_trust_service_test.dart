import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/security/identity_trust_service.dart';

void main() {
  test('maps persisted trust states safely', () {
    expect(identityTrustStateFromString('verified'), IdentityTrustState.verified);
    expect(identityTrustStateFromString('changed'), IdentityTrustState.changed);
    expect(identityTrustStateFromString('revoked'), IdentityTrustState.revoked);
    expect(identityTrustStateFromString('unexpected'), IdentityTrustState.unverified);
  });

  test('labels trust states for explicit UI', () {
    expect(IdentityTrustState.unverified.label, 'Unverified');
    expect(IdentityTrustState.verified.label, 'Verified');
    expect(IdentityTrustState.changed.label, 'Identity changed');
    expect(IdentityTrustState.revoked.label, 'Revoked');
  });
}
