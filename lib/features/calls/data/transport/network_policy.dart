import 'package:locallink/l10n/l10n.dart';
enum AdminWifiRadioPolicy {
  allowed,
  forcedOn,
  forcedOff,
}

extension AdminWifiRadioPolicyX on AdminWifiRadioPolicy {
  String get storageValue => switch (this) {
        AdminWifiRadioPolicy.allowed => 'allowed',
        AdminWifiRadioPolicy.forcedOn => 'forced_on',
        AdminWifiRadioPolicy.forcedOff => 'forced_off',
      };
  String get label => switch (this) {
        AdminWifiRadioPolicy.allowed => L.t.allowed,
        AdminWifiRadioPolicy.forcedOn => L.t.forcedOn,
        AdminWifiRadioPolicy.forcedOff => L.t.forcedOff,
      };
  static AdminWifiRadioPolicy? fromStorage(Object? raw) => switch (raw?.toString().trim().toLowerCase()) {
    'allowed' => AdminWifiRadioPolicy.allowed,
    'forced_on' => AdminWifiRadioPolicy.forcedOn,
    'forced_off' => AdminWifiRadioPolicy.forcedOff,
    _ => null,
  };
}

class EffectiveNetworkPolicy {
  final AdminWifiRadioPolicy? wifiRadioPolicy;
  final AdminWifiRadioPolicy? wifiRadioAdminPolicy;
  final String wifiRadioSource;

  const EffectiveNetworkPolicy({
    required this.wifiRadioPolicy,
    required this.wifiRadioAdminPolicy,
    required this.wifiRadioSource,
  });

  static EffectiveNetworkPolicy evaluate({
    AdminWifiRadioPolicy? wifiRadioPolicy,
  }) {
    final source = wifiRadioPolicy == null ? L.t.localPlatformState : L.t.adminPolicy;
    return EffectiveNetworkPolicy(
      wifiRadioPolicy: wifiRadioPolicy,
      wifiRadioAdminPolicy: wifiRadioPolicy,
      wifiRadioSource: source,
    );
  }
}
