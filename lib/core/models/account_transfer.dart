import 'dart:convert';

class AccountTransferPayload {
  final String serverId;
  final String fingerprint;
  final String transferId;
  final String secret;
  final DateTime expiresAt;
  final String username;
  const AccountTransferPayload({required this.serverId, required this.fingerprint, required this.transferId, required this.secret, required this.expiresAt, required this.username});

  static const prefix = 'locallink://account-transfer/';

  static AccountTransferPayload? parse(String value) {
    final raw = value.trim();
    if (!raw.startsWith(prefix)) return null;
    try {
      var encoded = raw.substring(prefix.length);
      while (encoded.length % 4 != 0) { encoded += '='; }
      final bytes = base64Url.decode(encoded);
      final map = jsonDecode(utf8.decode(bytes));
      if (map is! Map) return null;
      final expires = DateTime.tryParse(map['expires_at']?.toString() ?? '');
      final serverId = map['server_id']?.toString() ?? '';
      final fingerprint = map['fingerprint']?.toString() ?? '';
      final transferId = map['transfer_id']?.toString() ?? '';
      final secret = map['secret']?.toString() ?? '';
      if (map['v']?.toString() != '1' || serverId.isEmpty || fingerprint.length != 64 || transferId.isEmpty || secret.isEmpty || expires == null) return null;
      return AccountTransferPayload(serverId: serverId, fingerprint: fingerprint.toUpperCase(), transferId: transferId, secret: secret, expiresAt: expires, username: map['username']?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }
}
