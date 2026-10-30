import 'package:locallink/core/models/attachment.dart';

/// Bundle 151: what a message notification says.
///
/// * Text only -> the text.
/// * Media -> "Image received", "Video received", "Voice message received",
///   "Document received". Several of one kind -> "3 images received";
///   mixed kinds -> "3 files received".
/// * Media with a caption -> "Image received: <caption>".
enum NotificationMediaKind { image, video, voice, document }

NotificationMediaKind notificationMediaKind(Attachment a) {
  final mime = a.contentType.toLowerCase();
  final name = a.originalName.toLowerCase();
  bool ext(List<String> list) => list.any(name.endsWith);
  if (a.isImage || mime.startsWith('image/')) return NotificationMediaKind.image;
  if (mime.startsWith('video/') ||
      ext(const ['.mp4', '.m4v', '.mov', '.3gp', '.webm', '.mkv'])) {
    return NotificationMediaKind.video;
  }
  if (mime.startsWith('audio/') ||
      ext(const ['.m4a', '.aac', '.mp3', '.wav', '.ogg', '.opus'])) {
    return NotificationMediaKind.voice;
  }
  if (ext(const ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic'])) {
    return NotificationMediaKind.image;
  }
  return NotificationMediaKind.document;
}

String notificationBodyFor(String body, List<Attachment> attachments) {
  final caption = body.trim();
  if (attachments.isEmpty) return caption.isEmpty ? 'New message' : caption;

  final kinds = attachments.map(notificationMediaKind).toSet();
  final n = attachments.length;
  final String label;
  if (kinds.length > 1) {
    label = '$n files received';
  } else {
    final kind = kinds.single;
    if (n == 1) {
      label = switch (kind) {
        NotificationMediaKind.image => 'Image received',
        NotificationMediaKind.video => 'Video received',
        NotificationMediaKind.voice => 'Voice message received',
        NotificationMediaKind.document => 'Document received',
      };
    } else {
      label = switch (kind) {
        NotificationMediaKind.image => '$n images received',
        NotificationMediaKind.video => '$n videos received',
        NotificationMediaKind.voice => '$n voice messages received',
        NotificationMediaKind.document => '$n documents received',
      };
    }
  }
  return caption.isEmpty ? label : '$label: $caption';
}
