import 'dart:convert';

import 'package:locallink/features/admin/data/models/admin_block_record.dart';

/// Bundle 220: every admin action goes to all phones.
///
/// A card is a [SignedBlob] whose body is
/// `{v, kind:"admin_action", id, action, seq, at, by, signer, cert?, need,
/// to:[{k, box}], inner?, cancels?, parent?}` - the same shape the server
/// makes (`internal/httpapi/admin_actions_220.go`). Phones carry cards to
/// every linked phone (friends or not). Only the target phone can open its
/// box; it does the action and sends a signed "done" receipt back.
abstract final class AdminActionRules {
  static const String digestType = 'admin_act_digest';
  static const String cardsType = 'admin_act_cards';
  static const String doneType = 'admin_act_done';

  static bool isFrameType(String? t) =>
      t == digestType || t == cardsType || t == doneType;

  static const int appBuild = 131;
  static const int maxCardBytes = 16 * 1024;
  static const int maxLive = 1000;
  static const int maxTombstones = 5000;
  static const int maxPerFrame = 20;
  static const int maxPendingPerAdmin = 50;
  static const int maxLooseReceipts = 500;
  static const Duration digestEvery = Duration(seconds: 60);
  static const Duration digestGap = Duration(seconds: 30);
  static const Duration serverEvery = Duration(minutes: 10);
  static const Duration firstSync = Duration(seconds: 6);

  static const Set<String> actions = {
    'block', 'unblock', 'off', 'active', 'wifi_rule', 'sign_out',
    'remove_phone', 'admin_badge', 'version_rule', 'cancel',
    // Bundle 221 (Owner only): chats from phones + delete completely.
    'get_chat', 'get_file', 'delete_completely',
  };

  /// Actions for one person (all their phones); the others are one phone.
  static const Set<String> perPerson = {
    'block', 'unblock', 'off', 'active', 'admin_badge',
  };

  /// The admin role permission an action needs (same map as the server).
  /// "owner" = owner only.
  static String permissionFor(String action) => switch (action) {
        'block' || 'unblock' || 'off' || 'active' => 'manage_users',
        'wifi_rule' => 'manage_network_policy',
        'sign_out' => 'manage_sessions',
        'remove_phone' => 'manage_devices',
        _ => 'owner',
      };

  static const Map<String, Set<String>> _roles = {
    'owner': {'*'},
    'operator': {'read', 'manage_devices', 'manage_recovery', 'manage_network_policy'},
    'security': {'read', 'manage_recovery'},
    'auditor': {'read'},
  };

  static bool roleCan(String role, String action) {
    final p = permissionFor(action);
    if (p == 'owner') return role == 'owner';
    final set = _roles[role] ?? const <String>{};
    return set.contains('*') || set.contains(p);
  }

  /// Words for lists (app and logs).
  static String title(String action, {String detail = ''}) => switch (action) {
        'block' => 'Block',
        'unblock' => 'Unblock',
        'off' => 'Off (account closed)',
        'active' => 'Active again',
        'wifi_rule' => detail.isEmpty ? 'Wi-Fi rule' : 'Wi-Fi rule: $detail',
        'sign_out' => 'Sign out',
        'remove_phone' => 'Remove phone',
        'admin_badge' => detail.isEmpty ? 'Admin badge' : detail,
        'version_rule' => detail.isEmpty ? 'Old app rule' : detail,
        'rename_phone' => 'Rename phone',
        'cancel' => 'Cancel',
        'get_chat' => detail.isEmpty ? 'Get chat' : detail,
        'get_file' => detail.isEmpty ? 'Get full photo' : detail,
        'delete_completely' => detail.isEmpty ? 'Delete completely' : detail,
        _ => action,
      };
}

class AdminActionBox {
  final String k;
  final String box;
  const AdminActionBox(this.k, this.box);
  Map<String, dynamic> toJson() => {'k': k, 'box': box};
}

/// One admin action card.
class AdminActionCard {
  final String id;
  final String action;
  final int seq;
  final String at;
  final String by;
  final String signer; // server | admin
  final SignedBlob? cert;
  final int need;
  final List<AdminActionBox> to;
  final SignedBlob? inner;
  final String cancels;
  final String parent;
  final SignedBlob blob;

  /// Bundle 221: the X25519 key answers are locked for (the server's key
  /// for web requests, the admin phone's key for offline ones).
  final String replyKey;

  const AdminActionCard({
    required this.id,
    required this.action,
    required this.seq,
    required this.at,
    required this.by,
    required this.signer,
    required this.cert,
    required this.need,
    required this.to,
    required this.inner,
    required this.cancels,
    required this.parent,
    required this.blob,
    this.replyKey = '',
  });

  bool get isCancel => action == 'cancel';

  static AdminActionCard? fromBlob(SignedBlob blob) {
    if (blob.body.length > AdminActionRules.maxCardBytes) return null;
    final f = blob.fields;
    if (f == null || f['kind'] != 'admin_action' || f['v'] != 1) return null;
    String s(String k) => f[k]?.toString() ?? '';
    final action = s('action');
    if (!AdminActionRules.actions.contains(action)) return null;
    int n(String k) => f[k] is int ? f[k] as int : int.tryParse(s(k)) ?? 0;
    final to = <AdminActionBox>[
      for (final b in (f['to'] as List? ?? const []).whereType<Map>())
        if ((b['box']?.toString() ?? '').isNotEmpty)
          AdminActionBox(b['k']?.toString() ?? '', b['box'].toString()),
    ];
    final card = AdminActionCard(
      id: s('id'),
      action: action,
      seq: n('seq'),
      at: s('at'),
      by: s('by'),
      signer: s('signer'),
      cert: SignedBlob.fromJson(f['cert']),
      need: n('need'),
      to: to,
      inner: SignedBlob.fromJson(f['inner']),
      cancels: s('cancels'),
      parent: s('parent'),
      blob: blob,
      replyKey: s('reply_key'),
    );
    if (card.id.isEmpty || DateTime.tryParse(card.at) == null) return null;
    if (card.isCancel && card.cancels.isEmpty) return null;
    return card;
  }

  /// The body an admin phone signs (offline).
  static String newBody({
    required String id,
    required String action,
    required DateTime at,
    required String by,
    required SignedBlob cert,
    required int need,
    required List<AdminActionBox> to,
    SignedBlob? inner,
    String cancels = '',
    String parent = '',
    String replyKey = '',
  }) =>
      jsonEncode({
        'v': 1,
        'kind': 'admin_action',
        'id': id,
        'action': action,
        'seq': at.millisecondsSinceEpoch,
        'at': at.toUtc().toIso8601String(),
        'by': by,
        'signer': 'admin',
        'cert': cert.toJson(),
        'need': need,
        'to': [for (final b in to) b.toJson()],
        if (inner != null) 'inner': inner.toJson(),
        if (cancels.isNotEmpty) 'cancels': cancels,
        if (parent.isNotEmpty) 'parent': parent,
        if (replyKey.isNotEmpty) 'reply_key': replyKey,
      });
}

/// What is inside one box (only the target phone can read it).
class AdminActionPlain {
  final String device;
  final String user;
  final Map<String, dynamic> detail;
  const AdminActionPlain({required this.device, required this.user, this.detail = const {}});

  Map<String, dynamic> toJson() => {
        'device': device,
        'user': user,
        if (detail.isNotEmpty) 'detail': detail,
      };

  static AdminActionPlain? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final d = raw['device']?.toString() ?? '';
    if (d.isEmpty) return null;
    return AdminActionPlain(
      device: d,
      user: raw['user']?.toString() ?? '',
      detail: raw['detail'] is Map
          ? Map<String, dynamic>.from(raw['detail'] as Map)
          : const <String, dynamic>{},
    );
  }
}

/// The target phone's signed "done" (also "already" / "refused:<why>").
class AdminActionDone {
  final String actionId;
  final String device;
  final String user;
  final String result;
  final String at;
  final int build;
  final String via;
  final SignedBlob blob;

  const AdminActionDone({
    required this.actionId,
    required this.device,
    required this.user,
    required this.result,
    required this.at,
    required this.build,
    required this.via,
    required this.blob,
  });

  static AdminActionDone? fromBlob(SignedBlob blob) {
    if (blob.body.length > 4096) return null;
    final f = blob.fields;
    if (f == null || f['kind'] != 'admin_action_done' || f['v'] != 1) return null;
    String s(String k) => f[k]?.toString() ?? '';
    final d = AdminActionDone(
      actionId: s('action_id'),
      device: s('device'),
      user: s('user'),
      result: s('result'),
      at: s('at'),
      build: f['build'] is int ? f['build'] as int : 0,
      via: s('via'),
      blob: blob,
    );
    if (d.actionId.isEmpty || d.device.isEmpty || d.result.isEmpty) return null;
    if (DateTime.tryParse(d.at) == null) return null;
    return d;
  }

  static String newBody({
    required String actionId,
    required String device,
    required String user,
    required String result,
    required DateTime at,
    required int build,
    String via = '',
  }) =>
      jsonEncode({
        'v': 1,
        'kind': 'admin_action_done',
        'action_id': actionId,
        'device': device,
        'user': user,
        'result': result,
        'at': at.toUtc().toIso8601String(),
        'build': build,
        if (via.isNotEmpty) 'via': via,
      });
}

/// The "stop" note (done / cancelled / replaced): signed by the server, or
/// by the admin's phone with its admin cert (offline, the admin phone saw
/// enough receipts). Other phones then stop carrying the card.
class AdminActionStateNote {
  final String id;
  final String state;
  final int done;
  final int need;
  final SignedBlob? cert; // set = signed by an admin phone
  final SignedBlob blob;

  const AdminActionStateNote({
    required this.id,
    required this.state,
    required this.done,
    required this.need,
    required this.blob,
    this.cert,
  });

  static String newAdminBody({
    required String id,
    required int done,
    required int need,
    required DateTime at,
    required SignedBlob cert,
  }) =>
      jsonEncode({
        'v': 1,
        'kind': 'admin_action_state',
        'id': id,
        'state': 'done',
        'done': done,
        'need': need,
        'at': at.toUtc().toIso8601String(),
        'signer': 'admin',
        'cert': cert.toJson(),
      });

  static AdminActionStateNote? fromBlob(SignedBlob blob) {
    final f = blob.fields;
    if (f == null || f['kind'] != 'admin_action_state' || f['v'] != 1) return null;
    final id = f['id']?.toString() ?? '';
    final state = f['state']?.toString() ?? '';
    if (id.isEmpty || !const {'done', 'cancelled', 'replaced'}.contains(state)) {
      return null;
    }
    return AdminActionStateNote(
      id: id,
      state: state,
      done: f['done'] is int ? f['done'] as int : 0,
      need: f['need'] is int ? f['need'] as int : 0,
      cert: f['signer'] == 'admin' ? SignedBlob.fromJson(f['cert']) : null,
      blob: blob,
    );
  }
}
