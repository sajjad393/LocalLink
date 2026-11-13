import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
import 'package:locallink/features/recovery/presentation/screens/account_recovery_screen.dart';

/// Bundle 287: Forgot password new look - only the look changed.
void main() {
  test('errors go under the right field', () {
    ForgotField287 f(String e) => ForgotPasswordScreen222.fieldFor(e);
    expect(f('Enter your username.'), ForgotField287.username);
    expect(f('No account with this username.'), ForgotField287.username);
    expect(f('Enter your recovery code (like K7QM2-XPA9T-RC4WN-E8D3F).'), ForgotField287.code);
    expect(f('Username or recovery code is wrong.'), ForgotField287.code);
    expect(f('Password must be at least 8 characters.'), ForgotField287.password);
    expect(f('The two passwords are not the same.'), ForgotField287.again);
    expect(f('Enter the 12-digit code from the admin.'), ForgotField287.oneTime);
    expect(f('The admin has not approved it yet.'), ForgotField287.oneTime);
    expect(f('The code is wrong or too old. Ask the admin for a new code.'), ForgotField287.oneTime);
    expect(f('Could not reach the server. Try again.'), ForgotField287.none);
    expect(f('Too many tries. Try again in 1 minute.'), ForgotField287.none);
    expect(f('This needs the server. Try again when the server is back.'), ForgotField287.none);
  });

  test('code field adds the dashes itself', () {
    expect(RecoveryCodeFormatter290.format('k7qm2xpa9trc4wne8d3f'), 'K7QM2-XPA9T-RC4WN-E8D3F');
    expect(recoveryCodeLooksRight290('K7QM2-XPA9T-RC4WN-E8D3F'), isTrue);
    expect(recoveryCodeLooksRight290('K7QM2-XPA9T'), isFalse);
  });

  test('source: same bloc calls, new parts, no counter, no flat button', () {
    final s = File('lib/features/recovery/presentation/screens/account_recovery_screen.dart').readAsStringSync();
    final i = s.indexOf('class ForgotPasswordScreen222');
    final screen = s.substring(i);
    for (final call in ['_bloc.resetWithCode(', '_bloc.completeNoCode(', '_bloc.askAdmin(', '_bloc.cancelRequest', '_bloc.selectTab(']) {
      expect(screen, contains(call));
    }
    for (final part in ['HeroRow290(', 'LivePill290(', 'SegmentSwitch290(', 'LinkField290(', 'LinkStrength290(',
        'StepList290(', 'BrandButton290(', 'RecoveryCodeFormatter290()', "text: 'Match'"]) {
      expect(screen, contains(part));
    }
    expect(screen, isNot(contains('FilledButton(')));
    expect(screen, contains('dimmed: !filled'), reason: 'faded until filled, still says what is missing');
    expect(screen, isNot(contains('LocalLinkTextField(')));
    expect(screen, isNot(contains('RecoveryCodeNotes235')));
  });
}
