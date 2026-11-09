import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/security/sensitive_file_protection_service.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/delete_completely_doer.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/groups/data/group_sender_keys.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Bundle 221: user deletes are SOFT. Delete for me / for everyone / Clear
/// chat / Exit group / Delete group look exactly the same as before for the
/// user, but the rows are copied to hidden tables first and the full file +
/// thumbnail stay on disk. Only Get chat (Owner) and Delete completely read
/// these tables; every normal read of the app is unchanged.
///
/// Hidden text is kept forever; hidden full files go after 60 days
/// (thumbnails stay). New tables only, CREATE TABLE IF NOT EXISTS, so the
/// DB version stays 34 (like 220).
class Hidden221 {
  Hidden221(this._db);

  final Database Function() _db;
  bool _ready = false;

  Database get db => _db();

  /// Ids being deleted completely right now: no hidden copy, files go.
  final Set<String> purging = <String>{};

  static String _now() => DateTime.now().toUtc().toIso8601String();

  Future<void> ensure() async {
    if (_ready) return;
    final db = _db();
    await db.execute('''CREATE TABLE IF NOT EXISTS hidden_messages (
      id TEXT PRIMARY KEY, sender_id TEXT NOT NULL DEFAULT '', recipient_id TEXT NOT NULL DEFAULT '',
      body TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT '',
      channel TEXT NOT NULL DEFAULT '', hidden_at TEXT NOT NULL DEFAULT '', hidden_how TEXT NOT NULL DEFAULT 'me'
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_hidden_messages_pair ON hidden_messages(sender_id, recipient_id)');
    await db.execute('''CREATE TABLE IF NOT EXISTS hidden_group_messages (
      id TEXT PRIMARY KEY, group_id TEXT NOT NULL DEFAULT '', sender_id TEXT NOT NULL DEFAULT '',
      body TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '',
      hidden_at TEXT NOT NULL DEFAULT '', hidden_how TEXT NOT NULL DEFAULT 'me'
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_hidden_group_messages_group ON hidden_group_messages(group_id)');
    await db.execute('''CREATE TABLE IF NOT EXISTS hidden_attachments (
      message_id TEXT NOT NULL, kind TEXT NOT NULL, file_id TEXT NOT NULL,
      name TEXT NOT NULL DEFAULT '', mime TEXT NOT NULL DEFAULT '', size INTEGER NOT NULL DEFAULT 0,
      local_path TEXT NOT NULL DEFAULT '', thumb_path TEXT NOT NULL DEFAULT '',
      file_gone_at TEXT NOT NULL DEFAULT '',
      PRIMARY KEY(message_id, kind, file_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS hidden_reactions (
      message_id TEXT NOT NULL, kind TEXT NOT NULL, reactor TEXT NOT NULL,
      emoji TEXT NOT NULL DEFAULT '', at TEXT NOT NULL DEFAULT '',
      PRIMARY KEY(message_id, kind, reactor)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS hidden_files (
      path TEXT PRIMARY KEY, file_id TEXT NOT NULL DEFAULT '', message_id TEXT NOT NULL DEFAULT '',
      is_thumb INTEGER NOT NULL DEFAULT 0, kept_at TEXT NOT NULL DEFAULT ''
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS hidden_groups (
      group_id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '', members TEXT NOT NULL DEFAULT '',
      at TEXT NOT NULL DEFAULT ''
    )''');
    await db.execute(
        "CREATE TABLE IF NOT EXISTS purged_ids (id TEXT PRIMARY KEY, at TEXT NOT NULL DEFAULT '')");
    await db.execute('''CREATE TABLE IF NOT EXISTS answer_parts (
      answer_id TEXT NOT NULL, part INTEGER NOT NULL, of INTEGER NOT NULL, action_id TEXT NOT NULL,
      device TEXT NOT NULL, reply_to TEXT NOT NULL DEFAULT '', is_file INTEGER NOT NULL DEFAULT 0,
      body TEXT NOT NULL, sig TEXT NOT NULL, own INTEGER NOT NULL DEFAULT 0, at TEXT NOT NULL DEFAULT '',
      PRIMARY KEY(answer_id, part)
    )''');
    await db.execute(
        "CREATE TABLE IF NOT EXISTS answer_stops (answer_id TEXT PRIMARY KEY, action_id TEXT NOT NULL DEFAULT '', at TEXT NOT NULL DEFAULT '')");
    await db.execute('''CREATE TABLE IF NOT EXISTS answer_acks (
      answer_id TEXT PRIMARY KEY, action_id TEXT NOT NULL DEFAULT '', raw TEXT NOT NULL, at TEXT NOT NULL DEFAULT ''
    )''');
    _ready = true;
  }

  // ------------------------------------------------------------ soft delete

  /// Before a direct message row goes: copy it (+ files, reactions).
  Future<void> copyDirect(String id, {String how = 'me'}) async {
    if (id.isEmpty || purging.contains(id)) return;
    try {
      await ensure();
      final db = _db();
      final rows = await db.query('messages', where: 'id=?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return;
      final r = rows.first;
      final body = r['body']?.toString() ?? '';
      if (MessageEnvelope.isControl(body)) return;
      final at = _now();
      await db.insert(
          'hidden_messages',
          {
            'id': id,
            'sender_id': r['sender_id'] ?? '',
            'recipient_id': r['recipient_id'] ?? '',
            'body': body,
            'created_at': r['created_at'] ?? '',
            'status': r['status'] ?? '',
            'channel': r['channel'] ?? '',
            'hidden_at': at,
            'hidden_how': how,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await _copyFiles(db, 'message_attachments', 'message_id', id, 'direct');
      await _copyReactions(db, 'message_reactions', id, 'direct', at);
    } catch (error) {
      AppLogger.warning('HIDE_COPY_FAIL', detail: 'kind=direct $error');
    }
  }

  /// Before a group message row goes (locked / control lines are skipped).
  Future<void> copyGroup(String id, {String how = 'me'}) async {
    if (id.isEmpty || purging.contains(id)) return;
    try {
      await ensure();
      final db = _db();
      final rows = await db.query('group_messages', where: 'id=?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return;
      await _copyGroupRow(db, rows.first, how, _now());
    } catch (error) {
      AppLogger.warning('HIDE_COPY_FAIL', detail: 'kind=group $error');
    }
  }

  /// Exit / delete group: every message of the group + names of members.
  Future<void> copyGroupAll(String groupId, {String how = 'group'}) async {
    if (groupId.isEmpty) return;
    try {
      await ensure();
      final db = _db();
      final at = _now();
      final g = await db.query('groups', where: 'id=?', whereArgs: [groupId], limit: 1);
      final members = await db.query('group_members',
          columns: ['device_id', 'name'], where: 'group_id=?', whereArgs: [groupId]);
      await db.insert(
          'hidden_groups',
          {
            'group_id': groupId,
            'name': g.isEmpty ? '' : g.first['name'] ?? '',
            'members': jsonEncode({
              for (final m in members) m['device_id']?.toString() ?? '': m['name']?.toString() ?? '',
            }),
            'at': at,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      final rows = await db.query('group_messages', where: 'group_id=?', whereArgs: [groupId]);
      for (final r in rows) {
        await _copyGroupRow(db, r, how, at);
      }
    } catch (error) {
      AppLogger.warning('HIDE_COPY_FAIL', detail: 'kind=group_all $error');
    }
  }

  Future<void> _copyGroupRow(Database db, Map<String, Object?> r, String how, String at) async {
    final id = r['id']?.toString() ?? '';
    final body = r['body']?.toString() ?? '';
    if (id.isEmpty || purging.contains(id)) return;
    if (MessageEnvelope.isControl(body) || GroupSenderKeys.isLocked(body)) return;
    if (GroupSenderKeys.isKeys(body) || GroupSenderKeys.isAsk(body)) return;
    await db.insert(
        'hidden_group_messages',
        {
          'id': id,
          'group_id': r['group_id'] ?? '',
          'sender_id': r['sender_id'] ?? '',
          'body': body,
          'created_at': r['created_at'] ?? '',
          'hidden_at': at,
          'hidden_how': how,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await _copyFiles(db, 'group_message_attachments', 'group_message_id', id, 'group');
    await _copyReactions(db, 'group_message_reactions', id, 'group', at);
  }

  Future<void> _copyFiles(Database db, String table, String key, String id, String kind) async {
    final atts = await db.query(table, where: '$key=?', whereArgs: [id]);
    for (final a in atts) {
      final fileId = a['file_id']?.toString() ?? '';
      if (fileId.isEmpty) continue;
      await db.insert(
          'hidden_attachments',
          {
            'message_id': id,
            'kind': kind,
            'file_id': fileId,
            'name': a['original_name'] ?? '',
            'mime': a['content_type'] ?? '',
            'size': a['size'] ?? 0,
            'local_path': a['local_path'] ?? '',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _copyReactions(Database db, String table, String id, String kind, String at) async {
    final rows = await db.query(table, where: 'message_id=?', whereArgs: [id]);
    for (final r in rows) {
      await db.insert(
          'hidden_reactions',
          {
            'message_id': id,
            'kind': kind,
            'reactor': r['reactor_id'] ?? '',
            'emoji': r['emoji'] ?? '',
            'at': r['created_at'] ?? at,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static bool _belongs(String path, Set<String> fileIds, Set<String> localPaths) {
    if (localPaths.contains(path)) return true;
    final name = p.basename(path);
    return fileIds.any((f) => f.isNotEmpty && name.startsWith(f));
  }

  /// The paths the caller would delete, minus the files of hidden messages
  /// (kept: full file 60 days, thumbnails forever).
  Future<List<String>> keepFiles(Iterable<String> ids, List<String> paths) async {
    if (paths.isEmpty) return paths;
    final keepIds = [for (final id in ids) if (!purging.contains(id)) id];
    if (keepIds.isEmpty) return paths;
    try {
      await ensure();
      final db = _db();
      final fileIds = <String>{};
      final local = <String>{};
      for (var i = 0; i < keepIds.length; i += 500) {
        final chunk = keepIds.sublist(i, (i + 500).clamp(0, keepIds.length));
        final rows = await db.query('hidden_attachments',
            columns: ['file_id', 'local_path', 'message_id'],
            where: 'message_id IN (${List.filled(chunk.length, '?').join(',')})',
            whereArgs: chunk);
        for (final r in rows) {
          fileIds.add(r['file_id']?.toString() ?? '');
          final lp = r['local_path']?.toString() ?? '';
          if (lp.isNotEmpty) local.add(lp);
        }
      }
      if (fileIds.isEmpty && local.isEmpty) return paths;
      final at = _now();
      final out = <String>[];
      for (final path in paths) {
        if (!_belongs(path, fileIds, local)) {
          out.add(path);
          continue;
        }
        final name = p.basename(path);
        await db.insert(
            'hidden_files',
            {
              'path': path,
              'file_id': fileIds.firstWhere((f) => f.isNotEmpty && name.startsWith(f), orElse: () => ''),
              'is_thumb': name.contains('-thumb') ? 1 : 0,
              'kept_at': at,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      return out;
    } catch (error) {
      AppLogger.warning('HIDE_KEEP_FAIL', detail: '$error');
      return paths;
    }
  }

  /// Exit / delete group: keep the files of every hidden message of it.
  Future<List<String>> keepGroupFiles(String groupId, List<String> paths) async {
    if (paths.isEmpty) return paths;
    try {
      await ensure();
      final rows = await _db().query('hidden_group_messages',
          columns: ['id'], where: 'group_id=?', whereArgs: [groupId]);
      return await keepFiles([for (final r in rows) r['id']?.toString() ?? ''], paths);
    } catch (_) {
      return paths;
    }
  }

  /// Daily: full files of messages hidden 60+ days ago go (thumbnails stay).
  Future<int> sweep({DateTime? now, Future<void> Function(String path)? deleteFile}) async {
    await ensure();
    final db = _db();
    final cut = (now ?? DateTime.now()).toUtc().subtract(ChatAnswerRules.hiddenFileDays).toIso8601String();
    final rows = await db.query('hidden_files',
        where: 'is_thumb=0 AND kept_at<>? AND kept_at<?', whereArgs: ['', cut]);
    var n = 0;
    for (final r in rows) {
      final path = r['path']?.toString() ?? '';
      for (final x in [path, if (!path.endsWith('.enc')) '$path.enc']) {
        try {
          if (deleteFile != null) {
            await deleteFile(x);
          } else if (await File(x).exists()) {
            await File(x).delete();
          }
        } catch (_) {}
      }
      final fileId = r['file_id']?.toString() ?? '';
      if (fileId.isNotEmpty) {
        await db.update('hidden_attachments', {'file_gone_at': _now()},
            where: 'file_id=? AND file_gone_at=?', whereArgs: [fileId, '']);
      }
      await db.delete('hidden_files', where: 'path=?', whereArgs: [path]);
      n++;
    }
    final purgeCut = (now ?? DateTime.now()).toUtc().subtract(const Duration(days: 60)).toIso8601String();
    await db.delete('purged_ids', where: 'at<?', whereArgs: [purgeCut]);
    if (n > 0) AppLogger.info('HIDE_SWEEP', detail: 'files=$n');
    return n;
  }

  // -------------------------------------------------------- delete completely

  Future<bool> isPurged(String id) async {
    if (id.isEmpty) return false;
    await ensure();
    final rows = await _db().query('purged_ids', where: 'id=?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> addPurged(Iterable<String> ids) async {
    await ensure();
    final at = _now();
    final batch = _db().batch();
    for (final id in ids) {
      if (id.isNotEmpty) {
        batch.insert('purged_ids', {'id': id, 'at': at}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  /// Hidden rows of [ids] go for real; returns the file paths to delete.
  Future<List<String>> removeHidden(List<String> ids, {required bool group}) async {
    if (ids.isEmpty) return const [];
    await ensure();
    final db = _db();
    final paths = <String>{};
    final kind = group ? 'group' : 'direct';
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, (i + 500).clamp(0, ids.length));
      final q = List.filled(chunk.length, '?').join(',');
      final atts = await db.query('hidden_attachments',
          where: 'kind=? AND message_id IN ($q)', whereArgs: [kind, ...chunk]);
      final fileIds = <String>{};
      for (final a in atts) {
        final lp = a['local_path']?.toString() ?? '';
        if (lp.isNotEmpty) paths.add(lp);
        fileIds.add(a['file_id']?.toString() ?? '');
      }
      fileIds.remove('');
      final kept = await db.query('hidden_files',
          where: 'message_id IN ($q) OR file_id IN (${List.filled(fileIds.isEmpty ? 1 : fileIds.length, '?').join(',')})',
          whereArgs: [...chunk, ...(fileIds.isEmpty ? const [''] : fileIds.toList())]);
      for (final k in kept) {
        paths.add(k['path']?.toString() ?? '');
      }
      paths.addAll(await thumbPathsOf(fileIds));
      await db.delete('hidden_files',
          where: 'path IN (${List.filled(kept.isEmpty ? 1 : kept.length, '?').join(',')})',
          whereArgs: kept.isEmpty ? [''] : [for (final k in kept) k['path']]);
      await db.delete('hidden_attachments', where: 'kind=? AND message_id IN ($q)', whereArgs: [kind, ...chunk]);
      await db.delete('hidden_reactions', where: 'kind=? AND message_id IN ($q)', whereArgs: [kind, ...chunk]);
      await db.delete(group ? 'hidden_group_messages' : 'hidden_messages',
          where: 'id IN ($q)', whereArgs: chunk);
    }
    paths.remove('');
    return paths.toList();
  }

  /// `-thumb` files of these file ids in the attachments folder.
  static Future<List<String>> thumbPathsOf(Iterable<String> fileIds) async {
    final ids = fileIds.where((f) => RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(f)).toSet();
    if (ids.isEmpty) return const [];
    try {
      final dir = Directory(p.join(await getDatabasesPath(), 'attachments'));
      if (!await dir.exists()) return const [];
      final out = <String>[];
      await for (final e in dir.list(followLinks: false)) {
        final name = p.basename(e.path);
        if (ids.any((f) => name.startsWith('$f-thumb'))) out.add(e.path);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

/// The chat rows Get chat reads (live + hidden).
class SqlChatRows221 implements ChatRows221 {
  SqlChatRows221({
    required this.hidden,
    required this.db,
    required this.name,
    SensitiveFileProtectionService? files,
  }) : _files = files;

  final Hidden221 hidden;
  final Database Function() db;
  final Future<String> Function(String deviceId) name;
  SensitiveFileProtectionService? _files;
  SensitiveFileProtectionService get files => _files ??= SensitiveFileProtectionService();

  static List<List<T>> _chunks<T>(List<T> list) => [
        for (var i = 0; i < list.length; i += 500) list.sublist(i, (i + 500).clamp(0, list.length)),
      ];

  @override
  Future<List<ChatRow221>> rows(ChatRef221 chat) async {
    await hidden.ensure();
    final d = db();
    final live = <Map<String, Object?>>[];
    final hid = <Map<String, Object?>>[];
    if (chat.isGroup) {
      live.addAll(await d.query('group_messages', where: 'group_id=?', whereArgs: [chat.groupId]));
      hid.addAll(await d.query('hidden_group_messages', where: 'group_id=?', whereArgs: [chat.groupId]));
    } else {
      final devs = chat.devices.toSet().toList();
      final q = List.filled(devs.length, '?').join(',');
      final where = 'sender_id IN ($q) AND recipient_id IN ($q) AND sender_id<>recipient_id';
      live.addAll(await d.query('messages', where: where, whereArgs: [...devs, ...devs]));
      hid.addAll(await d.query('hidden_messages', where: where, whereArgs: [...devs, ...devs]));
    }
    final kind = chat.isGroup ? 'group' : 'direct';
    final liveIds = [for (final r in live) r['id']?.toString() ?? ''];
    final hidIds = [for (final r in hid) r['id']?.toString() ?? ''];
    final atts = <String, List<ChatAtt221>>{};
    final reacts = <String, List<Map<String, String>>>{};
    String s(Map<String, Object?> r, String k) => r[k]?.toString() ?? '';
    int n(Map<String, Object?> r, String k) => r[k] is int ? r[k] as int : int.tryParse(s(r, k)) ?? 0;
    for (final c in _chunks(liveIds)) {
      final q = List.filled(c.length, '?').join(',');
      final key = chat.isGroup ? 'group_message_id' : 'message_id';
      for (final a in await d.query(chat.isGroup ? 'group_message_attachments' : 'message_attachments',
          where: '$key IN ($q)', whereArgs: c, orderBy: 'position')) {
        (atts[s(a, key)] ??= <ChatAtt221>[]).add(ChatAtt221(
            messageId: s(a, key),
            fileId: s(a, 'file_id'),
            name: s(a, 'original_name'),
            type: s(a, 'content_type'),
            size: n(a, 'size'),
            localPath: s(a, 'local_path')));
      }
      for (final r in await d.query(chat.isGroup ? 'group_message_reactions' : 'message_reactions',
          where: 'message_id IN ($q)', whereArgs: c)) {
        (reacts[s(r, 'message_id')] ??= <Map<String, String>>[])
            .add({'by': s(r, 'reactor_id'), 'emoji': s(r, 'emoji')});
      }
    }
    final hidAtts = <String, List<ChatAtt221>>{};
    final hidReacts = <String, List<Map<String, String>>>{};
    for (final c in _chunks(hidIds)) {
      final q = List.filled(c.length, '?').join(',');
      for (final a in await d.query('hidden_attachments',
          where: 'kind=? AND message_id IN ($q)', whereArgs: [kind, ...c])) {
        (hidAtts[s(a, 'message_id')] ??= <ChatAtt221>[]).add(ChatAtt221(
            messageId: s(a, 'message_id'),
            fileId: s(a, 'file_id'),
            name: s(a, 'name'),
            type: s(a, 'mime'),
            size: n(a, 'size'),
            localPath: s(a, 'local_path'),
            goneAt: s(a, 'file_gone_at')));
      }
      for (final r in await d.query('hidden_reactions',
          where: 'kind=? AND message_id IN ($q)', whereArgs: [kind, ...c])) {
        (hidReacts[s(r, 'message_id')] ??= <Map<String, String>>[])
            .add({'by': s(r, 'reactor'), 'emoji': s(r, 'emoji')});
      }
    }
    final out = <ChatRow221>[];
    for (final r in live) {
      final body = s(r, 'body');
      if (chat.isGroup && (GroupSenderKeys.isLocked(body) || GroupSenderKeys.isKeys(body) || GroupSenderKeys.isAsk(body))) {
        continue;
      }
      out.add(ChatRow221(
          id: s(r, 'id'),
          sender: s(r, 'sender_id'),
          body: body,
          createdAt: s(r, 'created_at'),
          status: chat.isGroup ? '' : s(r, 'status'),
          route: chat.isGroup ? '' : s(r, 'channel'),
          atts: atts[s(r, 'id')] ?? const [],
          reactions: reacts[s(r, 'id')] ?? const []));
    }
    for (final r in hid) {
      out.add(ChatRow221(
          id: s(r, 'id'),
          sender: s(r, 'sender_id'),
          body: s(r, 'body'),
          createdAt: s(r, 'created_at'),
          status: s(r, 'status'),
          route: s(r, 'channel'),
          hiddenAt: s(r, 'hidden_at').isEmpty ? '-' : s(r, 'hidden_at'),
          hiddenHow: s(r, 'hidden_how'),
          atts: hidAtts[s(r, 'id')] ?? const [],
          reactions: hidReacts[s(r, 'id')] ?? const []));
    }
    return out;
  }

  @override
  Future<String> nameOf(String deviceId) async {
    final n = await name(deviceId).catchError((_) => '');
    if (n.isNotEmpty) return n;
    final d = db();
    final m = await d.query('group_members',
        columns: ['name'], where: 'device_id=? AND name<>?', whereArgs: [deviceId, ''], limit: 1);
    if (m.isNotEmpty) return m.first['name']?.toString() ?? '';
    for (final g in await d.query('hidden_groups', columns: ['members'])) {
      try {
        final map = jsonDecode(g['members']?.toString() ?? '');
        if (map is Map && (map[deviceId]?.toString() ?? '').isNotEmpty) return map[deviceId].toString();
      } catch (_) {}
    }
    return '';
  }

  Future<Uint8List?> _plain(String path) async {
    if (path.isEmpty) return null;
    final enc = path.endsWith('.enc') ? path : '$path.enc';
    if (await File(enc).exists()) {
      final view = await files.materializeForView(enc, extension: p.extension(path.replaceAll('.enc', '')));
      try {
        return await File(view).readAsBytes();
      } finally {
        try {
          await File(view).delete();
        } catch (_) {}
      }
    }
    if (await File(path).exists()) return File(path).readAsBytes();
    return null;
  }

  /// Shrinks a picture to a small PNG (≤ 8 KB) with the engine's decoder.
  static Future<Uint8List?> shrink(Uint8List bytes) async {
    for (final w in const [96, 72, 56]) {
      try {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: w);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        codec.dispose();
        if (data == null) return null;
        final out = data.buffer.asUint8List();
        if (out.length <= ChatAnswerRules.thumbBytes) return out;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  Future<({Uint8List bytes, String type})?> thumbOf(ChatAtt221 att) async {
    final t = att.type.toLowerCase();
    if (!t.startsWith('image/') && !t.startsWith('video/')) return null;
    for (final path in await Hidden221.thumbPathsOf([att.fileId])) {
      if (path.endsWith('.part')) continue;
      final bytes = await _plain(path).catchError((_) => null);
      if (bytes == null || bytes.isEmpty) continue;
      if (bytes.length <= ChatAnswerRules.thumbBytes) {
        final png = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
        return (bytes: bytes, type: png ? 'image/png' : 'image/jpeg');
      }
      final small = await shrink(bytes);
      if (small != null) return (bytes: small, type: 'image/png');
    }
    if (t.startsWith('image/') && att.goneAt.isEmpty && att.size <= 15 * 1024 * 1024) {
      final bytes = await _plain(att.localPath).catchError((_) => null);
      if (bytes != null) {
        final small = await shrink(bytes);
        if (small != null) return (bytes: small, type: 'image/png');
      }
    }
    return null;
  }

  @override
  Future<ChatAtt221?> fileOf(String fileId, String messageId) async {
    if (fileId.isEmpty) return null;
    await hidden.ensure();
    final d = db();
    String s(Map<String, Object?> r, String k) => r[k]?.toString() ?? '';
    int n(Map<String, Object?> r, String k) => r[k] is int ? r[k] as int : int.tryParse(s(r, k)) ?? 0;
    for (final (table, key) in const [
      ('message_attachments', 'message_id'),
      ('group_message_attachments', 'group_message_id'),
    ]) {
      final rows = await d.query(table, where: 'file_id=?', whereArgs: [fileId], limit: 1);
      if (rows.isNotEmpty) {
        final a = rows.first;
        return ChatAtt221(
            messageId: s(a, key),
            fileId: fileId,
            name: s(a, 'original_name'),
            type: s(a, 'content_type'),
            size: n(a, 'size'),
            localPath: s(a, 'local_path'));
      }
    }
    final rows = await d.query('hidden_attachments', where: 'file_id=?', whereArgs: [fileId], limit: 1);
    if (rows.isEmpty) return null;
    final a = rows.first;
    return ChatAtt221(
        messageId: s(a, 'message_id'),
        fileId: fileId,
        name: s(a, 'name'),
        type: s(a, 'mime'),
        size: n(a, 'size'),
        localPath: s(a, 'local_path'),
        goneAt: s(a, 'file_gone_at'));
  }

  @override
  Future<Uint8List?> readFile(ChatAtt221 att) => _plain(att.localPath);
}

/// Answer parts / acks / stops on the phone.
class SqlAnswerPartStore implements AnswerPartStore {
  SqlAnswerPartStore(this.hidden, this.db);

  final Hidden221 hidden;
  final Database Function() db;

  HeldPart? _row(Map<String, Object?> r) => HeldPart.fromBlob(
      SignedBlob(body: r['body']?.toString() ?? '', sig: r['sig']?.toString() ?? ''),
      own: r['own'] == 1,
      at: r['at']?.toString() ?? '');

  @override
  Future<bool> put(HeldPart x) async {
    await hidden.ensure();
    final id = await db().insert(
        'answer_parts',
        {
          'answer_id': x.answerId,
          'part': x.part,
          'of': x.of,
          'action_id': x.actionId,
          'device': x.device,
          'reply_to': x.replyTo,
          'is_file': x.isFile ? 1 : 0,
          'body': x.blob.body,
          'sig': x.blob.sig,
          'own': x.own ? 1 : 0,
          'at': x.at,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return id > 0;
  }

  @override
  Future<List<HeldPart>> parts({String? answerId}) async {
    await hidden.ensure();
    final rows = answerId == null
        ? await db().query('answer_parts')
        : await db().query('answer_parts', where: 'answer_id=?', whereArgs: [answerId]);
    return [for (final r in rows) if (_row(r) case final HeldPart h) h];
  }

  @override
  Future<void> remove(String answerId, Iterable<int> parts) async {
    final list = parts.toList();
    if (list.isEmpty) return;
    await hidden.ensure();
    await db().delete('answer_parts',
        where: 'answer_id=? AND part IN (${List.filled(list.length, '?').join(',')})',
        whereArgs: [answerId, ...list]);
  }

  @override
  Future<void> dropAnswer(String answerId, {String keepFor = ''}) async {
    await hidden.ensure();
    if (keepFor.isEmpty) {
      await db().delete('answer_parts', where: 'answer_id=?', whereArgs: [answerId]);
    } else {
      await db().delete('answer_parts',
          where: 'answer_id=? AND reply_to<>?', whereArgs: [answerId, keepFor]);
    }
  }

  @override
  Future<void> stop(String answerId, String actionId, String at) async {
    await hidden.ensure();
    await db().insert('answer_stops', {'answer_id': answerId, 'action_id': actionId, 'at': at},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<Set<String>> stops() async {
    await hidden.ensure();
    return {for (final r in await db().query('answer_stops', columns: ['answer_id'])) r['answer_id'].toString()};
  }

  @override
  Future<void> saveAck(AnswerAck ack) async {
    await hidden.ensure();
    await db().insert(
        'answer_acks',
        {
          'answer_id': ack.answerId,
          'action_id': ack.actionId,
          'raw': jsonEncode({
            ...ack.raw,
            'checked': {
              'have': PartRanges.write(ack.have),
              'of': ack.of,
              'all': ack.all,
              'at': ack.at,
            },
          }),
          'at': ack.at,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<Map<String, AnswerAck>> acks() async {
    await hidden.ensure();
    final out = <String, AnswerAck>{};
    for (final r in await db().query('answer_acks')) {
      try {
        final raw = Map<String, dynamic>.from(jsonDecode(r['raw'].toString()) as Map);
        final c = Map<String, dynamic>.from(raw.remove('checked') as Map);
        final id = r['answer_id'].toString();
        out[id] = AnswerAck(
          answerId: id,
          actionId: r['action_id']?.toString() ?? '',
          have: PartRanges.read(c['have']?.toString() ?? ''),
          of: c['of'] is int ? c['of'] as int : 0,
          all: c['all'] == true,
          at: c['at']?.toString() ?? '',
          raw: raw,
        );
      } catch (_) {}
    }
    return out;
  }
}

/// Delete completely on this phone (the existing deletes for live rows,
/// with no hidden copy; hidden rows go for real here).
class SqlPurgeTarget221 implements PurgeTarget221 {
  SqlPurgeTarget221({
    required this.hidden,
    required this.source,
    required this.deleteDirect,
    required this.deleteGroup,
    required this.deleteFileFn,
    required this.notify,
  });

  final Hidden221 hidden;
  final ChatRows221 source;
  final Future<List<String>> Function(String id) deleteDirect;
  final Future<List<String>> Function(String id) deleteGroup;
  final Future<void> Function(String path) deleteFileFn;
  final Future<void> Function(String id) notify;

  @override
  Future<List<ChatRow221>> rows(ChatRef221 chat) => source.rows(chat);

  @override
  Future<List<String>> removeLive(String id, {required bool group}) =>
      group ? deleteGroup(id) : deleteDirect(id);

  @override
  Future<List<String>> removeHidden(List<String> ids, {required bool group}) =>
      hidden.removeHidden(ids, group: group);

  @override
  Future<void> deleteFile(String path) => deleteFileFn(path);

  @override
  Future<void> addPurged(Iterable<String> ids) => hidden.addPurged(ids);

  @override
  Future<bool> isPurged(String id) => hidden.isPurged(id);

  @override
  Future<void> notificationGone(String id) => notify(id);

  @override
  void purging(Iterable<String> ids, bool on) =>
      on ? hidden.purging.addAll(ids) : hidden.purging.removeAll(ids);
}

/// Offline lists for the Owner's Conversations screen (this phone's chats,
/// its people and groups). Same row shape as `GET /api/v1/admin/conversations`.
class LocalChats221 {
  LocalChats221({required this.db, required this.selfDeviceId, required this.selfUserId, required this.nameOf});

  final Database Function() db;
  final String Function() selfDeviceId;
  final String Function() selfUserId;
  final Future<String> Function(String deviceId) nameOf;

  Future<String> _userOf(String device) async {
    final rows = await db().query('directory_profiles',
        columns: ['user_id'], where: 'device_id=?', whereArgs: [device], limit: 1);
    return rows.isEmpty ? device : rows.first['user_id']?.toString() ?? device;
  }

  Future<List<Map<String, dynamic>>> chats() async {
    final self = selfDeviceId();
    final d = db();
    final out = <Map<String, dynamic>>[];
    if (self.isNotEmpty) {
      final rows = await d.rawQuery(
          'SELECT CASE WHEN sender_id=? THEN recipient_id ELSE sender_id END AS peer, '
          'COUNT(*) AS n, MAX(created_at) AS last FROM messages '
          'WHERE sender_id=? OR recipient_id=? GROUP BY peer ORDER BY last DESC LIMIT 300',
          [self, self, self]);
      final me = await nameOf(self).catchError((_) => '');
      for (final r in rows) {
        final peer = r['peer']?.toString() ?? '';
        if (peer.isEmpty || peer == self) continue;
        out.add({
          'id': 'd:$peer',
          'kind': 'direct',
          'participants': [
            {'id': selfUserId().isEmpty ? self : selfUserId(), 'name': me.isEmpty ? 'Me' : me},
            {'id': await _userOf(peer), 'name': await nameOf(peer).catchError((_) => '')},
          ],
          'message_count': r['n'] ?? 0,
          'last_message_at': r['last']?.toString() ?? '',
        });
      }
    }
    for (final g in await groups()) {
      out.add({
        'id': 'g:${g['id']}',
        'kind': 'group',
        'group_id': g['id'],
        'group_name': g['name'],
        'member_count': g['members'],
        'message_count': g['count'],
        'last_message_at': g['last'],
      });
    }
    out.sort((a, b) => '${b['last_message_at']}'.compareTo('${a['last_message_at']}'));
    return out;
  }

  Future<List<Map<String, dynamic>>> groups() async {
    final rows = await db().rawQuery(
        'SELECT g.id AS id, g.name AS name, '
        '(SELECT COUNT(*) FROM group_members m WHERE m.group_id=g.id) AS members, '
        '(SELECT COUNT(*) FROM group_messages x WHERE x.group_id=g.id) AS count, '
        '(SELECT MAX(created_at) FROM group_messages x WHERE x.group_id=g.id) AS last '
        'FROM groups g ORDER BY name COLLATE NOCASE');
    return [
      for (final r in rows)
        {
          'id': r['id']?.toString() ?? '',
          'name': r['name']?.toString() ?? '',
          'members': r['members'] ?? 0,
          'count': r['count'] ?? 0,
          'last': r['last']?.toString() ?? '',
        },
    ];
  }

  /// People this phone knows (directory), for the request sheet.
  Future<List<Map<String, dynamic>>> people() async {
    final rows = await db().query('directory_profiles',
        columns: ['user_id', 'device_id', 'username', 'display_name', 'updated_at'],
        orderBy: 'display_name COLLATE NOCASE',
        limit: 2000);
    final self = selfUserId();
    // Bundle 254 (21.2): "Me" on top; device + @username on every row; when
    // two accounts share one phone the older one is marked "old account".
    final out = <Map<String, dynamic>>[
      {
        'id': self.isEmpty ? selfDeviceId() : self,
        'name': await nameOf(selfDeviceId()).catchError((_) => 'Me'),
        'username': '',
        'device': selfDeviceId(),
        'me': true,
      },
    ];
    final newestOnPhone = <String, String>{}; // device -> newest updated_at
    for (final r in rows) {
      final d = r['device_id']?.toString() ?? '';
      final at = r['updated_at']?.toString() ?? '';
      if (d.isEmpty) continue;
      final cur = newestOnPhone[d];
      if (cur == null || at.compareTo(cur) > 0) newestOnPhone[d] = at;
    }
    final perPhone = <String, int>{};
    for (final r in rows) {
      final d = r['device_id']?.toString() ?? '';
      if (d.isNotEmpty) perPhone[d] = (perPhone[d] ?? 0) + 1;
    }
    for (final r in rows) {
      final id = r['user_id']?.toString() ?? '';
      if (id.isEmpty || id == self) continue;
      final dn = r['display_name']?.toString() ?? '';
      final un = r['username']?.toString() ?? '';
      final d = r['device_id']?.toString() ?? '';
      final at = r['updated_at']?.toString() ?? '';
      final old = d.isNotEmpty && (perPhone[d] ?? 0) > 1 && at.compareTo(newestOnPhone[d] ?? '') < 0;
      out.add({
        'id': id,
        'name': dn.isNotEmpty ? dn : un,
        'username': un,
        'device': d,
        if (old) 'old': true,
      });
    }
    return out;
  }

  Future<List<String>> groupDevices(String groupId) async => [
        for (final r in await db().query('group_members',
            columns: ['device_id'], where: 'group_id=?', whereArgs: [groupId]))
          if ((r['device_id']?.toString() ?? '').isNotEmpty) r['device_id'].toString(),
      ];
}
