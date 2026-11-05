import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bundle 215 (D): Account profile card ends with the arrow (was a pencil).
/// The card itself (tap → Edit profile, key, 104 high) is checked by the
/// bundle183 widget test, which stays unchanged.
void main() {
  test('Account card: chevron with the same key; no pencil', () {
    final s = File('lib/features/account/presentation/screens/account_center_screen.dart')
        .readAsStringSync();
    expect(
        s,
        contains('Icon(Icons.chevron_right,\n'
            "                                    key: const ValueKey('account_profile_edit'),"));
    expect(s, isNot(contains('Icons.edit_outlined')));
    expect(s, contains("key: const ValueKey('account_profile_card'),\n"
        '                          onTap: _openProfile,'));
    expect(s, contains("'Tap to edit name and photo'"));
  });

  test('group name pencil in Group info stays (not part of this change)', () {
    final s = File('lib/features/groups/presentation/screens/group_info_screen.dart')
        .readAsStringSync();
    expect(s, contains("key: const ValueKey('info_name_edit'),"));
    expect(s, contains('Icons.edit_outlined'));
  });
}
