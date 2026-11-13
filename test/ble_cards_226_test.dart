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

  // Bundle 283 (owner chose a): the Bluetooth cards left the screen; the
  // Bluetooth OK is asked with the one Nearby "Allow" tap. The rules stay:
  // never a pop-up by itself, the app never turns Bluetooth on, "Don't ask
  // again" opens the app settings, and nothing without the native control.
  group('283 Bluetooth without a card', () {
    final src = File('lib/features/directory/presentation/nearby_people_section.dart')
        .readAsStringSync();
    test('no Bluetooth card or words on the screen', () {
      expect(src, isNot(contains('Widget _bleCard(')));
      expect(src, isNot(contains("'Faster connect with Bluetooth'")));
      expect(src, isNot(contains("'Bluetooth is off'")));
      expect(src, isNot(contains('NearbyChips256')));
    });
    test('asked only from the Allow tap (with Nearby), then rests 7 days', () {
      final start = src.substring(src.indexOf('Future<void> _startSearch('),
          src.indexOf('bool get _bleNeedsOk283'));
      expect(start, contains('if (askPermission) await _askBle283();'));
      final ask = src.substring(src.indexOf('Future<void> _askBle283()'),
          src.indexOf('Future<void> _bleRest283()'));
      expect(ask, contains('.askBlePermission()'));
      expect(ask, contains('.timeout(const Duration(seconds: 60))'));
      expect(ask, contains('await _bleRest283();'));
      expect(src, contains('BleRules.cardHideMs'));
    });
    test('never a pop-up by itself; the app never turns Bluetooth on', () {
      final init = src.substring(
          src.indexOf('void initState()'), src.indexOf('void _onWaiting('));
      expect(init, isNot(contains('askBlePermission')));
      expect(init, isNot(contains('_askBle283')));
      expect(src, isNot(contains('control.openBluetoothSettings()')));
      expect(src, contains('openBluetoothSettings(app: true)'),
          reason: '"Don\'t ask again" opens the app settings');
    });
    test('nothing without the native control (tests, other platforms)', () {
      expect(src, contains('if (NearbyBleActions.control == null) return false;'));
    });
  });
}
