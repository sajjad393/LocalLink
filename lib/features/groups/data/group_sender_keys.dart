import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:locallink/core/services/message_seal_service.dart';

/// Bundle G6: end-to-end "sender keys" for group messages that go through
/// the server.
///
/// * Each member has one random 32-byte key per group (its "sender key",
///   with a short id). Messages it sends through the server are locked with
///   AES-256-GCM under that key: one lock, every member opens it. The
///   server keeps only `llsk:v1:<kid>.<nonce>.<box>`.
/// * The key goes to every other member inside one control note
///   `llskd:v1:{"kid":..,"k":{member: sealed}}` - one sealed entry per
///   member (the same X25519 + AES-GCM seal as offline 1:1 messages), so
///   only that member can open its entry.
/// * A new key is made whenever the member list changes (someone added,
///   removed or left): people who left can't read new messages, and new
///   people can't read old ones.
/// * A member who can't open a message (no key yet) asks once with
///   `llskq:v1:{"to": writer, "kid": ..}`; the writer sends its key again.
/// * Nearby packets stay as they are (already sealed per member).
/// * Bound into each lock: group id, writer id, message id, key id - the
///   server can't move a message to another group, writer or id.
class GroupSenderKeys {
  GroupSenderKeys({
    required this.selfId,
    required this.read,
    required this.write,
    required this.ownKeys,
    required this.publicKeyOf,
    MessageSealService? sealer,
    Random? random,
  })  : _sealer = sealer ?? MessageSealService(),
        _random = random ?? Random.secure();

  static const lockedPrefix = 'llsk:v1:';
  static const keysPrefix = 'llskd:v1:';
  static const askPrefix = 'llskq:v1:';

  /// Shown for a message that can't be opened yet.
  static const waitingText = '🔒 Waiting for this message';

  static bool isLocked(String body) => body.startsWith(lockedPrefix);
  static bool isKeys(String body) => body.startsWith(keysPrefix);
  static bool isAsk(String body) => body.startsWith(askPrefix);

  /// Notes about keys - never a chat line, never locked themselves.
  static bool isKeyNote(String body) => isKeys(body) || isAsk(body);

  final String Function() selfId;
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final Future<List<SealKeyPair>> Function() ownKeys;

  /// A member's identity (seal) public key, 32 bytes, or null.
  final Future<List<int>?> Function(String gid, String deviceId) publicKeyOf;

  final MessageSealService _sealer;
  final Random _random;
  final AesGcm _aes = AesGcm.with256bits();

  static String _mineKey(String gid) => 'gsk_mine_$gid';
  static String _ownOldKey(String gid, String kid) => 'gsk_own_${gid}_$kid';
  static String _peerKey(String gid, String sender, String kid) =>
      'gsk_peer_${gid}_${sender}_$kid';

  // ------------------------------------------------------------ my key

  /// My key for [gid] for exactly these [members] (other members, any
  /// order). A changed list makes a new key.
  Future<GroupMyKey> current(String gid, List<String> members) async {
    final want = ({...members}..remove(selfId())).toList()..sort();
    final now = await _loadMine(gid);
    if (now != null && _same(now.members, want)) return now;
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final kid = List.generate(8, (_) => _random.nextInt(16).toRadixString(16))
        .join();
    final next = GroupMyKey(
        kid: kid, key: bytes, members: want, distributed: false, noteId: '');
    await write(_ownOldKey(gid, kid),
        jsonEncode({'k': base64Url.encode(bytes), 'm': want}));
    await _saveMine(gid, next);
    return next;
  }

  /// The key note for [key] reached the server.
  Future<void> markDistributed(String gid, String noteId) async {
    final now = await _loadMine(gid);
    if (now == null || now.noteId != noteId) return;
    await _saveMine(gid, now.copy(distributed: true));
  }

  /// Someone asked for my current key: send the note again.
  Future<void> markUndistributed(String gid) async {
    final now = await _loadMine(gid);
    if (now == null) return;
    await _saveMine(gid, now.copy(distributed: false, noteId: ''));
  }

  /// The id the key note goes out with (stays the same until it is acked,
  /// so resends are the same server message).
  Future<String> noteIdFor(String gid, String Function() newId) async {
    final now = await _loadMine(gid);
    if (now == null) return newId();
    if (now.noteId.isNotEmpty) return now.noteId;
    final id = newId();
    await _saveMine(gid, now.copy(noteId: id));
    return id;
  }

  Future<GroupMyKey?> _loadMine(String gid) async {
    try {
      final raw = await read(_mineKey(gid));
      if (raw == null || raw.isEmpty) return null;
      return GroupMyKey.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveMine(String gid, GroupMyKey key) =>
      write(_mineKey(gid), jsonEncode(key.toJson()));

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ------------------------------------------------------- key notes

  /// The key note for [kid]/[key] to [to] (null = a member's public key
  /// is missing; then nothing is locked for now).
  Future<String?> keysNote(String gid, String kid, List<int> key,
      List<String> to) async {
    final self = selfId();
    final mine = await ownKeys();
    if (self.isEmpty || mine.isEmpty) return null;
    final entries = <String, String>{};
    for (final member in to) {
      if (member == self) continue;
      final theirs = await publicKeyOf(gid, member);
      if (theirs == null || theirs.length != 32) return null;
      final sealed = await _sealer.seal(
        payload: {
          'type': 'group_sender_key',
          'g': gid,
          'kid': kid,
          'k': base64Url.encode(key),
        },
        senderId: self,
        recipientId: member,
        mine: mine.first,
        theirPublic: theirs,
        outerType: MessageSealService.sealedType,
      );
      entries[member] = jsonEncode(sealed);
    }
    if (entries.isEmpty) return null;
    return keysPrefix + jsonEncode({'kid': kid, 'k': entries});
  }

  /// A key note from [sender]: keeps my entry. Returns the key id it gave
  /// (null = nothing for me / can't open).
  Future<String?> acceptKeys(String gid, String sender, String body) async {
    final self = selfId();
    if (!isKeys(body) || sender.isEmpty || sender == self) return null;
    try {
      final raw = jsonDecode(body.substring(keysPrefix.length));
      if (raw is! Map) return null;
      final kid = raw['kid']?.toString() ?? '';
      final k = raw['k'];
      if (kid.isEmpty || k is! Map) return null;
      final entry = k[self];
      if (entry == null) return null;
      final theirs = await publicKeyOf(gid, sender);
      if (theirs == null) return null;
      final opened = await _sealer.open(
        sealed: Map<String, dynamic>.from(jsonDecode(entry.toString()) as Map),
        senderId: sender,
        recipientId: self,
        mine: await ownKeys(),
        theirPublic: theirs,
      );
      if (opened['type'] != 'group_sender_key' ||
          opened['g']?.toString() != gid ||
          opened['kid']?.toString() != kid) {
        return null;
      }
      final key = base64Url.decode(opened['k']?.toString() ?? '');
      if (key.length != 32) return null;
      await write(_peerKey(gid, sender, kid), base64Url.encode(key));
      return kid;
    } catch (_) {
      return null;
    }
  }

  /// "Please send me your key [kid]" (to [writer]).
  static String askNote(String writer, String kid) =>
      askPrefix + jsonEncode({'to': writer, 'kid': kid});

  /// (writer, kid) of an ask note, or null.
  static (String, String)? parseAsk(String body) {
    if (!isAsk(body)) return null;
    try {
      final raw = jsonDecode(body.substring(askPrefix.length));
      if (raw is! Map) return null;
      final to = raw['to']?.toString() ?? '';
      final kid = raw['kid']?.toString() ?? '';
      if (to.isEmpty || kid.isEmpty) return null;
      return (to, kid);
    } catch (_) {
      return null;
    }
  }

  /// My key [kid] for [gid] (current or older), or null.
  Future<List<int>?> ownKey(String gid, String kid) async =>
      (await _ownRecord(gid, kid))?.$1;

  /// Whether [member] was in the group when my key [kid] was made (only
  /// they may get that old key again - new members never read older
  /// messages).
  Future<bool> ownKeyWasFor(String gid, String kid, String member) async =>
      (await _ownRecord(gid, kid))?.$2.contains(member) ?? false;

  Future<(List<int>, List<String>)?> _ownRecord(String gid, String kid) async {
    try {
      final raw = await read(_ownOldKey(gid, kid));
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final bytes = base64Url.decode(m['k']?.toString() ?? '');
      final members = m['m'];
      if (bytes.length != 32) return null;
      return (
        bytes,
        members is List ? [for (final e in members) e.toString()] : <String>[]
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<int>?> _stored(String settingKey) async {
    try {
      final raw = await read(settingKey);
      if (raw == null || raw.isEmpty) return null;
      final bytes = base64Url.decode(raw);
      return bytes.length == 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------- lock / open

  static List<int> _aad(String gid, String sender, String id, String kid) =>
      utf8.encode('llsk1|$gid|$sender|$id|$kid');

  /// The key id inside a locked body ('' = not one).
  static String kidOf(String body) {
    if (!isLocked(body)) return '';
    final rest = body.substring(lockedPrefix.length);
    final dot = rest.indexOf('.');
    return dot <= 0 ? '' : rest.substring(0, dot);
  }

  Future<String> lock(String gid, String messageId, String body,
      GroupMyKey key) async {
    final box = await _aes.encrypt(
      utf8.encode(body),
      secretKey: SecretKey(key.key),
      nonce: _aes.newNonce(),
      aad: _aad(gid, selfId(), messageId, key.kid),
    );
    return '$lockedPrefix${key.kid}.${_b64(box.nonce)}.'
        '${_b64([...box.cipherText, ...box.mac.bytes])}';
  }

  /// The text of a locked body, or null when this phone has no key for it
  /// (or it was changed on the way).
  Future<String?> open(
      String gid, String sender, String messageId, String body) async {
    if (!isLocked(body)) return body;
    final parts = body.substring(lockedPrefix.length).split('.');
    if (parts.length != 3) return null;
    final kid = parts[0];
    final key = sender == selfId()
        ? await ownKey(gid, kid)
        : await _stored(_peerKey(gid, sender, kid));
    if (key == null) return null;
    try {
      final nonce = _unb64(parts[1]);
      final data = _unb64(parts[2]);
      if (data.length < 16) return null;
      final clear = await _aes.decrypt(
        SecretBox(data.sublist(0, data.length - 16),
            nonce: nonce, mac: Mac(data.sublist(data.length - 16))),
        secretKey: SecretKey(key),
        aad: _aad(gid, sender, messageId, kid),
      );
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _unb64(String value) {
    var v = value;
    while (v.length % 4 != 0) {
      v += '=';
    }
    return base64Url.decode(v);
  }

  /// A 32-byte key from base64 / base64url text with or without "=".
  static List<int>? decodePublicKey(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return null;
    try {
      final bytes = _unb64(v.replaceAll('+', '-').replaceAll('/', '_'));
      return bytes.length == 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }
}

/// My sender key for one group.
class GroupMyKey {
  const GroupMyKey({
    required this.kid,
    required this.key,
    required this.members,
    required this.distributed,
    required this.noteId,
  });

  final String kid;
  final List<int> key;

  /// The other members (sorted) the key was made for.
  final List<String> members;

  /// The key note reached the server.
  final bool distributed;

  /// Id of the key note (same id on resends).
  final String noteId;

  GroupMyKey copy({bool? distributed, String? noteId}) => GroupMyKey(
      kid: kid,
      key: key,
      members: members,
      distributed: distributed ?? this.distributed,
      noteId: noteId ?? this.noteId);

  Map<String, dynamic> toJson() => {
        'kid': kid,
        'k': base64Url.encode(key),
        'm': members,
        'd': distributed,
        'n': noteId,
      };

  static GroupMyKey? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = base64Url.decode(raw['k']?.toString() ?? '');
    final m = raw['m'];
    if (key.length != 32) return null;
    return GroupMyKey(
      kid: raw['kid']?.toString() ?? '',
      key: key,
      members: m is List ? [for (final e in m) e.toString()] : const [],
      distributed: raw['d'] == true,
      noteId: raw['n']?.toString() ?? '',
    );
  }
}

/// Bundle G6: where a member's public key comes from, best first:
/// 1. the signed group card / my friend list (Nearby groups, friends),
/// 2. the saved directory profile,
/// 3. the server's device key list (cached 10 minutes).
class GroupMemberKeys {
  GroupMemberKeys({
    this.cardOrFriend,
    this.directory,
    this.server,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<String> Function(String gid, String id)? cardOrFriend;
  final Future<Map<String, dynamic>?> Function(String id)? directory;
  final Future<Map<String, String>> Function()? server;
  final DateTime Function() _clock;

  Map<String, String> _server = const {};
  DateTime? _serverAt;

  Future<List<int>?> lookup(String gid, String id) async {
    try {
      final k = GroupSenderKeys.decodePublicKey(
          await cardOrFriend?.call(gid, id));
      if (k != null) return k;
    } catch (_) {}
    try {
      final p = await directory?.call(id);
      final k = GroupSenderKeys.decodePublicKey(
          p?['identity_public_key']?.toString());
      if (k != null) return k;
    } catch (_) {}
    final load = server;
    if (load == null) return null;
    final now = _clock();
    final at = _serverAt;
    if (at == null ||
        now.difference(at) > const Duration(minutes: 10) ||
        (!_server.containsKey(id) &&
            now.difference(at) > const Duration(seconds: 30))) {
      try {
        _server = await load();
        _serverAt = now;
      } catch (_) {}
    }
    return GroupSenderKeys.decodePublicKey(_server[id]);
  }
}
