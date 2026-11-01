import 'dart:convert';

import 'package:locallink/core/models/attachment.dart';

/// Bundle 197a: hidden "envelopes" that ride inside a normal message body.
///
/// * `llmsg:v1:{"t":"text","r":{...},"f":1}` - a message with a quote (`r`)
///   and / or the Forwarded label (`f`). Plain old bodies (no prefix) are
///   simply text, so old messages keep working.
/// * `lldel:v1:{"id","by","at"}` - Delete for everyone (control message,
///   never shown as a bubble).
///
/// The envelope travels every path (Online, Nearby, through other phones)
/// because it is just the body of a normal message.
const String kMessageEnvelopePrefix = 'llmsg:v1:';
const String kDeleteEnvelopePrefix = 'lldel:v1:';
const String kReactionEnvelopePrefix = 'llrx:v1:';

/// Bundle 198: read receipt / voice "played" note (control message).
/// `llread:v1:{"r":["m1"],"p":["m7"],"at":"2026-11-04T09:14:00Z"}`
const String kReadEnvelopePrefix = 'llread:v1:';

/// Bundle 198: most ids in one read note (read + played together).
const int kReadReceiptMaxIds = 200;

/// Delete for everyone is offered for 5 minutes after sending.
const Duration kDeleteForEveryoneWindow = Duration(minutes: 5);

/// Receivers allow 2 more minutes because phone clocks differ.
const Duration kDeleteClockSlack = Duration(minutes: 2);

/// A delete that arrives before its message is remembered this long.
const Duration kEarlyDeleteKeep = Duration(days: 7);

/// Longest quote snippet (letters).
const int kReplySnippetMax = 80;

/// The quoted message inside a reply.
class ReplyRef {
  final String id;

  /// Sender (device id) of the quoted message.
  final String from;
  final String snip;

  /// text / photo / video / voice / file
  final String kind;

  const ReplyRef({
    required this.id,
    required this.from,
    this.snip = '',
    this.kind = 'text',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'snip': snip,
        'kind': kind,
      };

  static ReplyRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return ReplyRef(
      id: id,
      from: raw['from']?.toString() ?? '',
      snip: cutSnippet(raw['snip']?.toString() ?? ''),
      kind: _kinds.contains(raw['kind']?.toString())
          ? raw['kind'].toString()
          : 'text',
    );
  }

  static const _kinds = {'text', 'photo', 'video', 'voice', 'file'};

  @override
  bool operator ==(Object other) =>
      other is ReplyRef &&
      other.id == id &&
      other.from == from &&
      other.snip == snip &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, from, snip, kind);
}

/// Cut a quote snippet to [kReplySnippetMax] letters on one line.
String cutSnippet(String text) {
  final one = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  final chars = one.runes.toList();
  if (chars.length <= kReplySnippetMax) return one;
  return '${String.fromCharCodes(chars.take(kReplySnippetMax - 1))}…';
}

/// text / photo / video / voice / file for the first attachment.
String replyKindFor(List<Attachment> attachments) {
  if (attachments.isEmpty) return 'text';
  final a = attachments.first;
  final type = a.contentType.toLowerCase();
  if (a.isImage || type.startsWith('image/')) return 'photo';
  if (type.startsWith('video/')) return 'video';
  if (type.startsWith('audio/')) return 'voice';
  return 'file';
}

/// "📷 Photo" style label for a quote without text.
String replyKindLabel(String kind) => switch (kind) {
      'photo' => '📷 Photo',
      'video' => '🎥 Video',
      'voice' => '🎤 Voice message',
      'file' => '📄 Document',
      _ => '',
    };

/// The line shown inside a quote box.
String replyLine(ReplyRef reply) {
  final label = replyKindLabel(reply.kind);
  if (reply.snip.isEmpty) return label.isEmpty ? 'Message' : label;
  if (label.isEmpty) return reply.snip;
  return '${label.split(' ').first} ${reply.snip}';
}

class MessageEnvelope {
  final String text;
  final ReplyRef? reply;
  final bool forwarded;

  /// True when the body had an `llmsg` prefix but bad JSON.
  final bool bad;

  const MessageEnvelope({
    required this.text,
    this.reply,
    this.forwarded = false,
    this.bad = false,
  });

  // Small parse cache (bubbles rebuild often). Strings can't be Expando keys.
  static final Map<String, MessageEnvelope> _cache = <String, MessageEnvelope>{};

  /// Never throws. Plain old bodies are just text. A delete / reaction
  /// control body shows as empty text.
  static MessageEnvelope parse(String body) {
    if (body.startsWith(kDeleteEnvelopePrefix) ||
        body.startsWith(kReactionEnvelopePrefix) ||
        body.startsWith(kReadEnvelopePrefix)) {
      return const MessageEnvelope(text: '');
    }
    if (!body.startsWith(kMessageEnvelopePrefix)) {
      return MessageEnvelope(text: body);
    }
    try {
      final raw = jsonDecode(body.substring(kMessageEnvelopePrefix.length));
      if (raw is! Map) throw const FormatException('not a map');
      final f = raw['f'];
      return MessageEnvelope(
        text: raw['t']?.toString() ?? '',
        reply: ReplyRef.fromJson(raw['r']),
        forwarded: f == 1 || f == true || f?.toString() == '1',
      );
    } catch (_) {
      // Bad JSON: show the plain text rather than crash.
      return MessageEnvelope(
          text: body.substring(kMessageEnvelopePrefix.length), bad: true);
    }
  }

  /// Cached parse keyed on the body string object.
  static MessageEnvelope of(String body) {
    if (!body.startsWith('ll')) return MessageEnvelope(text: body);
    final hit = _cache[body];
    if (hit != null) return hit;
    final parsed = parse(body);
    if (_cache.length >= 400) _cache.remove(_cache.keys.first);
    _cache[body] = parsed;
    return parsed;
  }

  static String textOf(String body) => of(body).text;

  /// Body to send. Without a quote or Forwarded it stays plain text, so a
  /// normal message is byte-for-byte the same as before 197a.
  static String build({
    required String text,
    ReplyRef? reply,
    bool forwarded = false,
  }) {
    if (reply == null && !forwarded) return text;
    return '$kMessageEnvelopePrefix${jsonEncode({
          't': text,
          if (reply != null) 'r': reply.toJson(),
          if (forwarded) 'f': 1,
        })}';
  }

  /// Control bodies are never bubbles.
  static bool isControl(String body) =>
      body.startsWith(kDeleteEnvelopePrefix) ||
      body.startsWith(kReactionEnvelopePrefix) ||
      body.startsWith(kReadEnvelopePrefix);
}

/// Bundle 198: `llread:v1:` - "I read these" ([read]) and "I played these
/// voice notes" ([played]). Sent by the reader to the sender only.
class ReadCommand {
  final List<String> read;
  final List<String> played;
  final DateTime at;

  ReadCommand({
    required List<String> read,
    List<String> played = const [],
    required this.at,
  })  : read = _clean(read),
        played = _clean(played);

  bool get isEmpty => read.isEmpty && played.isEmpty;
  int get count => read.length + played.length;

  static List<String> _clean(Iterable<String> ids) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(id);
    }
    return out;
  }

  static bool isRead(String body) => body.startsWith(kReadEnvelopePrefix);

  String encode() => '$kReadEnvelopePrefix${jsonEncode({
        'r': read,
        if (played.isNotEmpty) 'p': played,
        'at': at.toUtc().toIso8601String(),
      })}';

  /// Never throws. Bad JSON, no ids, or more than [kReadReceiptMaxIds]
  /// ids (cut to the cap) are handled here.
  static ReadCommand? parse(String body) {
    if (!isRead(body)) return null;
    try {
      final raw = jsonDecode(body.substring(kReadEnvelopePrefix.length));
      if (raw is! Map) return null;
      List<String> ids(Object? v) =>
          v is List ? v.map((e) => e?.toString() ?? '').toList() : <String>[];
      var read = _clean(ids(raw['r']));
      var played = _clean(ids(raw['p']));
      if (played.length > kReadReceiptMaxIds) {
        played = played.sublist(0, kReadReceiptMaxIds);
      }
      final room = kReadReceiptMaxIds - played.length;
      if (read.length > room) read = read.sublist(0, room);
      if (read.isEmpty && played.isEmpty) return null;
      final at = DateTime.tryParse(raw['at']?.toString() ?? '');
      if (at == null) return null;
      return ReadCommand(read: read, played: played, at: at.toUtc());
    } catch (_) {
      return null;
    }
  }
}

/// `lldel:v1:` Delete for everyone.
class DeleteCommand {
  final String messageId;

  /// Device id of the phone that deleted (must be the message sender).
  final String by;
  final DateTime at;

  const DeleteCommand(
      {required this.messageId, required this.by, required this.at});

  String encode() => '$kDeleteEnvelopePrefix${jsonEncode({
        'id': messageId,
        'by': by,
        'at': at.toUtc().toIso8601String(),
      })}';

  static bool isDelete(String body) => body.startsWith(kDeleteEnvelopePrefix);

  /// Null for bad JSON or a missing id.
  static DeleteCommand? parse(String body) {
    if (!isDelete(body)) return null;
    try {
      final raw = jsonDecode(body.substring(kDeleteEnvelopePrefix.length));
      if (raw is! Map) return null;
      final id = raw['id']?.toString() ?? '';
      final by = raw['by']?.toString() ?? '';
      final at = DateTime.tryParse(raw['at']?.toString() ?? '');
      if (id.isEmpty || by.isEmpty || at == null) return null;
      return DeleteCommand(messageId: id, by: by, at: at.toUtc());
    } catch (_) {
      return null;
    }
  }
}

/// Why a received Delete for everyone is refused (null = accept).
String? deleteRejectReason({
  required DeleteCommand command,
  required String envelopeSender,
  required String originalSender,
  required DateTime originalCreatedAt,
}) {
  if (command.by != envelopeSender || command.by != originalSender) {
    return 'not_sender';
  }
  final age = command.at.toUtc().difference(originalCreatedAt.toUtc());
  if (age > kDeleteForEveryoneWindow + kDeleteClockSlack) return 'too_old';
  return null;
}

/// May I still offer / do Delete for everyone on my own message?
bool canDeleteForEveryone({
  required bool mine,
  required DateTime createdAt,
  DateTime? now,
}) {
  if (!mine) return false;
  final age = (now ?? DateTime.now()).toUtc().difference(createdAt.toUtc());
  return age <= kDeleteForEveryoneWindow;
}

/// "Today, 8:41 PM" / "Yesterday, 8:41 PM" / "2 Nov 2026, 8:41 PM".
String messageInfoTime(DateTime value, {DateTime? now}) {
  final t = value.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final clock =
      '$hour:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today, $clock';
  if (diff == 1) return 'Yesterday, $clock';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${t.day} ${months[t.month - 1]} ${t.year}, $clock';
}
