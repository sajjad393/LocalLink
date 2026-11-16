import 'dart:convert';
import 'dart:typed_data';

import 'package:locallink/features/admin/data/actions/kept_copy_318.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Bundle 318 (K1): kept copies in the phone's locked database (the same
/// SQLCipher DB as the hidden tables). Big values are split in pieces so
/// no row is near Android's 2 MB cursor window.
/// New tables only (CREATE TABLE IF NOT EXISTS): the DB version stays.
class SqlKeptStore318 implements KeptStore318 {
  SqlKeptStore318(this.db);

  final Database Function() db;
  bool _ready = false;

  /// Characters of message JSON per row.
  static const int textPiece = 256 * 1024;

  /// File bytes per row.
  static const int filePiece = 512 * 1024;

  Future<void> _ensure() async {
    if (_ready) return;
    final d = db();
    await d.execute('CREATE TABLE IF NOT EXISTS kept_copies_318 (id TEXT PRIMARY KEY, meta TEXT NOT NULL)');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS kept_text_318 (id TEXT NOT NULL, n INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY(id, n))');
    await d.execute('CREATE TABLE IF NOT EXISTS kept_files_318 '
        '(file_id TEXT PRIMARY KEY, copy_id TEXT NOT NULL, size INTEGER NOT NULL, at TEXT NOT NULL)');
    await d.execute('CREATE TABLE IF NOT EXISTS kept_file_data_318 '
        '(file_id TEXT NOT NULL, n INTEGER NOT NULL, data BLOB NOT NULL, PRIMARY KEY(file_id, n))');
    _ready = true;
  }

  @override
  Future<List<KeptCopy318>> metas() async {
    await _ensure();
    final out = <KeptCopy318>[];
    for (final r in await db().query('kept_copies_318')) {
      try {
        if (KeptCopy318.fromMeta(jsonDecode(r['meta']?.toString() ?? '')) case final c?) out.add(c);
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<KeptCopy318?> copy(String id) async {
    await _ensure();
    final rows = await db().query('kept_copies_318', where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final text = StringBuffer();
    for (final r in await db().query('kept_text_318', where: 'id=?', whereArgs: [id], orderBy: 'n')) {
      text.write(r['body']?.toString() ?? '');
    }
    try {
      final list = text.isEmpty ? const [] : jsonDecode(text.toString());
      final msgs = <Map<String, dynamic>>[
        for (final m in (list is List ? list : const [])) if (m is Map) Map<String, dynamic>.from(m),
      ];
      return KeptCopy318.fromMeta(jsonDecode(rows.first['meta']?.toString() ?? ''), messages: msgs);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(KeptCopy318 c) async {
    await _ensure();
    final text = jsonEncode(c.messages);
    await db().transaction((t) async {
      await t.insert('kept_copies_318', {'id': c.id, 'meta': jsonEncode(c.metaJson())},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await t.delete('kept_text_318', where: 'id=?', whereArgs: [c.id]);
      for (var i = 0, n = 0; i < text.length; i += textPiece, n++) {
        final end = i + textPiece < text.length ? i + textPiece : text.length;
        await t.insert('kept_text_318', {'id': c.id, 'n': n, 'body': text.substring(i, end)});
      }
    });
  }

  @override
  Future<void> remove(String id) async {
    await _ensure();
    await db().transaction((t) async {
      await t.delete('kept_copies_318', where: 'id=?', whereArgs: [id]);
      await t.delete('kept_text_318', where: 'id=?', whereArgs: [id]);
      final files = await t.query('kept_files_318', columns: ['file_id'], where: 'copy_id=?', whereArgs: [id]);
      for (final f in files) {
        await t.delete('kept_file_data_318', where: 'file_id=?', whereArgs: [f['file_id']]);
      }
      await t.delete('kept_files_318', where: 'copy_id=?', whereArgs: [id]);
    });
  }

  @override
  Future<Uint8List?> file(String fileId) async {
    await _ensure();
    final head = await db().query('kept_files_318', where: 'file_id=?', whereArgs: [fileId], limit: 1);
    if (head.isEmpty) return null;
    final out = BytesBuilder(copy: false);
    for (final r in await db().query('kept_file_data_318', where: 'file_id=?', whereArgs: [fileId], orderBy: 'n')) {
      final d = r['data'];
      if (d is Uint8List) {
        out.add(d);
      } else if (d is List<int>) {
        out.add(Uint8List.fromList(d));
      }
    }
    final bytes = out.takeBytes();
    final size = head.first['size'];
    return bytes.length == (size is int ? size : -1) ? bytes : null;
  }

  @override
  Future<void> putFile(String fileId, String copyId, Uint8List bytes, String at) async {
    await _ensure();
    await db().transaction((t) async {
      await t.delete('kept_file_data_318', where: 'file_id=?', whereArgs: [fileId]);
      for (var i = 0, n = 0; i < bytes.length; i += filePiece, n++) {
        final end = i + filePiece < bytes.length ? i + filePiece : bytes.length;
        await t.insert('kept_file_data_318', {'file_id': fileId, 'n': n, 'data': Uint8List.sublistView(bytes, i, end)});
      }
      await t.insert('kept_files_318', {'file_id': fileId, 'copy_id': copyId, 'size': bytes.length, 'at': at},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<List<({String fileId, String copyId, int size, String at})>> files() async {
    await _ensure();
    return [
      for (final r in await db().query('kept_files_318'))
        (
          fileId: r['file_id']?.toString() ?? '',
          copyId: r['copy_id']?.toString() ?? '',
          size: r['size'] is int ? r['size'] as int : 0,
          at: r['at']?.toString() ?? '',
        ),
    ];
  }

  @override
  Future<void> moveFiles(String fromCopy, String toCopy) async {
    await _ensure();
    await db().update('kept_files_318', {'copy_id': toCopy}, where: 'copy_id=?', whereArgs: [fromCopy]);
  }

  @override
  Future<void> removeFile(String fileId) async {
    await _ensure();
    await db().transaction((t) async {
      await t.delete('kept_file_data_318', where: 'file_id=?', whereArgs: [fileId]);
      await t.delete('kept_files_318', where: 'file_id=?', whereArgs: [fileId]);
    });
  }
}
