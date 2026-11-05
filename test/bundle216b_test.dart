// Bundle 216b: Settings card tap zones — an admin's card opens the switch
// sheet, only the round arrow opens Account; others open Account anywhere.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final s = File('lib/features/home/presentation/screens/messenger_settings_screen.dart')
      .readAsStringSync();

  test('card → _photoTap (sheet for admins, Account for others)', () {
    final card = s.indexOf("ValueKey('settings_profile_card')");
    expect(card, greaterThan(0));
    expect(s.indexOf('onTap: () => _photoTap(context),', card), greaterThan(card));
    final tap = s.indexOf('Future<void> _photoTap(BuildContext ctx) async {');
    final body = s.substring(tap, s.indexOf('Future<void> _openAccount', tap));
    expect(body, contains('if (session == null) {'));
    expect(body, contains('await _openAccount(ctx);'));
    expect(body, contains('showAccountSwitchSheet('));
  });

  test('round arrow → Account for everyone', () {
    final a = s.indexOf("ValueKey('settings_account_arrow')");
    expect(a, greaterThan(0));
    expect(s.indexOf('onTap: () => _openAccount(context),', a), greaterThan(a));
    expect(s, contains('shape: const CircleBorder(),'));
    expect(s, contains('Icons.chevron_right_rounded'));
    expect('_openAccount(context)'.allMatches(s).length, 1);
  });

  test('admin tag uses the painted crown tag', () {
    expect(s, contains('AdminRoleTag216(level: card.roleLabel, small: true)'));
    expect(s, isNot(contains('\\u{1F451}')));
  });
}
