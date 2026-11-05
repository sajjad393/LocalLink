import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';

/// What Delete completely touches on the phone (SQL: `hidden_store_221.dart`
/// + the existing delete functions of `local_store.dart`).
abstract class PurgeTarget221 {
  /// Live + hidden rows of the chat.
  Future<List<ChatRow221>> rows(ChatRef221 chat);

  /// The normal delete of one live row (rows, files, outbox, pending files)
  /// with no hidden copy. Returns the file paths to delete.
  Future<List<String>> removeLive(String id, {required bool group});

  /// Hidden rows go for real. Returns the file paths to delete.
  Future<List<String>> removeHidden(List<String> ids, {required bool group});

  Future<void> deleteFile(String path);
  Future<void> addPurged(Iterable<String> ids);
  Future<bool> isPurged(String id);

  /// The notification of a removed message goes too.
  Future<void> notificationGone(String id);

  /// Marks ids as "deleted completely now" (no hidden copy) / done.
  void purging(Iterable<String> ids, bool on);
}

/// Bundle 221: the Owner's Delete completely - the only delete that removes
/// everything: live and hidden rows, files, thumbnails, queued copies and
/// the notification. Ids go to `purged_ids` (60 days) so a late copy that
/// still comes over mesh is deleted right after it arrives.
class DeleteCompletelyDoer {
  DeleteCompletelyDoer(this.target);

  final PurgeTarget221 target;
  static DeleteCompletelyDoer? instance;

  /// The ids the box asks for. `scope`: message (ids) | full | range.
  Future<({List<String> live, List<String> hidden})> pick(Map<String, dynamic> detail) async {
    final chat = ChatRef221.fromJson(detail['chat']);
    if (chat == null || !chat.valid) throw StateError('no_chat');
    final scope = detail['scope']?.toString() ?? '';
    final want = {
      for (final x in (detail['ids'] as List? ?? const [])) x.toString(),
    }..remove('');
    final range = ChatRange221.of(detail);
    final live = <String>{};
    final hidden = <String>{};
    for (final r in await target.rows(chat)) {
      final ok = switch (scope) {
        'message' => want.contains(r.id),
        'full' => true,
        'range' => () {
            final at = DateTime.tryParse(r.createdAt);
            return at != null && range.place(at, margin: false) != null;
          }(),
        _ => false,
      };
      if (!ok) continue;
      (r.hiddenAt.isEmpty ? live : hidden).add(r.id);
    }
    // Ids asked for but not on this phone (yet): a late copy is dropped too.
    if (scope == 'message') hidden.addAll(want.difference(live).difference(hidden));
    return (live: live.toList(), hidden: hidden.toList());
  }

  /// Runs the box detail. Returns how many messages went.
  Future<int> run(Map<String, dynamic> detail) async {
    final chat = ChatRef221.fromJson(detail['chat']);
    if (chat == null || !chat.valid) throw StateError('no_chat');
    final ids = await pick(detail);
    final all = {...ids.live, ...ids.hidden};
    await target.addPurged(all);
    target.purging(all, true);
    var removed = 0;
    var files = 0;
    try {
      for (final id in ids.live) {
        final paths = await target.removeLive(id, group: chat.isGroup);
        files += await _delete(paths);
        await target.notificationGone(id);
        removed++;
      }
      final hiddenPaths = await target.removeHidden(ids.hidden, group: chat.isGroup);
      files += await _delete(hiddenPaths);
      removed += ids.hidden.length;
    } finally {
      target.purging(all, false);
    }
    AppLogger.info('ADMIN_PURGE_DONE',
        detail: 'scope=${detail['scope']} messages=$removed files=$files kind=${chat.kind}');
    return removed;
  }

  Future<int> _delete(List<String> paths) async {
    var n = 0;
    for (final path in paths) {
      for (final x in [path, if (!path.endsWith('.enc')) '$path.enc']) {
        try {
          await target.deleteFile(x);
          n++;
        } catch (_) {}
      }
    }
    return n;
  }

  /// A message that arrived after Delete completely: gone again at once.
  Future<bool> dropLate(String id, {required bool group}) async {
    if (!await target.isPurged(id)) return false;
    target.purging([id], true);
    try {
      await _delete(await target.removeLive(id, group: group));
      await target.notificationGone(id);
    } finally {
      target.purging([id], false);
    }
    AppLogger.info('ADMIN_PURGE_LATE_COPY', detail: 'group=$group');
    return true;
  }
}
