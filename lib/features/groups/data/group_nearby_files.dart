import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/files/data/services/media_transfer_actions.dart';

/// Bundle G7 (TODO_G7): photos, videos, voice notes and documents in a
/// group with no internet.
///
/// * The group message carries a short list of its files (`att`), signed
///   by the writer together with the text.
/// * The sender's phone sends each file to each member on its own (like
///   1:1), with a file id per member: `<fileId>.g<8 hex>` so two members
///   never share one transfer.
/// * A member's "got it" (`group_ack` with `fv: 2`) starts that member's
///   files. Old phones (no `fv`) get the files from the server only.
/// * 50 MB per file over Nearby (bigger ones go by the server only).

/// One file of a group message, as it travels Nearby.
class GroupNearbyFile {
  const GroupNearbyFile({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
  });

  final String id;
  final String name;
  final String type;
  final int size;

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9_.-]{1,99}$');

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'type': type, 'size': size};

  static GroupNearbyFile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    final name = raw['name']?.toString() ?? '';
    final type = raw['type']?.toString() ?? '';
    final size = int.tryParse(raw['size']?.toString() ?? '') ?? -1;
    if (!_idPattern.hasMatch(id) || GroupFileWire.isWire(id)) return null;
    if (name.isEmpty || name.length > 200) return null;
    if (type.isEmpty || type.length > 100 || !type.contains('/')) return null;
    if (size < 0 || size > GroupFileWire.maxBytes) return null;
    return GroupNearbyFile(id: id, name: name, type: type, size: size);
  }

  static GroupNearbyFile fromAttachment(Attachment a) => GroupNearbyFile(
      id: a.id, name: a.originalName, type: a.contentType, size: a.size);

  Attachment toAttachment({String? localPath}) => Attachment(
        id: id,
        originalName: name,
        contentType: type,
        size: size,
        sha256: '',
        isImage: type.toLowerCase().startsWith('image/'),
        localPath: localPath,
      );
}

/// Wire ids, the signed text and the file list format.
class GroupFileWire {
  GroupFileWire._();

  /// Same limit as 1:1 files over Nearby.
  static const int maxBytes = 50 * 1024 * 1024;
  static const int maxFiles = 10;

  /// `fv` in `group_ack`: this phone takes group files Nearby.
  static const int filesVersion = 2;

  static final RegExp _wire = RegExp(r'\.g[0-9a-f]{8}$');

  static String tag(String memberId) =>
      sha256.convert(utf8.encode(memberId)).toString().substring(0, 8);

  /// The transfer id for [fileId] going to [memberId].
  static String wireId(String fileId, String memberId) =>
      '$fileId.g${tag(memberId)}';

  static bool isWire(String id) => _wire.hasMatch(id);

  static String fileIdOf(String wire) => wire.replaceFirst(_wire, '');

  static bool isFor(String wire, String memberId) =>
      isWire(wire) && wire.endsWith('.g${tag(memberId)}');

  /// Canonical text of a file list (signed with the message).
  static String canonical(List<GroupNearbyFile> files) => jsonEncode([
        for (final f in files) [f.id, f.name, f.type, f.size]
      ]);

  static List<GroupNearbyFile> parseList(Object? raw) {
    if (raw is! List) return const [];
    final out = <GroupNearbyFile>[];
    final seen = <String>{};
    for (final e in raw.take(maxFiles)) {
      final f = GroupNearbyFile.fromJson(e);
      if (f == null || !seen.add(f.id)) continue;
      out.add(f);
    }
    return out;
  }

  /// A copy row keeps the list as JSON text ('' = no files).
  static String encodeList(List<GroupNearbyFile> files) => files.isEmpty
      ? ''
      : jsonEncode([for (final f in files) f.toJson()]);

  static List<GroupNearbyFile> decodeList(String text) {
    if (text.isEmpty) return const [];
    try {
      return parseList(jsonDecode(text));
    } catch (_) {
      return const [];
    }
  }

  /// Bundle G7: what the writer signs for a message with files.
  static String messageText2(String gid, String id, String writer,
          String createdAt, String body, List<GroupNearbyFile> files) =>
      'llgm2\n$gid\n$id\n$writer\n$createdAt\n$body\n${canonical(files)}';

  /// The group photo travels as a "message" of its own.
  static const String photoMessagePrefix = 'gphoto-';
  static String photoMessageId(String gid) => '$photoMessagePrefix$gid';
  static String photoFileId(int version) => 'gp$version';
  static bool isPhotoMessage(String messageId) =>
      messageId.startsWith(photoMessagePrefix);
  static String photoGid(String messageId) =>
      messageId.substring(photoMessagePrefix.length);
  static int photoVersion(String fileId) =>
      fileId.startsWith('gp') ? int.tryParse(fileId.substring(2)) ?? 0 : 0;
}

// ------------------------------------------------------------ sender rows

/// One file to one member. Status:
/// * `wait`    - the member has not said "got it" for the message yet;
/// * `ready`   - send when the member is reachable (next_at);
/// * `sending` - with the phone's transfer engine (next_at = give up at);
/// * `done`    - the member's phone has the whole file;
/// * `old`     - the member's app is too old (server only, P2);
/// * `stop`    - the member pressed X (until they tap to download).
class GroupFileSend {
  GroupFileSend({
    required this.msgId,
    required this.fileId,
    required this.memberId,
    required this.gid,
    this.status = 'wait',
    this.tries = 0,
    this.nextAt = 0,
    required this.createdAt,
  });

  final String msgId;
  final String fileId;
  final String memberId;
  final String gid;
  String status;
  int tries;
  int nextAt;
  final int createdAt;

  String get key => '$msgId|$fileId|$memberId';
  String get wireId => GroupFileWire.wireId(fileId, memberId);

  Map<String, Object?> toRow() => {
        'msg_id': msgId,
        'file_id': fileId,
        'member_id': memberId,
        'group_id': gid,
        'status': status,
        'tries': tries,
        'next_at': nextAt,
        'created_at': createdAt,
      };

  static GroupFileSend fromRow(Map<String, dynamic> r) => GroupFileSend(
        msgId: r['msg_id']?.toString() ?? '',
        fileId: r['file_id']?.toString() ?? '',
        memberId: r['member_id']?.toString() ?? '',
        gid: r['group_id']?.toString() ?? '',
        status: r['status']?.toString() ?? 'wait',
        tries: int.tryParse(r['tries']?.toString() ?? '') ?? 0,
        nextAt: int.tryParse(r['next_at']?.toString() ?? '') ?? 0,
        createdAt: int.tryParse(r['created_at']?.toString() ?? '') ?? 0,
      );
}

/// Where the sender rows live (table `group_file_sends`, DB v33).
abstract class GroupFileSendStore {
  /// Adds rows that are not there yet (existing rows stay).
  Future<void> putSends(List<GroupFileSend> rows);
  Future<List<GroupFileSend>> sends({String? msgId, String? memberId});
  Future<void> updateSend(GroupFileSend row);
  Future<void> purgeSends(int olderThanMs);
}

/// For tests (and phones without a database seam).
class MemoryGroupFileSendStore implements GroupFileSendStore {
  final Map<String, GroupFileSend> rows = <String, GroupFileSend>{};

  GroupFileSend _copy(GroupFileSend r) => GroupFileSend.fromRow(
      Map<String, dynamic>.from(r.toRow()));

  @override
  Future<void> putSends(List<GroupFileSend> list) async {
    for (final r in list) {
      rows.putIfAbsent(r.key, () => _copy(r));
    }
  }

  @override
  Future<List<GroupFileSend>> sends({String? msgId, String? memberId}) async => [
        for (final r in rows.values)
          if ((msgId == null || r.msgId == msgId) &&
              (memberId == null || r.memberId == memberId))
            _copy(r)
      ];

  @override
  Future<void> updateSend(GroupFileSend row) async {
    if (rows.containsKey(row.key)) rows[row.key] = _copy(row);
  }

  @override
  Future<void> purgeSends(int olderThanMs) async =>
      rows.removeWhere((_, r) => r.createdAt < olderThanMs);
}

/// Hands one file to the phone's transfer engine (FileTransfer
/// sendDirectFile) - the same road as 1:1 files.
typedef GroupDirectFileSend = Future<void> Function({
  required String memberId,
  required String messageId,
  required String wireId,
  required PickedFile file,
});

/// Bundle G7: the sender sends each file to each member one by one.
class GroupFileSender {
  GroupFileSender({
    required this.store,
    required this.source,
    required this.sendFile,
    this.beforeSend,
    this.onChanged,
    this.lowBattery,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final GroupFileSendStore store;

  /// The sender's own copy of a file (null = gone).
  final Future<PickedFile?> Function(String msgId, String fileId) source;
  final GroupDirectFileSend sendFile;

  /// Runs before a send round (pushes the pair file keys).
  final Future<void> Function()? beforeSend;

  /// A row changed (the message's ticks / ring may change).
  final void Function(String msgId)? onChanged;

  /// Battery 10% or less: only small files (voice notes under 1 MB) go.
  final bool Function()? lowBattery;
  static const int smallFileBytes = 1024 * 1024;
  final int Function() _nowMs;

  static const int maxActive = 6;
  static const Duration keepFor = Duration(days: 7);
  static const Duration sendingTimeout = Duration(minutes: 10);
  static const List<int> _backoffSeconds = [15, 30, 60, 120, 300, 600, 900];

  /// Tap to download: at most 5 asks per member per 10 minutes.
  static const int needMax = 5;
  static const Duration needWindow = Duration(minutes: 10);

  final Map<String, List<int>> _needs = <String, List<int>>{};
  bool _pumping = false;
  bool _pumpAgain = false;

  /// Rows for a new message: every file to every member (waiting for the
  /// member's "got it").
  Future<void> queue(String gid, String msgId, List<GroupNearbyFile> files,
      Iterable<String> members) async {
    if (files.isEmpty) return;
    final now = _nowMs();
    await store.putSends([
      for (final m in members)
        for (final f in files)
          if (f.size <= GroupFileWire.maxBytes)
            GroupFileSend(
                msgId: msgId, fileId: f.id, memberId: m, gid: gid, createdAt: now),
    ]);
  }

  /// [member] said "got it" for [msgId]; `fv >= 2` = it takes files.
  Future<void> memberGot(String member, String msgId,
      {required int fv, String? fileId}) async {
    final rows = await store.sends(msgId: msgId, memberId: member);
    if (rows.isEmpty) return;
    var changed = false;
    for (final r in rows) {
      if (r.status != 'wait') continue;
      if (fileId != null && r.fileId != fileId) continue;
      r.status = fv >= GroupFileWire.filesVersion ? 'ready' : 'old';
      r.nextAt = 0;
      await store.updateSend(r);
      changed = true;
    }
    if (!changed) return;
    AppLogger.info('GROUP_FILE_READY',
        detail: 'to=${_id6(member)} files=${rows.length} fv=$fv');
    onChanged?.call(msgId);
    await pump();
  }

  /// [member] came near: its waiting files go now.
  Future<void> peerUp(String member) async {
    final rows = await store.sends(memberId: member);
    var any = false;
    for (final r in rows) {
      if (r.status != 'ready' || r.nextAt == 0) continue;
      r.nextAt = 0;
      await store.updateSend(r);
      any = true;
    }
    if (any || rows.any((r) => r.status == 'ready')) await pump();
  }

  /// [member] tapped "Tap to download" ([fileId] = '' for all files).
  Future<bool> need(String member, String msgId, String fileId) async {
    final now = _nowMs();
    final list = _needs[member] ??= <int>[];
    list.removeWhere((t) => now - t > needWindow.inMilliseconds);
    if (list.length >= needMax) {
      AppLogger.info('GROUP_FILE_NEED', detail: 'refused why=rate');
      return false;
    }
    list.add(now);
    final rows = await store.sends(msgId: msgId, memberId: member);
    var any = false;
    for (final r in rows) {
      if (fileId.isNotEmpty && r.fileId != fileId) continue;
      if (r.status == 'old') continue;
      r
        ..status = 'ready'
        ..tries = 0
        ..nextAt = 0;
      await store.updateSend(r);
      any = true;
    }
    AppLogger.info('GROUP_FILE_NEED', detail: 'from=${_id6(member)} ok=$any');
    if (any) await pump();
    return any;
  }

  /// P1: every one of [members] has every Nearby file of [msgId].
  /// [fileIds]: every one of these must be there (a file over 50 MB never
  /// has rows, so it still goes by the server).
  Future<bool> allDelivered(String msgId, Iterable<String> members,
      {Iterable<String>? fileIds}) async {
    final rows = await store.sends(msgId: msgId);
    final wanted = members.toSet();
    if (rows.isEmpty || wanted.isEmpty) return false;
    for (final m in wanted) {
      final mine = rows.where((r) => r.memberId == m).toList();
      if (mine.isEmpty || mine.any((r) => r.status != 'done')) return false;
      if (fileIds != null) {
        final have = {for (final r in mine) r.fileId};
        if (fileIds.any((f) => !have.contains(f))) return false;
      }
    }
    return true;
  }

  /// Rows still busy for [msgId] (for the sender's ring).
  Future<bool> busy(String msgId) async => (await store.sends(msgId: msgId))
      .any((r) => r.status == 'ready' || r.status == 'sending');

  /// Native file events (sender side). Returns true when it was ours.
  Future<bool> handleEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString() ?? '';
    if (type != 'file_sent' && type != 'file_failed' && type != 'file_cancelled') {
      return false;
    }
    final wire = (event['transfer_id'] ?? event['file_id'])?.toString() ?? '';
    final msgId = event['message_id']?.toString() ?? '';
    if (!GroupFileWire.isWire(wire)) return false;
    final fileId = GroupFileWire.fileIdOf(wire);
    final rows = msgId.isNotEmpty
        ? await store.sends(msgId: msgId)
        : <GroupFileSend>[];
    final row = rows
        .where((r) => r.fileId == fileId && r.wireId == wire)
        .cast<GroupFileSend?>()
        .firstWhere((_) => true, orElse: () => null);
    if (row == null) return false;
    final now = _nowMs();
    switch (type) {
      case 'file_sent':
        row.status = 'done';
        row.nextAt = 0;
        AppLogger.info('GROUP_FILE_SENT', detail: 'to=${_id6(row.memberId)}');
      case 'file_cancelled':
        // The member pressed X (or I did): wait for "Tap to download".
        row.status = 'stop';
      default:
        row.tries++;
        row.status = 'ready';
        row.nextAt = now + _backoff(row.tries);
        AppLogger.warning('GROUP_FILE_FAILED',
            detail: 'to=${_id6(row.memberId)} try=${row.tries} '
                'why=${event['reason'] ?? ''}');
    }
    await store.updateSend(row);
    onChanged?.call(row.msgId);
    unawaited(pump());
    return true;
  }

  /// Sends what is due, at most [maxActive] at once.
  Future<void> pump() async {
    if (_pumping) {
      _pumpAgain = true;
      return;
    }
    _pumping = true;
    try {
      do {
        _pumpAgain = false;
        await _pumpOnce();
      } while (_pumpAgain);
    } finally {
      _pumping = false;
    }
  }

  Future<void> _pumpOnce() async {
    final now = _nowMs();
    await store.purgeSends(now - keepFor.inMilliseconds);
    final rows = await store.sends();
    var active = 0;
    for (final r in rows) {
      if (r.status != 'sending') continue;
      if (r.nextAt > 0 && r.nextAt <= now) {
        // No answer from the transfer engine: try again.
        r
          ..status = 'ready'
          ..tries = r.tries + 1
          ..nextAt = now + _backoff(r.tries);
        await store.updateSend(r);
        continue;
      }
      active++;
    }
    final due = rows
        .where((r) => r.status == 'ready' && r.nextAt <= now)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (due.isEmpty || active >= maxActive) return;
    try {
      await beforeSend?.call();
    } catch (_) {}
    for (final r in due) {
      if (active >= maxActive) break;
      final file = await source(r.msgId, r.fileId);
      if (file != null && file.size > smallFileBytes && _low()) {
        r.nextAt = now + 300 * 1000;
        await store.updateSend(r);
        continue;
      }
      if (file == null) {
        // My own copy is gone: nothing to send (server only now).
        r.status = 'old';
        await store.updateSend(r);
        AppLogger.warning('GROUP_FILE_SOURCE_GONE', detail: 'msg=${_id6(r.msgId)}');
        continue;
      }
      r
        ..status = 'sending'
        ..nextAt = now + sendingTimeout.inMilliseconds;
      await store.updateSend(r);
      active++;
      try {
        await sendFile(
            memberId: r.memberId, messageId: r.msgId, wireId: r.wireId, file: file);
      } catch (error) {
        r
          ..status = 'ready'
          ..tries = r.tries + 1
          ..nextAt = now + _backoff(r.tries);
        await store.updateSend(r);
        active--;
        AppLogger.info('GROUP_FILE_WAIT',
            detail: 'to=${_id6(r.memberId)} try=${r.tries} why=$error');
      }
    }
  }

  bool _low() {
    try {
      return lowBattery?.call() ?? false;
    } catch (_) {
      return false;
    }
  }

  int _backoff(int tries) {
    final i = (tries - 1).clamp(0, _backoffSeconds.length - 1);
    return _backoffSeconds[i] * 1000;
  }

  static String _id6(String id) =>
      id.length <= 6 ? id : id.substring(id.length - 6);
}

// ------------------------------------------------------------ receiver

/// Bundle G7: a group file coming to me Nearby. When nothing moves for
/// [stall] the bubble shows "Tap to download" (asks the sender again).
class GroupFileWatch {
  GroupFileWatch({
    this.stall = const Duration(minutes: 3),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration stall;
  final DateTime Function() _clock;

  /// message id -> last time bytes moved (or the message came).
  final Map<String, DateTime> _seen = <String, DateTime>{};
  Timer? _timer;

  bool watching(String messageId) => _seen.containsKey(messageId);

  void expect(String messageId) {
    if (messageId.isEmpty) return;
    _seen[messageId] = _clock();
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => check());
  }

  void moved(String messageId) {
    if (!_seen.containsKey(messageId)) return;
    _seen[messageId] = _clock();
    MediaTransferActions.instance.clearCancelled(messageId);
  }

  void done(String messageId) {
    _seen.remove(messageId);
    MediaTransferActions.instance.clearCancelled(messageId);
    if (_seen.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Native events (receiver side). Returns true when it was ours.
  bool handleEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    final id = event['message_id']?.toString() ?? '';
    if (id.isEmpty || !_seen.containsKey(id)) return false;
    if (type == 'file_progress') {
      moved(id);
      return true;
    }
    if (type == 'file_expired' || type == 'file_cancelled') {
      // Bundle 208 (E7): the writer pressed X -> no auto ask.
      MediaTransferActions.instance
          .markCancelled(id, bySender: type == 'file_cancelled');
      return true;
    }
    return false;
  }

  void check() {
    final now = _clock();
    for (final e in _seen.entries) {
      if (now.difference(e.value) >= stall) {
        MediaTransferActions.instance.markCancelled(e.key);
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

// ------------------------------------------------------------ pair keys

/// Bundle G7: a file lock key for each group member who is not a friend
/// (friends already have link keys). Both phones get the same key:
/// HKDF-SHA256(X25519(my seal key, their seal key), "llgfk1|a|b").
class GroupPairFileKeys {
  GroupPairFileKeys({
    required this.selfId,
    required this.ownKey,
    required this.members,
    required this.push,
  });

  final String Function() selfId;
  final Future<SealKeyPair?> Function() ownKey;

  /// Every member of my Nearby groups -> their seal public key (32 bytes).
  final Future<Map<String, List<int>>> Function() members;

  /// {peer: {o: kid, p: kid, k: 64 hex}} to the phone's transfer engine.
  final Future<bool> Function(Map<String, Map<String, String>> keys) push;

  static final X25519 _x = X25519();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const Duration refreshGap = Duration(seconds: 30);

  String _pushed = '';
  DateTime? _lastRun;

  static String _hex(List<int> b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  /// The key id both phones use ("g" + 15 hex).
  static String kidOf(List<int> key) =>
      'g${sha256.convert(key).toString().substring(0, 15)}';

  static Future<List<int>> derive(
      SealKeyPair mine, List<int> theirs, String a, String b) async {
    final ids = [a, b]..sort();
    final shared = await _x.sharedSecretKey(
        keyPair: mine.pair,
        remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519));
    final out = await _hkdf.deriveKey(
        secretKey: shared,
        nonce: const <int>[],
        info: utf8.encode('llgfk1|${ids[0]}|${ids[1]}'));
    return out.extractBytes();
  }

  Future<Map<String, Map<String, String>>> build() async {
    final self = selfId();
    final mine = await ownKey();
    if (self.isEmpty || mine == null) return const {};
    final out = <String, Map<String, String>>{};
    final all = await members();
    for (final e in all.entries) {
      if (e.key == self || e.value.length != 32) continue;
      try {
        final key = await derive(mine, e.value, self, e.key);
        final kid = kidOf(key);
        out[e.key] = {'o': kid, 'p': kid, 'k': _hex(key)};
      } catch (_) {}
      if (out.length >= 256) break;
    }
    return out;
  }

  /// Pushes the keys when they changed (at most every [refreshGap] unless
  /// [force]).
  Future<void> refresh({bool force = false}) async {
    final now = DateTime.now();
    final last = _lastRun;
    if (!force && last != null && now.difference(last) < refreshGap) return;
    _lastRun = now;
    try {
      final map = await build();
      final signature = jsonEncode(map);
      if (signature == _pushed) return;
      if (!await push(map)) return;
      _pushed = signature;
      AppLogger.info('GROUP_FILE_KEYS', detail: 'peers=${map.length}');
    } catch (error) {
      AppLogger.warning('GROUP_FILE_KEYS', detail: 'failed error=$error');
    }
  }
}
