import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/domain/file_size_rule.dart';

import 'media_progress_hub.dart';
import 'media_transfer_actions.dart';

/// Bundle 208 (E1): one file that came to me and is not saved yet.
@immutable
class AutoFile {
  const AutoFile({
    required this.messageId,
    required this.attachment,
    required this.senderId,
    required this.createdAt,
    this.groupId,
  });

  final String messageId;
  final Attachment attachment;
  final String senderId;
  final DateTime createdAt;

  /// Set for a group file.
  final String? groupId;

  bool get group => groupId != null;
  String get fileId => attachment.id;
  int get size => attachment.size;
  bool get online => (attachment.downloadUrl ?? '').isNotEmpty;
  String get key => '$messageId|${MediaTransferActions.baseId(fileId)}';

  /// A row of `LocalStore.missingIncomingAttachments` /
  /// `missingGroupAttachments`.
  static AutoFile? fromRow(Map<String, Object?> r) {
    final messageId = r['message_id']?.toString() ?? '';
    final fileId = r['file_id']?.toString() ?? '';
    if (messageId.isEmpty || fileId.isEmpty) return null;
    final gid = r['group_id']?.toString();
    return AutoFile(
      messageId: messageId,
      senderId: r['sender_id']?.toString() ?? '',
      createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      groupId: (gid == null || gid.isEmpty) ? null : gid,
      attachment: Attachment.fromJson({
        'id': fileId,
        'original_name': r['original_name'],
        'content_type': r['content_type'],
        'size': r['size'],
        'sha256': r['sha256'],
        'width': r['width'],
        'height': r['height'],
        'is_image': r['is_image'] == 1 || r['is_image'] == true,
        'download_url': r['download_url'],
        'thumbnail_url': r['thumbnail_url'],
      }),
    );
  }
}

typedef AutoDownload = Future<String> Function(
  AutoFile file, {
  required String operationId,
  required void Function(TransferProgress progress) onProgress,
});

/// Bundle 208 (E): every file that comes to me downloads by itself - offline
/// first (the sender's phone sends it again when it is near), online one
/// at a time. Runs while the app runs, also with the chat closed.
///
/// Never by itself: a file I stopped with X, a file the sender stopped, a
/// file removed to save space, my own files, files older than 7 days or
/// bigger than 50 MB. During a voice call it waits. Low space: skipped.
class AutoFetch {
  AutoFetch({
    required this.missing,
    required this.download,
    required this.ask,
    required this.cancelDownload,
    required this.inCall,
    required this.serverUp,
    required this.freeBytes,
    this.isNear,
    this.selfId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The one running service (null in tests that don't make one).
  static AutoFetch? instance;

  /// Files I should have (from the DB).
  final Future<List<AutoFile>> Function() missing;

  /// Online download (saves the path in the DB itself).
  final AutoDownload download;

  /// Ask the sender's phone to send it again (1:1 `media_resend_request`,
  /// group `need`). True = the ask went out.
  final Future<bool> Function(String messageId, String fileId) ask;
  final Future<void> Function(String operationId) cancelDownload;
  final bool Function() inCall;
  final bool Function() serverUp;

  /// Free bytes on the phone; 0 = not known (not a reason to skip).
  final Future<int> Function() freeBytes;

  /// The friend / member is Nearby right now.
  final bool Function(String deviceId)? isNear;
  final String Function()? selfId;
  final DateTime Function() _clock;

  static const int maxBytes = FileSizeRule.maxBytes;
  static const Duration maxAge = Duration(days: 7);
  static const Duration stallBeforeAsk = Duration(seconds: 60);
  static const Duration askGap = Duration(minutes: 2);
  static const Duration showWaitingAfter = Duration(minutes: 3);
  static const Duration tick = Duration(minutes: 2);
  static const Duration callTick = Duration(seconds: 30);
  static const int spaceMargin = 200 * 1024 * 1024;
  static const List<Duration> retryWaits = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  /// Changes when an online download starts or ends (the bubble listens).
  final ValueNotifier<int> arrived = ValueNotifier<int>(0);
  final Map<String, String> _paths = <String, String>{};

  final Map<String, DateTime> _firstSeen = <String, DateTime>{};
  final Map<String, DateTime> _lastMove = <String, DateTime>{};
  final Map<String, DateTime> _lastAsk = <String, DateTime>{};
  final Map<String, int> _failures = <String, int>{};
  final Map<String, DateTime> _retryAt = <String, DateTime>{};
  final Map<String, String> _skipLogged = <String, String>{};
  final List<AutoFile> _queue = <AutoFile>[];
  final Set<String> _forced = <String>{};
  String? _runningKey;
  String? _runningOp;
  bool _checking = false;
  bool _checkAgain = false;
  bool _started = false;
  Timer? _timer;
  Timer? _soon;
  Timer? _callTimer;
  Timer? _retryTimer;
  final List<StreamSubscription<Object?>> _subs = <StreamSubscription<Object?>>[];

  // ------------------------------------------------------------ start / stop

  void start({
    Stream<Map<String, dynamic>>? events,
    List<Stream<Object?>> newMessages = const [],
    Stream<bool>? server,
    Duration firstLook = const Duration(seconds: 20),
  }) {
    if (_started) return;
    _started = true;
    instance = this;
    if (events != null) _subs.add(events.listen(_onEvent));
    for (final stream in newMessages) {
      _subs.add(stream.listen((_) => soon()));
    }
    if (server != null) {
      _subs.add(server.listen((up) {
        if (up) {
          soon();
        } else if (_queue.isNotEmpty) {
          // No server: nothing waits in line (no ring that turns for ever).
          _queue.clear();
          arrived.value++;
        }
      }));
    }
    _soon = Timer(firstLook, () => unawaited(check()));
    AppLogger.info('AUTO_DL_SERVICE_START');
  }

  void dispose() {
    _timer?.cancel();
    _soon?.cancel();
    _callTimer?.cancel();
    _retryTimer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    if (identical(instance, this)) instance = null;
  }

  /// A new message came: look in a moment (a few together = one look).
  void soon([Duration wait = const Duration(seconds: 3)]) {
    _soon?.cancel();
    _soon = Timer(wait, () => unawaited(check()));
  }

  // ------------------------------------------------------------ the bubble

  /// Being downloaded online (or waiting in line) right now.
  bool isFetching(String messageId, String fileId) {
    final key = '$messageId|${MediaTransferActions.baseId(fileId)}';
    return _runningKey == key || _queue.any((f) => f.key == key);
  }

  /// Saved by an online download (the bubble may still show the old row).
  String? pathFor(String fileId) => _paths[MediaTransferActions.baseId(fileId)];

  /// True when a stuck Nearby file will be asked for by itself (\"Waiting
  /// for Sajjad\"); false = \"Tap to download\".
  bool willAsk(String messageId, String fileId) {
    final actions = MediaTransferActions.instance;
    return !actions.stoppedByMe(fileId) && !actions.stoppedBySender(messageId);
  }

  /// Online: the bubble wants this file now (a tap, or a small file on
  /// screen). [force] = a tap: no retry wait, no space check.
  void fetchNow(AutoFile file, {bool force = false}) {
    if (!file.online || !serverUp()) return;
    if (_runningKey == file.key) return;
    _queue.removeWhere((f) => f.key == file.key);
    if (force) {
      _forced.add(file.key);
      _failures.remove(file.key);
      _retryAt.remove(file.key);
      _queue.insert(0, file);
    } else {
      _queue.add(file);
    }
    unawaited(_pump());
  }

  /// X on the ring of an online download.
  Future<void> stop(String messageId, String fileId) async {
    final key = '$messageId|${MediaTransferActions.baseId(fileId)}';
    MediaTransferActions.instance.stopByMe(fileId);
    _queue.removeWhere((f) => f.key == key);
    final op = _runningOp;
    if (_runningKey == key && op != null) {
      try {
        await cancelDownload(op);
      } catch (_) {}
    }
    MediaProgressHub.instance.clear(messageId, fileId: fileId);
  }

  // ------------------------------------------------------------ events

  void _onEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    if (type == 'file_progress') {
      final id = event['message_id']?.toString() ?? '';
      final file = (event['file_id'] ?? event['transfer_id'])?.toString() ?? '';
      if (id.isNotEmpty && file.isNotEmpty) {
        _lastMove['$id|${MediaTransferActions.baseId(file)}'] = _clock();
        // Bytes move again: the ring comes back ("Waiting for…" goes).
        final actions = MediaTransferActions.instance;
        if (actions.isCancelled(id) && willAsk(id, file)) {
          actions.clearCancelled(id);
        }
      }
      return;
    }
    if (type == 'peer_connected' ||
        type == 'route_recovered' ||
        type == 'peer_discovered' ||
        type == 'relay_connected') {
      final peer = event['peer_id']?.toString() ?? '';
      if (peer.isNotEmpty) unawaited(check(seen: peer));
    }
  }

  /// A friend / member was seen Nearby (also used by tests).
  Future<void> peerSeen(String peer) => check(seen: peer);

  // ------------------------------------------------------------ the look

  Future<void> check({String? seen}) async {
    if (_checking) {
      _checkAgain = true;
      _seenWhileBusy.addAll([if (seen != null) seen]);
      return;
    }
    _checking = true;
    try {
      await _look(seen: seen);
      while (_checkAgain) {
        _checkAgain = false;
        final again = _seenWhileBusy.toList();
        _seenWhileBusy.clear();
        if (again.isEmpty) {
          await _look();
        } else {
          for (final peer in again) {
            await _look(seen: peer);
          }
        }
      }
    } catch (error) {
      AppLogger.warning('AUTO_DL_CHECK_FAILED', detail: '$error');
    } finally {
      _checking = false;
    }
  }

  final Set<String> _seenWhileBusy = <String>{};

  Future<void> _look({String? seen}) async {
    final now = _clock();
    final files = await missing();
    final self = selfId?.call() ?? '';
    var waiting = false;
    final live = <String>{};
    for (final f in files) {
      live.add(f.key);
      final why = _skipReason(f, now, self);
      if (why != null) {
        _logSkip(f, why);
        continue;
      }
      waiting = true;
      _firstSeen.putIfAbsent(f.key, () => now);
      if (f.online && serverUp()) {
        if (_runningKey != f.key && !_queue.any((q) => q.key == f.key)) {
          final at = _retryAt[f.key];
          if ((_failures[f.key] ?? 0) >= retryWaits.length) continue;
          if (at != null && now.isBefore(at)) continue;
          _queue.add(f);
        }
        continue;
      }
      if (f.online) continue; // the server is away: wait for it
      _nearby(f, now, seen: seen);
    }
    // Forget files that came (or went).
    _firstSeen.removeWhere((k, _) => !live.contains(k));
    _lastAsk.removeWhere((k, _) => !live.contains(k));
    _lastMove.removeWhere((k, _) => !live.contains(k));
    _skipLogged.removeWhere((k, _) => !live.contains(k));
    _timer?.cancel();
    _timer = waiting ? Timer(tick, () => unawaited(check())) : null;
    unawaited(_pump());
  }

  String? _skipReason(AutoFile f, DateTime now, String self) {
    if (f.senderId.isNotEmpty && f.senderId == self) return 'mine';
    if (now.toUtc().difference(f.createdAt) > maxAge) return 'old';
    if (f.size > FileSizeRule.maxBytes) return 'toobig';
    if (MediaTransferActions.instance.stoppedByMe(f.fileId)) return 'stopped';
    if (MediaTransferActions.instance.stoppedBySender(f.messageId)) {
      return 'sender_stopped';
    }
    if (MediaBook.instance.of(f.fileId)?.isRemoved ?? false) return 'removed';
    return null;
  }

  void _logSkip(AutoFile f, String why) {
    if (why == 'old') return; // too many and not useful
    if (_skipLogged[f.key] == why) return;
    _skipLogged[f.key] = why;
    AppLogger.info('AUTO_DL_SKIP', detail: 'id=${_short(f.fileId)} why=$why');
  }

  /// Bundle 208 (E3 / E4): a Nearby file that stopped moving.
  void _nearby(AutoFile f, DateTime now, {String? seen}) {
    final moved = _lastMove[f.key];
    final first = _firstSeen[f.key]!;
    final since = (moved != null && moved.isAfter(first)) ? moved : first;
    final quiet = now.difference(since);
    // \"Waiting for Sajjad\" instead of a ring that turns for ever.
    if (quiet >= showWaitingAfter) {
      MediaTransferActions.instance.markCancelled(f.messageId);
    }
    if (quiet < stallBeforeAsk) return;
    if (inCall()) {
      _logSkip(f, 'call');
      _waitForCall();
      return;
    }
    final near = seen == f.senderId || (isNear?.call(f.senderId) ?? false);
    if (!near) return;
    final last = _lastAsk[f.key];
    if (last != null && now.difference(last) < askGap) return;
    _lastAsk[f.key] = now;
    final way = f.group ? 'group' : '1to1';
    AppLogger.info('AUTO_DL_ASK',
        detail: 'id=${_short(f.fileId)} to=${_short(f.senderId)} way=$way');
    unawaited(ask(f.messageId, f.fileId).then((ok) {
      if (!ok) AppLogger.info('AUTO_DL_ASK_FAILED', detail: 'id=${_short(f.fileId)}');
    }).catchError((Object e) {
      AppLogger.warning('AUTO_DL_ASK_FAILED', detail: 'id=${_short(f.fileId)} $e');
    }));
  }

  void _waitForCall() {
    _callTimer ??= Timer(callTick, () {
      _callTimer = null;
      unawaited(check());
    });
  }

  // ------------------------------------------------------------ online line

  Future<void> _pump() async {
    if (_runningKey != null || _queue.isEmpty) return;
    if (!serverUp()) return;
    if (inCall()) {
      _waitForCall();
      return;
    }
    final f = _queue.removeAt(0);
    final forced = _forced.remove(f.key);
    final self = selfId?.call() ?? '';
    final why = _skipReason(f, _clock(), self);
    if (why != null && !(forced && (why == 'stopped' || why == 'old'))) {
      _logSkip(f, why);
      unawaited(_pump());
      return;
    }
    if (!forced) {
      var free = 0;
      try {
        free = await freeBytes();
      } catch (_) {}
      if (free > 0 && free < f.size + spaceMargin) {
        _logSkip(f, 'space');
        unawaited(_pump());
        return;
      }
    }
    final key = f.key;
    final op = 'auto-${f.fileId}';
    _runningKey = key;
    _runningOp = op;
    arrived.value++; // an open bubble shows its ring now
    final started = _clock();
    AppLogger.info('AUTO_DL_START',
        detail: 'id=${_short(f.fileId)} way=online size=${f.size}');
    try {
      final path = await download(f, operationId: op, onProgress: (p) {
        if (p.total > 0) {
          MediaProgressHub.instance.update(f.messageId,
              done: p.completed, total: p.total, fileId: f.fileId);
        }
      });
      _paths[MediaTransferActions.baseId(f.fileId)] = path;
      _failures.remove(key);
      _retryAt.remove(key);
      arrived.value++;
      AppLogger.info('AUTO_DL_DONE',
          detail: 'id=${_short(f.fileId)} ms=${_clock().difference(started).inMilliseconds}');
    } on FileTransferCancelledException {
      AppLogger.info('AUTO_DL_STOPPED', detail: 'id=${_short(f.fileId)}');
    } catch (error) {
      final n = (_failures[key] ?? 0) + 1;
      _failures[key] = n;
      if (n <= retryWaits.length) {
        _retryAt[key] = _clock().add(retryWaits[n - 1]);
      }
      AppLogger.warning('AUTO_DL_FAILED',
          detail: 'id=${_short(f.fileId)} try=$n $error');
      if (n < retryWaits.length + 1) {
        _retryTimer?.cancel();
        _retryTimer = Timer(retryWaits[n - 1], () => unawaited(check()));
      }
    } finally {
      MediaProgressHub.instance.clear(f.messageId, fileId: f.fileId);
      _runningKey = null;
      _runningOp = null;
      arrived.value++; // the ring goes away either way
      unawaited(_pump());
    }
  }

  /// Online: 3 tries failed - the bubble shows its download button.
  bool gaveUp(String messageId, String fileId) =>
      (_failures['$messageId|${MediaTransferActions.baseId(fileId)}'] ?? 0) >=
      retryWaits.length;

  static String _short(String id) =>
      id.length <= 8 ? id : id.substring(id.length - 8);

  @visibleForTesting
  int get queued => _queue.length;
}
