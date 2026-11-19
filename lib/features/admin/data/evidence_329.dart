import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Bundle 329: export evidence.
///
/// A plain record of what THIS phone did - asks it made, answers it gave, and
/// the owner's answers to the 326 consent cards - written so that any later
/// edit shows up. Each line carries the hash of the line before it, so if a
/// single word is changed, [verify] says which line broke.
///
/// **No server, no internet, nothing expires.** The file is made on the phone
/// and leaves it only when the owner copies it out. It is a record, not a
/// promise: it proves what this phone wrote, nothing more - saying that plainly
/// is the point.
class Evidence329 {
  Evidence329({
    Future<String?> Function(String key)? read,
    Future<void> Function(String key, String value)? write,
    DateTime Function()? clock,
  })  : _read = read ?? _memoryRead,
        _write = write ?? _memoryWrite,
        _clock = clock ?? DateTime.now;

  /// The key the lines are kept under on this phone.
  static const String key = 'evidence_329';

  /// Never change: it is part of every hash.
  static const String domain = 'locallink-evidence-329';

  /// How many lines are kept. Old lines drop off the front, newest kept.
  static const int keep = 500;

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final DateTime Function() _clock;

  static final Map<String, String> _mem = {};
  static Future<String?> _memoryRead(String k) async => _mem[k];
  static Future<void> _memoryWrite(String k, String v) async => _mem[k] = v;

  /// The one used by the app. Tests build their own.
  static Evidence329 instance = Evidence329();

  /// Point the app's instance at the real phone storage.
  static void bind({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) {
    instance = Evidence329(read: read, write: write);
  }

  static void resetForTest() {
    _mem.clear();
    instance = Evidence329();
  }

  /// One line: `{"n":1,"at":"...","kind":"ask","words":"...","prev":"","hash":"..."}`
  Future<({int n, String at, String kind, String words, String prev, String hash})?>
      last() async {
    final lines = _lines(await _read(key) ?? '');
    if (lines.isEmpty) return null;
    return _asRecord(lines.last);
  }

  /// Add one line. Returns the new line count.
  Future<int> add(String kind, String words) async {
    final text = await _read(key) ?? '';
    final lines = _lines(text);
    final prev = lines.isEmpty ? '' : (_asRecord(lines.last)?.hash ?? '');
    final n = lines.isEmpty ? 1 : (_asRecord(lines.last)?.n ?? lines.length) + 1;
    final rec = _record(n: n, at: _iso(_clock()), kind: kind, words: words, prev: prev);
    lines.add(lineOf(rec));
    final kept = lines.length > keep ? lines.sublist(lines.length - keep) : lines;
    await _write(key, kept.join('\n'));
    return kept.length;
  }

  /// How many lines this phone holds.
  Future<int> count() async => _lines(await _read(key) ?? '').length;

  /// The whole file, ready to copy out.
  Future<String> export() async {
    final lines = _lines(await _read(key) ?? '');
    if (lines.isEmpty) return '';
    return [
      '# LinkUp evidence · $domain',
      '# lines: ${lines.length}',
      '# each line carries the hash of the line before it',
      ...lines,
    ].join('\n');
  }

  /// Check a file (the export, or one the user pasted). Stops at the first line
  /// that does not add up and says which one - never "looks fine" when it does
  /// not.
  static ({bool ok, int lines, int firstBad, String why}) verify(String text) {
    final rows = _lines(text);
    if (rows.isEmpty) {
      return (ok: false, lines: 0, firstBad: 0, why: 'empty');
    }
    var prev = '';
    for (var i = 0; i < rows.length; i++) {
      final rec = _asRecord(rows[i]);
      if (rec == null) return (ok: false, lines: i, firstBad: i + 1, why: 'not a line');
      if (rec.n != i + 1) return (ok: false, lines: i, firstBad: i + 1, why: 'number');
      if (rec.prev != prev) return (ok: false, lines: i, firstBad: i + 1, why: 'chain');
      if (rec.hash != _hashOf(rec)) return (ok: false, lines: i, firstBad: i + 1, why: 'changed');
      prev = rec.hash;
    }
    return (ok: true, lines: rows.length, firstBad: 0, why: '');
  }

  /// Big words for the two things the owner can do with it.
  static String fileWords(int lines) =>
      lines == 0 ? 'Nothing recorded yet' : '$lines line${lines == 1 ? '' : 's'} on this phone';

  // ---------------------------------------------------------------- inside

  static List<String> _lines(String text) => text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();

  static String _iso(DateTime t) => t.toUtc().toIso8601String();

  static ({int n, String at, String kind, String words, String prev, String hash}) _record({
    required int n,
    required String at,
    required String kind,
    required String words,
    required String prev,
  }) {
    final body = <String, String>{
      'n': '$n',
      'at': at,
      'kind': _clean(kind),
      'words': _clean(words),
      'prev': prev,
    };
    final hash = _hashBody(body);
    return (
      n: n,
      at: at,
      kind: body['kind']!,
      words: body['words']!,
      prev: prev,
      hash: hash,
    );
  }

  static String _hashBody(Map<String, String> body) => sha256
      .convert(utf8.encode(
          '$domain|${body['n']}|${body['at']}|${body['kind']}|${body['words']}|${body['prev']}'))
      .toString();

  static String _hashOf(({int n, String at, String kind, String words, String prev, String hash}) rec) =>
      _hashBody({
        'n': '${rec.n}',
        'at': rec.at,
        'kind': rec.kind,
        'words': rec.words,
        'prev': rec.prev,
      });

  /// One line of text per line of the file: newlines inside a word would break
  /// the file, so they become spaces.
  static String _clean(String s) => s.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();

  static ({int n, String at, String kind, String words, String prev, String hash})? _asRecord(
      String line) {
    if (!line.startsWith('{')) return null;
    try {
      final m = jsonDecode(line);
      if (m is! Map) return null;
      final n = m['n'];
      if (n is! num) return null;
      return (
        n: n.toInt(),
        at: m['at']?.toString() ?? '',
        kind: m['kind']?.toString() ?? '',
        words: m['words']?.toString() ?? '',
        prev: m['prev']?.toString() ?? '',
        hash: m['hash']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// The line as it is written to the file.
  static String lineOf(({int n, String at, String kind, String words, String prev, String hash}) r) =>
      jsonEncode({'n': r.n, 'at': r.at, 'kind': r.kind, 'words': r.words, 'prev': r.prev, 'hash': r.hash});
}
