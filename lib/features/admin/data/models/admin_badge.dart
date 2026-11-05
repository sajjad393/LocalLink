import 'package:locallink/features/admin/data/models/admin_block_record.dart';

/// Bundle 214: the server-signed admin card ("crown"). Signed with the
/// 212 server key, so a phone can't make itself (or anyone) an admin.
/// `on:false` = admin removed (crown off). Newest wins: seq, time, id.
class AdminBadge {
  final String id;
  final String userId;
  final String username;
  final String role; // owner | operator | security | auditor
  final bool on;
  final int seq;
  final String at; // RFC 3339, UTC
  final String by;
  final String signer;
  final SignedBlob blob;

  const AdminBadge({
    required this.id,
    required this.userId,
    required this.username,
    required this.role,
    required this.on,
    required this.seq,
    required this.at,
    required this.by,
    required this.signer,
    required this.blob,
  });

  static AdminBadge? fromBlob(SignedBlob blob) {
    final f = blob.fields;
    if (f == null) return null;
    String s(String k) => f[k]?.toString() ?? '';
    if (s('kind') != AdminBadges.kind) return null;
    final seq = f['seq'] is int ? f['seq'] as int : int.tryParse(s('seq')) ?? 0;
    final badge = AdminBadge(
      id: s('id'),
      userId: s('user_id'),
      username: s('username'),
      role: s('role'),
      on: f['on'] == true,
      seq: seq,
      at: s('at'),
      by: s('by'),
      signer: s('signer'),
      blob: blob,
    );
    if (badge.id.isEmpty || badge.userId.isEmpty || badge.seq < 1) return null;
    if (badge.on && !AdminBadges.roles.contains(badge.role)) return null;
    return badge;
  }

  /// "Owner", "Operator", ...
  String get roleLabel => AdminBadges.roleLabel(role);
}

class AdminBadges {
  AdminBadges._();

  static const String kind = 'admin_badge';
  static const String digestType = 'admin_badge_digest';
  static const String recordsType = 'admin_badge_records';
  static const List<String> roles = ['owner', 'operator', 'security', 'auditor'];
  static const int maxCards = 200;
  static const int maxPerFrame = 20;
  static const Duration digestEvery = Duration(seconds: 60);
  static const Duration digestGap = Duration(seconds: 30);
  static const Duration serverEvery = Duration(minutes: 10);

  static bool isFrameType(String? t) => t == digestType || t == recordsType;

  static String roleLabel(String role) => switch (role) {
        'owner' => 'Owner',
        'operator' => 'Operator',
        'security' => 'Security',
        'auditor' => 'Auditor',
        _ => role,
      };

  /// [a] is newer than [b] (seq, then time, then id).
  static bool newer(AdminBadge a, AdminBadge? b) {
    if (b == null) return true;
    if (a.seq != b.seq) return a.seq > b.seq;
    if (a.id == b.id) return false;
    final ta = DateTime.tryParse(a.at);
    final tb = DateTime.tryParse(b.at);
    if (ta != null && tb != null && !ta.isAtSameMomentAs(tb)) {
      return ta.isAfter(tb);
    }
    return a.id.compareTo(b.id) > 0;
  }

  /// Null when [badge] is a real server card, else the reason.
  static Future<String?> check(
    AdminBadge badge, {
    required String? serverKey,
    required Future<bool> Function(String body, String sig, String key) verify,
  }) async {
    if (badge.signer != 'server') return 'not_server';
    final key = serverKey;
    if (key == null || key.isEmpty) return 'no_trust';
    if (!await verify(badge.blob.body, badge.blob.sig, key)) return 'bad_sig';
    return null;
  }
}
