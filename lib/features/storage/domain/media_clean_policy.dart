/// Bundle 197b: pure rules for "Free up space automatically" and the
/// Settings › Storage numbers. No I/O here - unit-tested.
library;

enum MediaKind { photo, video, document, voice }

MediaKind mediaKindOf({required String contentType, required String name, bool isImage = false}) {
  final type = contentType.toLowerCase();
  final lower = name.toLowerCase();
  // Same rule as the chat bubble (AttachmentTile._isAudio).
  if (type.startsWith('audio/')) return MediaKind.voice;
  if (type.startsWith('video/')) return MediaKind.video;
  if (const ['.m4a', '.aac', '.mp3', '.wav', '.ogg', '.opus'].any(lower.endsWith)) {
    return MediaKind.voice;
  }
  if (const ['.mp4', '.m4v', '.mov', '.3gp', '.webm', '.mkv'].any(lower.endsWith)) {
    return MediaKind.video;
  }
  if (isImage || type.startsWith('image/')) return MediaKind.photo;
  return MediaKind.document;
}

/// One media file of one message, as this phone sees it.
class MediaFile {
  const MediaFile({
    required this.fileId,
    required this.messageId,
    required this.chatId,
    required this.isGroup,
    required this.mine,
    required this.sent,
    required this.kind,
    required this.name,
    required this.contentType,
    required this.rowPath,
    required this.diskPath,
    required this.bytes,
    required this.messageAt,
    this.openedAt,
    this.removed = false,
    this.saved = false,
  });

  final String fileId;
  final String messageId;
  final String chatId;
  final bool isGroup;
  final bool mine;

  /// Own message: delivered (direct) or accepted by the server (group).
  /// Received: always true.
  final bool sent;
  final MediaKind kind;
  final String name;
  final String contentType;

  /// `local_path` of the row (may be empty).
  final String rowPath;

  /// The real file on disk (`local_path` or `local_path.enc`), null = none.
  final String? diskPath;
  final int bytes;
  final DateTime messageAt;
  final DateTime? openedAt;
  final bool removed;
  final bool saved;

  bool get present => !removed && diskPath != null && bytes > 0;

  /// Last time it mattered: opened, or the message time if never opened.
  DateTime get lastUsed {
    final o = openedAt;
    return (o != null && o.isAfter(messageAt)) ? o : messageAt;
  }
}

class MediaCleanResult {
  const MediaCleanResult(this.picked, {this.skippedRecent = 0, this.skippedUnsent = 0, this.skippedVoice = 0});
  final List<MediaFile> picked;
  final int skippedRecent;
  final int skippedUnsent;
  final int skippedVoice;

  int get bytes => picked.fold(0, (sum, f) => sum + f.bytes);
}

class MediaCleanPolicy {
  static const double maxUsed = 0.70;
  static const Duration minAge = Duration(days: 10);
  static const int bigDownloadBytes = 20 * 1024 * 1024;
  static const Duration minGap = Duration(hours: 24);
  static const Duration startDelay = Duration(seconds: 60);

  static double usedFraction(int total, int free) {
    if (total <= 0) return 0;
    final f = free.clamp(0, total);
    return (total - f) / total;
  }

  static bool overLimit(int total, int free) => usedFraction(total, free) > maxUsed;

  /// Q3: oldest first, stop as soon as the phone is at 70% or less.
  /// [openNow] = files open on screen right now (never removed).
  static MediaCleanResult pick(
    List<MediaFile> files, {
    required DateTime now,
    required int totalBytes,
    required int freeBytes,
    Duration age = minAge,
    Set<String> openNow = const {},
  }) {
    if (totalBytes <= 0 || !overLimit(totalBytes, freeBytes)) {
      return const MediaCleanResult([]);
    }
    var recent = 0, unsent = 0, voice = 0;
    final candidates = <MediaFile>[];
    final cutoff = now.subtract(age);
    for (final f in files) {
      if (!f.present) continue;
      if (f.kind == MediaKind.voice) {
        voice++;
        continue;
      }
      if (f.mine && !f.sent) {
        unsent++;
        continue;
      }
      if (openNow.contains(f.fileId) || !f.lastUsed.isBefore(cutoff)) {
        recent++;
        continue;
      }
      candidates.add(f);
    }
    candidates.sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    var used = totalBytes - freeBytes.clamp(0, totalBytes);
    final limit = (totalBytes * maxUsed).floor();
    final picked = <MediaFile>[];
    for (final f in candidates) {
      if (used <= limit) break;
      picked.add(f);
      used -= f.bytes;
    }
    return MediaCleanResult(picked, skippedRecent: recent, skippedUnsent: unsent, skippedVoice: voice);
  }

  /// K1: should a run start now? Returns null = go, else the skip reason.
  static String? skipReason({
    required bool switchOn,
    required bool inCall,
    required bool busy,
    required String trigger,
    DateTime? lastRun,
    required DateTime now,
  }) {
    if (!switchOn) return 'off';
    if (busy) return 'busy';
    if (inCall) return 'call';
    if (trigger == 'resume' && lastRun != null && now.difference(lastRun) < minGap) {
      return 'recent_run';
    }
    return null;
  }
}

class ChatStorage {
  ChatStorage(this.chatId, this.isGroup);
  final String chatId;
  final bool isGroup;
  int bytes = 0;
  int count = 0;
}

/// Sizes by type and by chat (Settings › Storage).
class StorageSummary {
  StorageSummary._(this.total, this.byKind, this.chats);

  final int total;
  final Map<MediaKind, int> byKind;

  /// Biggest first; chats with no files are left out.
  final List<ChatStorage> chats;

  factory StorageSummary.of(Iterable<MediaFile> files) {
    final byKind = {for (final k in MediaKind.values) k: 0};
    final chats = <String, ChatStorage>{};
    var total = 0;
    for (final f in files) {
      if (!f.present) continue;
      total += f.bytes;
      byKind[f.kind] = byKind[f.kind]! + f.bytes;
      final key = '${f.isGroup ? 'g' : 'd'}:${f.chatId}';
      final c = chats.putIfAbsent(key, () => ChatStorage(f.chatId, f.isGroup));
      c.bytes += f.bytes;
      c.count++;
    }
    final list = chats.values.where((c) => c.bytes > 0).toList()
      ..sort((a, b) => b.bytes.compareTo(a.bytes));
    return StorageSummary._(total, byKind, list);
  }

  /// Files of one chat, biggest first (removed ones not listed).
  static List<MediaFile> filesOf(Iterable<MediaFile> files, String chatId, bool isGroup) =>
      files.where((f) => f.present && f.chatId == chatId && f.isGroup == isGroup).toList()
        ..sort((a, b) => b.bytes.compareTo(a.bytes));
}

/// "1.2 GB", "640 MB", "19.7 MB", "900 KB".
String formatStorageBytes(int bytes) {
  const kb = 1024, mb = 1024 * 1024, gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= 100 * mb) return '${(bytes / mb).round()} MB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).round()} KB';
  return '$bytes B';
}
