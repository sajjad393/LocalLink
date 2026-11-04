import 'dart:convert';

import 'package:locallink/core/models/group_event.dart';

/// Bundle G3: one member on a signed group card.
class GroupCardMember {
  const GroupCardMember({
    required this.id,
    required this.name,
    required this.role,
    required this.seal,
    required this.sign,
    this.addedBy = '',
    this.joinedAt = '',
  });

  /// Device id.
  final String id;
  final String name;

  /// "owner" | "admin" | "member".
  final String role;

  /// The member's profile lock key (X25519, base64url) - packets to this
  /// member are locked with it.
  final String seal;

  /// The member's profile signing key (Ed25519, base64url) - a card or a
  /// leave note from this member is checked with it.
  final String sign;
  final String addedBy;
  final String joinedAt;

  bool get isAdmin => role == 'owner' || role == 'admin';

  GroupCardMember copyWith({String? role, String? name}) => GroupCardMember(
        id: id,
        name: name ?? this.name,
        role: role ?? this.role,
        seal: seal,
        sign: sign,
        addedBy: addedBy,
        joinedAt: joinedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'n': name,
        'r': role,
        'k': seal,
        's': sign,
        'a': addedBy,
        'j': joinedAt,
      };

  static GroupCardMember? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    final role = raw['r']?.toString() ?? 'member';
    return GroupCardMember(
      id: id,
      name: raw['n']?.toString() ?? '',
      role: const {'owner', 'admin', 'member'}.contains(role) ? role : 'member',
      seal: raw['k']?.toString() ?? '',
      sign: raw['s']?.toString() ?? '',
      addedBy: raw['a']?.toString() ?? '',
      joinedAt: raw['j']?.toString() ?? '',
    );
  }
}

/// Bundle G3 (TODO_groups §9): the signed group card of a Nearby group.
///
/// Made and signed on an admin's phone; every member keeps the newest one
/// it accepted. A card says who is in the group, their keys, the roles and
/// the settings, so the group works without the server.
class GroupCard {
  const GroupCard({
    required this.gid,
    required this.version,
    required this.name,
    required this.owner,
    required this.members,
    required this.by,
    required this.at,
    this.createdAt = '',
    this.description = '',
    this.editInfo = 'admins',
    this.sendMessages = 'all',
    this.addMembers = 'admins',
    this.left = const [],
    this.signature = '',
    this.approve = false,
    this.qrToken = '',
    this.qrUntil = 0,
  });

  /// Nearby groups are up to 32 people (mock 3).
  static const int maxMembers = 32;

  final String gid;
  final int version;
  final String name;
  final String description;
  final String owner;
  final String editInfo;
  final String sendMessages;
  final String addMembers;
  final List<GroupCardMember> members;

  /// Who signed this version (an admin of the previous version).
  final String by;

  /// Signed at (ms since epoch).
  final int at;

  /// When the group was made (ISO, same on every phone).
  final String createdAt;

  /// Members that left on their own in this version ("Ali left").
  final List<String> left;
  final String signature;

  /// Bundle G4: "Approve new members" (mock 33) - people who scan the
  /// group QR wait for an admin.
  final bool approve;

  /// Bundle G4: the group QR secret and until when it works (ms). Empty =
  /// no code made yet. "Reset code" puts a new one on the card.
  final String qrToken;
  final int qrUntil;

  bool qrValid(String token, int nowMs) =>
      qrToken.isNotEmpty && token == qrToken && nowMs < qrUntil;

  GroupCardMember? member(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  bool has(String id) => member(id) != null;
  bool isAdmin(String id) => member(id)?.isAdmin ?? false;
  List<String> get memberIds => [for (final m in members) m.id];

  static String _setting(Object? v, String fallback) {
    final s = v?.toString() ?? '';
    return s == 'all' || s == 'admins' ? s : fallback;
  }

  Map<String, Object?> _body() {
    final sorted = [...members]..sort((a, b) => a.id.compareTo(b.id));
    final leftSorted = [...left]..sort();
    return {
      'add': addMembers,
      if (approve) 'ap': 1,
      'at': at,
      'by': by,
      'ca': createdAt,
      'd': description,
      'edit': editInfo,
      'gid': gid,
      'lft': leftSorted,
      'm': [for (final m in sorted) m.toJson()],
      'n': name,
      'o': owner,
      if (qrToken.isNotEmpty) 'qt': qrToken,
      if (qrToken.isNotEmpty) 'qx': qrUntil,
      'send': sendMessages,
      't': 'llgc1',
      'v': version,
    };
  }

  /// The exact text that is signed (keys sorted, members by id).
  String canonical() => jsonEncode(_canon(_body()));

  static Object? _canon(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _canon(v[k])};
    }
    if (v is List) return [for (final e in v) _canon(e)];
    return v;
  }

  Map<String, Object?> toJson() => {..._body(), 'sig': signature};

  String encode() => jsonEncode(toJson());

  static GroupCard? decode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static GroupCard? fromJson(Object? raw) {
    if (raw is! Map || raw['t']?.toString() != 'llgc1') return null;
    final list = raw['m'];
    if (list is! List) return null;
    final members = <GroupCardMember>[];
    final seen = <String>{};
    for (final e in list) {
      final m = GroupCardMember.fromJson(e);
      if (m == null || !seen.add(m.id)) return null;
      members.add(m);
    }
    final lft = raw['lft'];
    return GroupCard(
      gid: raw['gid']?.toString() ?? '',
      version: int.tryParse(raw['v']?.toString() ?? '') ?? 0,
      name: raw['n']?.toString() ?? '',
      description: raw['d']?.toString() ?? '',
      owner: raw['o']?.toString() ?? '',
      editInfo: _setting(raw['edit'], 'admins'),
      sendMessages: _setting(raw['send'], 'all'),
      addMembers: _setting(raw['add'], 'admins'),
      members: members,
      by: raw['by']?.toString() ?? '',
      at: int.tryParse(raw['at']?.toString() ?? '') ?? 0,
      createdAt: raw['ca']?.toString() ?? '',
      left: lft is List ? [for (final e in lft) e.toString()] : const [],
      signature: raw['sig']?.toString() ?? '',
      approve: raw['ap']?.toString() == '1',
      qrToken: raw['qt']?.toString() ?? '',
      qrUntil: int.tryParse(raw['qx']?.toString() ?? '') ?? 0,
    );
  }

  GroupCard withSignature(String sig) => GroupCard(
        gid: gid,
        version: version,
        name: name,
        description: description,
        owner: owner,
        editInfo: editInfo,
        sendMessages: sendMessages,
        addMembers: addMembers,
        members: members,
        by: by,
        at: at,
        createdAt: createdAt,
        left: left,
        signature: sig,
        approve: approve,
        qrToken: qrToken,
        qrUntil: qrUntil,
      );

  /// The next version (not signed yet) made by [by].
  GroupCard next({
    required String by,
    required int at,
    String? name,
    String? description,
    String? owner,
    String? editInfo,
    String? sendMessages,
    String? addMembers,
    List<GroupCardMember>? members,
    List<String> left = const [],
    bool? approve,
    String? qrToken,
    int? qrUntil,
  }) =>
      GroupCard(
        gid: gid,
        version: version + 1,
        name: name ?? this.name,
        description: description ?? this.description,
        owner: owner ?? this.owner,
        editInfo: editInfo ?? this.editInfo,
        sendMessages: sendMessages ?? this.sendMessages,
        addMembers: addMembers ?? this.addMembers,
        members: members ?? this.members,
        by: by,
        at: at,
        createdAt: createdAt,
        left: left,
        approve: approve ?? this.approve,
        qrToken: qrToken ?? this.qrToken,
        qrUntil: qrUntil ?? this.qrUntil,
      );

  /// Local rows for the group_members table.
  List<Map<String, dynamic>> memberRows() => [
        for (final m in members)
          {
            'device_id': m.id,
            'role': m.role,
            'joined_at': m.joinedAt,
            'name': m.name,
            'added_by': m.addedBy,
          }
      ];

  /// Local row for the groups table.
  Map<String, dynamic> groupRow() => {
        'id': gid,
        'name': name,
        'owner_id': owner,
        'created_at': createdAt,
        'description': description,
        'edit_info': editInfo,
        'send_messages': sendMessages,
        'add_members': addMembers,
        'created_by': owner,
      };
}

/// Bundle G3: what a phone accepts (pure, tested).
class GroupCardRules {
  const GroupCardRules._();

  static bool _key(String v) => v.length >= 42 && v.length <= 44;

  /// Null = the card looks right; else the reason.
  static String? shape(GroupCard c) {
    if (c.gid.isEmpty || c.gid.length > 64) return 'gid';
    if (c.version < 1) return 'version';
    final name = c.name.trim();
    if (name.isEmpty || name.length > 80) return 'name';
    if (c.description.length > 300) return 'desc';
    if (c.members.isEmpty || c.members.length > GroupCard.maxMembers) {
      return 'size';
    }
    final owners = c.members.where((m) => m.role == 'owner').toList();
    if (owners.length != 1 || owners.first.id != c.owner) return 'owner';
    if (!c.isAdmin(c.by) && !c.left.contains(c.by)) return 'signer';
    for (final m in c.members) {
      if (!_key(m.seal) || !_key(m.sign)) return 'keys';
    }
    if (c.signature.isEmpty) return 'unsigned';
    return null;
  }

  /// A first card for a group this phone does not have yet ("Ali added
  /// you"). Only a friend may add me: [signerFriendSignKey] is the signing
  /// key from that friend's profile on this phone (null = not a friend).
  /// Returns the key to check the signature with, or null = refuse.
  static String? firstSigner(GroupCard c,
      {required String self, required String? signerFriendSignKey}) {
    if (shape(c) != null) return null;
    if (!c.has(self) || c.by == self) return null;
    final signer = c.member(c.by);
    if (signer == null || !signer.isAdmin) return null;
    final friendKey = signer.sign;
    if (signerFriendSignKey == null || signerFriendSignKey != friendKey) {
      return null;
    }
    return friendKey;
  }

  /// A newer card for a group I have. The signer must be an admin in MY
  /// card (or the owner leaving and naming a new owner). Returns the key to
  /// check the signature with, or null = refuse / not newer.
  static String? updateSigner(GroupCard old, GroupCard next) {
    if (shape(next) != null || next.gid != old.gid) return null;
    final newer = next.version > old.version ||
        (next.version == old.version &&
            next.signature != old.signature &&
            next.signature.compareTo(old.signature) < 0);
    if (!newer) return null;
    final signer = old.member(next.by);
    if (signer == null || !signer.isAdmin) return null;
    return signer.sign;
  }

  /// Bundle G4: a first card after I scanned a group QR and asked to join.
  /// The admin whose code I scanned must have signed it (key from the QR).
  static String? joinSigner(GroupCard c,
      {required String self,
      required String issuer,
      required String issuerSign}) {
    if (shape(c) != null) return null;
    if (!c.has(self) || c.by == self || c.by != issuer) return null;
    final signer = c.member(issuer);
    if (signer == null || !signer.isAdmin) return null;
    if (issuerSign.isEmpty || signer.sign != issuerSign) return null;
    return signer.sign;
  }

  /// The system lines a new card means on this phone.
  static List<GroupEvent> events(GroupCard? old, GroupCard next,
      {required String self}) {
    final names = <String, String>{
      if (old != null)
        for (final m in old.members)
          if (m.name.isNotEmpty) m.id: m.name,
      for (final m in next.members)
        if (m.name.isNotEmpty) m.id: m.name,
    };
    if (old == null) {
      final others = [
        for (final m in next.members)
          if (m.id != next.owner) m.id
      ]..sort();
      if (next.version == 1) {
        return [
          GroupEvent(
              kind: 'create',
              by: next.owner,
              targets: others,
              name: next.name,
              names: names)
        ];
      }
      return [
        GroupEvent(kind: 'add', by: next.by, targets: [self], names: names)
      ];
    }
    final out = <GroupEvent>[];
    final before = old.memberIds.toSet();
    final after = next.memberIds.toSet();
    final added = after.difference(before).toList()..sort();
    final gone = before.difference(after).toList()..sort();
    final leftIds = gone.where(next.left.contains).toList();
    final removed = gone.where((id) => !next.left.contains(id)).toList();
    if (added.isNotEmpty) {
      out.add(GroupEvent(kind: 'add', by: next.by, targets: added, names: names));
    }
    if (removed.isNotEmpty) {
      out.add(GroupEvent(
          kind: 'remove', by: next.by, targets: removed, names: names));
    }
    for (final id in leftIds) {
      out.add(GroupEvent(
          kind: 'leave',
          by: id,
          owner: old.owner == id && next.owner != id ? next.owner : '',
          names: names));
    }
    for (final m in next.members) {
      final was = old.member(m.id);
      if (was == null || was.isAdmin == m.isAdmin) continue;
      if (leftIds.isNotEmpty && m.id == next.owner && old.owner != m.id) {
        continue; // the leave line already names the new owner
      }
      out.add(GroupEvent(
          kind: m.isAdmin ? 'admin' : 'unadmin',
          by: next.by,
          targets: [m.id],
          names: names));
    }
    if (next.name != old.name) {
      out.add(GroupEvent(kind: 'name', by: next.by, name: next.name, names: names));
    }
    if (next.description != old.description) {
      out.add(GroupEvent(kind: 'desc', by: next.by, names: names));
    }
    void setting(String field, String a, String b) {
      if (a != b) {
        out.add(GroupEvent(
            kind: 'set', by: next.by, field: field, value: b, names: names));
      }
    }

    setting('edit_info', old.editInfo, next.editInfo);
    setting('send_messages', old.sendMessages, next.sendMessages);
    setting('add_members', old.addMembers, next.addMembers);
    // Bundle G4: "Approve new members" -> "… changed the group settings".
    setting('approve', old.approve ? 'on' : 'off', next.approve ? 'on' : 'off');
    return out;
  }
}
