import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/identity/display_label.dart';

void main() {
  group('displayNameFromProfile — the single peer-nickname rule', () {
    test('profile display_name wins over username', () {
      expect(
        displayNameFromProfile({'display_name': 'Sana Oz', 'username': 'sana'}),
        'Sana Oz',
      );
    });

    test('username is the fallback when display name is missing/blank', () {
      expect(
        displayNameFromProfile({'display_name': '  ', 'username': 'sana'}),
        'sana',
      );
      expect(
        displayNameFromProfile({'username': 'sana'}),
        'sana',
      );
    });

    test('null profile and empty rows produce null so callers show a generic label', () {
      expect(displayNameFromProfile(null), isNull);
      expect(displayNameFromProfile(const {}), isNull);
      expect(
        displayNameFromProfile({'display_name': '', 'username': ' '}),
        isNull,
      );
    });

    test('device labels are never emitted: the rule ignores device_name keys', () {
      // The regression being guarded against: "My Android Phone (ed16a834)"
      // (an auto-generated DEVICE name) appearing as a person's name on call
      // screens, headers and history. A row that carries ONLY the device
      // label must yield null, i.e. "Unknown user" down the line.
      expect(
        displayNameFromProfile({'device_name': 'My Android Phone (ed16a834)'}),
        isNull,
      );
    });
  });
}
