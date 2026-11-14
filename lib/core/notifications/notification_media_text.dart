import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/l10n/l10n.dart';

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
  if (attachments.isEmpty) return caption.isEmpty ? L.t.newMessage : caption;

  final kinds = attachments.map(notificationMediaKind).toSet();
  final n = attachments.length;
  final String label;
  if (kinds.length > 1) {
    label = L.t.filesReceived(n);
  } else {
    final kind = kinds.single;
    if (n == 1) {
      label = switch (kind) {
        NotificationMediaKind.image => L.t.imageReceived,
        NotificationMediaKind.video => L.t.videoReceived,
        NotificationMediaKind.voice => L.t.voiceMessageReceived,
        NotificationMediaKind.document => L.t.documentReceived,
      };
    } else {
      label = switch (kind) {
        NotificationMediaKind.image => L.t.imagesReceived(n),
        NotificationMediaKind.video => L.t.videosReceived(n),
        NotificationMediaKind.voice => L.t.voiceMessagesReceived(n),
        NotificationMediaKind.document => L.t.documentsReceived(n),
      };
    }
  }
  return caption.isEmpty ? label : '$label: $caption';
}
