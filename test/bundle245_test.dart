import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/core/security/safety_number.dart';
import 'package:locallink/core/security/security_code_245.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/presentation/contact_sheets.dart';
import 'package:locallink/features/directory/presentation/security_code_screen.dart';

// Bundle 245 (audit S7): Security code + key-change warning.

String _k(int seed) => base64Url.encode(List<int>.generate(32, (i) => (i * 7 + seed) % 256)).replaceAll('=', '');

DirectoryProfile _card(String key, {String device = 'android-ali', int v = 1}) => DirectoryProfile(
      userId: 'u-ali',
      deviceId: device,
      displayName: 'Ali',
      signingPublicKey: key,
      identityPublicKey: 'id',
      signature: 'sig',
      profileVersion: v,
    );

class _World {
  final settings = <String, String>{};
  final trust = <String, IdentityTrustState>{};
  final saved = <Map<String, dynamic>>[];
  var contacts = <String>{'u-ali'};
  var verifyOk = true;
  var friendKey = _k(1);

  SecurityCode245 hub() {
    final h = SecurityCode245()
      ..myKey = (() async => _k(9))
      ..myUserId = (() => 'u-me')
      ..profileFor = ((id) async => _card(friendKey).toMap())
      ..saveProfile = ((m) async => saved.add(m))
      ..verifyProfile = ((p) async => verifyOk)
      ..isContact = ((u) async => contacts.contains(u))
      ..trustState = ((d) async => trust[d] ?? IdentityTrustState.unverified)
      ..markVerified = ((d) async => trust[d] = IdentityTrustState.verified)
      ..markChanged = ((d) async => trust[d] = IdentityTrustState.changed)
      ..clearTrust = ((d) async => trust.remove(d));
    return h;
  }
}

void main() {
  setUpAll(() => SecurityCode245.digitsRunner = (a) async => SecurityCode245.digitsNow(a));

  group('safety number', () {
    test('the same 12 x 5 digits on both phones', () {
      final a = SafetyNumber.of('u-me', _k(9), 'u-ali', _k(1));
      final b = SafetyNumber.of('u-ali', _k(1), 'u-me', _k(9));
      expect(a, b);
      expect(a.length, 60);
      expect(RegExp(r'^\d{60}$').hasMatch(a), isTrue);
      expect(SafetyNumber.groups(a).length, 12);
      expect(SafetyNumber.of('u-me', _k(9), 'u-ali', _k(2)), isNot(a), reason: 'a new key = a new code');
    });
  });

  group('key change', () {
    test('a contact\'s new key is kept aside; a verified friend becomes changed', () async {
      final w = _World();
      final h = w.hub();
      await h.load(read: (k) async => w.settings[k], write: (k, v) async => w.settings[k] = v);
      w.trust['android-ali'] = IdentityTrustState.verified;
      await h.noteCardChange(_card(_k(1)), _card(_k(2)));
      expect(h.pendingFor('android-ali'), isNotNull);
      expect(w.trust['android-ali'], IdentityTrustState.changed);
      await h.noteCardChange(_card(_k(1)), _card(_k(2)));
      expect(h.pendingCount, 1, reason: 'the same change again is one entry');

      // Survives a restart.
      final again = w.hub();
      await again.load(read: (k) async => w.settings[k], write: (k, v) async => w.settings[k] = v);
      expect(again.pendingFor('android-ali')?.profile.signingPublicKey, _k(2));
    });

    test('unverified friend: no changed mark (calls as before); stranger: ignored', () async {
      final w = _World();
      final h = w.hub();
      await h.load(read: (k) async => w.settings[k], write: (k, v) async => w.settings[k] = v);
      await h.noteCardChange(_card(_k(1)), _card(_k(2)));
      expect(w.trust['android-ali'], isNull);
      expect(h.pendingCount, 1);
      w.contacts = {};
      final h2 = w.hub();
      await h2.noteCardChange(_card(_k(1)), _card(_k(3)));
      expect(h2.pendingCount, 0);
    });

    test('Accept new code saves the checked card and resets trust', () async {
      final w = _World();
      final h = w.hub();
      await h.load(read: (k) async => w.settings[k], write: (k, v) async => w.settings[k] = v);
      w.trust['android-ali'] = IdentityTrustState.verified;
      await h.noteCardChange(_card(_k(1)), _card(_k(2)));
      w.verifyOk = false;
      expect(await h.accept('u-ali'), isFalse, reason: 'a bad signature is never saved');
      expect(w.saved, isEmpty);
      w.verifyOk = true;
      expect(await h.accept('u-ali'), isTrue);
      expect(w.saved.single['signing_public_key'], _k(2));
      expect(w.trust['android-ali'], isNull);
      expect(h.pendingCount, 0);
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester, SecurityCode245 h, {Future<String?> Function(BuildContext)? scanner}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: SecurityCodeScreen(deviceId: 'android-ali', name: 'Ali', hub: h, scanner: scanner)));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('shows the code; Mark as verified', (tester) async {
      final w = _World();
      final h = w.hub();
      await pump(tester, h);
      final digits = SafetyNumber.of('u-me', _k(9), 'u-ali', _k(1));
      expect(find.text(SafetyNumber.groups(digits).first), findsOneWidget);
      expect(find.byKey(const Key('security_code_state_unverified')), findsOneWidget);
      await tester.tap(find.byKey(const Key('security_code_verify')));
      await tester.pump();
      await tester.pump();
      expect(w.trust['android-ali'], IdentityTrustState.verified);
      expect(find.byKey(const Key('security_code_state_verified')), findsOneWidget);
    });

    testWidgets('scan: a match verifies, another code does not', (tester) async {
      final w = _World();
      final h = w.hub();
      final digits = SafetyNumber.of('u-me', _k(9), 'u-ali', _k(1));
      var next = '${SecurityCodeScreen.qrPrefix}${'1' * 60}';
      await pump(tester, h, scanner: (_) async => next);
      await tester.tap(find.byKey(const Key('security_code_scan')));
      await tester.pump();
      expect(find.textContaining("The codes don't match"), findsOneWidget);
      expect(w.trust['android-ali'], isNull);
      next = '${SecurityCodeScreen.qrPrefix}$digits';
      await tester.tap(find.byKey(const Key('security_code_scan')));
      await tester.pump();
      await tester.pump();
      expect(w.trust['android-ali'], IdentityTrustState.verified);
    });

    testWidgets('a waiting change shows Accept new code', (tester) async {
      final w = _World();
      final h = w.hub();
      await h.load(read: (k) async => w.settings[k], write: (k, v) async => w.settings[k] = v);
      await h.noteCardChange(_card(_k(1)), _card(_k(2)));
      await pump(tester, h);
      expect(find.text("Ali's security code changed"), findsOneWidget);
      await tester.tap(find.byKey(const Key('security_code_accept')));
      await tester.pump();
      await tester.pump();
      expect(w.saved, hasLength(1));
      expect(find.byKey(const Key('security_code_changed_card')), findsNothing);
    });

    testWidgets('Conversation info shows Security code only when asked', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => showChatInfoSheet(c,
                name: 'Ali', subtitle: 'x', blocked: false, showCall: true, showSecurity: true, securityChanged: true),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat_info_security')), findsOneWidget);
      expect(find.text('Security code changed'), findsOneWidget);
    });
  });

  test('source: a new key is no longer dropped with no word', () {
    final s = File('lib/features/directory/data/repositories/directory_repository.dart').readAsStringSync();
    final i = s.indexOf('old.signingPublicKey != profile.signingPublicKey');
    expect(s.substring(i, i + 300), contains('SecurityCode245.instance.noteCardChange(old, profile);'));
    final chat = File('lib/features/messaging/presentation/screens/chat_screen.dart').readAsStringSync();
    // Bundle 263 (C): no bar on top; the notes are in the messages.
    expect(chat, isNot(contains('_keyChangeBanner245(context, device), // Bundle 245')));
    expect(chat, contains('_autoKeyLine258(context, device,'));
    final store = File('lib/core/services/local_store.dart').readAsStringSync();
    expect(store, contains('SecurityCode245.instance.load(read: readSetting, write: writeSetting)'));
  });
}
