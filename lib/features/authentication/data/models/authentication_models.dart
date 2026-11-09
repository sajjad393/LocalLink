import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';

class PairingInfo {
  final String service;
  final String version;
  final String serverId;
  final String fingerprint;
  final String name;
  final bool pairingRequired;

  /// Bundle 231 (audit S2): only from a 231 server asked with a nonce.
  final String serverKey;
  final String keyId;
  final String proofTs;
  final String proof;

  /// True only after [LocalLinkApi] verified [proof] with our nonce.
  final bool proofOk;

  /// Bundle 243 (S3): a v2 proof also covers the HTTPS port and the
  /// certificate hash. 0 / '' from a server without HTTPS.
  final int proofVersion;
  final int tlsPort;
  final String tlsCertSha256;

  const PairingInfo({
    required this.service,
    required this.version,
    required this.serverId,
    required this.fingerprint,
    required this.name,
    required this.pairingRequired,
    this.serverKey = '',
    this.keyId = '',
    this.proofTs = '',
    this.proof = '',
    this.proofOk = false,
    this.proofVersion = 0,
    this.tlsPort = 0,
    this.tlsCertSha256 = '',
  });

  bool get hasProof => proof.isNotEmpty;

  PairingInfo withProofOk(bool ok) => PairingInfo(
        service: service,
        version: version,
        serverId: serverId,
        fingerprint: fingerprint,
        name: name,
        pairingRequired: pairingRequired,
        serverKey: serverKey,
        keyId: keyId,
        proofTs: proofTs,
        proof: proof,
        proofOk: ok,
        proofVersion: proofVersion,
        tlsPort: tlsPort,
        tlsCertSha256: tlsCertSha256,
      );

  factory PairingInfo.fromJson(Map<String, dynamic> json) => PairingInfo(
        service: json['service']?.toString() ?? 'locallink',
        version: json['version']?.toString() ?? '1',
        serverId: json['server_id']?.toString() ?? '',
        fingerprint: json['fingerprint']?.toString() ?? '',
        name: json['name']?.toString() ?? 'LinkUp Server',
        pairingRequired: json['pairing_required'] == true,
        serverKey: json['server_key']?.toString() ?? '',
        keyId: json['key_id']?.toString() ?? '',
        proofTs: json['ts']?.toString() ?? '',
        proof: json['proof']?.toString() ?? '',
        proofVersion: int.tryParse(json['proof_v']?.toString() ?? '') ?? 0,
        tlsPort: int.tryParse(json['tls_port']?.toString() ?? '') ?? 0,
        tlsCertSha256: (json['tls_cert_sha256']?.toString() ?? '').toLowerCase(),
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
