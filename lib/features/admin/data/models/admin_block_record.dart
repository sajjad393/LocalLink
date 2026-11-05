import 'dart:convert';

/// Bundle 212: a signed text. [body] is a JSON string; [sig] is Ed25519 over
/// its UTF-8 bytes, base64url without padding. The same shape the server
/// uses (`internal/httpapi/trust.go`), so no canonical JSON is needed: the
/// body is signed and checked exactly as it travels.
class SignedBlob {
  final String body;
  final String sig;

  const SignedBlob({required this.body, required this.sig});

  Map<String, dynamic> toJson() => {'body': body, 'sig': sig};

  static SignedBlob? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final body = raw['body'];
    final sig = raw['sig'];
    if (body is! String || sig is! String || body.isEmpty || sig.isEmpty) {
      return null;
    }
    return SignedBlob(body: body, sig: sig);
  }

  /// The decoded body, or null when it is not a JSON object.
  Map<String, dynamic>? get fields {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SignedBlob && other.body == body && other.sig == sig;

  @override
  int get hashCode => Object.hash(body, sig);
}

/// The admin offline key (server-signed): which phone key may sign blocks.
class AdminCert {
  final String certId;
  final String adminId;
  final String username;
  final String role;
  final String deviceId;
  final String signingKey;
  final String sessionId;
  final String issuedAt;

  const AdminCert({
    required this.certId,
    required this.adminId,
    required this.username,
    required this.role,
    required this.deviceId,
    required this.signingKey,
    required this.sessionId,
    required this.issuedAt,
  });

  static AdminCert? fromBlob(SignedBlob blob) {
    final f = blob.fields;
    if (f == null || f['kind'] != 'admin_cert') return null;
    String s(String k) => f[k]?.toString() ?? '';
    final cert = AdminCert(
      certId: s('cert_id'),
      adminId: s('admin_id'),
      username: s('username'),
      role: s('role'),
      deviceId: s('device_id'),
      signingKey: s('signing_key'),
      sessionId: s('session_id'),
      issuedAt: s('issued_at'),
    );
    if (cert.certId.isEmpty || cert.signingKey.isEmpty) return null;
    return cert;
  }
}

/// One block / unblock of one user (newest wins per user).
class AdminBlockRecord {
  final String id;
  final String targetUserId;
  final List<String> targetDevices;
  final String targetName;
  final String action; // block | unblock
  final int seq;
  final String at; // RFC 3339, UTC
  final String by;
  final String signer; // admin | server
  final SignedBlob? cert;
  final SignedBlob blob;

  const AdminBlockRecord({
    required this.id,
    required this.targetUserId,
    required this.targetDevices,
    required this.targetName,
    required this.action,
    required this.seq,
    required this.at,
    required this.by,
    required this.signer,
    required this.cert,
    required this.blob,
  });

  bool get isBlock => action == 'block';

  /// Every id this record covers (the account and its phones).
  Set<String> get ids => {
        if (targetUserId.isNotEmpty) targetUserId,
        for (final d in targetDevices)
          if (d.isNotEmpty) d,
      };

  static AdminBlockRecord? fromBlob(SignedBlob blob) {
    final f = blob.fields;
    if (f == null || f['kind'] != 'admin_block' || f['v'] != 1) return null;
    String s(String k) => f[k]?.toString() ?? '';
    final action = s('action');
    if (action != 'block' && action != 'unblock') return null;
    final seq = f['seq'] is int ? f['seq'] as int : int.tryParse(s('seq')) ?? 0;
    final devices = f['target_devices'] is List
        ? [
            for (final d in f['target_devices'] as List)
              if (d is String && d.isNotEmpty) d,
          ]
        : const <String>[];
    final record = AdminBlockRecord(
      id: s('id'),
      targetUserId: s('target_user_id'),
      targetDevices: devices,
      targetName: s('target_name'),
      action: action,
      seq: seq,
      at: s('at'),
      by: s('by'),
      signer: s('signer'),
      cert: SignedBlob.fromJson(f['cert']),
      blob: blob,
    );
    if (record.id.isEmpty || record.targetUserId.isEmpty || record.seq < 1) {
      return null;
    }
    if (DateTime.tryParse(record.at) == null) return null;
    return record;
  }

  /// Body for a new record made on this phone (signed by the caller).
  static String newBody({
    required String id,
    required String targetUserId,
    required List<String> targetDevices,
    required String targetName,
    required String action,
    required int seq,
    required DateTime at,
    required String by,
    required SignedBlob cert,
  }) =>
      jsonEncode({
        'v': 1,
        'kind': 'admin_block',
        'id': id,
        'target_user_id': targetUserId,
        'target_devices': targetDevices,
        'target_name': targetName,
        'action': action,
        'seq': seq,
        'at': at.toUtc().toIso8601String(),
        'by': by,
        'signer': 'admin',
        'cert': cert.toJson(),
      });
}

/// Bundle 212 rules (pure, no store, no network).
class AdminBlockRules {
  AdminBlockRules._();

  static const int maxRecords = 200;
  static const int maxPerFrame = 20;
  static const Duration digestEvery = Duration(seconds: 60);
  static const Duration digestGap = Duration(seconds: 30);
  static const Duration serverEvery = Duration(minutes: 10);

  static const String digestType = 'admin_block_digest';
  static const String recordsType = 'admin_block_records';
  static const String gotType = 'admin_block_got';

  static bool isFrameType(String? type) =>
      type == digestType || type == recordsType || type == gotType;

  /// Newest wins: seq, then time, then id (same as the server).
  static bool newer(AdminBlockRecord a, AdminBlockRecord? b) {
    if (b == null) return true;
    if (a.seq != b.seq) return a.seq > b.seq;
    final ta = DateTime.tryParse(a.at);
    final tb = DateTime.tryParse(b.at);
    if (ta != null && tb != null && !ta.isAtSameMomentAs(tb)) {
      return ta.isAfter(tb);
    }
    return a.id.compareTo(b.id) > 0;
  }

  /// Checks a record. Returns null when it is good, else the reason.
  /// Order (TODO B3): server key known, cert signed by the server and not
  /// ended, record signed by the cert key, role owner, not the admin's own
  /// account. "Newer than mine" is checked by the caller.
  static Future<String?> check(
    AdminBlockRecord record, {
    required String? serverKey,
    required Set<String> endedCerts,
    required Future<bool> Function(String body, String sig, String key) verify,
  }) async {
    if (serverKey == null || serverKey.isEmpty) return 'no_trust';
    if (record.signer == 'server') {
      return await verify(record.blob.body, record.blob.sig, serverKey)
          ? null
          : 'bad_server_sig';
    }
    if (record.signer != 'admin') return 'bad_signer';
    final certBlob = record.cert;
    if (certBlob == null) return 'no_cert';
    if (!await verify(certBlob.body, certBlob.sig, serverKey)) {
      return 'bad_cert_sig';
    }
    final cert = AdminCert.fromBlob(certBlob);
    if (cert == null) return 'bad_cert';
    if (endedCerts.contains(cert.certId)) return 'cert_ended';
    if (!await verify(record.blob.body, record.blob.sig, cert.signingKey)) {
      return 'bad_sig';
    }
    if (cert.role != 'owner') return 'not_owner';
    if (cert.deviceId.isNotEmpty && record.ids.contains(cert.deviceId)) {
      return 'self_block';
    }
    return null;
  }

  /// A server-signed "key ended" note: the cert id, or null.
  static Future<String?> endedCertId(
    SignedBlob note, {
    required String? serverKey,
    required Future<bool> Function(String body, String sig, String key) verify,
  }) async {
    if (serverKey == null || serverKey.isEmpty) return null;
    final f = note.fields;
    if (f == null || f['kind'] != 'cert_ended') return null;
    final id = f['cert_id']?.toString() ?? '';
    if (id.isEmpty) return null;
    if (!await verify(note.body, note.sig, serverKey)) return null;
    return id;
  }
}
