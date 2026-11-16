import 'dart:convert';
import 'dart:typed_data';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart' show dMMM216;
import 'package:locallink/l10n/l10n.dart';

/// Bundle 318 (K1): the Owner phone's kept copy of a Get chat answer.
///
/// - Saved (locked: SQLCipher on the phone) when a complete answer is
///   opened; kept [Kept318.keep] (7 days) after that first open, or until
///   Close / Delete completely of that chat.
/// - "Get new messages only" answers are merged into it by message id
///   ([Kept318.mergeMessages]); [kids] are those requests.
/// - [lastAt] = when the newest answer came (full or new only).
class KeptCopy318 {
  const KeptCopy318({
    required this.id,
    required this.chat,
    this.label = '',
    this.from = '',
    this.to = '',
    required this.gotAt,
    required this.firstOpen,
    String? lastAt,
    this.fromName = '',
    this.kids = const [],
    this.newIds = const [],
    this.newAt = '',
    this.fixed = const [],
    this.messages = const [],
    this.count = 0,
    this.newest = '',
  }) : lastAt = lastAt ?? gotAt;

  /// The request whose full answer made the copy.
  final String id;
  final Map<String, dynamic> chat;
  final String label;

  /// The range days (YYYY-MM-DD, '' = full chat).
  final String from;
  final String to;

  /// UTC times (ISO).
  final String gotAt;
  final String firstOpen;
  final String lastAt;
  final String fromName;

  /// "Get new messages only" requests merged in (oldest first).
  final List<String> kids;

  /// The ids the last new-only answer added, and when.
  final List<String> newIds;
  final String newAt;

  /// Days asked again once (day counts did not match).
  final List<String> fixed;

  /// Messages (oldest first); empty in a [KeptStore318.metas] row.
  final List<Map<String, dynamic>> messages;
  final int count;

  /// The newest `created_at` in the copy.
  final String newest;

  bool get full => from.isEmpty && to.isEmpty;

  DateTime? get until {
    final o = DateTime.tryParse(firstOpen);
    return o?.add(Kept318.keep);
  }

  Set<String> get family => {id, ...kids};

  KeptCopy318 copyWith({
    String? lastAt,
    String? to,
    List<String>? kids,
    List<String>? newIds,
    String? newAt,
    List<String>? fixed,
    List<Map<String, dynamic>>? messages,
  }) {
    final msgs = messages ?? this.messages;
    return KeptCopy318(
      id: id,
      chat: chat,
      label: label,
      from: from,
      to: to ?? this.to,
      gotAt: gotAt,
      firstOpen: firstOpen,
      lastAt: lastAt ?? this.lastAt,
      fromName: fromName,
      kids: kids ?? this.kids,
      newIds: newIds ?? this.newIds,
      newAt: newAt ?? this.newAt,
      fixed: fixed ?? this.fixed,
      messages: msgs,
      count: messages == null ? count : msgs.length,
      newest: messages == null ? newest : Kept318.newestOf(msgs),
    );
  }

  /// Everything but the messages (one small row).
  Map<String, dynamic> metaJson() => {
        'id': id,
        'chat': chat,
        'label': label,
        'from': from,
        'to': to,
        'got_at': gotAt,
        'first_open': firstOpen,
        'last_at': lastAt,
        'from_name': fromName,
        'kids': kids,
        'new_ids': newIds,
        'new_at': newAt,
        'fixed': fixed,
        'count': count,
        'newest': newest,
      };

  static KeptCopy318? fromMeta(Object? raw, {List<Map<String, dynamic>> messages = const []}) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = m['id']?.toString() ?? '';
    if (id.isEmpty || m['chat'] is! Map) return null;
    List<String> list(String k) => [for (final x in (m[k] as List? ?? const [])) '$x'];
    String s(String k) => m[k]?.toString() ?? '';
    return KeptCopy318(
      id: id,
      chat: Map<String, dynamic>.from(m['chat'] as Map),
      label: s('label'),
      from: s('from'),
      to: s('to'),
      gotAt: s('got_at'),
      firstOpen: s('first_open'),
      lastAt: s('last_at').isEmpty ? s('got_at') : s('last_at'),
      fromName: s('from_name'),
      kids: list('kids'),
      newIds: list('new_ids'),
      newAt: s('new_at'),
      fixed: list('fixed'),
      messages: messages,
      count: m['count'] is int ? m['count'] as int : messages.length,
      newest: s('newest'),
    );
  }
}

/// Bundle 318 (K1): where kept copies live. On the phone: SQLCipher tables
/// (`kept_sql_318.dart`); tests: [MemoryKeptStore318].
abstract class KeptStore318 {
  /// Every copy without its messages.
  Future<List<KeptCopy318>> metas();

  /// One copy with its messages (null = not here).
  Future<KeptCopy318?> copy(String id);
  Future<void> save(KeptCopy318 c);
  Future<void> remove(String id);

  /// Kept files (full photo / video / voice bytes) by file id.
  Future<Uint8List?> file(String fileId);
  Future<void> putFile(String fileId, String copyId, Uint8List bytes, String at);
  Future<List<({String fileId, String copyId, int size, String at})>> files();
  Future<void> removeFile(String fileId);

  /// "Get all again": the files of the old copy stay with the new one.
  Future<void> moveFiles(String fromCopy, String toCopy);
}

class MemoryKeptStore318 implements KeptStore318 {
  final Map<String, KeptCopy318> _copies = {};
  final Map<String, (String, Uint8List, String)> _files = {};

  @override
  Future<List<KeptCopy318>> metas() async =>
      [for (final c in _copies.values) KeptCopy318.fromMeta(c.metaJson())!];

  @override
  Future<KeptCopy318?> copy(String id) async => _copies[id];

  @override
  Future<void> save(KeptCopy318 c) async => _copies[c.id] = c;

  @override
  Future<void> remove(String id) async {
    _copies.remove(id);
    _files.removeWhere((_, v) => v.$1 == id);
  }

  @override
  Future<Uint8List?> file(String fileId) async => _files[fileId]?.$2;

  @override
  Future<void> putFile(String fileId, String copyId, Uint8List bytes, String at) async =>
      _files[fileId] = (copyId, bytes, at);

  @override
  Future<List<({String fileId, String copyId, int size, String at})>> files() async => [
        for (final e in _files.entries) (fileId: e.key, copyId: e.value.$1, size: e.value.$2.length, at: e.value.$3),
      ];

  @override
  Future<void> removeFile(String fileId) async => _files.remove(fileId);

  @override
  Future<void> moveFiles(String fromCopy, String toCopy) async {
    for (final e in _files.entries.toList()) {
      if (e.value.$1 == fromCopy) _files[e.key] = (toCopy, e.value.$2, e.value.$3);
    }
  }
}

/// Bundle 318: the rules of the kept copy (pure parts are static + tested).
class Kept318 {
  Kept318({required this.store, DateTime Function()? clock, this.fileCap = maxFileBytes}) : _clock = clock ?? DateTime.now;

  /// [maxFileBytes]; smaller in tests.
  final int fileCap;

  static Kept318? instance;

  /// K1 (USER PICK): 7 days after the first open.
  static const Duration keep = Duration(days: 7);

  /// K1: kept files never use more than this (oldest go first).
  static const int maxFileBytes = 300 * 1024 * 1024;

  /// K4: the new-only request starts 1 day before the newest message
  /// (wrong clocks, late mesh messages).
  static const Duration overlap = Duration(days: 1);

  final KeptStore318 store;
  final DateTime Function() _clock;

  String _now() => _clock().toUtc().toIso8601String();

  static String newestOf(List<Map<String, dynamic>> msgs) {
    var best = '';
    DateTime? bestAt;
    for (final m in msgs) {
      final s = m['created_at']?.toString() ?? '';
      final at = DateTime.tryParse(s);
      if (at == null) continue;
      if (bestAt == null || at.isAfter(bestAt)) {
        bestAt = at;
        best = s;
      }
    }
    return best;
  }

  /// K4: `since` (newest - 1 day), `since_n` (messages of the copy from
  /// then on) and `since_h` (their check, [ChatAnswerBuilder.sinceHash318]).
  static ({String since, int n, String h})? sinceOf(KeptCopy318 c) {
    final newest = DateTime.tryParse(newestOf(c.messages));
    if (newest == null) return null;
    final since = newest.toUtc().subtract(overlap);
    final from = [
      for (final m in c.messages)
        if (DateTime.tryParse(m['created_at']?.toString() ?? '') case final at? when !at.isBefore(since)) m,
    ];
    return (since: since.toIso8601String(), n: from.length, h: ChatAnswerBuilder.sinceHashOfJson318(from));
  }

  /// K6: merge by message id. The newer copy of a message wins; a deleted
  /// mark stays; a message missing in the new answer stays (history).
  /// [added] = ids that were not in the copy (oldest first).
  static ({List<Map<String, dynamic>> messages, List<String> added}) mergeMessages(
      List<Map<String, dynamic>> old, List<Map<String, dynamic>> incoming) {
    final by = <String, Map<String, dynamic>>{
      for (final m in old)
        if ((m['id']?.toString() ?? '').isNotEmpty) m['id'].toString(): m,
    };
    final added = <String>[];
    for (final m in incoming) {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final prev = by[id];
      if (prev == null) {
        added.add(id);
        by[id] = m;
        continue;
      }
      final next = Map<String, dynamic>.from(m);
      if ((prev['deleted_at']?.toString() ?? '').isNotEmpty && (next['deleted_at']?.toString() ?? '').isEmpty) {
        next['deleted_at'] = prev['deleted_at'];
        if (prev['hidden_how'] != null) next['hidden_how'] = prev['hidden_how'];
      }
      // A thumbnail the old copy had (the new answer may be trimmed).
      final pa = prev['attachments'];
      final na = next['attachments'];
      if (pa is List && na is List) {
        final thumbs = <String, Map>{
          for (final a in pa.whereType<Map>())
            if (a['thumb'] != null) '${a['file_id']}': a,
        };
        next['attachments'] = [
          for (final a in na)
            if (a is Map && a['thumb'] == null && thumbs[a['file_id']?.toString()] != null)
              {...Map<String, dynamic>.from(a), 'thumb': thumbs['${a['file_id']}']!['thumb'], 'thumb_type': thumbs['${a['file_id']}']!['thumb_type']}
            else
              a,
        ];
      }
      if (prev['outside'] != true) next.remove('outside');
      by[id] = next;
    }
    final list = by.values.toList()
      ..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
    final order = {for (var i = 0; i < list.length; i++) list[i]['id'].toString(): i};
    added.sort((a, b) => order[a]!.compareTo(order[b]!));
    return (messages: list, added: added);
  }

  /// K6: days (UTC) before `since` where the answering phone has MORE
  /// messages than the copy (late mesh messages with an old time). Days
  /// before the copy's first day are not compared.
  static List<String> shortDays(List<Map<String, dynamic>> merged, Map<String, int> theirs, String since) {
    final s = DateTime.tryParse(since);
    if (s == null || theirs.isEmpty) return const [];
    final ours = <String, int>{};
    for (final m in merged) {
      final at = DateTime.tryParse(m['created_at']?.toString() ?? '');
      if (at == null) continue;
      final d = ChatAnswerBuilder.utcDay318(at);
      ours[d] = (ours[d] ?? 0) + 1;
    }
    if (ours.isEmpty) return const [];
    final first = (ours.keys.toList()..sort()).first;
    final sinceDay = ChatAnswerBuilder.utcDay318(s);
    return [
      for (final e in theirs.entries)
        if (e.key.compareTo(first) > 0 && e.key.compareTo(sinceDay) < 0 && e.value > (ours[e.key] ?? 0)) e.key,
    ]..sort();
  }

  /// K3: does the copy hold the picked range up to [toDay]? The sheet
  /// asks: `inside` = opens at once; `same` = Already here (new only).
  static String modeOf(KeptCopy318 c, {required String from, required String to, required String today}) {
    final lastDay = _localDay(DateTime.tryParse(c.lastAt)) ?? '';
    final startsIn = c.full || (from.isNotEmpty && c.from.compareTo(from) <= 0);
    if (!startsIn) return 'none';
    final sameRange = c.from == from && (c.to == to || (c.full && from.isEmpty));
    final endDay = to.isEmpty ? today : to;
    if (!sameRange && endDay.compareTo(lastDay) <= 0) return 'inside';
    return 'same';
  }

  static String? _localDay(DateTime? d) {
    if (d == null) return null;
    final l = d.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  /// K3: messages of one range (local days, inclusive).
  static List<Map<String, dynamic>> within(List<Map<String, dynamic>> msgs, String from, String to) => [
        for (final m in msgs)
          if (_localDay(DateTime.tryParse(m['created_at']?.toString() ?? '')) case final d?
              when (from.isEmpty || d.compareTo(from) >= 0) && (to.isEmpty || d.compareTo(to) <= 0))
            m,
      ];

  // ------------------------------------------------------------ store work

  /// The copy a request belongs to (its own or as a new-only kid).
  Future<KeptCopy318?> forRequest(String requestId) async {
    for (final c in await store.metas()) {
      if (c.family.contains(requestId)) return c;
    }
    return null;
  }

  /// K1: a complete full answer was opened -> it becomes the copy of its
  /// chat ([sameChat] finds older copies of the same chat: they go).
  Future<KeptCopy318> keepAnswer({
    required String requestId,
    required Map<String, dynamic> chat,
    required String label,
    required String from,
    required String to,
    required String fromName,
    required List<Map<String, dynamic>> messages,
    required Future<bool> Function(Map<String, dynamic> chat) sameChat,
  }) async {
    for (final c in await store.metas()) {
      if (c.id != requestId && await sameChat(c.chat)) {
        await store.moveFiles(c.id, requestId); // K8: files are not fetched again
        await store.remove(c.id);
      }
    }
    final old = await store.copy(requestId);
    final now = _now();
    final msgs = [...messages]..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
    final c = KeptCopy318(
      id: requestId,
      chat: chat,
      label: label,
      from: from,
      to: to,
      gotAt: old?.gotAt ?? now,
      firstOpen: old?.firstOpen ?? now,
      fromName: fromName,
      messages: msgs,
      count: msgs.length,
      newest: newestOf(msgs),
    );
    await store.save(c);
    AppLogger.info('KEPT318_SAVED', detail: 'messages=${msgs.length}');
    return c;
  }

  /// K6: a new-only answer goes into the copy once. Returns the ids added
  /// and the short days (asked again once by the caller).
  Future<({KeptCopy318 copy, List<String> added, List<String> shortDays})> merge(
    KeptCopy318 c, {
    required String kidId,
    required List<Map<String, dynamic>> incoming,
    required Map<String, int> days,
    required String since,
  }) async {
    final full = c.messages.isEmpty && c.count > 0 ? (await store.copy(c.id) ?? c) : c;
    final m = mergeMessages(full.messages, incoming);
    final short = [for (final d in shortDays(m.messages, days, since)) if (!full.fixed.contains(d)) d];
    final today = _localDay(_clock()) ?? '';
    final next = full.copyWith(
      messages: m.messages,
      kids: [...full.kids.where((k) => k != kidId), kidId],
      newIds: m.added,
      newAt: _now(),
      lastAt: _now(),
      // A dated copy now reaches today (the new-only range ended today).
      to: full.full ? null : today,
      fixed: [...full.fixed, ...short],
    );
    await store.save(next);
    AppLogger.info('KEPT318_MERGED', detail: 'added=${m.added.length} short_days=${short.length}');
    return (copy: next, added: m.added, shortDays: short);
  }

  /// K1: Close / Delete completely / 7 days: the copy and its files go.
  Future<void> drop(String copyId) async {
    for (final f in await store.files()) {
      if (f.copyId == copyId) await store.removeFile(f.fileId);
    }
    await store.remove(copyId);
  }

  /// K6: Delete completely of messages: those ids leave every copy.
  Future<void> dropIds(Iterable<String> ids) async {
    final gone = ids.toSet();
    if (gone.isEmpty) return;
    for (final meta in await store.metas()) {
      final c = await store.copy(meta.id);
      if (c == null) continue;
      final left = [for (final m in c.messages) if (!gone.contains(m['id']?.toString())) m];
      if (left.length != c.messages.length) await store.save(c.copyWith(messages: left));
    }
  }

  /// K2: copies opened 7+ days ago go (start + every 6 h).
  Future<int> sweep() async {
    final now = _clock();
    var n = 0;
    final alive = <String>{};
    for (final c in await store.metas()) {
      final until = c.until;
      if (until != null && !now.isBefore(until)) {
        await drop(c.id);
        n++;
      } else {
        alive.add(c.id);
      }
    }
    // Files whose copy is gone.
    for (final f in await store.files()) {
      if (!alive.contains(f.copyId)) await store.removeFile(f.fileId);
    }
    if (n > 0) AppLogger.info('KEPT318_SWEEP', detail: 'copies=$n');
    return n;
  }

  /// K8: a file that is already here (bytes), or null.
  Future<Uint8List?> fileBytes(String fileId) => fileId.isEmpty ? Future.value(null) : store.file(fileId);

  Future<Set<String>> fileIds() async => {for (final f in await store.files()) f.fileId};

  /// K8: keeps a file of a copy; over [maxFileBytes] the oldest go first.
  Future<void> keepFile(String fileId, String copyId, Uint8List bytes) async {
    if (fileId.isEmpty || bytes.isEmpty || bytes.length > fileCap) return;
    await store.putFile(fileId, copyId, bytes, _now());
    final all = (await store.files())..sort((a, b) => a.at.compareTo(b.at));
    var total = all.fold<int>(0, (n, f) => n + f.size);
    for (final f in all) {
      if (total <= fileCap) break;
      if (f.fileId == fileId) continue;
      await store.removeFile(f.fileId);
      total -= f.size;
    }
  }

  // ------------------------------------------------------------ words (K7)

  static String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// "15 Nov 10:05" ('' = no time).
  static String dayTime(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    return t == null ? '' : '${dMMM216(t)} ${hm(t)}';
  }

  /// "10:05" today, else "15 Nov 10:05".
  static String shortWhen(String iso, DateTime now) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final n = now.toLocal();
    return t.year == n.year && t.month == n.month && t.day == n.day ? hm(t) : dayTime(iso);
  }

  /// "22 Nov".
  static String day(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    return t == null ? '' : dMMM216(t);
  }

  /// "full chat" / "1 Nov - 9 Nov".
  static String rangeWords(KeptCopy318 c) {
    if (c.full) return L.t.fullChatLower318;
    final f = DateTime.tryParse(c.from);
    final t = DateTime.tryParse(c.to);
    if (f == null || t == null) return L.t.fullChatLower318;
    return '${dMMM216(f)} - ${dMMM216(t)}';
  }

  /// JSON size of a copy (logs).
  static int sizeOf(KeptCopy318 c) => jsonEncode(c.messages).length;
}
