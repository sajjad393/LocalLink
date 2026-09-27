import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/transport/network_policy.dart';

void main() {
  test('Wi-Fi radio policy only', () {
    expect(AdminWifiRadioPolicyX.fromStorage('forced_on'), AdminWifiRadioPolicy.forcedOn);
    expect(AdminWifiRadioPolicyX.fromStorage('forced_off'), AdminWifiRadioPolicy.forcedOff);
    expect(AdminWifiRadioPolicyX.fromStorage('unknown'), isNull);
  });
}
