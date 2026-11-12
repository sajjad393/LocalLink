import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/identity/person_name_276.dart';
import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';

/// Bundle 276: a phone's default name is never a person's name.
void main() {
  test('person: display name -> username without @ -> LinkUp user', () {
    expect(personName276('Sajjad', 'sajjad'), 'Sajjad');
    expect(personName276('My Android Phone (d5d181c0)', 'noshad'), 'noshad');
    expect(personName276('My LinkUp phone', '@ibrahim'), 'ibrahim');
    expect(personName276('Phone', '@@ali'), 'ali');
    expect(personName276('', ''), 'LinkUp user');
    expect(personName276(null, 'My Android Phone (1)'), 'LinkUp user');
    expect(personName276('LinkUp user', null, 'zara'), 'zara');
  });

  test('phone label: custom name, or "<name>\'s phone"', () {
    expect(phoneTitle255('My Android Phone (1a2b)', 'noshad'), "noshad's phone");
    expect(phoneTitle255('Office tab', 'noshad'), 'Office tab');
  });

  test('admin person name skips defaults and @', () {
    expect(personName216({'display_name': 'My Android Phone (1a2b)', 'username': '@noshad'}), 'noshad');
    expect(personName216({'name': 'Phone'}, fallback: 'LinkUp user'), 'LinkUp user');
  });

  test('no default phone name used as a person anywhere in these screens', () {
    for (final f in [
      'lib/features/admin/presentation/screens/admin_sessions_screen.dart',
      'lib/features/admin/presentation/screens/admin_security_screen.dart',
      'lib/features/admin/presentation/screens/admin_recovery_screen.dart',
    ]) {
      expect(File(f).readAsStringSync(), contains('phoneTitle255('), reason: f);
    }
    expect(File('lib/features/admin/presentation/widgets/admin_people216.dart').readAsStringSync(),
        isNot(contains("m['device_name'] ??")));
  });
}
