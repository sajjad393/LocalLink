/// Bundle 163 (4.7): the last message of a conversation, for the Chats list.
class ChatPreview {
  final String messageId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  /// First attachment's content type ('' = text only).
  final String attachmentType;
  final bool attachmentIsImage;

  const ChatPreview({
    required this.messageId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.attachmentType = '',
    this.attachmentIsImage = false,
  });

  /// Builds from a row with id, sender_id, body, created_at, att_type,
  /// att_image. Null when the time can't be read.
  static ChatPreview? fromRow(Map<String, Object?> row) {
    final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final id = row['id']?.toString() ?? '';
    if (created == null || id.isEmpty) return null;
    return ChatPreview(
      messageId: id,
      senderId: row['sender_id']?.toString() ?? '',
      body: row['body']?.toString() ?? '',
      createdAt: created,
      attachmentType: row['att_type']?.toString() ?? '',
      attachmentIsImage: (int.tryParse(row['att_image']?.toString() ?? '') ?? 0) == 1,
    );
  }
}

/// Short words for media, same set everywhere in the list.
String chatPreviewMediaWord(String contentType, {bool isImage = false}) {
  final type = contentType.toLowerCase();
  if (isImage || type.startsWith('image/')) return 'Photo';
  if (type.startsWith('video/')) return 'Video';
  if (type.startsWith('audio/')) return 'Voice message';
  return 'Document';
}

/// The line under the name: "You: ok", "Bilal: see you", "Photo",
/// "You: Voice message". [senderName] is used in groups only.
String chatPreviewText(
  ChatPreview preview, {
  required String localDeviceId,
  String? senderName,
}) {
  final body = preview.body.trim().replaceAll(RegExp(r'\s+'), ' ');
  final hasMedia = preview.attachmentType.isNotEmpty || preview.attachmentIsImage;
  final text = body.isNotEmpty
      ? body
      : hasMedia
          ? chatPreviewMediaWord(preview.attachmentType,
              isImage: preview.attachmentIsImage)
          : 'Message';
  if (localDeviceId.isNotEmpty && preview.senderId == localDeviceId) {
    return 'You: $text';
  }
  final name = senderName?.trim() ?? '';
  return name.isEmpty ? text : '$name: $text';
}

/// The icon to show before the preview text for media-only messages
/// (null = no icon).
String? chatPreviewMediaKind(ChatPreview preview) {
  if (preview.body.trim().isNotEmpty) return null;
  if (preview.attachmentType.isEmpty && !preview.attachmentIsImage) return null;
  return chatPreviewMediaWord(preview.attachmentType,
      isImage: preview.attachmentIsImage);
}

/// Time on the right: "3:42 PM" today, "Yesterday", a weekday within a
/// week, else "31/10/26".
String chatPreviewTime(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo <= 0) {
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
  }
  if (daysAgo == 1) return 'Yesterday';
  if (daysAgo < 7) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[local.weekday - 1];
  }
  final yy = (local.year % 100).toString().padLeft(2, '0');
  return '${local.day}/${local.month}/$yy';
}
