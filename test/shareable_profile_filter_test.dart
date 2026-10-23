import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/directory/data/shareable_profile_filter.dart';

void main() {
  group('isShareableRow (bundle 90 per-contact privacy)', () {
    test('public contact is shared onward (default)', () {
      expect(isShareableRow('u-b', const <String>{}), isTrue);
      expect(isShareableRow('u-b', const <String>{'u-c'}), isTrue);
    });

    test('private contact is excluded from rows this device re-shares', () {
      expect(isShareableRow('u-b', const <String>{'u-b'}), isFalse);
    });

    test('privacy is per-user: a private mark never silences OTHER contacts', () {
      const privates = <String>{'u-b'};
      expect(isShareableRow('u-c', privates), isTrue);
      expect(isShareableRow('u-d', privates), isTrue);
    });

    test('empty/self garbage is defensively excluded', () {
      expect(isShareableRow('', const <String>{}), isFalse);
    });
  });
}
