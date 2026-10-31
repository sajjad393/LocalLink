// Bundle 170: Profile fixes + Nearby moved inside Add Contact.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart';
import 'package:locallink/features/directory/presentation/nearby_search_animation.dart';
import 'package:locallink/features/directory/presentation/profile_view_rules.dart';

class _Dir extends Fake implements DirectoryRepositoryContract {
  _Dir(this.contactIds);
  final Set<String> contactIds;

  @override
  Future<List<DirectoryProfile>> contacts() async => [
        for (final id in contactIds) DirectoryProfile(userId: id),
      ];

  @override
  Future<bool> contactPrivate(String userId) async => false;
}

const _sajjad = DirectoryProfile(
  userId: 'u-sajjad',
  username: 'sajjad',
  displayName: 'sajjad',
  phoneNumber: '+923143283282',
);

Future<void> _pumpProfile(WidgetTester tester,
    {required Set<String> contacts, String selfUserId = ''}) async {
  await tester.pumpWidget(MaterialApp(
    home: DirectoryProfileView(
      profile: _sajjad,
      repository: _Dir(contacts),
      onStartChat: (_) async {},
      selfUserId: selfUserId,
    ),
  ));
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('profile rules', () {
    test('relation', () {
      expect(
          profileRelation(
              profileUserId: 'a', selfUserId: 'a', isContact: false),
          ProfileRelation.self);
      expect(
          profileRelation(profileUserId: 'a', selfUserId: 'b', isContact: true),
          ProfileRelation.contact);
      expect(
          profileRelation(
              profileUserId: 'a', selfUserId: 'b', isContact: false),
          ProfileRelation.stranger);
      // Unknown own id never claims "This is you".
      expect(
          profileRelation(profileUserId: '', selfUserId: '', isContact: false),
          ProfileRelation.stranger);
    });

    test('masked phone number', () {
      expect(maskPhone('+923143283282'), '+92 314 ••• 3282');
      expect(maskPhone('+92 314 3283282'), '+92 314 ••• 3282');
      expect(maskPhone('03143283282'), '0314 ••• 3282');
      expect(maskPhone('12345'), '••• 45');
      expect(maskPhone(''), '');
      expect(maskPhone('+923143283282'), isNot(contains('328328')));
    });

    test('nearby name filter uses real names only', () {
      expect(nearbyNameMatches('Ali Raza', 'al'), isTrue);
      expect(nearbyNameMatches('Ali Raza', 'RAZ'), isTrue);
      expect(nearbyNameMatches('Ali Raza', 'zain'), isFalse);
      expect(nearbyNameMatches(null, 'al'), isFalse);
      expect(nearbyNameMatches(null, ''), isTrue);
    });

    test('initials', () {
      expect(initialOf('ali'), 'A');
      expect(initialOf(nearbyUnknownName), 'N');
      expect(initialOf(''), '?');
      expect(initialOf(null), '?');
    });
  });

  group('profile screen', () {
    testWidgets('your own profile: This is you, no buttons', (tester) async {
      await _pumpProfile(tester, contacts: {}, selfUserId: 'u-sajjad');
      expect(find.text('This is you'), findsOneWidget);
      expect(find.text('Add Contact'), findsNothing);
      expect(find.text('Message'), findsNothing);
      expect(find.text('Block user'), findsNothing);
      expect(find.text('+923143283282'), findsOneWidget);
    });

    testWidgets('a stranger: masked number, gap, red Block', (tester) async {
      await _pumpProfile(tester, contacts: {}, selfUserId: 'u-me');
      expect(find.text('+92 314 ••• 3282'), findsOneWidget);
      expect(find.text('+923143283282'), findsNothing);
      expect(find.text('Add Contact'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('This is you'), findsNothing);
      expect(find.text('In your contacts'), findsNothing);
      final add = tester.getRect(find.widgetWithText(FilledButton, 'Add Contact'));
      final msg =
          tester.getRect(find.widgetWithText(OutlinedButton, 'Message'));
      expect(msg.top - add.bottom, greaterThanOrEqualTo(12));
      final block = tester.widget<Text>(find.text('Block user'));
      final ctx = tester.element(find.text('Block user'));
      final style = DefaultTextStyle.of(ctx).style.merge(block.style);
      expect(style.color, Theme.of(ctx).colorScheme.error);
    });

    testWidgets('a contact: full number, Message, no Add', (tester) async {
      await _pumpProfile(tester, contacts: {'u-sajjad'}, selfUserId: 'u-me');
      expect(find.text('In your contacts'), findsOneWidget);
      expect(find.text('+923143283282'), findsOneWidget);
      expect(find.text('Add Contact'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Message'), findsOneWidget);
      expect(find.text('Block user'), findsOneWidget);
    });
  });

  group('add contact', () {
    testWidgets('without the nearby engine it still searches', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AddContactScreen(
          repository: _Dir({}),
          crypto: IdentityCryptoService(),
        ),
      ));
      expect(find.text('Add Contact'), findsOneWidget);
      expect(find.text('Scan QR code'), findsOneWidget);
      expect(find.text('Type at least 2 characters to search.'),
          findsOneWidget);
    });

    test('the separate Nearby screen and button are gone', () {
      final contacts = File(
              'lib/features/directory/presentation/contacts_screen.dart')
          .readAsStringSync();
      expect(contacts.contains('NearbyDevicesScreen'), isFalse);
      expect(contacts.contains('Icons.wifi_find'), isFalse);
      expect(contacts.contains('connectivity: widget.connectivity'), isTrue);
      final nearby = File(
              'lib/features/directory/presentation/nearby_devices_screen.dart')
          .readAsStringSync();
      expect(nearby.contains('class NearbyDevicesScreen'), isFalse);
      expect(nearby.contains('Same Wi-Fi'), isFalse);
      expect(nearby.contains('LocalLink phone nearby'), isFalse);
      expect(nearby.contains('Icons.wifi_find'), isFalse);
    });
  });

  group('search animation', () {
    test('links glow one after another', () {
      final g0 = NearbySearchPainter.glowAt(0, 0.3);
      final g3 = NearbySearchPainter.glowAt(3, 0.3);
      expect(g0, greaterThan(0));
      expect(g3, 0);
    });

    test('dots stay inside the box', () {
      const size = Size(300, 170);
      for (var t = 0.0; t < 30; t += 1.7) {
        for (final n in NearbySearchPainter.nodesAt(t, size)) {
          expect(n.dx, inInclusiveRange(0, size.width));
          expect(n.dy, inInclusiveRange(0, size.height));
        }
      }
    });

    testWidgets('paints looking and found frames', (tester) async {
      for (final f in [0.0, 0.3, 0.8, 1.0]) {
        await tester.pumpWidget(MaterialApp(
          home: SizedBox(
            width: 300,
            height: 170,
            child: NearbySearchAnimation(foundProgress: f, foundInitial: 'A'),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
