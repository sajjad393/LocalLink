import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';

/// Bundle 317 (G1): every photo / video / voice note / file of a Get chat
/// answer comes by itself - no Get button. When a chat request is Ready the
/// Owner's phone reads the answer's attachments ONCE (one entry per file id,
/// newest message first) and asks for them in turn:
///
/// * gone on the phone (`file_gone`) and over 50 MB are never asked;
/// * at most 2 files / 16 MB on the way at once, at most 3 pending cards;
/// * the next file is asked when one is here or refused; a refused file is
///   never asked again;
/// * Stop files / Close: the files not here yet are stopped (signed stop).
enum FileState317 { next, coming, here, gone, tooBig, stopped }

/// One attachment of the plan.
class FilePlanItem317 {
  const FilePlanItem317({
    required this.fileId,
    required this.messageId,
    required this.name,
    required this.type,
    required this.size,
    this.gone = false,
  });

  final String fileId;
  final String messageId;
  final String name;
  final String type;
  final int size;
  final bool gone;

  bool get tooBig => size > ChatAnswerRules.maxFileBytes;

  Map<String, dynamic> toJson() => {
        'f': fileId,
        'm': messageId,
        'n': name,
        't': type,
        's': size,
        if (gone) 'g': true,
      };

  static FilePlanItem317? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['f']?.toString() ?? '';
    if (id.isEmpty) return null;
    final s = raw['s'];
    return FilePlanItem317(
      fileId: id,
      messageId: raw['m']?.toString() ?? '',
      name: raw['n']?.toString() ?? '',
      type: raw['t']?.toString() ?? '',
      size: s is int ? s : int.tryParse('${s ?? ''}') ?? 0,
      gone: raw['g'] == true,
    );
  }
}

/// What one file shows (viewer rows, app + web).
class FileView317 {
  const FileView317(this.state, {this.parts = 0, this.of = 0, this.row});
  final FileState317 state;
  final int parts;
  final int of;
  final ChatRequestRow221? row;
}

/// The files of one chat request (phone card, admin card, viewer strip).
class FileTrip317 {
  const FileTrip317({
    required this.requestId,
    required this.total,
    required this.here,
    required this.gone,
    required this.tooBig,
    required this.coming,
    required this.bytesHere,
    required this.bytesTotal,
    required this.waiting,
    required this.stopped,
    this.from = '',
    this.via = '',
    this.quietMin = 0,
    this.kind321 = '',
    this.thumb321 = '',
    this.pieces321 = '',
  });

  /// Bundle 321 (N1/N2): the file the phone card shows - its type
  /// (`photo` / `video` / `voice` / `file`; the one coming, else the newest
  /// here), its small picture (base64, '' = none -> the faces) and one fill
  /// 0-100 per file that can come (here first, then coming, then next),
  /// comma separated so [toArgs] compares by value.
  final String kind321;
  final String thumb321;
  final String pieces321;

  /// Bytes in one trip (a middle phone carries 8 MB at a time).
  static const int tripBytes = 8 * 1024 * 1024;

  /// Android 16 progress segments (NOT VERIFIED above 7 on phones).
  static const int maxTrips = 7;

  final String requestId;
  final int total;
  final int here;
  final int gone; // gone on the phone / refused
  final int tooBig;
  final int coming; // asked, not here yet
  final int bytesHere;
  final int bytesTotal; // of the files that can come
  final bool waiting; // no new parts for 2 min
  final bool stopped;
  final String from;
  final String via;

  /// Minutes since the last new part (while files are on the way).
  final int quietMin;

  /// Bundle 322 (S6): nothing moved for this long -> the card can be swiped.
  /// Set to [Duration.zero] to go back to the 321 value of 30 min.
  static const Duration swipeAfter322 = Duration(minutes: 10);

  /// Waiting more than 30 min (321) / [swipeAfter322] (322): swiped away.
  bool get waitingLong =>
      waiting && quietMin >= (swipeAfter322 > Duration.zero ? swipeAfter322 : const Duration(minutes: 30)).inMinutes;

  /// Files that can come (not gone, not too big).
  int get wanted => total - gone - tooBig;
  bool get active => !stopped && here < wanted;
  bool get done => total > 0 && !active;
  int get trips {
    final n = (bytesTotal + tripBytes - 1) ~/ tripBytes;
    return n < 1 ? 1 : (n > maxTrips ? maxTrips : n);
  }

  /// 0-1 by bytes (the bar), files here count whole.
  double get fill => bytesTotal <= 0 ? (wanted <= 0 ? 1 : here / wanted) : (bytesHere / bytesTotal).clamp(0, 1).toDouble();

  @override
  bool operator ==(Object other) =>
      other is FileTrip317 &&
      other.requestId == requestId &&
      other.coming == coming &&
      other.stopped == stopped &&
      mapEquals(other.toArgs(), toArgs());

  @override
  int get hashCode => Object.hash(requestId, here, coming, bytesHere, waiting, stopped);

  Map<String, Object?> toArgs() => {
        'files_total': total,
        'files_here': here,
        'files_wanted': wanted,
        'files_gone': gone + tooBig,
        'files_bytes_here': bytesHere,
        'files_bytes_total': bytesTotal,
        'files_trips': trips,
        'files_waiting': waiting,
        'files_quiet_min': quietMin,
        'files_from': from,
        'files_via': via,
        'files_kind': kind321,
        'files_thumb': thumb321,
        'files_pieces': pieces321,
      };

  /// Bundle 321 (N2): `image/*` -> photo, `video/*` -> video, `audio/*` -> voice.
  static String kindOf321(String type) {
    final t = type.toLowerCase();
    if (t.startsWith('image/')) return 'photo';
    if (t.startsWith('video/')) return 'video';
    if (t.startsWith('audio/')) return 'voice';
    return 'file';
  }
}

class FileQueue317 {
  /// Bundle 322 (S1): a [ChatRequestRow221] for this file is on the server
  /// but no new part came. A `pending` row (or one this queue does not know)
  /// means the card was made and the answer is lost - it is on the way, so
  /// the 321 clock must run on it. Turning this off restores 321 exactly
  /// (such a file showed `next` and could never time out).
  static const bool cardMeansComing322 = true;

  FileQueue317({
    required this.rows,
    required this.mineIds,
    required this.open,
    required this.ask,
    required this.close,
    required this.isOwner,
    required this.read,
    required this.write,
    this.cancel,
    this.nameOf,
    this.changes,
    this.every = const Duration(seconds: 5),
    this.keptFiles318,
    this.keep318,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Bundle 318 (K8): file ids whose bytes are kept on this phone (null = none).
  final Future<Set<String>> Function()? keptFiles318;

  /// Bundle 318 (K8): reads a file that is here once so its bytes are kept
  /// with the copy (the server copy goes 24 h after open). One per tick.
  final Future<void> Function(ChatRequestRow221 row)? keep318;
  final Set<String> _keepTried318 = {};
  bool _keeping318 = false;

  static FileQueue317? instance;

  /// Request id -> its files now (listened to by the cards + viewer).
  static final ValueNotifier<Map<String, FileTrip317>> trips =
      ValueNotifier<Map<String, FileTrip317>>(const {});

  static const String planKey = 'file_plans_317';
  static const int maxOnTheWay = 2;
  static const int maxBytesOnTheWay = 16 * 1024 * 1024;
  static const int maxPendingCards = 3;
  static const Duration waitAfter = Duration(minutes: 2);
  static const int maxPlans = 50;

  /// Bundle 321 (F7): a file with no new part this long is asked once
  /// more; the 2nd time it is gone.
  static const Duration stuckAfter321 = Duration(minutes: 10);

  /// Bundle 321 (F7): pending Get file cards older than this do not count.
  static const Duration oldCardAfter321 = Duration(days: 1);

  static bool _older321(String madeAt, DateTime than) {
    final t = DateTime.tryParse(madeAt);
    return t != null && t.toUtc().isBefore(than.toUtc());
  }

  /// Bundle 322 (S2): an ask that fails releases its slot and waits this
  /// long before the same file is tried again (last value repeats).
  static const List<Duration> askBackoff322 = [
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  /// Bundle 322 (S2): after this many failed asks the file counts as gone.
  static const int maxAskTries322 = 5;

  final Map<String, (int, DateTime)> _fileMoved321 = {};

  /// Bundle 322 (S1): request/file -> (state, parts, since) for EVERY file,
  /// not only the coming ones.
  final Map<String, (FileState317, int, DateTime)> _stateMoved322 = {};

  /// Bundle 322 (S2): request/file -> (not before, last try) after a failed ask.
  final Map<String, (DateTime, int)> _askLater322 = {};

  /// Bundle 322 (S2): the wait for the [tries]-th retry (0-based index).
  static Duration askWait322(int tries) =>
      askBackoff322[tries.clamp(0, askBackoff322.length - 1)];

  /// Bundle 321 (N1): request id -> file id -> small picture (base64), read
  /// from the answer once per run (not saved: the plan stays small).
  final Map<String, Map<String, String>> _thumbs321 = {};

  /// Bundle 321 (N1): the small pictures of an answer's attachments.
  static Map<String, String> thumbsOf321(ChatAnswerView v) => {
        for (final m in v.messages)
          for (final a in (m['attachments'] as List? ?? const []))
            if (a is Map && '${a['file_id'] ?? ''}'.isNotEmpty && '${a['thumb'] ?? ''}'.isNotEmpty)
              '${a['file_id']}': '${a['thumb']}',
      };

  final Future<List<ChatRequestRow221>> Function() rows;
  final Future<Set<String>> Function() mineIds;
  final Future<ChatAnswerView> Function(ChatRequestRow221 r) open;
  final Future<String> Function(ChatRequestRow221 parent,
      {required String fileId, String messageId, String name}) ask;
  final Future<void> Function(ChatRequestRow221 r) close;
  final Future<void> Function(ChatRequestRow221 r)? cancel;
  final Future<bool> Function() isOwner;
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final Future<String> Function(String deviceId)? nameOf;
  final Listenable? changes;
  final Duration every;
  final DateTime Function() _clock;

  Map<String, Map<String, dynamic>>? _plans;
  final Map<String, Map<String, FileView317>> _views = {};
  final Map<String, (int, DateTime)> _moved = {};
  Timer? _timer;
  bool _busy = false;
  bool _again = false;

  /// The state of every file of a request (viewer rows).
  Map<String, FileView317> viewsOf(String requestId) => Map.unmodifiable(_views[requestId] ?? const {});

  void start() {
    changes?.addListener(kick);
    _timer ??= Timer.periodic(every, (_) {
      if (trips.value.values.any((t) => t.active)) kick();
    });
    kick();
  }

  void stop() {
    changes?.removeListener(kick);
    _timer?.cancel();
    _timer = null;
  }

  void kick() => unawaited(tick());

  Future<void> tick() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _tickOnce();
      } while (_again);
    } catch (error) {
      AppLogger.info('FILE_QUEUE_317', detail: 'error=$error');
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, Map<String, dynamic>>> _load() async {
    if (_plans != null) return _plans!;
    final out = <String, Map<String, dynamic>>{};
    try {
      final d = jsonDecode(await read(planKey) ?? '{}');
      if (d is Map) {
        d.forEach((k, v) {
          if (v is Map) out['$k'] = Map<String, dynamic>.from(v);
        });
      }
    } catch (_) {}
    return _plans = out;
  }

  Future<void> _save() async {
    final plans = await _load();
    if (plans.length > maxPlans) {
      final ids = plans.keys.toList()
        ..sort((a, b) => '${plans[a]!['at']}'.compareTo('${plans[b]!['at']}'));
      for (final id in ids.take(plans.length - maxPlans)) {
        plans.remove(id);
      }
    }
    await write(planKey, jsonEncode(plans));
  }

  /// The plan of a request: one entry per file id, newest message first.
  /// Bundle 318 (K8): a new-only request plans only its new messages.
  static List<FilePlanItem317> planOf(ChatAnswerView v) {
    final out = <FilePlanItem317>[];
    final seen = <String>{};
    final only = v.newOnly318 ? v.newIds318.toSet() : null;
    final msgs = [
      for (final m in v.messages)
        if (only == null || only.contains(m['id']?.toString())) m,
    ]..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    for (final m in msgs) {
      for (final a in (m['attachments'] as List? ?? const [])) {
        if (a is! Map) continue;
        final id = a['file_id']?.toString() ?? '';
        if (id.isEmpty || !seen.add(id)) continue;
        final s = a['size'];
        out.add(FilePlanItem317(
          fileId: id,
          messageId: m['id']?.toString() ?? '',
          name: a['name']?.toString() ?? '',
          type: a['type']?.toString() ?? '',
          size: s is int ? s : int.tryParse('${s ?? ''}') ?? 0,
          gone: a['file_gone'] == true,
        ));
      }
    }
    return out;
  }

  List<FilePlanItem317> _items(Map<String, dynamic> plan) => [
        for (final x in (plan['files'] as List? ?? const []))
          if (FilePlanItem317.fromJson(x) case final i?) i,
      ];

  Future<void> _tickOnce() async {
    if (!await isOwner()) return;
    final all = await rows();
    final mine = await mineIds();
    final plans = await _load();
    var dirty = false;
    final files = <String, List<ChatRequestRow221>>{};
    // Bundle 318 (K8): every live Get file by file id (any request).
    final byFile = <String, List<ChatRequestRow221>>{};
    for (final r in all) {
      if (r.action == 'get_file' && r.parent.isNotEmpty) (files[r.parent] ??= []).add(r);
      if (r.action == 'get_file' && r.fileId.isNotEmpty && !r.cancelled && !r.closed && !r.empty && r.refused.isEmpty) {
        (byFile[r.fileId] ??= []).add(r);
      }
    }
    final keptIds = await keptFiles318?.call().catchError((Object _) => <String>{}) ?? const <String>{};
    // Bundle 321 (F7): old pending Get file cards (over a day, e.g. the
    // 3.0.107 manual ones) no longer fill the 3-card window.
    final cardCut = _clock().toUtc().subtract(oldCardAfter321);
    var pendingCards = all
        .where((r) => r.action == 'get_file' && r.state == 'pending' && !r.cancelled && !_older321(r.madeAt, cardCut))
        .length;
    // Bundle 321 (F7): the Get file ids the queue asked (any request).
    final queueIds = <String>{
      for (final p in plans.values)
        for (final v in (p['asked'] as Map? ?? const {}).values) '$v',
    };
    final out = <String, FileTrip317>{};
    for (final r in all) {
      if (r.action != 'get_chat' || !mine.contains(r.id) || r.cancelled || r.empty) continue;
      var plan = plans[r.id];
      if (plan == null) {
        if (!r.ready || r.closed) continue;
        final v = await open(r);
        if (!v.complete) continue;
        final items = planOf(v);
        _thumbs321[r.id] = thumbsOf321(v);
        plan = plans[r.id] = {
          'files': [for (final i in items) i.toJson()],
          'asked': <String, dynamic>{},
          'from': v.fromName.trim().isNotEmpty ? v.fromName.trim() : r.fromName,
          'at': _clock().toUtc().toIso8601String(),
        };
        dirty = true;
        AppLogger.info('FILE_QUEUE_PLAN', detail: 'files=${items.length}');
      }
      final items = _items(plan);
      if (items.isEmpty) continue;
      final asked = Map<String, dynamic>.from(plan['asked'] as Map? ?? const {});
      var stopped = plan['stopped'] == true;
      if (r.closed && !stopped) {
        plan['stopped'] = stopped = true;
        dirty = true;
      }
      final mineFiles = files[r.id] ?? const <ChatRequestRow221>[];
      // Bundle 321 (F7): stuck files - asked once more, then gone.
      final retry = Map<String, dynamic>.from(plan['retry321'] as Map? ?? const {});
      final dead = Map<String, dynamic>.from(plan['dead321'] as Map? ?? const {});
      // Bundle 322 (S2): failed asks per file (kept across a restart).
      final fails322 = Map<String, dynamic>.from(plan['fails322'] as Map? ?? const {});
      final planAt = DateTime.tryParse(plan['at']?.toString() ?? '');
      ChatRequestRow221? rowOf(String fileId) {
        ChatRequestRow221? best;
        for (final f in mineFiles) {
          if (f.fileId != fileId) continue;
          // Bundle 321 (F7): a row made before this plan and not by the
          // queue (old manual Get file) counts only once it is here.
          if (!f.ready && !queueIds.contains(f.id) && planAt != null && _older321(f.madeAt, planAt)) continue;
          // The row stopped by the retry (until the new one shows).
          if (retry.containsKey(fileId) && f.id != '${asked[fileId] ?? ''}' && (f.cancelled || f.closed)) continue;
          if (best == null ||
              (!best.ready && (f.ready || f.madeAt.compareTo(best.madeAt) > 0))) {
            best = f;
          }
        }
        // Bundle 318 (K8): here / on the way for another request of this
        // phone -> reuse or wait (never asked twice).
        if (best == null) {
          for (final f in byFile[fileId] ?? const <ChatRequestRow221>[]) {
            if (f.parent == r.id && !f.ready && !queueIds.contains(f.id)) continue; // Bundle 321 (F7)
            if (best == null || (!best.ready && f.ready)) best = f;
          }
        }
        return best;
      }

      final views = <String, FileView317>{};
      final now = _clock();
      for (final i in items) {
        final row = rowOf(i.fileId);
        views[i.fileId] = row == null && keptIds.contains(i.fileId)
            ? const FileView317(FileState317.here) // Bundle 318 (K8): kept here
            : _stateOf(i, row, asked.containsKey(i.fileId) || (cardMeansComing322 && row != null), stopped);
        if (dead.containsKey(i.fileId) && views[i.fileId]!.state != FileState317.here) {
          views[i.fileId] = const FileView317(FileState317.gone);
          continue;
        }
        // Bundle 322 (S3): a file whose request was stopped on the other
        // phone can never come - it counts as gone, not as "still wanted"
        // (321 left it `next`/`stopped`, which kept the card at "6/8").
        if (views[i.fileId]!.state == FileState317.stopped) {
          views[i.fileId] = const FileView317(FileState317.gone);
          dead[i.fileId] = true;
          plan['dead321'] = dead;
          AppLogger.info('FILE_QUEUE_GONE', detail: 'why=stopped');
          dirty = true;
          continue;
        }
        // Bundle 321 (F7): no new part for 10 min -> asked once more; the
        // 2nd time -> gone (the window is free for the next file).
        final v = views[i.fileId]!;
        final key = '${r.id}/${i.fileId}';
        // Bundle 322 (S1/S2): the file's state now, seen last time.
        final seen = _stateMoved322[key];
        if (seen == null || seen.$1 != v.state || seen.$2 != v.parts) {
          final was = seen?.$1;
          _stateMoved322[key] = (v.state, v.parts, now);
          // Bundle 322 (S2): the file really moved (a part came, or a card
          // appeared) - the failed-ask counter starts again.
          if (was != v.state || (seen != null && seen.$2 != v.parts)) {
            if (fails322.remove(i.fileId) != null) {
              plan['fails322'] = fails322;
              dirty = true;
            }
          }
        }
        if (v.state != FileState317.coming || stopped) {
          _fileMoved321.remove(key);
        } else {
          final m = _fileMoved321[key];
          if (m == null || m.$1 != v.parts) {
            _fileMoved321[key] = (v.parts, now);
          } else if (now.difference(m.$2) >= stuckAfter321) {
            _fileMoved321.remove(key);
            final old = v.row;
            if (old != null) {
              try {
                if (old.state == 'pending' && cancel != null) {
                  await cancel!(old);
                } else {
                  await close(old);
                }
              } catch (error) {
                AppLogger.info('FILE_QUEUE_STOP_LATER', detail: '$error');
              }
            }
            final tries = retry[i.fileId] is int ? retry[i.fileId] as int : 0;
            if (tries < 1) {
              retry[i.fileId] = tries + 1;
              plan['retry321'] = retry;
              asked.remove(i.fileId);
              plan['asked'] = asked;
              views[i.fileId] = const FileView317(FileState317.next);
              AppLogger.info('FILE_QUEUE_RETRY', detail: 'quiet_min=${stuckAfter321.inMinutes} parts=${v.parts}/${v.of}');
            } else {
              dead[i.fileId] = true;
              plan['dead321'] = dead;
              views[i.fileId] = const FileView317(FileState317.gone);
              AppLogger.info('FILE_QUEUE_GONE', detail: 'why=stuck_twice parts=${v.parts}/${v.of}');
            }
            dirty = true;
            continue;
          }
        }
        final keep = keep318;
        if (keep != null && !_keeping318 && row != null && row.ready && !keptIds.contains(i.fileId) &&
            _keepTried318.add(i.fileId)) {
          _keeping318 = true;
          unawaited(keep(row).catchError((Object _) {}).whenComplete(() => _keeping318 = false));
        }
      }
      // Ask the next ones (window 2 files / 16 MB, max 3 pending cards).
      if (!stopped) {
        var onWay = views.values.where((x) => x.state == FileState317.coming).length;
        var onWayBytes = 0;
        for (final i in items) {
          if (views[i.fileId]!.state == FileState317.coming) onWayBytes += i.size;
        }
        for (final i in items) {
          if (views[i.fileId]!.state != FileState317.next) continue;
          // Bundle 322 (S2): a file whose ask just failed waits its turn; a
          // failed ask never keeps the window full.
          final later = _askLater322['${r.id}/${i.fileId}'];
          if (later != null && now.isBefore(later.$1)) continue;
          if (onWay >= maxOnTheWay || pendingCards >= maxPendingCards) break;
          if (onWay > 0 && onWayBytes + i.size > maxBytesOnTheWay) break;
          try {
            final id = await ask(r, fileId: i.fileId, messageId: i.messageId, name: i.name);
            _askLater322.remove('${r.id}/${i.fileId}');
            asked[i.fileId] = id;
            plan['asked'] = asked;
            dirty = true;
            views[i.fileId] = const FileView317(FileState317.coming);
            onWay++;
            onWayBytes += i.size;
            pendingCards++;
            AppLogger.info('FILE_QUEUE_ASKED', detail: 'size=${i.size}');
          } catch (error) {
            // Bundle 322 (S2): the slot is released and the file is retried
            // later with a backoff; after [maxAskTries322] it is gone.
            final k = '${r.id}/${i.fileId}';
            final tries = (fails322[i.fileId] is int ? fails322[i.fileId] as int : 0) + 1;
            fails322[i.fileId] = tries;
            plan['fails322'] = fails322;
            if (tries >= maxAskTries322) {
              _askLater322.remove(k);
              dead[i.fileId] = true;
              plan['dead321'] = dead;
              views[i.fileId] = const FileView317(FileState317.gone);
              AppLogger.info('FILE_QUEUE_GONE',
                  detail: 'why=ask_failed tries=$tries');
            } else {
              final wait = askWait322(tries - 1);
              _askLater322[k] = (now.add(wait), tries);
              AppLogger.info('FILE_QUEUE_ASK_FAILED',
                  detail: 'try=$tries next_s=${wait.inSeconds}');
            }
            AppLogger.info('FILE_QUEUE_LATER', detail: '$error');
            dirty = true;
            continue;
          }
        }
      }
      _views[r.id] = views;
      // Bundle 321 (N1): after a restart the plan is saved but the pictures
      // are not - read the answer once (only while files still come).
      if (!_thumbs321.containsKey(r.id) && !stopped && views.values.any((v) => v.state != FileState317.here)) {
        _thumbs321[r.id] = const {};
        try {
          _thumbs321[r.id] = thumbsOf321(await open(r));
        } catch (_) {}
      }
      out[r.id] = await _trip(r, plan, items, views, stopped);
    }
    // Bundle 322 (S1/S2): drop the clocks of requests that are no longer
    // tracked and of files that are done (keeps the maps small).
    if (_stateMoved322.length > 200 || _askLater322.length > 200) {
      final live = {
        for (final e in out.entries)
          for (final v in (_views[e.key] ?? const <String, FileView317>{}).entries)
            if (v.value.state == FileState317.next || v.value.state == FileState317.coming)
              '${e.key}/${v.key}',
      };
      _stateMoved322.removeWhere((k, _) => !live.contains(k));
      _askLater322.removeWhere((k, _) => !live.contains(k));
    }
    if (dirty) await _save();
    if (!mapEquals(trips.value, out)) trips.value = out;
  }

  FileView317 _stateOf(FilePlanItem317 i, ChatRequestRow221? row, bool asked, bool stopped) {
    if (i.gone) return const FileView317(FileState317.gone);
    if (i.tooBig) return const FileView317(FileState317.tooBig);
    if (row != null) {
      if (row.ready) return FileView317(FileState317.here, parts: row.parts, of: row.of, row: row);
      if (row.refused == 'file_too_big') return FileView317(FileState317.tooBig, row: row);
      if (row.refused.isNotEmpty || row.empty) return FileView317(FileState317.gone, row: row);
      if (row.cancelled || row.closed || stopped) return FileView317(FileState317.stopped, row: row);
      return FileView317(FileState317.coming, parts: row.parts, of: row.of, row: row);
    }
    if (stopped) return const FileView317(FileState317.stopped);
    return asked ? const FileView317(FileState317.coming) : const FileView317(FileState317.next);
  }

  Future<FileTrip317> _trip(ChatRequestRow221 r, Map<String, dynamic> plan, List<FilePlanItem317> items,
      Map<String, FileView317> views, bool stopped) async {
    var here = 0, gone = 0, big = 0, coming = 0, bytesHere = 0, bytesTotal = 0, moved = 0;
    String viaDevice = '';
    // Bundle 321 (N1/N2): the card's file + one fill per file that can come.
    final fillsHere = <int>[], fillsComing = <int>[], fillsNext = <int>[];
    FilePlanItem317? show, newestHere;
    for (final i in items) {
      final v = views[i.fileId]!;
      switch (v.state) {
        case FileState317.here:
          fillsHere.add(100);
          newestHere ??= i;
        case FileState317.coming:
          fillsComing.add(v.of > 0 ? (100 * v.parts / v.of).floor().clamp(0, 99) : 0);
          show ??= i;
        case FileState317.next || FileState317.stopped:
          fillsNext.add(0);
        case FileState317.gone || FileState317.tooBig:
          break;
      }
      switch (v.state) {
        case FileState317.gone:
          gone++;
          continue;
        case FileState317.tooBig:
          big++;
          continue;
        case FileState317.here:
          here++;
          bytesHere += i.size;
        case FileState317.coming:
          coming++;
          if (v.of > 0) bytesHere += (i.size * v.parts / v.of).round();
        case FileState317.next || FileState317.stopped:
          break;
      }
      bytesTotal += i.size;
      moved += v.parts + (v.state == FileState317.here ? 1 : 0);
      final via = v.row == null ? null : ChatAnswerCarrier.lastVia[v.row!.id];
      if (via != null && via.isNotEmpty) viaDevice = via;
    }
    final now = _clock();
    final last = _moved[r.id];
    // Bundle 321 (F7): a retried file starts at 0 parts again - that is
    // not a new part (the quiet time goes on).
    if (last == null || moved > last.$1) {
      _moved[r.id] = (moved, now);
    } else if (moved < last.$1) {
      _moved[r.id] = (moved, last.$2);
    }
    final waiting = coming > 0 && now.difference(_moved[r.id]!.$2) >= waitAfter;
    var via = '';
    if (viaDevice.isNotEmpty) via = await nameOf?.call(viaDevice).catchError((_) => '') ?? '';
    show ??= newestHere;
    final pics = _thumbs321[r.id] ?? const <String, String>{};
    return FileTrip317(
      requestId: r.id,
      total: items.length,
      here: here,
      gone: gone,
      tooBig: big,
      coming: coming,
      bytesHere: bytesHere,
      bytesTotal: bytesTotal,
      waiting: waiting,
      stopped: stopped,
      from: plan['from']?.toString() ?? '',
      via: via.trim(),
      quietMin: coming > 0 ? now.difference(_moved[r.id]!.$2).inMinutes : 0,
      kind321: show == null ? '' : FileTrip317.kindOf321(show.type),
      thumb321: show == null ? '' : pics[show.fileId] ?? '',
      pieces321: [...fillsHere, ...fillsComing, ...fillsNext].join(','),
    );
  }

  /// Stop files: the queue stops; files not here yet are stopped (pending
  /// cards cancelled, answers on the way get the signed stop + closed).
  Future<void> stopFiles(String requestId) async {
    final plans = await _load();
    final plan = plans[requestId];
    if (plan == null) return;
    plan['stopped'] = true;
    await _save();
    for (final v in (_views[requestId] ?? const <String, FileView317>{}).values) {
      final row = v.row;
      if (row == null || v.state != FileState317.coming) continue;
      try {
        if (row.state == 'pending' && cancel != null) {
          await cancel!(row);
        } else {
          await close(row);
        }
      } catch (error) {
        AppLogger.info('FILE_QUEUE_STOP_LATER', detail: '$error');
      }
    }
    AppLogger.info('FILE_QUEUE_STOPPED', detail: 'id=${requestId.length > 6 ? requestId.substring(requestId.length - 6) : requestId}');
    await tick();
  }

  @visibleForTesting
  Future<Map<String, dynamic>?> planForTest(String requestId) async => (await _load())[requestId];
}
