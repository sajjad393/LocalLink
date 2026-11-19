import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/request_scope_324.dart';
import 'package:locallink/features/admin/data/actions/waiting_325.dart'; // Bundle 325
import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/admin_action_box.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/actions/delete_completely_doer.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart' show AdminSignIn;
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/kept_copy_318.dart';
import 'package:locallink/l10n/l10n.dart';
import 'package:locallink/features/admin/data/evidence_329.dart';

/// Bundle 221: what the Owner reads. Online the server opens the parts
/// (web requests are locked for the server key); a request made on the
/// admin's phone offline is locked for this phone and opens here. Half an
/// answer can be read: "40 of 80 parts, the rest is on the way".
class ChatAnswerView {
  final String id; // the card (request) id
  final String action;
  final String answerId;
  final String fromDevice;
  final String fromName;
  final int of;
  final int parts;
  final bool complete;
  final Map<String, dynamic>? chat;
  final String from;
  final String to;
  final bool trimmed;
  final List<Map<String, dynamic>> messages;
  final Map<String, dynamic>? file;
  final Uint8List? fileBytes;
  final int broken;

  /// The request was made on the admin's phone: it opens only there.
  final bool forAdminPhone;

  /// Bundle 318 (K5): a new-only answer - `since`, per-day counts (UTC) of
  /// the whole range, and "nothing new" (one part, no messages).
  final String since318;
  final Map<String, int> days318;
  final bool upToDate318;

  /// Bundle 318 (K7): shown from the kept copy - the ids of the last
  /// new-only answer ([newOnly318] = opened from that request: the
  /// "12 new messages" bar), when the copy came and when the new ones came.
  final bool fromKept318;
  final bool newOnly318;
  final List<String> newIds318;
  final String keptGotAt318;
  final String keptNewAt318;
  final String keptUntil318;
  final bool keptFull318;

  const ChatAnswerView({
    required this.id,
    this.action = 'get_chat',
    this.answerId = '',
    this.fromDevice = '',
    this.fromName = '',
    this.of = 0,
    this.parts = 0,
    this.complete = false,
    this.chat,
    this.from = '',
    this.to = '',
    this.trimmed = false,
    this.messages = const [],
    this.file,
    this.fileBytes,
    this.broken = 0,
    this.forAdminPhone = false,
    this.since318 = '',
    this.days318 = const {},
    this.upToDate318 = false,
    this.fromKept318 = false,
    this.newOnly318 = false,
    this.newIds318 = const [],
    this.keptGotAt318 = '',
    this.keptNewAt318 = '',
    this.keptUntil318 = '',
    this.keptFull318 = false,
  });

  /// Bundle 318 (K5): `days` of a part / server answer.
  static Map<String, int> days318Of(Object? raw) => {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt() else if (int.tryParse('${e.value}') case final n?) '${e.key}': n,
      };

  bool get empty => answerId.isEmpty;

  /// "40 of 80 parts" (or '' when complete / nothing yet).
  String get partsWords => empty || complete ? '' : L.t.ofParts(parts, of);

  static ChatAnswerView fromServer(String id, Map<String, dynamic> j) {
    int n(String k) => j[k] is int ? j[k] as int : int.tryParse('${j[k] ?? ''}') ?? 0;
    String s(String k) => j[k]?.toString() ?? '';
    return ChatAnswerView(
      id: id,
      action: s('action').isEmpty ? 'get_chat' : s('action'),
      answerId: s('answer_id'),
      fromDevice: s('from_device'),
      fromName: s('from_name'),
      of: n('of'),
      parts: n('parts'),
      complete: j['complete'] == true,
      chat: j['chat'] is Map ? Map<String, dynamic>.from(j['chat'] as Map) : null,
      from: s('from'),
      to: s('to'),
      trimmed: j['trimmed'] == true,
      messages: [
        for (final m in (j['messages'] as List? ?? const []))
          if (m is Map) Map<String, dynamic>.from(m),
      ],
      file: j['file'] is Map ? Map<String, dynamic>.from(j['file'] as Map) : null,
      broken: n('broken'),
      since318: s('since'),
      days318: days318Of(j['days']),
      upToDate318: j['up_to_date'] == true,
    );
  }
}

/// The Owner endpoints (admin token).
abstract class ChatAdminServer {
  Future<List<Map<String, dynamic>>> conversations(String token);
  Future<List<Map<String, dynamic>>> requests(String token);

  /// `{kind:"direct", users:[a,b]} | {kind:"group", group_id}` + range.
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body);
  Future<ChatAnswerView> answer(String token, String id);
  Future<Uint8List?> download(String token, String id);
  Future<void> close(String token, String id);
  Future<Map<String, dynamic>> file(String token, String id,
      {required String fileId, String messageId = '', String name = ''});
  Future<Map<String, dynamic>> purge(String token, Map<String, dynamic> body);
}

class ChatAdminRefused implements Exception {
  final int status;
  final String code;
  final String message;

  /// Bundle 314 (1b): `already_asked` = the open request of this chat.
  final String openId;
  const ChatAdminRefused(this.status, this.code, this.message, {this.openId = ''});
  @override
  String toString() => message;
}

/// Bundle 324e: the running server refuses the whole body when it meets a key
/// it does not know. `with` is the only key 324 added to this body, so a 400
/// whose words are about the body means "old server", nothing else.
bool isOldServerNoWith324(ChatAdminRefused e) {
  if (e.status != 400) return false;
  final m = e.message.toLowerCase();
  return m.contains('invalid') || m.contains('bad request') || m.contains('body');
}

class HttpChatAdminServer implements ChatAdminServer {
  HttpChatAdminServer({required this.baseUrl, http.Client? client})
      : _client = BuildHeaderClient(client ?? http.Client());

  final String Function() baseUrl;
  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 30);

  /// Bundle 321 (F4): the lists (conversations / requests / groups) give
  /// up after 8 s - the screen already shows what is saved here.
  static const Duration listTimeout = Duration(seconds: 8);

  Map<String, String> _h(String token) =>
      {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  Uri _uri(String path) {
    final base = baseUrl();
    if (base.isEmpty) throw Exception('no server');
    return Uri.parse('$base$path');
  }

  Object? _body(http.Response r) {
    Object? d;
    try {
      d = jsonDecode(r.body);
    } catch (_) {}
    if (r.statusCode < 200 || r.statusCode > 299) {
      final m = d is Map ? d : const {};
      throw ChatAdminRefused(r.statusCode, m['code']?.toString() ?? '',
          m['error']?.toString() ?? 'server ${r.statusCode}',
          openId: m['open_id']?.toString() ?? '');
    }
    return d;
  }

  Map<String, dynamic> _map(http.Response r) {
    final d = _body(r);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> _list(http.Response r, String key) {
    final d = _body(r);
    final raw = d is List ? d : (d is Map ? d[key] : null);
    return [
      for (final x in (raw is List ? raw : const []))
        if (x is Map) Map<String, dynamic>.from(x),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => _list(
      await _client.get(_uri('/api/v1/admin/conversations'), headers: _h(token)).timeout(listTimeout),
      'conversations');

  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => _list(
      await _client.get(_uri('/api/v1/admin/chat-requests'), headers: _h(token)).timeout(listTimeout),
      'requests');

  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async {
    final r = await _client
        .post(_uri('/api/v1/admin/chat-requests'), headers: _h(token), body: jsonEncode(body))
        .timeout(_timeout);
    // Bundle 324e: this client is NOT ApiHttpClient, so a refusal here used to
    // leave no line in the log at all (the 18 Nov 20:53 "invalid request body"
    // toast had nothing to find). One short line, no personal data.
    if (r.statusCode < 200 || r.statusCode > 299) {
      final t = r.body.replaceAll(RegExp(r'\s+'), ' ');
      final hasWith = body.containsKey('with');
      AppLogger.info('CHAT_REQ_POST',
          detail: '-> ${r.statusCode} with=$hasWith '
              '${t.length > 120 ? t.substring(0, 120) : t}');
    }
    return _map(r);
  }

  @override
  Future<ChatAnswerView> answer(String token, String id) async {
    final r = await _client
        .get(_uri('/api/v1/admin/chat-requests/${Uri.encodeComponent(id)}/answer'), headers: _h(token))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode == 409 && r.body.contains('answer_for_admin_phone')) {
      return ChatAnswerView(id: id, forAdminPhone: true);
    }
    return ChatAnswerView.fromServer(id, _map(r));
  }

  @override
  Future<Uint8List?> download(String token, String id) async {
    final r = await _client
        .get(_uri('/api/v1/admin/chat-requests/${Uri.encodeComponent(id)}/answer?download=1'),
            headers: _h(token))
        .timeout(const Duration(minutes: 3));
    if (r.statusCode != 200 || (r.headers['content-type'] ?? '').contains('application/json')) {
      return null;
    }
    return r.bodyBytes;
  }

  @override
  Future<void> close(String token, String id) async => _body(await _client
      .post(_uri('/api/v1/admin/chat-requests/${Uri.encodeComponent(id)}/close'), headers: _h(token))
      .timeout(_timeout));

  @override
  Future<Map<String, dynamic>> file(String token, String id,
          {required String fileId, String messageId = '', String name = ''}) async =>
      _map(await _client
          .post(_uri('/api/v1/admin/chat-requests/${Uri.encodeComponent(id)}/file'),
              headers: _h(token),
              body: jsonEncode({'file_id': fileId, 'message_id': messageId, 'name': name}))
          .timeout(_timeout));

  @override
  Future<Map<String, dynamic>> purge(String token, Map<String, dynamic> body) async => _map(
      await _client
          .post(_uri('/api/v1/admin/purge'), headers: _h(token), body: jsonEncode(body))
          .timeout(_timeout));

  /// Bundle 314 (1): the server's groups (`me` flag, member phones) + the
  /// nearby groups members reported (`nearby`).
  Future<Map<String, dynamic>> groups314(String token) async => _map(await _client
      .get(_uri('/api/v1/admin/groups?limit=200'), headers: _h(token))
      .timeout(listTimeout));
}

/// Opens answers meant for this (admin) phone from the local parts.
class ChatAnswerReader {
  static ChatAnswerReader? instance;

  /// The admin phone's copy goes 24 h after it was first opened (or Close).
  /// Bundle 318 (K1/K2, USER PICK): 7 days.
  static const Duration keepAfterOpen = Duration(days: 7);

  /// Bundle 318 (K2): the first-open times live here (setting, JSON
  /// `{answer id: UTC time}`), so an app restart does not forget them
  /// (they were only in memory: copies stayed until Close).
  static const String openedKey318 = 'answer_opened_318';

  final AnswerPartStore store;
  final String Function() selfDeviceId;
  final Future<List<SimpleKeyPair>> Function() boxKeys;
  final Future<String> Function(String device) nameOf;
  final DateTime Function() _clock;
  final Map<String, DateTime> _openedAt = <String, DateTime>{};

  /// Bundle 318 (K2): settings (null = memory only; tests).
  final Future<String?> Function(String key)? readSetting;
  final Future<void> Function(String key, String value)? writeSetting;
  bool _loaded318 = false;

  ChatAnswerReader({
    required this.store,
    required this.selfDeviceId,
    required this.boxKeys,
    required this.nameOf,
    DateTime Function()? clock,
    this.readSetting,
    this.writeSetting,
  }) : _clock = clock ?? DateTime.now;

  /// Bundle 318 (K2): the saved first-open times (once).
  Future<void> _load318() async {
    if (_loaded318) return;
    _loaded318 = true;
    final read = readSetting;
    if (read == null) return;
    try {
      final d = jsonDecode(await read(openedKey318) ?? '{}');
      if (d is Map) {
        d.forEach((k, v) {
          final at = DateTime.tryParse('$v');
          if (at != null) _openedAt.putIfAbsent('$k', () => at);
        });
      }
    } catch (_) {}
  }

  Future<void> _save318() async {
    final write = writeSetting;
    if (write == null) return;
    try {
      await write(openedKey318,
          jsonEncode({for (final e in _openedAt.entries) e.key: e.value.toUtc().toIso8601String()}));
    } catch (_) {}
  }

  @visibleForTesting
  Map<String, DateTime> get openedAt318 => Map.unmodifiable(_openedAt);

  /// One part opened: null when it doesn't open with this phone's keys.
  static Future<Map<String, dynamic>?> openPart(List<SimpleKeyPair> pairs, HeldPart p) async {
    final f = p.blob.fields;
    if (f == null) return null;
    final raw = await AdminActionBoxLock.open(pairs, f['data']?.toString() ?? '');
    if (raw == null) return null;
    try {
      final plain = jsonDecode(utf8.decode(gzip.decode(raw)));
      return plain is Map ? Map<String, dynamic>.from(plain) : null;
    } catch (_) {
      return null;
    }
  }

  /// The best local answer of a request (most parts), opened.
  Future<ChatAnswerView> read(String actionId, {String action = 'get_chat'}) async {
    // Bundle 316 (F1): light rows first; each blob is read when opened.
    final mine = (await store.metas())
        .where((p) => p.actionId == actionId && p.replyTo == selfDeviceId())
        .toList();
    if (mine.isEmpty) return ChatAnswerView(id: actionId, action: action);
    final by = <String, Map<int, PartMeta>>{};
    for (final p in mine) {
      (by[p.answerId] ??= <int, PartMeta>{})[p.part] = p; // duplicates joined by number
    }
    final best = by.entries.reduce((a, b) => b.value.length > a.value.length ? b : a);
    final parts = best.value.values.toList()..sort((a, b) => a.part.compareTo(b.part));
    final pairs = await boxKeys();
    final messages = <Map<String, dynamic>>[];
    Map<String, dynamic>? chat;
    Map<String, dynamic>? file;
    var from = '', to = '';
    var trimmed = false;
    var broken = 0;
    var since = '';
    var days = const <String, int>{};
    var upToDate = false;
    final data = BytesBuilder(copy: false);
    for (final p in parts) {
      final full = await store.part(p.answerId, p.part);
      final plain = full == null ? null : await openPart(pairs, full);
      if (plain == null) {
        broken++;
        continue;
      }
      if (p.part == 1) {
        if (plain['chat'] is Map) chat = Map<String, dynamic>.from(plain['chat'] as Map);
        from = plain['from']?.toString() ?? '';
        to = plain['to']?.toString() ?? '';
        trimmed = plain['trimmed'] == true;
        since = plain['since']?.toString() ?? ''; // Bundle 318 (K5)
        days = ChatAnswerView.days318Of(plain['days']);
        upToDate = plain['up_to_date'] == true;
      }
      if (plain['file'] is Map) file = Map<String, dynamic>.from(plain['file'] as Map);
      for (final m in (plain['messages'] as List? ?? const [])) {
        if (m is Map) messages.add(Map<String, dynamic>.from(m));
      }
      final d = plain['data']?.toString() ?? '';
      if (d.isNotEmpty) {
        try {
          data.add(ChatAnswerBuilder.unb64url(d));
        } catch (_) {
          broken++;
        }
      }
    }
    messages.sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
    final of = parts.first.of;
    final complete = parts.length >= of && broken == 0;
    await _load318();
    if (!_openedAt.containsKey(best.key)) {
      _openedAt[best.key] = _clock();
      await _save318();
    }
    return ChatAnswerView(
      id: actionId,
      action: action,
      answerId: best.key,
      fromDevice: parts.first.device,
      // Bundle 255 B7: a default phone label is not a name -> '' (the
      // viewer then takes the name from the answering phone's messages).
      fromName: await nameOf(parts.first.device)
          .then((n) => isDefaultPhoneLabel255(n) ? '' : n.trim())
          .catchError((_) => ''),
      of: of,
      parts: parts.length,
      complete: complete,
      chat: chat,
      from: from,
      to: to,
      trimmed: trimmed,
      messages: messages,
      file: file,
      fileBytes: action == 'get_file' && complete ? data.takeBytes() : null,
      broken: broken,
      since318: since,
      days318: days,
      upToDate318: upToDate,
    );
  }

  /// Close: the admin phone's copy goes now.
  Future<void> close(String actionId) async {
    final ids = {
      for (final p in await store.metas())
        if (p.actionId == actionId && p.replyTo == selfDeviceId()) p.answerId,
    };
    await _load318();
    for (final id in ids) {
      await store.dropAnswer(id);
      await store.stop(id, actionId, _clock().toUtc().toIso8601String());
      _openedAt.remove(id);
    }
    if (ids.isNotEmpty) await _save318();
    AppLogger.info('ADMIN_ANSWER_CLOSED', detail: 'answers=${ids.length}');
  }

  /// Copies opened more than [keepAfterOpen] ago go (called at start and
  /// every 6 h; Bundle 318 K2: the open times survive a restart).
  Future<int> sweep() async {
    await _load318();
    final now = _clock();
    final old = [
      for (final e in _openedAt.entries)
        if (now.difference(e.value) >= keepAfterOpen) e.key,
    ];
    for (final id in old) {
      await store.dropAnswer(id);
      _openedAt.remove(id);
    }
    if (old.isNotEmpty) await _save318();
    // Bundle 321 (F3 / D1): a copy for this phone that was NEVER opened
    // goes [keepAfterOpen] after its last part came (it stayed forever).
    // The 318 kept copies live in their own store and are not touched.
    final self = selfDeviceId();
    final lastPart = <String, DateTime>{};
    for (final p in await store.metas()) {
      if (p.replyTo != self || _openedAt.containsKey(p.answerId)) continue;
      final t = DateTime.tryParse(p.at);
      if (t == null) continue;
      final seen = lastPart[p.answerId];
      if (seen == null || t.isAfter(seen)) lastPart[p.answerId] = t;
    }
    final never = [
      for (final e in lastPart.entries)
        if (now.difference(e.value) >= keepAfterOpen) e.key,
    ];
    for (final id in never) {
      await store.dropAnswer(id);
    }
    if (never.isNotEmpty) {
      AppLogger.info('ADMIN_ANSWER_SWEPT_UNOPENED', detail: 'answers=${never.length}');
    }
    return old.length + never.length;
  }
}

/// Which chat the Owner picked (2 people or a group).
class ChatPick221 {
  final String kind; // direct | group
  final String userA;
  final String userB;
  final String groupId;
  final String label;

  const ChatPick221.direct(this.userA, this.userB, {this.label = ''})
      : kind = 'direct',
        groupId = '';
  const ChatPick221.group(this.groupId, {this.label = ''})
      : kind = 'group',
        userA = '',
        userB = '';

  bool get isGroup => kind == 'group';

  Map<String, dynamic> toServer() => isGroup
      ? {'kind': 'group', 'group_id': groupId}
      : {'kind': 'direct', 'user_a': userA, 'user_b': userB};

  static ChatPick221? fromRef(Map<String, dynamic>? chat, {String label = ''}) {
    if (chat == null) return null;
    if (chat['kind'] == 'group') {
      final g = chat['group_id']?.toString() ?? '';
      return g.isEmpty ? null : ChatPick221.group(g, label: label);
    }
    final users = [for (final u in (chat['users'] as List? ?? const [])) u.toString()];
    final devs = [for (final d in (chat['devices'] as List? ?? const [])) d.toString()];
    final who = users.length >= 2 ? users : devs;
    return who.length >= 2 ? ChatPick221.direct(who[0], who[1], label: label) : null;
  }
}

/// One row of the Requests tab (server list or this phone's own requests).
class ChatRequestRow221 {
  final String id;
  final String action;
  final String label;
  final String words;
  final String state; // pending | done | cancelled
  final int parts;
  final int of;
  final bool offline; // made on an admin phone: the answer opens there
  final bool oldApp;
  final String madeAt;
  final String parent;
  final String fileId;
  final Map<String, dynamic>? chat;
  final String from;
  final String to;
  /// Bundle 254 (21.12): every phone said it has no copy of this chat.
  final bool empty;
  /// Bundle 307 (live card): phones asked / phones that answered anything,
  /// whose phone sends the answer, and whether the answer was opened / its
  /// copy deleted (then it leaves the live row).
  final int phones;
  final int reached;
  final String fromName;
  final bool opened;
  final bool closed;
  /// Bundle 317 (G5): why the phone said no (`file_gone`), '' = not refused.
  final String refused;

  /// Bundle 318 (K7): a "Get new messages only" request (made on this
  /// phone): how many new ones it added (-1 = not known yet), nothing new,
  /// and since when (the copy's last time, UTC).
  final bool newOnly318;
  final int newCount318;
  final bool upToDate318;
  final String sinceAt318;

  /// Bundle 318 (K7): this request made the kept copy ('' = none): until when.
  final String keptUntil318;

  /// Bundle 318 (K3): opens the kept copy only (a range inside it; no request).
  final bool inside318;

  /// Bundle 325: asked while their phone was away - it waits here and goes by
  /// itself the moment that phone is reachable.
  final bool waiting325;

  const ChatRequestRow221({
    required this.id,
    required this.action,
    this.label = '',
    this.words = '',
    this.state = 'pending',
    this.parts = 0,
    this.of = 0,
    this.offline = false,
    this.oldApp = false,
    this.madeAt = '',
    this.parent = '',
    this.fileId = '',
    this.chat,
    this.from = '',
    this.to = '',
    this.empty = false,
    this.phones = 0,
    this.reached = 0,
    this.fromName = '',
    this.opened = false,
    this.closed = false,
    this.refused = '',
    this.newOnly318 = false,
    this.newCount318 = -1,
    this.upToDate318 = false,
    this.sinceAt318 = '',
    this.keptUntil318 = '',
    this.inside318 = false,
    this.waiting325 = false,
  });

  /// Bundle 318: the same row with the kept-copy facts of this phone.
  ChatRequestRow221 with318({
    bool? newOnly,
    int? newCount,
    bool? upToDate,
    String? sinceAt,
    String? keptUntil,
  }) =>
      ChatRequestRow221(
        id: id,
        action: action,
        label: label,
        words: words,
        state: state,
        parts: parts,
        of: of,
        offline: offline,
        oldApp: oldApp,
        madeAt: madeAt,
        parent: parent,
        fileId: fileId,
        chat: chat,
        from: from,
        to: to,
        empty: empty,
        phones: phones,
        reached: reached,
        fromName: fromName,
        opened: opened,
        closed: closed,
        refused: refused,
        newOnly318: newOnly ?? newOnly318,
        newCount318: newCount ?? newCount318,
        upToDate318: upToDate ?? upToDate318,
        sinceAt318: sinceAt ?? sinceAt318,
        keptUntil318: keptUntil ?? keptUntil318,
        inside318: inside318,
      );

  bool get ready => of > 0 && parts >= of;
  bool get half => parts > 0 && !ready;
  bool get cancelled => state == 'cancelled';

  /// The words on the right of a row (mock A-1 / A-2).
  String get tag {
    if (empty) return L.t.noMessages;
    if (cancelled) return L.t.cancelled;
    if (ready) return L.t.ready;
    if (half) return L.t.ofParts(parts, of);
    if (oldApp) return L.t.oldApp;
    return L.t.pending;
  }

  static ChatRequestRow221 fromServer(Map<String, dynamic> m) {
    int n(String k) => m[k] is int ? m[k] as int : int.tryParse('${m[k] ?? ''}') ?? 0;
    String s(String k) => m[k]?.toString() ?? '';
    return ChatRequestRow221(
      id: s('id'),
      action: s('action'),
      label: s('label'),
      words: s('words'),
      state: s('state').isEmpty ? 'pending' : s('state'),
      parts: n('parts'),
      of: n('of'),
      offline: m['offline'] == true,
      oldApp: n('old_app') > 0,
      madeAt: s('made_at'),
      parent: s('parent'),
      fileId: s('file_id'),
      chat: m['chat'] is Map ? Map<String, dynamic>.from(m['chat'] as Map) : null,
      from: s('from'),
      to: s('to'),
      // Bundle 307 (A2): the server closes "No messages" requests too.
      empty: m['empty'] == true,
      phones: n('phones'),
      reached: n('reached'),
      fromName: s('from_name'),
      opened: m['opened'] == true,
      closed: m['closed'] == true,
      refused: s('refused'),
    );
  }

  Map<String, dynamic> toSaved() => {
        'id': id,
        'action': action,
        'label': label,
        'words': words,
        'made_at': madeAt,
        'parent': parent,
        'file_id': fileId,
        if (chat != null) 'chat': chat,
        'from': from,
        'to': to,
      };
}

/// Bundle 314: the codes of a refused Get chat (server 409 and this phone).
const String ownChatCode314 = 'own_chat';
const String alreadyAskedCode314 = 'already_asked';

/// What the Owner screens use: online the server makes the card and opens
/// the answer; offline this phone signs the card (owner cert) and the
/// answer comes back locked for this phone.
class ChatRequests221 {
  static ChatRequests221? instance;
  static const String savedKey = 'admin_chat_requests_221';
  /// Bundle 307 (C3): ids of the server requests made on THIS phone (the
  /// offline ones are in [savedKey]); only these get the phone card.
  static const String mineKey307 = 'chat_req_mine_307';

  /// Bundle 307 (C3): a request was made or cancelled here (the phone card
  /// updates at once instead of on its next check).
  static void Function()? changed307;

  final ChatAdminServer server;
  final Future<AdminSignIn?> Function() signIn;
  final bool Function() serverOnline;
  final AdminActionService? actions;
  final ChatAnswerReader reader;
  final Future<String> Function() myBoxKey;
  final String Function() selfUserId;
  final String Function() selfDeviceId;
  final Future<List<String>> Function(String userOrDevice) phonesOf;
  final Future<List<String>> Function(String groupId) groupDevices;
  final Future<List<Map<String, dynamic>>> Function() localChats;
  final Future<List<Map<String, dynamic>>> Function() people;
  final Future<List<Map<String, dynamic>>> Function() localGroups;
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final DeleteCompletelyDoer? purgeHere;
  final Future<AnswerProgress?> Function(String actionId)? progressOf;

  /// Bundle 321 (F2): the progress of every request in one count.
  final Future<Map<String, AnswerProgress>> Function()? progressAll;

  /// Bundle 314 (1): the server's group list `{groups:[...], nearby:[...]}`.
  final Future<Map<String, dynamic>> Function(String token)? serverGroups;

  /// Bundle 314 (1c): the nearby groups members reported to this phone
  /// `{id, name, members:[device], made_at}`.
  final Future<List<Map<String, dynamic>>> Function()? reportedGroups;
  final DateTime Function() _clock;

  ChatRequests221({
    required this.server,
    required this.signIn,
    required this.serverOnline,
    required this.actions,
    required this.reader,
    required this.myBoxKey,
    required this.selfUserId,
    required this.selfDeviceId,
    required this.phonesOf,
    required this.groupDevices,
    required this.localChats,
    required this.people,
    required this.localGroups,
    required this.read,
    required this.write,
    this.purgeHere,
    this.progressOf,
    this.progressAll,
    this.serverGroups,
    this.reportedGroups,
    this.kept,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Bundle 318 (K1): the Owner phone's kept copies (null = none; tests).
  final Kept318? kept;

  /// Bundle 314 (K5): the last server chat list (owner phone, no message
  /// text) and group list, for the offline Chats tab and offline Get chat.
  static const String chatsSavedKey314 = 'admin_chats_saved_314';
  static const String groupsSavedKey314 = 'admin_groups_saved_314';
  static const int maxSaved314 = 500;

  /// Bundle 323 (P6): when the saved conversations list was last written, so
  /// the Conversations header can say "Saved 18:44" instead of pretending an
  /// old list is today's (17 Nov: the list on screen was 10 minutes old and
  /// nothing said so).
  static const String chatsSavedAt314 = 'admin_chats_saved_at_314';

  Future<String?> _token() async {
    final s = await signIn();
    return s == null || s.role != 'owner' ? null : s.token;
  }

  Future<bool> isOwner() async => (await signIn())?.role == 'owner';

  Future<bool> online() async => serverOnline() && await _token() != null;

  // ----------------------------------------------------------------- lists

  /// Bundle 314: online = the server list (my own chats marked `me`, no
  /// Get chat); offline = the last server list saved here + the nearby
  /// groups members reported, without my own chats (USER PICK K5).
  Future<List<Map<String, dynamic>>> conversations() => _chats321();

  /// Bundle 321 (F13): the saved list only (no server call) - the first
  /// paint of Conversations.
  Future<List<Map<String, dynamic>>> savedConversations321() => _chats321(ask: false);

  Future<List<Map<String, dynamic>>> _chats321({bool ask = true}) async {
    final token = ask ? await _token() : null;
    if (token != null && serverOnline()) {
      try {
        final list = await server.conversations(token);
        final mine = await _mine314();
        final out = [
          for (final c in list) {...c, if (c['me'] == true || await _rowIsMine314(c, mine)) 'me': true},
        ];
        await _saveList314(chatsSavedKey314, [for (final c in out) if (c['me'] != true) c]);
        await _stamp323();
        // Bundle 323 (P2): the group list carries `member_devices` - the only
        // place a group's phones can come from while the server is off. It
        // used to be saved only by the picker (which may never be opened while
        // the server answers), so offline Get chat had no phones to ask.
        await _saveGroups323(token);
        return out;
      } catch (error) {
        AppLogger.info('ADMIN_CHATS_LIST_LOCAL', detail: '$error');
      }
    }
    final mine = await _mine314();
    final out = <Map<String, dynamic>>[];
    final groups = <String>{};
    for (final c in await _savedList314(chatsSavedKey314)) {
      if (c['me'] == true || await _rowIsMine314(c, mine)) continue;
      if (c['kind'] == 'group') groups.add(c['group_id']?.toString() ?? '');
      out.add(c);
    }
    for (final g in await _reported314()) {
      final id = g['id']?.toString() ?? '';
      if (id.isEmpty || groups.contains(id) || g['me'] == true) continue;
      groups.add(id);
      out.add({
        'id': 'n:$id',
        'kind': 'group',
        'group_id': id,
        'group_name': g['name'] ?? '',
        'member_count': g['members'] ?? 0,
        'message_count': 0,
        'last_message_at': g['made_at'] ?? '',
        'nearby': true,
      });
    }
    return out;
  }

  /// Bundle 323 (P2): `/admin/groups` (+ the nearby groups the server knows)
  /// into [groupsSavedKey314], the same shape [pickerGroups314] writes.
  /// Best effort: a failure leaves the old list alone.
  Future<void> _saveGroups323(String token) async {
    final load = serverGroups;
    if (load == null) return;
    try {
      final d = await load(token);
      List<String> devsOf(Map<String, dynamic> m) =>
          [for (final x in (m['member_devices'] as List? ?? const [])) if ('$x'.isNotEmpty) '$x'];
      final list = <Map<String, dynamic>>[];
      for (final g in (d['groups'] as List? ?? const [])) {
        if (g is! Map) continue;
        final m = Map<String, dynamic>.from(g);
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final devices = devsOf(m);
        final n = m['members'];
        list.add({
          'id': id,
          'name': m['name']?.toString() ?? '',
          'members': n is int ? n : int.tryParse('${n ?? ''}') ?? devices.length,
          'nearby': false,
          'member_devices': devices,
          if (m['me'] == true) 'me': true,
        });
      }
      for (final g in (d['nearby'] as List? ?? const [])) {
        if (g is! Map) continue;
        final m = Map<String, dynamic>.from(g);
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final devices = devsOf(m);
        list.add({
          'id': id,
          'name': m['name']?.toString() ?? '',
          'members': devices.length,
          'nearby': true,
          'member_devices': devices,
          if (m['me'] == true) 'me': true,
        });
      }
      if (list.isEmpty) return;
      await _saveList314(groupsSavedKey314, list);
      AppLogger.info('GROUPS_SAVED323', detail: 'groups=${list.length}');
    } catch (error) {
      AppLogger.info('ADMIN_GROUPS_LIST323_SKIP', detail: '$error');
    }
  }

  // ----------------------------------------------------- Bundle 314 lists

  /// My phones + my user id (one phone = one account; more after a move).
  Future<Set<String>> _mine314() async => {
        selfDeviceId(),
        selfUserId(),
        ...await phonesOf(selfUserId()).catchError((_) => <String>[]),
      }..remove('');

  Future<bool> _groupIsMine314(String groupId, Set<String> mine) async {
    if (groupId.isEmpty) return false;
    final devices = await groupDevices(groupId).catchError((_) => <String>[]);
    return devices.any(mine.contains);
  }

  Future<bool> _rowIsMine314(Map<String, dynamic> c, Set<String> mine) async {
    if (c['kind'] == 'group') return _groupIsMine314(c['group_id']?.toString() ?? '', mine);
    for (final x in (c['participants'] as List? ?? const [])) {
      if (x is Map && mine.contains(x['id']?.toString() ?? '')) return true;
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> _savedList314(String key) async {
    try {
      final d = jsonDecode(await read(key) ?? '[]');
      return [for (final x in (d is List ? d : const [])) if (x is Map) Map<String, dynamic>.from(x)];
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveList314(String key, List<Map<String, dynamic>> list) async {
    try {
      await write(key, jsonEncode(list.take(maxSaved314).toList()));
    } catch (_) {}
  }

  /// Bundle 323 (P6): the time the saved list was written.
  Future<void> _stamp323() async {
    try {
      await write(chatsSavedAt314, _clock().toUtc().toIso8601String());
    } catch (_) {}
  }

  /// Bundle 323 (P5): the words a person sees when this phone cannot reach a
  /// chat yet. Online, the old sentence is true and stays. Offline, it is a
  /// dead end - the phones live in the server's group list, so say that.
  @visibleForTesting
  static String unknownPhonesWords323({required bool group, required bool serverOff}) {
    if (!serverOff) return "This phone doesn't know their phones yet.";
    return group ? L.t.serverOffGroupPhones324 : L.t.serverOffPersonPhone324;
  }

  /// Bundle 323 (P6): null when this phone never saved a list yet.
  Future<DateTime?> savedAt323() async {
    try {
      final raw = await read(chatsSavedAt314);
      return raw == null || raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Reported nearby groups, `me` when one of my phones is a member.
  Future<List<Map<String, dynamic>>> _reported314() async {
    final mine = await _mine314();
    final out = <Map<String, dynamic>>[];
    for (final g in await (reportedGroups?.call() ?? Future.value(const <Map<String, dynamic>>[]))
        .catchError((_) => <Map<String, dynamic>>[])) {
      final members = [for (final d in (g['members'] as List? ?? const [])) d.toString()];
      out.add({
        'id': g['id']?.toString() ?? '',
        'name': g['name']?.toString() ?? '',
        'members': members.length,
        'member_devices': members,
        'made_at': g['made_at']?.toString() ?? '',
        'nearby': true,
        if (members.any(mine.contains)) 'me': true,
      });
    }
    return out;
  }

  /// Bundle 314 (1): the group picker = every group I am NOT in: the
  /// server's groups (+ reported nearby ones it knows), the last saved
  /// server list when offline, groups this phone knows that I am not in,
  /// and the nearby groups reported to this phone.
  /// Rows: `{id, name, members, nearby, member_devices}`.
  Future<List<Map<String, dynamic>>> pickerGroups314() async {
    final mine = await _mine314();
    final byId = <String, Map<String, dynamic>>{};
    void add(Map<String, dynamic> g) {
      final id = g['id']?.toString() ?? '';
      if (id.isEmpty || byId.containsKey(id)) return;
      byId[id] = g;
    }

    Map<String, dynamic> row(Map<String, dynamic> g, {bool nearby = false}) {
      final devices = [for (final d in (g['member_devices'] as List? ?? const [])) d.toString()];
      final n = g['members'];
      return {
        'id': g['id']?.toString() ?? '',
        'name': g['name']?.toString() ?? '',
        'members': n is int ? n : int.tryParse('${n ?? ''}') ?? devices.length,
        'nearby': nearby || g['nearby'] == true,
        'member_devices': devices,
        if (g['me'] == true || devices.any(mine.contains)) 'me': true,
      };
    }

    // Bundle 323 (P3): where the rows came from, for the one log line below.
    var src323 = 'local';
    var fromServer = false;
    final token = await _token();
    final load = serverGroups;
    if (load != null && token != null && serverOnline()) {
      try {
        final d = await load(token);
        final list = <Map<String, dynamic>>[
          for (final g in (d['groups'] as List? ?? const [])) if (g is Map) row(Map<String, dynamic>.from(g)),
          for (final g in (d['nearby'] as List? ?? const []))
            if (g is Map) row(Map<String, dynamic>.from(g), nearby: true),
        ];
        await _saveList314(groupsSavedKey314, list);
        list.forEach(add);
        fromServer = true;
        src323 = 'server';
      } catch (error) {
        AppLogger.info('ADMIN_GROUPS_LIST_LOCAL', detail: '$error');
      }
    }
    if (!fromServer) {
      final savedGroups323 = await _savedList314(groupsSavedKey314);
      savedGroups323.map((g) => row(g)).forEach(add);
      // Bundle 323 (P1): the groups the Conversations list already shows are
      // askable here too. The saved server chats carry the name and the member
      // count only (no phones), so a group the saved server list already knows
      // keeps that row - and its `member_devices`.
      var fromChats323 = 0;
      for (final c in await _savedList314(chatsSavedKey314)) {
        if (c['kind'] != 'group') continue;
        final id = c['group_id']?.toString() ?? '';
        if (id.isEmpty || byId.containsKey(id)) continue;
        final n = c['member_count'];
        add({
          'id': id,
          'name': c['group_name']?.toString() ?? '',
          'members': n is int ? n : int.tryParse('${n ?? ''}') ?? 0,
          'nearby': false,
          'member_devices': const <String>[],
        });
        fromChats323++;
      }
      src323 = savedGroups323.isNotEmpty
          ? (fromChats323 > 0 ? 'saved+chats' : 'saved')
          : (fromChats323 > 0 ? 'chats' : 'local');
    }
    for (final g in await localGroups().catchError((_) => <Map<String, dynamic>>[])) {
      final id = g['id']?.toString() ?? '';
      if (id.isEmpty || byId.containsKey(id)) continue;
      final devices = await groupDevices(id).catchError((_) => <String>[]);
      add({
        'id': id,
        'name': g['name']?.toString() ?? '',
        'members': devices.length,
        'nearby': false,
        'member_devices': devices,
        if (devices.any(mine.contains)) 'me': true,
      });
    }
    (await _reported314()).map((g) => row(g, nearby: true)).forEach(add);
    // A group a member phone of mine is in is mine (also when only the
    // local list knows it).
    final out = <Map<String, dynamic>>[];
    for (final g in byId.values) {
      if (g['me'] == true || await _groupIsMine314(g['id'].toString(), mine)) continue;
      out.add(g);
    }
    out.sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
    // Bundle 323 (P3): one line per picker open - 17 Nov had no line at all,
    // so "only one group" could not be explained from a log.
    AppLogger.info('PICKER_LIST323',
        detail: 'src=$src323 known=${byId.length} shown=${out.length} mine=${byId.length - out.length}');
    return out;
  }

  /// Bundle 314 (1): the people picker - everyone but me.
  Future<List<Map<String, dynamic>>> pickerPeople314() async {
    final mine = await _mine314();
    return [
      for (final p in await people())
        if (p['me'] != true && !mine.contains(p['id']?.toString() ?? '')) p,
    ];
  }

  /// Bundle 314 (1): I am one of the two people / a member of the group.
  Future<bool> isOwnChat314(ChatPick221 pick) async {
    final mine = await _mine314();
    if (pick.isGroup) {
      if (await _groupIsMine314(pick.groupId, mine)) return true;
      return (await _knownGroupDevices314(pick.groupId)).any(mine.contains);
    }
    if (mine.contains(pick.userA) || mine.contains(pick.userB)) return true;
    final a = await phonesOf(pick.userA).catchError((_) => <String>[]);
    final b = await phonesOf(pick.userB).catchError((_) => <String>[]);
    return [...a, ...b].any((d) => d.isNotEmpty && d == selfDeviceId());
  }

  /// Member phones of a group this phone is not in: the saved server list or
  /// a member's nearby note.
  Future<List<String>> _knownGroupDevices314(String groupId) async {
    for (final g in [...await _savedList314(groupsSavedKey314), ...await _reported314()]) {
      if (g['id']?.toString() != groupId) continue;
      final d = [for (final x in (g['member_devices'] as List? ?? const [])) x.toString()]..remove('');
      if (d.isNotEmpty) return d;
    }
    return const [];
  }

  /// Bundle 314 (1b): the open (Sent / Reached / Coming) Get chat request
  /// of this chat, or null. Ready, cancelled, empty and done don't block.
  Future<ChatRequestRow221?> openRequestFor314(ChatPick221 pick, {List<ChatRequestRow221>? rows}) async {
    final mine324 = RequestScope324.chatKeyOfPick(pick);
    for (final r in rows ?? await requests()) {
      if (r.action != 'get_chat' || r.state != 'pending' || r.ready || r.empty || r.closed || r.cancelled) continue;
      // Bundle 324 (2.4): the offline-proof guard. `_samePeople314` compares
      // phones, and offline the phone list is empty - that is how the 17 Nov
      // 18:53 request got through 6 minutes after the 18:47 one. The key the
      // request was made with is saved next to it, so it always matches.
      if (mine324.isNotEmpty && RequestScope324.chatKeyOf(r.id) == mine324) return r;
      final p = ChatPick221.fromRef(r.chat);
      if (p == null || p.kind != pick.kind) continue;
      if (pick.isGroup ? p.groupId == pick.groupId : await _samePeople314(p, pick)) return r;
    }
    return null;
  }

  Future<bool> _samePeople314(ChatPick221 x, ChatPick221 y) async {
    if ({x.userA, x.userB}.containsAll([y.userA, y.userB])) return true;
    // Server rows have phone ids, saved ones user ids: compare the phones.
    Future<Set<String>> phones(String who) async =>
        {who, ...await phonesOf(who).catchError((_) => <String>[])}..remove('');
    final xa = await phones(x.userA), xb = await phones(x.userB);
    final ya = await phones(y.userA), yb = await phones(y.userB);
    bool meet(Set<String> p, Set<String> q) => p.any(q.contains);
    return (meet(xa, ya) && meet(xb, yb)) || (meet(xa, yb) && meet(xb, ya));
  }

  Future<List<Map<String, dynamic>>> _saved() async {
    try {
      final d = jsonDecode(await read(savedKey) ?? '[]');
      return [for (final x in (d is List ? d : const [])) if (x is Map) Map<String, dynamic>.from(x)];
    } catch (_) {
      return [];
    }
  }

  Future<void> _remember(ChatRequestRow221 r) async {
    final all = await _saved()..removeWhere((m) => m['id'] == r.id);
    all.insert(0, r.toSaved());
    // Bundle 317 (G1): Get file rows don't push Get chat rows out: 200 other
    // rows; a Get file row stays while its chat request stays (max 600).
    final kept = <Map<String, dynamic>>[];
    for (final m in all) {
      if (m['action'] != 'get_file' && kept.length < 200) kept.add(m);
    }
    final parents = {for (final m in kept) m['id']?.toString() ?? ''};
    var files = 0;
    for (final m in all) {
      if (m['action'] == 'get_file' && files < 600 && (parents.contains(m['parent']?.toString() ?? '') ||
          !all.any((x) => x['id'] == m['parent']))) {
        kept.add(m);
        files++;
      }
    }
    final order = {for (var i = 0; i < all.length; i++) all[i]['id']?.toString() ?? '': i};
    kept.sort((a, b) => (order[a['id']?.toString() ?? ''] ?? 0).compareTo(order[b['id']?.toString() ?? ''] ?? 0));
    await write(savedKey, jsonEncode(kept));
  }

  /// Requests: the server list when online + this phone's own ones.
  Future<List<ChatRequestRow221>> requests() => _rows321();

  /// Bundle 321 (F13): this phone's own requests only (no server call).
  Future<List<ChatRequestRow221>> savedRequests321() => _rows321(ask: false);

  Future<List<ChatRequestRow221>> _rows321({bool ask = true}) async {
    // Bundle 325: every card check is also a chance to deliver a Waiting ask
    // (at most one attempt a minute, see fireWaiting325).
    if (ask) {
      try {
        await fireWaiting325();
      } catch (_) {}
    }
    final out = <String, ChatRequestRow221>{};
    final token = ask ? await _token() : null;
    if (token != null && serverOnline()) {
      try {
        for (final m in await server.requests(token)) {
          final r = ChatRequestRow221.fromServer(m);
          if (r.id.isNotEmpty) out[r.id] = r;
        }
      } catch (_) {}
    }
    final states = {for (final r in actions?.rows() ?? const []) r.id: r};
    // Bundle 321 (F2): ONE count for all requests (was one parts read per
    // saved request).
    Map<String, AnswerProgress>? all;
    try {
      all = await progressAll?.call();
    } catch (_) {}
    final waitingIds325 = {for (final w in await waitingAll325()) w.id};
    // Bundle 327: my own phones answered here -> the row says 0 MB.
    final mineIds327 = {selfDeviceId(), ...await phonesOf(selfUserId()).catchError((_) => <String>[])}
      ..remove('');
    for (final m in await _saved()) {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final p = all != null ? all[id] : await progressOf?.call(id);
      final st = states[id];
      final known = out[id];
      out[id] = ChatRequestRow221(
        id: id,
        action: m['action']?.toString() ?? 'get_chat',
        label: m['label']?.toString() ?? known?.label ?? '',
        // Bundle 327: one of MY phones answered - say it cost 0 MB.
        words: mineIds327.contains(m['from']?.toString() ?? '')
            ? '${m['words']?.toString() ?? ''} \u00b7 ${L.t.phoneToPhone327}'.trim()
            : m['words']?.toString() ?? '',
        state: st?.state ?? known?.state ?? 'pending',
        parts: p?.have ?? known?.parts ?? 0,
        of: p?.of ?? known?.of ?? 0,
        offline: true,
        oldApp: st?.oldApp ?? false,
        madeAt: m['made_at']?.toString() ?? '',
        parent: m['parent']?.toString() ?? '',
        fileId: m['file_id']?.toString() ?? '',
        chat: m['chat'] is Map ? Map<String, dynamic>.from(m['chat'] as Map) : known?.chat,
        from: m['from']?.toString() ?? '',
        to: m['to']?.toString() ?? '',
        empty: (st?.emptyAll ?? false) || (known?.empty ?? false),
        waiting325: waitingIds325.contains(id), // Bundle 325
        phones: (st?.phones ?? 0) > 0 ? st!.phones : known?.phones ?? 0,
        reached: (st?.reached ?? 0) > (known?.reached ?? 0) ? st!.reached : known?.reached ?? 0,
        fromName: known?.fromName ?? '',
        opened: known?.opened ?? false,
        closed: known?.closed ?? false,
        refused: (st?.refused ?? '').isNotEmpty ? st!.refused : known?.refused ?? '',
      );
    }
    final list = out.values.toList()..sort((a, b) => b.madeAt.compareTo(a.madeAt));
    return _with318(list); // Bundle 318 (K7)
  }

  // -------------------------------------------------------------- requests

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Range words + days (same as the server's `chatRange`).
  ({String from, String to, String words}) rangeOf(String range, {DateTime? from, DateTime? to}) {
    final now = _clock();
    return switch (range) {
      '7' || '30' => (
          from: _day(now.subtract(Duration(days: int.parse(range)))),
          to: _day(now),
          words: 'Last $range days'
        ),
      'dates' when from != null && to != null => (
          from: _day(from),
          to: _day(to),
          words: '${_day(from)} - ${_day(to)}'
        ),
      _ => (from: '', to: '', words: 'Full chat'),
    };
  }

  /// Bundle 254 (21.12): both accounts are on the very same phone(s).
  Future<bool> samePhone(String userA, String userB) async {
    if (userA.isEmpty || userB.isEmpty || userA == userB) return false;
    final a = (await phonesOf(userA).catchError((_) => <String>[])).where((d) => d.isNotEmpty).toSet();
    final b = (await phonesOf(userB).catchError((_) => <String>[])).where((d) => d.isNotEmpty).toSet();
    return a.isNotEmpty && a.length == b.length && a.containsAll(b);
  }

  /// The chat ref (all phones of it) + the phones a card goes to (not mine).
  /// Bundle 314 tests: the offline targets of a pick.
  @visibleForTesting
  Future<({Map<String, dynamic> chat, List<String> targets, List<String> mine, bool meIn})> resolve314(
          ChatPick221 pick) =>
      _resolve(pick);

  Future<({Map<String, dynamic> chat, List<String> targets, List<String> mine, bool meIn})> _resolve(
      ChatPick221 pick) async {
    final mine = {selfDeviceId(), ...await phonesOf(selfUserId()).catchError((_) => <String>[])}
      ..remove('');
    List<String> devices;
    Map<String, dynamic> chat;
    if (pick.isGroup) {
      devices = await groupDevices(pick.groupId);
      // Bundle 314 (K8): a group I am not in - its phones from the saved
      // server list or a member's nearby note.
      if (devices.isEmpty) devices = await _knownGroupDevices314(pick.groupId);
      chat = {'kind': 'group', 'group_id': pick.groupId};
    } else {
      final a = await phonesOf(pick.userA);
      final b = await phonesOf(pick.userB);
      devices = {...a, ...b}.toList();
      chat = {
        'kind': 'direct',
        'users': [pick.userA, pick.userB],
        'devices': devices,
      };
    }
    final targets = [for (final d in devices) if (!mine.contains(d)) d];
    // Bundle 327: my own phones are a legal source too (they were dropped
    // from [targets] on purpose - a phone must not ask itself). The card goes
    // to my phones first, so a copy already on one of them costs 0 MB.
    final mine327 = [for (final d in devices) if (mine.contains(d)) d];
    return (chat: chat, targets: targets, mine: mine327, meIn: devices.any(mine.contains));
  }

  /// Get chat. Returns the request id.
  Future<String> request(ChatPick221 pick,
      {String range = 'full',
      DateTime? from,
      DateTime? to,
      Map<String, dynamic> since318 = const {},
      Set<String>? types324}) async {
    // Bundle 324: what this request may bring (null = everything).
    final with324 = RequestScope324.typesFrom(types324);
    final r = rangeOf(range, from: from, to: to);
    // Bundle 254 (21.12): two accounts on ONE phone have no chat together.
    if (!pick.isGroup && await samePhone(pick.userA, pick.userB)) {
      AppLogger.info('GET_CHAT_FAIL323', detail: 'why=same_phone');
      throw StateError('These two accounts are on the same phone - there is no chat between them.');
    }
    // Bundle 314 (1 / 1b): not my own chats; one open request per chat.
    if (await isOwnChat314(pick)) {
      AppLogger.info('GET_CHAT_FAIL323', detail: 'why=own group=${pick.isGroup}');
      throw ChatAdminRefused(409, ownChatCode314, L.t.ownChat314);
    }
    final open = await openRequestFor314(pick);
    if (open != null) {
      AppLogger.info('GET_CHAT_FAIL323', detail: 'why=already open=${open.id.length > 6 ? open.id.substring(open.id.length - 6) : open.id}');
      throw ChatAdminRefused(409, alreadyAskedCode314, L.t.alreadyAskedText314, openId: open.id);
    }
    final token = await _token();
    if (token != null && serverOnline()) {
      // Bundle 324e: `with` is a hint, and only a hint - this phone already
      // filters what it shows and what it downloads (RequestScope324). An older
      // server does not know the key and refuses the WHOLE body ("invalid
      // request body", 18 Nov 20:53), so ask once without it and remember.
      final sendWith324 = with324 != null && !RequestScope324.serverNoWith324;
      final body324 = <String, dynamic>{
        ...pick.toServer(),
        'range': range,
        if (range == 'dates') 'from': r.from,
        if (range == 'dates') 'to': r.to,
        ...since318, // Bundle 318 (K4)
        if (sendWith324) 'with': with324.toList()..sort(), // Bundle 324
      };
      Map<String, dynamic> res;
      try {
        res = await server.create(token, body324);
      } on ChatAdminRefused catch (e) {
        if (!(sendWith324 && isOldServerNoWith324(e))) rethrow;
        AppLogger.info('CHAT_REQ324',
            detail: 'with=refused status=${e.status} -> retry=without');
        await RequestScope324.markServerNoWith324();
        body324.remove('with');
        res = await server.create(token, body324);
      }
      final id = res['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        await _markMine307(id);
        await RequestScope324.remember(id,
            chatKey: RequestScope324.chatKeyOfPick(pick), types: with324);
        changed307?.call();
      }
      return id;
    }
    final svc = actions;
    if (svc == null) {
      AppLogger.info('GET_CHAT_FAIL323', detail: 'why=actions_not_ready');
      throw StateError('Admin actions are not ready.');
    }
    final who = await _resolve(pick);
    if (who.meIn) {
      AppLogger.info('GET_CHAT_FAIL323', detail: 'why=own_devices group=${pick.isGroup}');
      throw ChatAdminRefused(409, ownChatCode314, L.t.ownChat314); // Bundle 314 (1)
    }
    final chatKey325 = RequestScope324.chatKeyOfPick(pick);
    final to327 = [...who.mine, ...who.targets]; // Bundle 327: my phones first
    // Bundle 329: the phone keeps its own record of what it asked for.
    await Evidence329.instance
        .add('ask', 'Get chat \u00b7 ${pick.label}'.trim())
        .catchError((_) => 0);
    if (to327.isEmpty) {
      // Bundle 323 (P3) found the dead end; Bundle 325 ends it. Nothing is
      // thrown away: the ask is saved on this phone and shows as Waiting.
      // Bundle 323's words are kept as the row's words (offline, no server).
      final off323 = !serverOnline();
      return _waitHere325(
        pick,
        chatKey: chatKey325,
        range: range,
        from: r.from,
        to: r.to,
        types: with324?.toList(),
        words: unknownPhonesWords323(group: pick.isGroup, serverOff: off323),
        why: 'targets_empty server=${!off323}',
      );
    }
    final detail = {
      'chat': who.chat,
      'from': r.from,
      'to': r.to,
      'plus_day': true,
      ...since318,
      if (with324 != null) 'with': with324.toList()..sort(), // Bundle 324
    };
    final String id;
    try {
      id = await svc.make(
        action: 'get_chat',
        targetUserId: '',
        label: pick.label,
        targetDevices: to327, // Bundle 327: my own phones first
        detail: detail,
        words: 'Get chat \u00b7 ${r.words}',
        replyKey: await myBoxKey(),
        need: 1,
      );
    } catch (_) {
      // Bundle 325: the phones were listed but the card could not be made.
      // Same rule - the ask waits here instead of being lost.
      return _waitHere325(
        pick,
        chatKey: chatKey325,
        range: range,
        from: r.from,
        to: r.to,
        types: with324?.toList(),
        words: unknownPhonesWords323(group: pick.isGroup, serverOff: !serverOnline()),
        why: 'make_failed',
      );
    }
    await waitingDrop325(chatKey325); // 325: a real send clears its Waiting twin
    await RequestScope324.remember(id,
        chatKey: RequestScope324.chatKeyOfPick(pick), types: with324);
    await _remember(ChatRequestRow221(
        id: id,
        action: 'get_chat',
        label: pick.label,
        words: r.words,
        madeAt: _clock().toUtc().toIso8601String(),
        chat: who.chat,
        from: r.from,
        to: r.to,
        offline: true));
    changed307?.call();
    return id;
  }

  // ------------------------------------------------------- 325: Waiting asks

  /// Bundle 325: where the Waiting asks live (this phone only, no server).
  static const String waitingKey325 = 'waiting_ask_325';
  static const int maxWaiting325 = 100;

  /// One attempt a minute at most, however often the card refreshes.
  static const Duration fireGap325 = Duration(seconds: 60);
  DateTime? _lastFire325;
  bool _firing325 = false;

  Future<List<WaitingAsk325>> waitingAll325() async {
    try {
      return WaitingAsk325.listFrom(await read(waitingKey325));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _waitingSave325(List<WaitingAsk325> list) async {
    try {
      await write(waitingKey325, WaitingAsk325.encode(list.take(maxWaiting325).toList()));
    } catch (_) {
      // No store (tests, first run): the row still shows on this screen.
    }
  }

  /// Bundle 325: a real send (or a Stop) clears the Waiting twin of that chat.
  Future<void> waitingDrop325(String idOrChatKey) async {
    final all = await waitingAll325();
    final kept = [
      for (final w in all)
        if (w.id != idOrChatKey && w.chatKey != idOrChatKey) w,
    ];
    if (kept.length != all.length) await _waitingSave325(kept);
  }

  ChatPick221? _pickOf325(WaitingAsk325 w) {
    final p = w.pick;
    if (p['kind'] == 'group') {
      final g = p['group_id']?.toString() ?? '';
      return g.isEmpty ? null : ChatPick221.group(g, label: w.label);
    }
    final a = p['user_a']?.toString() ?? '';
    final b = p['user_b']?.toString() ?? '';
    return a.isEmpty || b.isEmpty ? null : ChatPick221.direct(a, b, label: w.label);
  }

  /// Bundle 325: save an ask that could not go out now, and show it as Waiting.
  /// One per chat (the 324 key), so a second tap opens the same card.
  Future<String> _waitHere325(
    ChatPick221 pick, {
    required String chatKey,
    required String range,
    required String from,
    required String to,
    required String words,
    required String why,
    List<String>? types,
  }) async {
    final now = _clock().toUtc();
    final id = 'w325-${now.millisecondsSinceEpoch}';
    final all = await waitingAll325()..removeWhere((w) => w.chatKey == chatKey || w.id == id);
    all.insert(
      0,
      WaitingAsk325(
        id: id,
        chatKey: chatKey,
        pick: pick.toServer(),
        madeAt: now.toIso8601String(),
        label: pick.label,
        range: range,
        from: from,
        to: to,
        types: types ?? const [],
      ),
    );
    await _waitingSave325(all);
    await RequestScope324.remember(id,
        chatKey: chatKey, types: types == null ? null : types.toSet());
    await _remember(ChatRequestRow221(
      id: id,
      action: 'get_chat',
      label: pick.label,
      words: words,
      madeAt: now.toIso8601String(),
      from: from,
      to: to,
      offline: true,
      waiting325: true,
    ));
    AppLogger.info('GET_CHAT_WAIT325', detail: 'why=$why group=${pick.isGroup}');
    changed307?.call();
    return id;
  }

  Future<void> _forgetSaved325(String id) async {
    final all = await _saved();
    final kept = [
      for (final m in all)
        if (m['id']?.toString() != id) m,
    ];
    if (kept.length != all.length) await write(savedKey, jsonEncode(kept));
  }

  /// Bundle 325: try every Waiting ask once. Called from the card refresh (so
  /// on app start and every check while the app is open), never faster than
  /// [fireGap325]. Returns how many went out.
  ///
  /// Nothing here needs a server: it is this phone reaching the other phone.
  Future<int> fireWaiting325({bool force = false}) async {
    if (_firing325) return 0;
    final svc = actions;
    if (svc == null) return 0;
    final now = _clock();
    final last = _lastFire325;
    if (!force && last != null && now.difference(last) < fireGap325) return 0;
    final all = await waitingAll325();
    if (all.isEmpty) return 0;
    _firing325 = true;
    _lastFire325 = now;
    var sent = 0;
    try {
      for (final w in all) {
        final pick = _pickOf325(w);
        if (pick == null) continue;
        try {
          final who = await _resolve(pick);
          final to327f = [...who.mine, ...who.targets]; // Bundle 327
          if (who.meIn || to327f.isEmpty) {
            await _bumpTry325(w);
            continue;
          }
          final id = await svc.make(
            action: 'get_chat',
            targetUserId: '',
            label: w.label.isNotEmpty ? w.label : pick.label,
            targetDevices: to327f, // Bundle 327
            detail: {
              'chat': who.chat,
              'from': w.from,
              'to': w.to,
              'plus_day': true,
              if (w.types.isNotEmpty) 'with': [...w.types]..sort(),
            },
            words: 'Get chat \u00b7 ${w.range}',
            replyKey: await myBoxKey(),
            need: 1,
          );
          await RequestScope324.remember(id,
              chatKey: w.chatKey,
              types: w.types.isEmpty ? null : w.types.toSet());
          await _forgetSaved325(w.id);
          await waitingDrop325(w.id);
          await _remember(ChatRequestRow221(
            id: id,
            action: 'get_chat',
            label: w.label,
            words: w.range,
            madeAt: w.madeAt,
            chat: who.chat,
            from: w.from,
            to: w.to,
            offline: true,
          ));
          await _markMine307(id);
          sent++;
          AppLogger.info('GET_CHAT_WAIT325_SENT',
              detail: 'tries=${w.tries + 1} group=${pick.isGroup}');
        } catch (_) {
          await _bumpTry325(w);
        }
      }
    } finally {
      _firing325 = false;
      if (sent > 0) changed307?.call();
    }
    return sent;
  }

  Future<void> _bumpTry325(WaitingAsk325 w) async {
    final all = await waitingAll325();
    for (var i = 0; i < all.length; i++) {
      if (all[i].id == w.id) all[i] = all[i].tried();
    }
    await _waitingSave325(all);
  }

  /// Bundle 324 (6.7): `Get photos` / `Get videos` on a ready row - the same
  /// request asks for the kinds it skipped. Returns the kinds it now asks
  /// for (unchanged when there was nothing to add).
  Future<Set<String>> topUp324(String requestId, Set<String> kinds) async {
    if (requestId.isEmpty || kinds.isEmpty) return const {};
    final missing = RequestScope324.skipped324(requestId).intersection(kinds);
    if (missing.isEmpty) return const {};
    final now = await RequestScope324.add324(requestId, missing);
    final q = FileQueue317.instance;
    if (q != null) await q.forgetPlan324(requestId);
    AppLogger.info('FILE_QUEUE_PLAN', detail: 'topup kinds=${missing.join(",")}');
    changed307?.call();
    return now;
  }

  Future<List<String>> _mine307() async {
    try {
      final d = jsonDecode(await read(mineKey307) ?? '[]');
      return [for (final x in (d is List ? d : const [])) if ('$x'.isNotEmpty) '$x'];
    } catch (_) {
      return [];
    }
  }

  Future<void> _markMine307(String id) async {
    final all = await _mine307()..remove(id);
    all.insert(0, id);
    await write(mineKey307, jsonEncode(all.take(100).toList()));
  }

  /// Bundle 307 (C3): the Get chat requests made on this phone (offline
  /// cards + server requests sent from here), newest first.
  Future<List<ChatRequestRow221>> mine307() async {
    final ids = {...await _mine307(), for (final m in await _saved()) m['id']?.toString() ?? ''}..remove('');
    if (ids.isEmpty) return const [];
    return [for (final r in await requests()) if (r.action == 'get_chat' && ids.contains(r.id)) r];
  }

  /// Opens an answer (half answers too).
  /// Bundle 318 (K1/K6): a request of a kept copy opens the copy; a
  /// new-only answer is merged into it first (once); a complete full answer
  /// becomes the copy of its chat.
  Future<ChatAnswerView> open(ChatRequestRow221 r) async {
    final k = kept;
    if (k == null || r.action != 'get_chat') return _openRaw(r);
    if (r.inside318) {
      final c = await k.store.copy(r.id);
      if (c != null) return _keptView318(c, r.id, messages: Kept318.within(c.messages, r.from, r.to));
    }
    final entry = (await _newOnly318())[r.id];
    if (entry != null) {
      // Block body: returning the removed Future would make it wait on itself.
      return _merging318[r.id] ??= _openNew318(r, entry).whenComplete(() {
        _merging318.remove(r.id);
      });
    }
    final meta = await k.forRequest(r.id);
    if (meta != null) {
      final c = await k.store.copy(meta.id);
      if (c != null) return _keptView318(c, r.id);
    }
    final v = await _openRaw(r);
    if (v.complete && !v.empty && !v.forAdminPhone && v.messages.isNotEmpty && r.chat != null) {
      try {
        await k.keepAnswer(
          requestId: r.id,
          chat: r.chat!,
          label: r.label,
          from: r.from,
          to: r.to,
          fromName: v.fromName.trim().isNotEmpty ? v.fromName.trim() : r.fromName,
          messages: v.messages,
          sameChat: (chat) => _sameChat318(chat, r.chat!),
        );
      } catch (error) {
        AppLogger.info('KEPT318_SAVE_FAILED', detail: '$error');
      }
    }
    return v;
  }

  // ------------------------------------------------- Bundle 318 kept copy

  /// Request id -> `{copy, n, up, since_at, merged, fix, at}` of the
  /// "Get new messages only" requests made on this phone.
  static const String newOnlyKey318 = 'chat_new_only_318';
  static const int maxNewOnly318 = 100;
  final Map<String, Future<ChatAnswerView>> _merging318 = {};
  final Set<String> _settling318 = {};

  Future<Map<String, Map<String, dynamic>>> _newOnly318() async {
    try {
      final d = jsonDecode(await read(newOnlyKey318) ?? '{}');
      return {
        if (d is Map)
          for (final e in d.entries)
            if (e.value is Map) '${e.key}': Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveNewOnly318(Map<String, Map<String, dynamic>> all) async {
    final ids = all.keys.toList()..sort((a, b) => '${all[b]!['at']}'.compareTo('${all[a]!['at']}'));
    await write(newOnlyKey318, jsonEncode({for (final id in ids.take(maxNewOnly318)) id: all[id]}));
  }

  Future<void> _setNewOnly318(String id, Map<String, dynamic> e) async {
    final all = await _newOnly318();
    all[id] = e;
    await _saveNewOnly318(all);
  }

  Future<bool> _sameChat318(Map<String, dynamic> a, Map<String, dynamic> b) async {
    final x = ChatPick221.fromRef(a);
    final y = ChatPick221.fromRef(b);
    if (x == null || y == null || x.kind != y.kind) return false;
    if (x.isGroup) return x.groupId == y.groupId;
    return _samePeople314(x, y);
  }

  ChatAnswerView _keptView318(KeptCopy318 c, String id,
          {List<Map<String, dynamic>>? messages, bool newOnly = false}) =>
      ChatAnswerView(
        id: id,
        answerId: 'kept318:${c.id}',
        fromName: c.fromName,
        of: 1,
        parts: 1,
        complete: true,
        chat: c.chat,
        from: c.from,
        to: c.to,
        messages: messages ?? c.messages,
        fromKept318: true,
        newOnly318: newOnly,
        newIds318: newOnly ? c.newIds : const [],
        keptGotAt318: c.gotAt,
        keptNewAt318: c.newAt,
        keptUntil318: c.until?.toUtc().toIso8601String() ?? '',
        keptFull318: c.full,
      );

  /// K6: a new-only request: its answer goes into the copy once.
  Future<ChatAnswerView> _openNew318(ChatRequestRow221 r, Map<String, dynamic> entry) async {
    final k = kept!;
    final meta = await k.store.copy(entry['copy']?.toString() ?? '');
    if (meta == null) return _openRaw(r); // the copy went (Close / 7 days)
    if (entry['merged'] == true) return _keptView318(meta, r.id, newOnly: true);
    final v = await _openRaw(r);
    if (!v.complete || v.empty || v.forAdminPhone) return v;
    final m = await k.merge(meta,
        kidId: r.id, incoming: v.messages, days: v.days318, since: v.since318.isNotEmpty ? v.since318 : '${entry['since'] ?? ''}');
    final fix = entry['fix'] == true;
    await _setNewOnly318(r.id, {
      ...entry,
      'merged': true,
      'n': m.added.length,
      'up': m.added.isEmpty,
    });
    AppLogger.info('KEPT318_NEW', detail: 'added=${m.added.length} up_to_date=${v.upToDate318}');
    // K6: late messages with an old time: that day once, by itself.
    if (!fix && m.shortDays.isNotEmpty) unawaited(_askDays318(m.copy, m.shortDays).catchError((Object _) => ''));
    return _keptView318(m.copy, r.id, newOnly: true);
  }

  Future<String> _askDays318(KeptCopy318 c, List<String> days) async {
    final pick = ChatPick221.fromRef(c.chat, label: c.label);
    final from = DateTime.tryParse(days.first);
    final to = DateTime.tryParse(days.last);
    if (pick == null || from == null || to == null) return '';
    final id = await request(pick, range: 'dates', from: from, to: to);
    if (id.isNotEmpty) {
      await _setNewOnly318(id, {
        'copy': c.id,
        'n': -1,
        'up': false,
        'since_at': c.lastAt,
        'fix': true,
        'at': _clock().toUtc().toIso8601String(),
      });
    }
    return id;
  }

  /// K3: the kept copy of a chat (null = none).
  Future<KeptCopy318?> keptFor318(ChatPick221 pick) async {
    final k = kept;
    if (k == null) return null;
    for (final c in await k.store.metas().catchError((Object _) => <KeptCopy318>[])) {
      final p = ChatPick221.fromRef(c.chat);
      if (p == null || p.kind != pick.kind) continue;
      if (pick.isGroup ? p.groupId == pick.groupId : await _samePeople314(p, pick)) return c;
    }
    return null;
  }

  /// K3: `inside` (opens at once), `same` (Already here) or `none`.
  String keptMode318(KeptCopy318 c, String range, {DateTime? from, DateTime? to}) {
    final r = rangeOf(range, from: from, to: to);
    return Kept318.modeOf(c, from: r.from, to: r.to, today: _day(_clock()));
  }

  /// K3: the row "Open it" opens (the copy, or a range inside it).
  ChatRequestRow221 keptRow318(KeptCopy318 c, {String range = '', DateTime? from, DateTime? to}) {
    final inside = range.isNotEmpty;
    final r = inside ? rangeOf(range, from: from, to: to) : (from: c.from, to: c.to, words: '');
    return ChatRequestRow221(
      id: c.id,
      action: 'get_chat',
      label: c.label,
      state: 'done',
      parts: 1,
      of: 1,
      chat: c.chat,
      from: r.from,
      to: r.to,
      fromName: c.fromName,
      opened: true,
      madeAt: c.gotAt,
      keptUntil318: c.until?.toUtc().toIso8601String() ?? '',
      inside318: inside,
    );
  }

  /// K4: "Get new messages only": the copy's range up to today, with
  /// `since` / `since_n` / `since_h`. No copy -> a normal request.
  Future<String> requestNew318(ChatPick221 pick) async {
    final k = kept;
    final meta = await keptFor318(pick);
    final c = meta == null || k == null ? null : await k.store.copy(meta.id);
    final since = c == null ? null : Kept318.sinceOf(c);
    if (c == null || since == null) return request(pick);
    final now = _clock();
    final id = await request(pick,
        range: c.full ? 'full' : 'dates',
        from: c.full ? null : DateTime.tryParse(c.from),
        to: c.full ? null : now,
        since318: {'since': since.since, 'since_n': since.n, 'since_h': since.h});
    if (id.isNotEmpty) {
      await _setNewOnly318(id, {
        'copy': c.id,
        'n': -1,
        'up': false,
        'since_at': c.lastAt,
        'since': since.since,
        'at': now.toUtc().toIso8601String(),
      });
      changed307?.call();
    }
    return id;
  }

  /// K7/K8: the requests of one kept copy (its own + new-only ones).
  Future<Set<String>> family318(String requestId) async {
    final c = await kept?.forRequest(requestId).catchError((Object _) => null);
    return c == null ? {requestId} : {...c.family, requestId};
  }

  /// K7: "full chat · got 15 Nov 10:05 · kept until 22 Nov" ('' = no copy).
  Future<String> copyLine318(String requestId) async {
    final c = await kept?.forRequest(requestId).catchError((Object _) => null);
    if (c == null) return '';
    return L.t.copyLine318(
        Kept318.rangeWords(c), Kept318.dayTime(c.gotAt), Kept318.day(c.until?.toIso8601String() ?? ''));
  }

  /// K8: file ids already here (kept bytes).
  Future<Set<String>> keptFileIds318() async =>
      await kept?.fileIds().catchError((Object _) => <String>{}) ?? <String>{};

  /// K7: rows with the kept-copy facts; a Ready new-only request is merged
  /// once here, so the card knows "12 new" / "Up to date" before opening.
  Future<List<ChatRequestRow221>> _with318(List<ChatRequestRow221> rows) async {
    final k = kept;
    if (k == null) return rows;
    var news = await _newOnly318();
    final metas = await k.store.metas().catchError((Object _) => <KeptCopy318>[]);
    if (news.isEmpty && metas.isEmpty) return rows;
    for (final r in rows) {
      final e = news[r.id];
      if (e == null || e['merged'] == true || !r.ready || r.closed || r.cancelled) continue;
      if (!_settling318.add(r.id)) continue;
      try {
        await open(r);
      } catch (_) {
      } finally {
        _settling318.remove(r.id);
      }
      news = await _newOnly318();
    }
    final until = {for (final c in metas) c.id: c.until?.toUtc().toIso8601String() ?? ''};
    return [
      for (final r in rows)
        if (news[r.id] case final e?)
          r.with318(
            newOnly: true,
            newCount: e['merged'] == true && e['n'] is int ? e['n'] as int : -1,
            upToDate: e['merged'] == true && e['up'] == true,
            sinceAt: e['since_at']?.toString() ?? '',
          )
        else if (until[r.id] case final u?)
          r.with318(keptUntil: u)
        else
          r,
    ];
  }

  Future<ChatAnswerView> _openRaw(ChatRequestRow221 r) async {
    if (!r.offline) {
      final token = await _token();
      if (token != null && serverOnline()) {
        final v = await server.answer(token, r.id);
        if (!v.forAdminPhone) return v;
      }
    }
    return reader.read(r.id, action: r.action);
  }

  /// Get full photo: a get_file card under the chat request.
  Future<String> getFile(ChatRequestRow221 parent,
      {required String fileId, String messageId = '', String name = ''}) async {
    final token = await _token();
    if (!parent.offline && token != null && serverOnline()) {
      final res = await server.file(token, parent.id, fileId: fileId, messageId: messageId, name: name);
      return res['id']?.toString() ?? '';
    }
    final svc = actions;
    final pick = ChatPick221.fromRef(parent.chat, label: parent.label);
    if (svc == null || pick == null) throw StateError('Open the chat again first.');
    final who = await _resolve(pick);
    final id = await svc.make(
      action: 'get_file',
      targetUserId: '',
      label: parent.label,
      targetDevices: [...who.mine, ...who.targets], // Bundle 327: my own phones first
      detail: {'file_id': fileId, 'message_id': messageId},
      words: name.isEmpty ? 'Get full photo' : 'Get full photo \u00b7 $name',
      replyKey: await myBoxKey(),
      need: 1,
      parent: parent.id,
    );
    await _remember(ChatRequestRow221(
        id: id,
        action: 'get_file',
        label: parent.label,
        words: name,
        madeAt: _clock().toUtc().toIso8601String(),
        parent: parent.id,
        fileId: fileId,
        chat: parent.chat,
        offline: true));
    return id;
  }

  Future<Uint8List?> fileBytes(ChatRequestRow221 r) async {
    // Bundle 318 (K8): a file already here is never fetched again.
    final k = kept;
    final have = k == null ? null : await k.fileBytes(r.fileId).catchError((Object _) => null);
    if (have != null && have.isNotEmpty) return have;
    Uint8List? bytes;
    var fromServer = false;
    if (!r.offline) {
      final token = await _token();
      if (token != null && serverOnline()) {
        fromServer = true;
        try {
          bytes = await server.download(token, r.id);
        } catch (error) {
          // Bundle 321 (F10): the server copy failed - the parts on this
          // phone are tried below.
          AppLogger.info('ADMIN_FILE_LOCAL', detail: 'why=server_failed id=${r.id}');
          bytes = null;
        }
      }
    }
    if (!fromServer || bytes == null || bytes.isEmpty) {
      final local = (await reader.read(r.id, action: 'get_file')).fileBytes;
      if (local != null && local.isNotEmpty) bytes = local;
    }
    if (k != null && bytes != null && bytes.isNotEmpty && r.action == 'get_file' && r.parent.isNotEmpty) {
      final c = await k.forRequest(r.parent).catchError((Object _) => null);
      if (c != null) await k.keepFile(r.fileId, c.id, bytes).catchError((Object _) {});
    }
    return bytes;
  }

  /// Bundle 317 (G2): signs the stop for the parts of a request that are
  /// still on the way (set by the app to the carrier's `stopRequest`).
  static Future<void> Function(String actionId)? stopCarried317;

  /// Bundle 317 (G1): ids of the requests made on this phone (no server call).
  Future<Set<String>> mineIds317() async =>
      {...await _mine307(), for (final m in await _saved()) m['id']?.toString() ?? ''}..remove('');

  /// Close: the copy goes now (server and this phone).
  Future<void> close(ChatRequestRow221 r) async {
    await stopCarried317?.call(r.id).catchError((Object _) {});
    final token = await _token();
    if (!r.offline && token != null && serverOnline()) {
      await server.close(token, r.id).catchError((_) {});
    }
    await reader.close(r.id);
    // Bundle 318 (K1): Close = the kept copy goes now (with its files).
    final k = kept;
    final c = k == null ? null : await k.forRequest(r.id).catchError((Object _) => null);
    if (c != null) await k!.drop(c.id).catchError((Object _) {});
  }

  /// Delete completely: message ids / full / range. Returns words for the
  /// snack ("Sent to 3 phones").
  Future<String> deleteCompletely(ChatPick221 pick,
      {required String scope, List<String> ids = const [], String range = '', DateTime? from, DateTime? to}) async {
    final r = rangeOf(range, from: from, to: to);
    // Bundle 318 (K1/K6): the kept copy follows Delete completely.
    final k = kept;
    if (k != null) {
      try {
        if (scope == 'message') {
          await k.dropIds(ids);
        } else if (await keptFor318(pick) case final c?) {
          await k.drop(c.id);
        }
      } catch (_) {}
    }
    final token = await _token();
    if (token != null && serverOnline()) {
      final res = await server.purge(token, {
        ...pick.toServer(),
        'scope': scope,
        if (scope == 'message') 'ids': ids,
        if (scope == 'range') 'range': range,
        if (scope == 'range' && range == 'dates') 'from': r.from,
        if (scope == 'range' && range == 'dates') 'to': r.to,
      });
      final need = res['need'] is int ? res['need'] as int : 0;
      return need > 0 ? 'Sent to $need phones' : 'Deleted on the server';
    }
    final svc = actions;
    if (svc == null) throw StateError('Admin actions are not ready.');
    final who = await _resolve(pick);
    final detail = {
      'chat': who.chat,
      'scope': scope,
      if (scope == 'message') 'ids': ids,
      if (scope == 'range') 'from': r.from,
      if (scope == 'range') 'to': r.to,
    };
    // The admin is in this chat: this phone deletes its own copy now.
    if (who.meIn) await purgeHere?.run(detail);
    if (who.targets.isEmpty) return 'Deleted on this phone';
    final words = switch (scope) {
      'message' => '${ids.length} message(s)',
      'full' => 'Full chat',
      _ => r.words,
    };
    await svc.make(
      action: 'delete_completely',
      targetUserId: '',
      label: pick.label,
      targetDevices: who.targets,
      detail: detail,
      words: 'Delete completely \u00b7 $words',
    );
    return 'Sent to ${who.targets.length} phones';
  }
}
