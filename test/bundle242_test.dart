import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart';

class _Dir extends Fake implements DirectoryRepositoryContract {
  @override
  Future<List<DirectoryProfile>> contacts() async => const [];
}

/// Bundle 242: letter circle on a notification with no picture; My QR at
/// the top right of Add Contact and on the Settings profile card.
void main() {
  String src(String p) => File(p).readAsStringSync();

  test('242-1 notification: letter circle only with no picture, colours = app', () {
    final kt = src('android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkNotificationManager.kt');
    expect(kt, contains('circlePicture(avatarPath)?.let { builder.setLargeIcon(it) }'));
    expect(kt, contains('letterCircle(initials, title)?.let { builder.setLargeIcon(it) }'));
    expect(kt, contains('0xFF1FD7D4.toInt(), 0xFF7C6BF0.toInt()'));
    final dart = src('lib/core/notifications/local_link_notification_service.dart');
    expect(dart, contains('initials: _initials242(identity.initials),'));
    expect(dart, contains("NotificationPrivacyMode.hidden ? '' : initials"));
  });

  testWidgets('242-2 Add Contact has My QR at the top right', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AddContactScreen(repository: _Dir(), crypto: IdentityCryptoService())));
    await tester.pump();
    final qr = find.byKey(const ValueKey('add_contact_my_qr_242'));
    expect(qr, findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: qr), findsOneWidget);
    // No pairing engine here: a short message instead of a crash.
    await tester.tap(qr);
    await tester.pump();
    expect(find.text('Your profile is not ready yet.'), findsOneWidget);
  });

  test('242-3 Settings card: My QR button before the Account arrow (source)', () {
    final s = src('lib/features/home/presentation/screens/messenger_settings_screen.dart');
    expect(s.indexOf("ValueKey('settings_my_qr_242')"), lessThan(s.indexOf("ValueKey('settings_account_arrow')")));
    expect(s, contains('MyQrScreen('));
    final p = src('lib/features/directory/data/services/pairing_service.dart');
    expect(p, contains('Future<DirectoryProfile?> ownQrProfile242()'));
  });
}
