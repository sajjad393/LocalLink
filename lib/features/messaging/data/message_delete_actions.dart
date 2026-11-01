import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/message_delete_book.dart';

/// Bundle 197a: the local half of every delete (1-to-1 and groups), shared
/// by the direct and the group messaging services.
class MessageDeleteActions {
  final LocalStore store;
  final Future<void> Function(String path) deleteFile;
  final MessageDeleteBook book;

  MessageDeleteActions({
    required this.store,
    required this.deleteFile,
    MessageDeleteBook? book,
  }) : book = book ?? MessageDeleteBook.instance;

  static String shortId(String id) =>
      id.length > 8 ? id.substring(id.length - 8) : id;

  /// Rows + reactions + pending files + outbox item + local files.
  /// Returns the number of files removed.
  Future<int> _removeLocal(String id, {required bool group}) async {
    final paths = group
        ? await store.deleteGroupMessageLocal(id)
        : await store.deleteMessageLocal(id);
    return deleteFiles(paths);
  }

  /// Bundle 197b: the file can be on disk as `path` or `path.enc`
  /// (encrypted after the first view) - delete both.
  Future<int> deleteFiles(Iterable<String> paths) async {
    var files = 0;
    for (final path in paths) {
      try {
        await deleteFile(path);
        if (!path.endsWith('.enc')) await deleteFile('$path.enc');
        files++;
      } catch (_) {}
    }
    return files;
  }

  /// Delete for me: gone from this phone only, never brought back.
  Future<void> deleteForMe(String id, {required bool group}) async {
    if (id.isEmpty) return;
    // Mark first so a copy arriving at the same moment is dropped.
    await book.markDeleted(id, kind: MessageDeleteBook.kindMe);
    final files = await _removeLocal(id, group: group);
    AppLogger.info('MESSAGE_DELETE_ME',
        detail: 'id=${shortId(id)} files=$files group=${group ? 'y' : 'n'}');
  }

  /// Delete for everyone, my side: the bubble disappears at once. The
  /// caller sends the `lldel` command.
  Future<void> deleteForEveryoneLocal(String id,
      {required bool group, required DateTime at}) async {
    if (id.isEmpty) return;
    await book.markDeleted(id,
        kind: MessageDeleteBook.kindAll, by: store.deviceId ?? '', at: at);
    await _removeLocal(id, group: group);
  }

  /// A received `lldel:v1:` body. Never throws, never shows a bubble.
  Future<void> applyRemote({
    required String body,
    required String envelopeSender,
    required bool group,
  }) async {
    final command = DeleteCommand.parse(body);
    if (command == null) {
      AppLogger.warning('MESSAGE_ENVELOPE_BAD', detail: 'kind=del');
      return;
    }
    final id = command.messageId;
    if (command.by != envelopeSender) {
      AppLogger.warning('MESSAGE_DELETE_ALL_REJECTED',
          detail: 'id=${shortId(id)} reason=not_sender');
      return;
    }
    if (book.isDeleted(id)) return; // same delete twice
    DateTime? originalAt;
    String originalSender = '';
    if (group) {
      final original = await store.groupMessageById(id);
      if (original != null) {
        originalAt = DateTime.tryParse(original.createdAt);
        originalSender = original.senderId;
      }
    } else {
      final original = await store.messageById(id);
      if (original != null) {
        originalAt = original.createdAt;
        originalSender = original.senderId;
      }
    }
    if (originalAt == null) {
      // The delete came first (different paths): the message is dropped
      // when it arrives. Forgotten after 7 days.
      await book.markDeleted(id,
          kind: MessageDeleteBook.kindEarly, by: command.by, at: command.at);
      AppLogger.info('MESSAGE_DELETE_EARLY', detail: 'id=${shortId(id)}');
      return;
    }
    final reason = deleteRejectReason(
      command: command,
      envelopeSender: envelopeSender,
      originalSender: originalSender,
      originalCreatedAt: originalAt,
    );
    if (reason != null) {
      AppLogger.warning('MESSAGE_DELETE_ALL_REJECTED',
          detail: 'id=${shortId(id)} reason=$reason');
      return;
    }
    await book.markDeleted(id,
        kind: MessageDeleteBook.kindAll, by: command.by, at: command.at);
    final files = await _removeLocal(id, group: group);
    AppLogger.info('MESSAGE_DELETE_ALL_RECEIVED',
        detail: 'id=${shortId(id)} files=$files group=${group ? 'y' : 'n'}');
  }

  /// Clear chat (keepRow) / Delete chat. Returns the removed count.
  Future<int> clearChat({
    required String chatId,
    required bool group,
    required bool keepRow,
  }) async {
    final key = group
        ? MessageDeleteBook.groupKey(chatId)
        : MessageDeleteBook.directKey(chatId);
    await book.clearChat(key, keepRow: keepRow);
    final ids = group
        ? await store.clearableGroupMessageIds(chatId)
        : await store.clearableDirectMessageIds(chatId);
    var files = 0;
    for (final id in ids) {
      files += await _removeLocal(id, group: group);
    }
    AppLogger.info(keepRow ? 'CHAT_CLEARED' : 'CHAT_DELETED',
        detail: 'chat=${shortId(chatId)} count=${ids.length} files=$files '
            'group=${group ? 'y' : 'n'}');
    return ids.length;
  }
}
