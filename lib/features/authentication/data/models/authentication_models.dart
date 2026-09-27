import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';

class PairingInfo {
  final String service;
  final String version;
  final String serverId;
  final String fingerprint;
  final String name;
  final bool pairingRequired;

  const PairingInfo({
    required this.service,
    required this.version,
    required this.serverId,
    required this.fingerprint,
    required this.name,
    required this.pairingRequired,
  });

  factory PairingInfo.fromJson(Map<String, dynamic> json) => PairingInfo(
        service: json['service']?.toString() ?? 'locallink',
        version: json['version']?.toString() ?? '1',
        serverId: json['server_id']?.toString() ?? '',
        fingerprint: json['fingerprint']?.toString() ?? '',
        name: json['name']?.toString() ?? 'LocalLink Server',
        pairingRequired: json['pairing_required'] == true,
      );
}

class AuthResult {
  final LocalAccount account;
  final Device device;
  final String expiresAt;
  final String recoveryCode;

  const AuthResult({
    required this.account,
    required this.device,
    required this.expiresAt,
    this.recoveryCode = '',
  });
}
