import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/admin_action_box.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/actions/delete_completely_doer.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart' show AdminSignIn;
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/l10n/l10n.dart';

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
  });

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

class HttpChatAdminServer implements ChatAdminServer {
  HttpChatAdminServer({required this.baseUrl, http.Client? client})
      : _client = BuildHeaderClient(client ?? http.Client());

  final String Function() baseUrl;
  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 30);

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
      await _client.get(_uri('/api/v1/admin/conversations'), headers: _h(token)).timeout(_timeout),
      'conversations');

  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => _list(
      await _client.get(_uri('/api/v1/admin/chat-requests'), headers: _h(token)).timeout(_timeout),
      'requests');

  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async => _map(
      await _client
          .post(_uri('/api/v1/admin/chat-requests'), headers: _h(token), body: jsonEncode(body))
          .timeout(_timeout));

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
      .timeout(_timeout));
}

/// Opens answers meant for this (admin) phone from the local parts.
class ChatAnswerReader {
  static ChatAnswerReader? instance;

  /// The admin phone's copy goes 24 h after it was first opened (or Close).
  static const Duration keepAfterOpen = Duration(hours: 24);

  final AnswerPartStore store;
  final String Function() selfDeviceId;
  final Future<List<SimpleKeyPair>> Function() boxKeys;
  final Future<String> Function(String device) nameOf;
  final DateTime Function() _clock;
  final Map<String, DateTime> _openedAt = <String, DateTime>{};

  ChatAnswerReader({
    required this.store,
    required this.selfDeviceId,
    required this.boxKeys,
    required this.nameOf,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

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
    final mine = (await store.parts())
        .where((p) => p.actionId == actionId && p.replyTo == selfDeviceId())
        .toList();
    if (mine.isEmpty) return ChatAnswerView(id: actionId, action: action);
    final by = <String, Map<int, HeldPart>>{};
    for (final p in mine) {
      (by[p.answerId] ??= <int, HeldPart>{})[p.part] = p; // duplicates joined by number
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
    final data = BytesBuilder(copy: false);
    for (final p in parts) {
      final plain = await openPart(pairs, p);
      if (plain == null) {
        broken++;
        continue;
      }
      if (p.part == 1) {
        if (plain['chat'] is Map) chat = Map<String, dynamic>.from(plain['chat'] as Map);
        from = plain['from']?.toString() ?? '';
        to = plain['to']?.toString() ?? '';
        trimmed = plain['trimmed'] == true;
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
    _openedAt.putIfAbsent(best.key, _clock);
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
    );
  }

  /// Close: the admin phone's copy goes now.
  Future<void> close(String actionId) async {
    final ids = {
      for (final p in await store.parts())
        if (p.actionId == actionId && p.replyTo == selfDeviceId()) p.answerId,
    };
    for (final id in ids) {
      await store.dropAnswer(id);
      await store.stop(id, actionId, _clock().toUtc().toIso8601String());
      _openedAt.remove(id);
    }
    AppLogger.info('ADMIN_ANSWER_CLOSED', detail: 'answers=${ids.length}');
  }

  /// Copies opened more than 24 h ago go (called with the daily sweep).
  Future<int> sweep() async {
    final now = _clock();
    final old = [
      for (final e in _openedAt.entries)
        if (now.difference(e.value) >= keepAfterOpen) e.key,
    ];
    for (final id in old) {
      await store.dropAnswer(id);
      _openedAt.remove(id);
    }
    return old.length;
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
  });

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
    this.serverGroups,
    this.reportedGroups,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Bundle 314 (K5): the last server chat list (owner phone, no message
  /// text) and group list, for the offline Chats tab and offline Get chat.
  static const String chatsSavedKey314 = 'admin_chats_saved_314';
  static const String groupsSavedKey314 = 'admin_groups_saved_314';
  static const int maxSaved314 = 500;

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
  Future<List<Map<String, dynamic>>> conversations() async {
    final token = await _token();
    if (token != null && serverOnline()) {
      try {
        final list = await server.conversations(token);
        final mine = await _mine314();
        final out = [
          for (final c in list) {...c, if (c['me'] == true || await _rowIsMine314(c, mine)) 'me': true},
        ];
        await _saveList314(chatsSavedKey314, [for (final c in out) if (c['me'] != true) c]);
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
      } catch (error) {
        AppLogger.info('ADMIN_GROUPS_LIST_LOCAL', detail: '$error');
      }
    }
    if (!fromServer) (await _savedList314(groupsSavedKey314)).map((g) => row(g)).forEach(add);
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
    for (final r in rows ?? await requests()) {
      if (r.action != 'get_chat' || r.state != 'pending' || r.ready || r.empty || r.closed || r.cancelled) continue;
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
    await write(savedKey, jsonEncode(all.take(200).toList()));
  }

  /// Requests: the server list when online + this phone's own ones.
  Future<List<ChatRequestRow221>> requests() async {
    final out = <String, ChatRequestRow221>{};
    final token = await _token();
    if (token != null && serverOnline()) {
      try {
        for (final m in await server.requests(token)) {
          final r = ChatRequestRow221.fromServer(m);
          if (r.id.isNotEmpty) out[r.id] = r;
        }
      } catch (_) {}
    }
    final states = {for (final r in actions?.rows() ?? const []) r.id: r};
    for (final m in await _saved()) {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final p = await progressOf?.call(id);
      final st = states[id];
      final known = out[id];
      out[id] = ChatRequestRow221(
        id: id,
        action: m['action']?.toString() ?? 'get_chat',
        label: m['label']?.toString() ?? known?.label ?? '',
        words: m['words']?.toString() ?? '',
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
        phones: (st?.phones ?? 0) > 0 ? st!.phones : known?.phones ?? 0,
        reached: (st?.reached ?? 0) > (known?.reached ?? 0) ? st!.reached : known?.reached ?? 0,
        fromName: known?.fromName ?? '',
        opened: known?.opened ?? false,
        closed: known?.closed ?? false,
      );
    }
    final list = out.values.toList()..sort((a, b) => b.madeAt.compareTo(a.madeAt));
    return list;
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
  Future<({Map<String, dynamic> chat, List<String> targets, bool meIn})> resolve314(ChatPick221 pick) =>
      _resolve(pick);

  Future<({Map<String, dynamic> chat, List<String> targets, bool meIn})> _resolve(ChatPick221 pick) async {
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
    return (chat: chat, targets: targets, meIn: devices.any(mine.contains));
  }

  /// Get chat. Returns the request id.
  Future<String> request(ChatPick221 pick, {String range = 'full', DateTime? from, DateTime? to}) async {
    final r = rangeOf(range, from: from, to: to);
    // Bundle 254 (21.12): two accounts on ONE phone have no chat together.
    if (!pick.isGroup && await samePhone(pick.userA, pick.userB)) {
      throw StateError('These two accounts are on the same phone - there is no chat between them.');
    }
    // Bundle 314 (1 / 1b): not my own chats; one open request per chat.
    if (await isOwnChat314(pick)) throw ChatAdminRefused(409, ownChatCode314, L.t.ownChat314);
    final open = await openRequestFor314(pick);
    if (open != null) {
      throw ChatAdminRefused(409, alreadyAskedCode314, L.t.alreadyAskedText314, openId: open.id);
    }
    final token = await _token();
    if (token != null && serverOnline()) {
      final res = await server.create(token, {
        ...pick.toServer(),
        'range': range,
        if (range == 'dates') 'from': r.from,
        if (range == 'dates') 'to': r.to,
      });
      final id = res['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        await _markMine307(id);
        changed307?.call();
      }
      return id;
    }
    final svc = actions;
    if (svc == null) throw StateError('Admin actions are not ready.');
    final who = await _resolve(pick);
    if (who.meIn) throw ChatAdminRefused(409, ownChatCode314, L.t.ownChat314); // Bundle 314 (1)
    if (who.targets.isEmpty) throw StateError("This phone doesn't know their phones yet.");
    final detail = {'chat': who.chat, 'from': r.from, 'to': r.to, 'plus_day': true};
    final id = await svc.make(
      action: 'get_chat',
      targetUserId: '',
      label: pick.label,
      targetDevices: who.targets,
      detail: detail,
      words: 'Get chat \u00b7 ${r.words}',
      replyKey: await myBoxKey(),
      need: 1,
    );
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
  Future<ChatAnswerView> open(ChatRequestRow221 r) async {
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
      targetDevices: who.targets,
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
    if (!r.offline) {
      final token = await _token();
      if (token != null && serverOnline()) return server.download(token, r.id);
    }
    return (await reader.read(r.id, action: 'get_file')).fileBytes;
  }

  /// Close: the copy goes now (server and this phone).
  Future<void> close(ChatRequestRow221 r) async {
    final token = await _token();
    if (!r.offline && token != null && serverOnline()) {
      await server.close(token, r.id).catchError((_) {});
    }
    await reader.close(r.id);
  }

  /// Delete completely: message ids / full / range. Returns words for the
  /// snack ("Sent to 3 phones").
  Future<String> deleteCompletely(ChatPick221 pick,
      {required String scope, List<String> ids = const [], String range = '', DateTime? from, DateTime? to}) async {
    final r = rangeOf(range, from: from, to: to);
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
