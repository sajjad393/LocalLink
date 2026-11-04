import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/group_event.dart';
import 'package:locallink/core/models/message.dart';

/// Bundle 207 (L1, mock 207 page 5): one message found by the Chats tab
/// search (1:1 or group).
class MessageSearchHit {
  const MessageSearchHit({
    required this.messageId,
    required this.chatId,
    required this.group,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.fileName = '',
  });

  final String messageId;

  /// The other person's device id (1:1) or the group id.
  final String chatId;
  final bool group;
  final String senderId;

  /// The words of the message ('' for a file without a caption).
  final String text;
  final DateTime createdAt;

  /// The matching file name (photo / video / document), '' when none.
  final String fileName;

  bool get isMedia => fileName.isNotEmpty;

  /// The line shown in the result: the words, else the file name.
  String get line => text.isNotEmpty ? text : fileName;

  /// A 1:1 row (messages table + matching file name) -> hit, or null when
  /// it doesn't really match (system notes, locked, deleted...).
  static MessageSearchHit? fromDirect(Map<String, Object?> row,
      {required String self,
      required String query,
      bool Function(String id)? deleted}) {
    final m = Message.fromDb(Map<String, dynamic>.from(row));
    final file = row['file']?.toString() ?? '';
    return _make(
      id: m.id,
      chat: m.senderId == self ? m.recipientId : m.senderId,
      group: false,
      sender: m.senderId,
      body: m.body,
      text: m.text,
      at: m.createdAt,
      file: file,
      query: query,
      deleted: deleted,
    );
  }

  /// A group row -> hit, or null.
  static MessageSearchHit? fromGroup(Map<String, Object?> row,
      {required String query, bool Function(String id)? deleted}) {
    final data = Map<String, dynamic>.from(row)
      ..['attachments'] = const <Object>[];
    final GroupMessage m;
    try {
      m = GroupMessage.fromJson(data);
    } catch (_) {
      return null;
    }
    if (GroupEvent.isEvent(m.body) || m.body.startsWith('llsk:v1:')) {
      return null;
    }
    return _make(
      id: m.id,
      chat: m.groupId,
      group: true,
      sender: m.senderId,
      body: m.body,
      text: m.text,
      at: DateTime.tryParse(m.createdAt)?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      file: row['file']?.toString() ?? '',
      query: query,
      deleted: deleted,
    );
  }

  static MessageSearchHit? _make({
    required String id,
    required String chat,
    required bool group,
    required String sender,
    required String body,
    required String text,
    required DateTime at,
    required String file,
    required String query,
    bool Function(String id)? deleted,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty || id.isEmpty || chat.isEmpty) return null;
    if (deleted?.call(id) ?? false) return null;
    final words = text.trim();
    final inText = words.toLowerCase().contains(q);
    final inFile = file.toLowerCase().contains(q);
    if (!inText && !inFile) return null; // matched only the hidden wire part
    return MessageSearchHit(
      messageId: id,
      chatId: chat,
      group: group,
      senderId: sender,
      text: words,
      createdAt: at,
      fileName: inFile ? file : '',
    );
  }
}
