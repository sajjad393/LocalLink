// Bundle 226 (B5): the Bluetooth cards in Add Contact -> Nearby.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/services/nearby_ble.dart';

const _now = 1000000000;

BleCard _card(String state,
        {int sdk = 34,
        bool wifi = false,
        int allowHidden = 0,
        int offHidden = 0}) =>
    bleCardFor(
      state: state,
      sdk: sdk,
      wifiCardShown: wifi,
      now: _now,
      allowHiddenUntil: allowHidden,
      offHiddenUntil: offHidden,
    );

void main() {
  group('226-B5 which card', () {
    test('Android 12+ not allowed -> Allow card', () {
      expect(_card('no_permission', sdk: 31), BleCard.allow);
      expect(_card('no_permission', sdk: 35), BleCard.allow);
    });
    test('Bluetooth off -> Turn on card', () {
      expect(_card('off'), BleCard.off);
      expect(_card('off', sdk: 29), BleCard.off);
    });
    test('no card: all OK, scan only, unsupported, unknown, Android 9', () {
      for (final s in ['on', 'scan_only', 'unsupported', 'unknown']) {
        expect(_card(s), BleCard.none, reason: s);
      }
      expect(_card('off', sdk: 28), BleCard.none);
    });
    test('Android 10-11 "no permission" = the Wi-Fi permission (its own card)',
        () {
      expect(_card('no_permission', sdk: 29), BleCard.none);
      expect(_card('no_permission', sdk: 30), BleCard.none);
    });
    test('the Wi-Fi "Allow nearby" card wins (one card at a time)', () {
      expect(_card('no_permission', wifi: true), BleCard.none);
      expect(_card('off', wifi: true), BleCard.none);
    });
    test('× hides a card for 7 days', () {
      expect(BleRules.cardHideMs, 7 * 24 * 60 * 60 * 1000);
      expect(_card('no_permission', allowHidden: _now + 1), BleCard.none);
      expect(_card('no_permission', allowHidden: _now), BleCard.allow);
      expect(_card('off', offHidden: _now + 1), BleCard.none);
      // Hiding one card never hides the other.
      expect(_card('off', allowHidden: _now + 1), BleCard.off);
    });
  });

  group('226-B5 status', () {
    setUp(() => NearbyBleStatus.instance.resetForTest());
    test('updates and notifies once per change', () {
      var n = 0;
      void l() => n++;
      NearbyBleStatus.instance.addListener(l);
      addTearDown(() => NearbyBleStatus.instance.removeListener(l));
      NearbyBleStatus.instance.updateFrom({'state': 'off', 'sdk': 34});
      NearbyBleStatus.instance.updateFrom({'state': 'off', 'sdk': 34});
      expect(n, 1);
      expect(NearbyBleStatus.instance.state, 'off');
      NearbyBleStatus.instance.updateFrom({'state': 'on'});
      expect(n, 2);
      expect(NearbyBleStatus.instance.sdk, 34, reason: 'sdk kept');
    });
  });

  group('226-B5 the card in code (your words, same look as the Wi-Fi card)',
      () {
    final src = File('lib/features/directory/presentation/nearby_people_section.dart')
        .readAsStringSync();
    test('texts', () {
      expect(src, contains("'Faster connect with Bluetooth'"));
      expect(src, contains("'Find friends in seconds.'"));
      expect(src, contains("'Bluetooth is off'"));
      expect(src, contains("'Turn it on for faster connect'"));
      expect(src, contains("'Allow'"));
      expect(src, contains("'Turn on'"));
      // Your rule: the Bluetooth card never talks about Wi-Fi for calls.
      final card = src.substring(src.indexOf('Widget _bleCard('),
          src.indexOf('Future<void> _bleAllow()'));
      expect(card.toLowerCase(), isNot(contains('wi-fi')));
      expect(card.toLowerCase(), isNot(contains('call')));
    });
    test('built like the Wi-Fi card + × + 8 dp gap', () {
      final card = src.substring(src.indexOf('Widget _bleCard('),
          src.indexOf('Future<void> _bleAllow()'));
      expect(card, contains('scheme.tertiaryContainer.withValues(alpha: .6)'));
      expect(card, contains('ListTile('));
      expect(card, contains('FilledButton('));
      expect(card, contains('Icons.close_rounded'));
      expect(card, contains('EdgeInsets.only(bottom: 8)'));
    });
    test('right under the Wi-Fi card, above the looking box', () {
      final wifi = src.indexOf('if (_permission == false) _permissionCard(context),');
      final ble = src.indexOf('listenable: NearbyBleStatus.instance');
      final looking = src.indexOf('_lookingBox(context,\n');
      expect(wifi, greaterThan(0));
      expect(ble, greaterThan(wifi));
      expect(looking, greaterThan(ble));
    });
    test('never a pop-up by itself; the app never turns Bluetooth on', () {
      final init = src.substring(
          src.indexOf('void initState()'), src.indexOf('void _onWaiting('));
      expect(init, isNot(contains('askBlePermission')));
      expect(src, contains('control.openBluetoothSettings()'));
      expect(src, contains('openBluetoothSettings(app: true)'),
          reason: '"Don\'t ask again" opens the app settings');
    });
    test('no card in tests / without the native control', () {
      expect(src, contains(
          'if (NearbyBleActions.control == null) return const SizedBox.shrink();'));
    });
  });
}
