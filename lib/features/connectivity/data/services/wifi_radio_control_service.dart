import 'package:flutter/services.dart';

final class WifiRadioStatus {
  final bool supported;
  final bool enabled;
  final bool managedDevice;
  final bool canControl;

  const WifiRadioStatus({required this.supported, required this.enabled, required this.managedDevice, required this.canControl});

  factory WifiRadioStatus.fromMap(Map<dynamic, dynamic> raw) => WifiRadioStatus(
        supported: raw['supported'] == true,
        enabled: raw['enabled'] == true,
        managedDevice: raw['managed_device'] == true,
        canControl: raw['can_control'] == true,
      );
}

final class WifiRadioControlService {
  static const MethodChannel _channel = MethodChannel('locallink/wifi_radio');

  Future<WifiRadioStatus> status() async {
    final raw = await _channel.invokeMethod<dynamic>('status');
    return WifiRadioStatus.fromMap(Map<dynamic, dynamic>.from(raw as Map));
  }

  Future<WifiRadioStatus> enforce(String policy) async {
    final normalized = policy.trim().toLowerCase();
    if (normalized != 'forced_on' && normalized != 'forced_off') return status();
    final raw = await _channel.invokeMethod<dynamic>('enforce', <String, dynamic>{'enabled': normalized == 'forced_on'});
    return WifiRadioStatus.fromMap(Map<dynamic, dynamic>.from(raw as Map));
  }
}
