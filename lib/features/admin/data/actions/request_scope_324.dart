import 'dart:convert';

import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';

/// Bundle 324: what a Get chat request is allowed to bring.
///
/// Two facts travel with every request and must survive a restart, because the
/// phone can be offline when the next request is made:
///
/// * **the chat key** - `g:<groupId>` or `d:<a|b>` (sorted). Comparing keys is
///   what stops the same chat being asked twice while the server is away
///   (`openRequestFor314` used to compare phones via [phonesOf], which is empty
///   offline - that is the 17 Nov 18:53 duplicate).
/// * **the types** - `voice`, `photo`, `video`, `file`. `null` means "no filter"
///   (an older app, or a request made before 324): everything comes, exactly as
///   before.
class RequestScope324 {
  RequestScope324._();

  static const String prefKey = 'request_scope_324';

  /// Wired in `app_dependencies.dart` (`store.readSetting` / `writeSetting`).
  static Future<String?> Function(String key)? read;
  static Future<void> Function(String key, String value)? write;

  /// request id -> {key, types}
  static final Map<String, ({String chatKey, Set<String>? types})> _byId = {};

  static bool _loaded = false;

  static Future<void> load() async {
    _byId.clear();
    _loaded = true;
    final r = read;
    if (r == null) return;
    try {
      final raw = await r(prefKey);
      if (raw == null || raw.isEmpty) return;
      final d = jsonDecode(raw);
      if (d is! Map) return;
      d.forEach((k, v) {
        if (v is! Map) return;
        final key = v['k']?.toString() ?? '';
        final t = v['t'];
        final types = t is List ? {for (final x in t) '$x'} : null;
        if (key.isEmpty && types == null) return;
        _byId['$k'] = (chatKey: key, types: types);
      });
    } catch (_) {}
  }

  static Future<void> _save() async {
    final w = write;
    if (w == null) return;
    final out = <String, dynamic>{};
    _byId.forEach((k, v) {
      out[k] = {
        'k': v.chatKey,
        if (v.types != null) 't': v.types!.toList()..sort(),
      };
    });
    // Keep the file small: 300 newest requests is plenty.
    if (out.length > 300) {
      final keys = out.keys.toList();
      for (final k in keys.take(out.length - 300)) {
        out.remove(k);
      }
    }
    try {
      await w(prefKey, jsonEncode(out));
    } catch (_) {}
  }

  /// [types] = null / every type = no filter (everything comes).
  static Future<void> remember(String id, {String chatKey = '', Iterable<String>? types}) async {
    if (id.isEmpty) return;
    if (!_loaded) await load();
    final t = types?.toSet();
    _byId[id] = (chatKey: chatKey, types: (t == null || t.length >= 4) ? null : t);
    await _save();
  }

  /// The chat key of a request this phone made ('' when unknown = older rows).
  static String chatKeyOf(String id) => _byId[id]?.chatKey ?? '';

  /// The types this request may bring; `null` = no filter (everything).
  static Set<String>? typesOf(String id) => _byId[id]?.types;

  /// Bundle 324 (6.7): top-up - the SAME request asked for more kinds
  /// (`Get photos` on a ready row). No new request, no second card, no
  /// second row: only the request's own `with` grows.
  static Future<Set<String>> add324(String id, Iterable<String> kinds) async {
    final cur = typesOf(id) ?? allTypes;
    final t = {...cur, ...kinds};
    await remember(id, chatKey: chatKeyOf(id), types: t);
    return typesOf(id) ?? allTypes;
  }

  /// The kinds this request did not ask for (empty = it asked for all).
  static Set<String> skipped324(String id) {
    final t = typesOf(id);
    if (t == null) return const {};
    return {'voice', 'photo', 'video'}.where((k) => !t.contains(k)).toSet();
  }

  /// The same rule as `chatKey320`: one key per chat, offline.
  static String chatKeyOfPick(ChatPick221 p) {
    if (p.isGroup) return 'g:${p.groupId}';
    final two = <String>[p.userA, p.userB]..sort();
    return 'd:${two.join('|')}';
  }

  /// The chat key of a request row, when the phone made it ('' otherwise).
  static String chatKeyOfRow(ChatRequestRow221 r) => chatKeyOf(r.id);

  /// Types asked for by the sheet: `null` means "everything".
  static Set<String>? typesFrom(Iterable<String>? asked) {
    if (asked == null) return null;
    final t = asked.toSet();
    return t.length >= 4 ? null : t;
  }

  static const Set<String> allTypes = {'voice', 'photo', 'video', 'file'};

  /// True when [type] may travel for this request.
  static bool allows(String id, String type) {
    final t = typesOf(id);
    if (t == null) return true;
    return t.contains(type);
  }
}
