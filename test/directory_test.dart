import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/directory/data/phone_number_normalizer.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';

void main() {
  group('PhoneNumberNormalizer', () {
    test('normalizes supported Pakistan formats', () {
      expect(PhoneNumberNormalizer.normalize('03001234567'), '+923001234567');
      expect(PhoneNumberNormalizer.normalize('0300 1234567'), '+923001234567');
      expect(PhoneNumberNormalizer.normalize('+92 300 1234567'), '+923001234567');
      expect(PhoneNumberNormalizer.normalize('0092 300 1234567'), '+923001234567');
      expect(PhoneNumberNormalizer.normalize('+923001234567'), '+923001234567');
    });

    test('rejects malformed numbers', () {
      expect(PhoneNumberNormalizer.normalize('03001234'), '');
      expect(PhoneNumberNormalizer.normalize('not-a-phone'), '');
      expect(PhoneNumberNormalizer.normalize('923001234567x'), '');
    });
  });

  test('directory canonical payload excludes mutable transport metadata', () {
    const profile = DirectoryProfile(
      userId: 'user-a',
      deviceId: 'device-a',
      username: 'sajjad',
      displayName: 'Sajjad',
      phoneNumber: '',
      profileVersion: 4,
      updatedAt: '2026-09-21T00:00:00Z',
      signingPublicKey: 'pub',
      identityPublicKey: 'identity',
      signature: 'sig',
      source: 'mesh',
      syncedAt: 'later',
    );

    final canonical = profile.canonical();
    expect(canonical, contains('"user_id":"user-a"'));
    expect(canonical, contains('"profile_version":4'));
    expect(canonical, contains('"identity_public_key":"identity"'));
    expect(canonical, isNot(contains('"signature"')));
    expect(canonical, isNot(contains('"synced_at"')));
    expect(canonical, isNot(contains('"source"')));
  });
}
