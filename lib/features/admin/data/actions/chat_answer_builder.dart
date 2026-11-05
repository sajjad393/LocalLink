import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/features/admin/data/actions/admin_action_box.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';

/// Bundle 221: the Owner gets a chat FROM THE PHONES. A phone of the chat
/// opens a `get_chat` card (220 delivery) and builds the answer once: live +
/// hidden (soft deleted) messages in the range, each message as JSON, packed
/// into parts. Every part is gzip-ed and locked on its own for the card's
/// `reply_key` (llaa1 box), so half an answer can already be read.
///
/// Part blob (signed by this phone, Ed25519):
/// `{v:1, kind:"admin_answer_part", answer_id, action_id, device, part, of,
/// sha256, data}` - the same shape the server reads
/// (`internal/httpapi/admin_chat_221.go`).
abstract final class ChatAnswerRules {
  static const String partsType = 'admin_act_parts';
  static const int appBuild = 132;

  /// Raw message JSON per part (gzip + box keep a blob far below 64 KB).
  static const int partJsonBytes = 30 * 1024;

  /// One message alone bigger than this: the text is cut ([cutChars]).
  static const int bigMessageBytes = 46 * 1024;
  static const int cutChars = 20000;

  /// A full photo / video: raw bytes per part (50 MB fits in 2000 parts).
  static const int fileChunkBytes = 26 * 1024;
  static const int maxParts = 2000;
  static const int maxFileBytes = 50 * 1024 * 1024;

  /// Answers built by phones: thumbnails of the oldest go first above this.
  static const int phoneAnswerBytes = 5 * 1024 * 1024;

  /// Text only: never more than the server keeps.
  static const int textAnswerBytes = 18 * 1024 * 1024;
  static const int thumbBytes = 8 * 1024;

  /// Hidden full files go 60 days after the user deleted them.
  static const Duration hiddenFileDays = Duration(days: 60);
}

/// Which chat (inside a box; the server and the phones agree).
class ChatRef221 {
  final String kind; // direct | group
  final List<String> users;
  final List<String> devices;
  final String groupId;

  const ChatRef221({
    required this.kind,
    this.users = const [],
    this.devices = const [],
    this.groupId = '',
  });

  bool get isGroup => kind == 'group';

  bool get valid => isGroup ? groupId.isNotEmpty : devices.length >= 2;

  static ChatRef221? fromJson(Object? raw) {
    if (raw is! Map) return null;
    List<String> list(Object? v) => [
          for (final x in (v is List ? v : const []))
            if (x != null && x.toString().isNotEmpty) x.toString(),
        ];
    final ref = ChatRef221(
      kind: raw['kind']?.toString() ?? '',
      users: list(raw['users']),
      devices: list(raw['devices']),
      groupId: raw['group_id']?.toString() ?? '',
    );
    return ref.kind == 'direct' || ref.kind == 'group' ? ref : null;
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (users.isNotEmpty) 'users': users,
        if (devices.isNotEmpty) 'devices': devices,
        if (groupId.isNotEmpty) 'group_id': groupId,
      };
}

/// One file of a message (live or hidden).
class ChatAtt221 {
  final String messageId;
  final String fileId;
  final String name;
  final String type;
  final int size;
  final String localPath;
  final String goneAt; // hidden full file removed after 60 days

  const ChatAtt221({
    required this.messageId,
    required this.fileId,
    this.name = '',
    this.type = '',
    this.size = 0,
    this.localPath = '',
    this.goneAt = '',
  });
}

/// One message row (live or hidden).
class ChatRow221 {
  final String id;
  final String sender;
  final String body;
  final String createdAt;
  final String status;
  final String route; // server | direct | mesh | ''
  final String hiddenAt; // '' = live
  final String hiddenHow;
  final List<ChatAtt221> atts;
  final List<Map<String, String>> reactions; // {by, emoji}

  const ChatRow221({
    required this.id,
    required this.sender,
    required this.body,
    required this.createdAt,
    this.status = '',
    this.route = '',
    this.hiddenAt = '',
    this.hiddenHow = '',
    this.atts = const [],
    this.reactions = const [],
  });
}

/// What the builder reads (SQL on the phone: `hidden_store_221.dart`).
abstract class ChatRows221 {
  /// Live + hidden messages of the chat (any order, any range).
  Future<List<ChatRow221>> rows(ChatRef221 chat);

  Future<String> nameOf(String deviceId);

  /// A small picture (≤ 8 KB) of a photo / video, or null.
  Future<({Uint8List bytes, String type})?> thumbOf(ChatAtt221 att);

  /// The file row for Get full photo (live or hidden), or null.
  Future<ChatAtt221?> fileOf(String fileId, String messageId);

  /// The full file bytes (decrypted), or null when it is not on this phone.
  Future<Uint8List?> readFile(ChatAtt221 att);
}

/// The range in a box: `from` / `to` are days (YYYY-MM-DD, empty = full).
/// The phone takes one more day on both sides (its clock may be wrong);
/// messages only in that margin are marked `outside`.
class ChatRange221 {
  final DateTime? from; // first local day 00:00 (inside)
  final DateTime? to; // day after the last local day 00:00 (inside < to)

  const ChatRange221(this.from, this.to);

  static ChatRange221 of(Map<String, dynamic> detail) {
    DateTime? day(Object? v) {
      final s = v?.toString().trim() ?? '';
      if (s.isEmpty) return null;
      final d = DateTime.tryParse(s);
      return d == null ? null : DateTime(d.year, d.month, d.day);
    }

    final from = day(detail['from']);
    final to = day(detail['to']);
    return ChatRange221(from, to == null ? null : DateTime(to.year, to.month, to.day + 1));
  }

  bool get full => from == null && to == null;

  /// null = not in the answer; false = inside; true = margin only.
  bool? place(DateTime at, {bool margin = true}) {
    final t = at.toLocal();
    final f = from;
    final e = to;
    final pad = margin ? const Duration(days: 1) : Duration.zero;
    if (f != null && t.isBefore(f.subtract(pad))) return null;
    if (e != null && !t.isBefore(e.add(pad))) return null;
    final outside = (f != null && t.isBefore(f)) || (e != null && !t.isBefore(e));
    return outside;
  }
}

/// One built part (before it travels).
class ChatAnswerPart {
  final String answerId;
  final String actionId;
  final int part;
  final int of;
  final SignedBlob blob;
  const ChatAnswerPart(this.answerId, this.actionId, this.part, this.of, this.blob);
}

class ChatAnswerBuilder {
  final ChatRows221 source;
  final String Function() selfDeviceId;
  final Future<String> Function(String body) sign;
  final DateTime Function() _clock;

  ChatAnswerBuilder({
    required this.source,
    required this.selfDeviceId,
    required this.sign,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static String newAnswerId() {
    final r = Random.secure();
    return 'an_${List<int>.generate(12, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  static String sha256Hex(String s) => hash.sha256.convert(utf8.encode(s)).toString();

  static String b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  static Uint8List unb64url(String s) {
    final t = s.trim().replaceAll('=', '');
    return base64Url.decode(t.padRight((t.length + 3) ~/ 4 * 4, '='));
  }

  /// The message JSON the viewers read (web + app).
  Future<Map<String, dynamic>> messageJson(
    ChatRow221 r, {
    required bool outside,
    required Map<String, String> names,
    bool withThumbs = true,
  }) async {
    final now = _clock();
    final atts = <Map<String, dynamic>>[];
    for (final a in r.atts) {
      var gone = a.goneAt.isNotEmpty;
      if (!gone && r.hiddenAt.isNotEmpty) {
        final hid = DateTime.tryParse(r.hiddenAt);
        gone = hid != null && now.difference(hid) >= ChatAnswerRules.hiddenFileDays;
      }
      final thumb = withThumbs ? await source.thumbOf(a).catchError((_) => null) : null;
      atts.add({
        'file_id': a.fileId,
        'name': a.name,
        'type': a.type,
        'size': a.size,
        if (thumb != null && thumb.bytes.length <= ChatAnswerRules.thumbBytes) ...{
          'thumb': base64.encode(thumb.bytes),
          'thumb_type': thumb.type,
        },
        if (gone) 'file_gone': true,
      });
    }
    final name = names[r.sender] ??= await source.nameOf(r.sender).catchError((_) => '');
    return {
      'id': r.id,
      'sender': r.sender,
      'sender_name': name,
      'created_at': r.createdAt,
      'body': MessageEnvelope.textOf(r.body),
      'route': r.route,
      'status': r.status,
      if (r.hiddenAt.isNotEmpty) 'deleted_at': r.hiddenAt,
      if (r.hiddenAt.isNotEmpty && r.hiddenHow.isNotEmpty) 'hidden_how': r.hiddenHow,
      if (outside) 'outside': true,
      if (r.reactions.isNotEmpty) 'reactions': r.reactions,
      if (atts.isNotEmpty) 'attachments': atts,
    };
  }

  /// The messages of the answer, oldest first (control lines skipped).
  Future<({List<Map<String, dynamic>> messages, bool trimmed, int total})> messages(
      ChatRef221 chat, ChatRange221 range) async {
    final rows = await source.rows(chat);
    final picked = <(ChatRow221, DateTime, bool)>[];
    final seen = <String>{};
    for (final r in rows) {
      if (r.id.isEmpty || MessageEnvelope.isControl(r.body)) continue;
      final at = DateTime.tryParse(r.createdAt);
      if (at == null) continue;
      final place = range.place(at);
      if (place == null) continue;
      // The live row wins over an older hidden copy of the same id.
      if (!seen.add(r.id)) {
        if (r.hiddenAt.isNotEmpty) continue;
        picked.removeWhere((p) => p.$1.id == r.id);
      }
      picked.add((r, at, place));
    }
    picked.sort((a, b) => a.$2.compareTo(b.$2));
    final names = <String, String>{};
    final out = <Map<String, dynamic>>[];
    for (final p in picked) {
      out.add(await messageJson(p.$1, outside: p.$3, names: names));
    }
    var trimmed = false;
    var total = out.fold<int>(0, (n, m) => n + jsonEncode(m).length);
    // Over 5 MB: thumbnails of the oldest go first, the text stays.
    for (var i = 0; i < out.length && total > ChatAnswerRules.phoneAnswerBytes; i++) {
      final atts = out[i]['attachments'];
      if (atts is! List) continue;
      for (final a in atts.whereType<Map>()) {
        final t = a.remove('thumb');
        a.remove('thumb_type');
        if (t is String) {
          total -= t.length;
          trimmed = true;
        }
      }
    }
    // Text alone too big for the server: the oldest messages go.
    while (out.isNotEmpty && total > ChatAnswerRules.textAnswerBytes) {
      total -= jsonEncode(out.removeAt(0)).length;
      trimmed = true;
    }
    return (messages: out, trimmed: trimmed, total: rows.length);
  }

  /// Packs messages into part JSON maps (`{messages}` each; one big message
  /// goes alone, its text cut when even that is too big).
  static List<List<Map<String, dynamic>>> pack(List<Map<String, dynamic>> messages) {
    final groups = <List<Map<String, dynamic>>>[];
    var cur = <Map<String, dynamic>>[];
    var size = 0;
    for (final m in messages) {
      var len = jsonEncode(m).length;
      if (len > ChatAnswerRules.bigMessageBytes) {
        final body = m['body']?.toString() ?? '';
        if (body.length > ChatAnswerRules.cutChars) {
          m['body'] = body.substring(0, ChatAnswerRules.cutChars);
          m['cut'] = true;
        }
        len = jsonEncode(m).length;
        if (len > ChatAnswerRules.bigMessageBytes) {
          for (final a in (m['attachments'] as List? ?? const []).whereType<Map>()) {
            a.remove('thumb');
            a.remove('thumb_type');
          }
          len = jsonEncode(m).length;
        }
      }
      if (cur.isNotEmpty && size + len > ChatAnswerRules.partJsonBytes) {
        groups.add(cur);
        cur = <Map<String, dynamic>>[];
        size = 0;
      }
      cur.add(m);
      size += len;
    }
    if (cur.isNotEmpty || groups.isEmpty) groups.add(cur);
    return groups;
  }

  /// Locks + signs the part plains (part / of are set here).
  Future<List<ChatAnswerPart>> seal({
    required String actionId,
    required String replyKey,
    required List<Map<String, dynamic>> plains,
    required String replyTo,
    bool isFile = false,
    String? answerId,
  }) async {
    final id = answerId ?? newAnswerId();
    final of = plains.length;
    final out = <ChatAnswerPart>[];
    for (var i = 0; i < of; i++) {
      final plain = {...plains[i], 'part': i + 1, 'of': of};
      final data = await AdminActionBoxLock.lock(replyKey, gzip.encode(utf8.encode(jsonEncode(plain))));
      final body = jsonEncode({
        'v': 1,
        'kind': 'admin_answer_part',
        'answer_id': id,
        'action_id': actionId,
        'device': selfDeviceId(),
        'part': i + 1,
        'of': of,
        'sha256': sha256Hex(data),
        'data': data,
        // Not secret, read by carriers: who the answer is for (`server` or
        // the admin phone) and whether it is a full file (direct only).
        'reply_to': replyTo,
        if (isFile) 'is_file': true,
      });
      out.add(ChatAnswerPart(id, actionId, i + 1, of, SignedBlob(body: body, sig: await sign(body))));
    }
    return out;
  }

  /// get_chat: the whole answer, ready to travel.
  Future<List<ChatAnswerPart>> buildChat({
    required String actionId,
    required String replyKey,
    required String replyTo,
    required Map<String, dynamic> detail,
  }) async {
    final chat = ChatRef221.fromJson(detail['chat']);
    if (chat == null || !chat.valid) throw StateError('no_chat');
    final range = ChatRange221.of(detail);
    final got = await messages(chat, range);
    // No copy of this chat at all on this phone: no answer (and no receipt),
    // another phone of the chat answers.
    if (got.total == 0) throw StateError('no_copy_here');
    var groups = pack(got.messages);
    var trimmed = got.trimmed;
    if (groups.length > ChatAnswerRules.maxParts) {
      groups = groups.sublist(groups.length - ChatAnswerRules.maxParts);
      trimmed = true;
    }
    final plains = <Map<String, dynamic>>[
      for (var i = 0; i < groups.length; i++)
        {
          if (i == 0) ...{
            'chat': chat.toJson(),
            'from': detail['from']?.toString() ?? '',
            'to': detail['to']?.toString() ?? '',
            if (trimmed) 'trimmed': true,
          },
          'messages': groups[i],
        },
    ];
    return seal(actionId: actionId, replyKey: replyKey, plains: plains, replyTo: replyTo);
  }

  /// get_file: the full file in raw parts (file meta on part 1).
  Future<List<ChatAnswerPart>> buildFile({
    required String actionId,
    required String replyKey,
    required String replyTo,
    required Map<String, dynamic> detail,
  }) async {
    final fileId = detail['file_id']?.toString() ?? '';
    final att = await source.fileOf(fileId, detail['message_id']?.toString() ?? '');
    if (att == null) throw StateError('no_file');
    final bytes = att.goneAt.isNotEmpty ? null : await source.readFile(att);
    if (bytes == null) throw StateError('file_gone');
    if (bytes.length > ChatAnswerRules.maxFileBytes) throw StateError('file_too_big');
    final plains = <Map<String, dynamic>>[];
    for (var at = 0; at < bytes.length || plains.isEmpty; at += ChatAnswerRules.fileChunkBytes) {
      final end = min(at + ChatAnswerRules.fileChunkBytes, bytes.length);
      plains.add({
        if (at == 0) 'file': {'name': att.name, 'type': att.type, 'size': bytes.length, 'file_id': fileId},
        'data': b64url(bytes.sublist(at, end)),
      });
      if (bytes.isEmpty) break;
    }
    return seal(
        actionId: actionId, replyKey: replyKey, plains: plains, replyTo: replyTo, isFile: true);
  }
}
