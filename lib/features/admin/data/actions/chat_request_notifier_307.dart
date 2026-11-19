import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/server_clock_255.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/request_scope_324.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 307 (TODO_307 C1/C3): the native side of the phone card.
abstract interface class ChatRequestCards307 {
  Future<void> show(Map<String, Object?> args);
  Future<void> cancel(Map<String, Object?> args);
  Future<void> cancelAll();
}

/// The existing `locallink/notifications` channel (MainActivity + the
/// background engine both answer it).
class ChannelChatRequestCards307 implements ChatRequestCards307 {
  const ChannelChatRequestCards307();
  static const MethodChannel channel = MethodChannel('locallink/notifications');

  @override
  Future<void> show(Map<String, Object?> args) => _call('showChatRequest', args);

  @override
  Future<void> cancel(Map<String, Object?> args) => _call('cancelChatRequest', args);

  @override
  Future<void> cancelAll() => _call('cancelAllChatRequests', null);

  static Future<void> _call(String method, Object? args) async {
    try {
      await channel.invokeMethod<void>(method, args);
    } catch (_) {
      // No notification support (tests, old engine): the app screens still show it.
    }
  }
}

/// Bundle 307 (C3): keeps one phone card per Get chat request made on THIS
/// phone (owner only), like a ride card: Sent -> 1 of 2 phones -> 12 of 40
/// parts -> Ready.
///
/// - An update is sent only when the step / numbers / words change, at most
///   one per second per request.
/// - Ready buzzes once per request (remembered in [buzzedKey], max 100 ids)
///   and is not posted again after a restart.
/// - No messages shows once (grey; Android removes it after 10 s).
/// - Cancelled / opened / closed / gone -> the card is removed.
/// - Not the owner any more (logged out, role changed) -> all cards go.
class ChatRequestNotifier307 {
  ChatRequestNotifier307({
    required this.mine,
    required this.isOwner,
    required this.read,
    required this.write,
    this.cards = const ChannelChatRequestCards307(),
    this.changes,
    this.taps,
    this.checkEvery = const Duration(seconds: 5),
    this.files317,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static ChatRequestNotifier307? instance;
  static const String buzzedKey = 'chat_req_ready_buzzed_307';
  static const Duration minGap = Duration(seconds: 1);
  static const int maxBuzzed = 100;

  /// Bundle 317 (G7): the Stop files button comes back as a tap with this prefix.
  static const String stopPrefix317 = 'stop317:';

  /// Bundle 317 (G7): the files of each request (null = no queue; tests).
  final Map<String, FileTrip317> Function()? files317;

  /// Bundle 322 (S5): a files card whose numbers do not move for this long
  /// is ended here (it can never stay un-swipeable forever). The 321 file
  /// queue gives up on its own within ~20 min; this is the backstop for a
  /// queue that is not running (restart, stopped slot, lost plan).
  /// `Duration.zero` = Bundle 321 behaviour (no backstop).
  static const Duration cardStuckAfter322 = Duration(minutes: 30);

  /// Opens the answer viewer for a tapped card (set by the app shell).
  static Future<void> Function(String requestId)? openViewer;

  final Future<List<ChatRequestRow221>> Function() mine;
  final Future<bool> Function() isOwner;
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final ChatRequestCards307 cards;
  final Listenable? changes;
  final Stream<String>? taps;
  final Duration checkEvery;
  final DateTime Function() _clock;

  /// Request id -> what the card shows now.
  final Map<String, String> _shown = {};

  /// Bundle 322 (S5): request id -> (here, coming, since) - the last time the
  /// files of that card moved. Read and written only in [_refreshOnce].
  final Map<String, (int, int, DateTime)> _tripMoved322 = {};

  /// Bundle 322 (S5): request id -> (here, coming) of a card ended by the
  /// backstop. It stays away until its numbers really move again (then it
  /// comes back - nothing is lost, the files keep coming in the chat).
  final Map<String, (int, int)> _ended322 = {};
  final Map<String, DateTime> _lastPost = {};
  final Set<String> _emptyShown = {};
  List<String>? _buzzed;
  Timer? _every;
  Timer? _later;
  StreamSubscription<String>? _tapSub;
  bool _busy = false;
  bool _again = false;
  bool _started = false;

  @visibleForTesting
  Map<String, String> get shown => Map.unmodifiable(_shown);

  void start() {
    if (_started) return;
    _started = true;
    changes?.addListener(kick);
    _tapSub = taps?.listen((id) {
      // Bundle 317 (G7): "Stop files" on the card.
      if (id.startsWith(stopPrefix317)) {
        final rid = id.substring(stopPrefix317.length);
        unawaited(FileQueue317.instance?.stopFiles(rid).catchError((Object _) {}));
        return;
      }
      final open = openViewer;
      if (open != null && id.isNotEmpty) unawaited(open(id).catchError((Object _) {}));
    });
    _every = Timer.periodic(checkEvery, (_) {
      // Only while a card is running (the server numbers come by polling).
      if (_shown.isNotEmpty) kick();
    });
    kick();
  }

  void stop() {
    _started = false;
    changes?.removeListener(kick);
    unawaited(_tapSub?.cancel());
    _tapSub = null;
    _every?.cancel();
    _later?.cancel();
  }

  void kick() => unawaited(refresh());

  Future<List<String>> _buzzedIds() async {
    if (_buzzed != null) return _buzzed!;
    try {
      final d = jsonDecode(await read(buzzedKey) ?? '[]');
      _buzzed = [for (final x in (d is List ? d : const [])) '$x'];
    } catch (_) {
      _buzzed = [];
    }
    return _buzzed!;
  }

  Future<void> _rememberBuzz(String id) async {
    final all = await _buzzedIds();
    all
      ..remove(id)
      ..insert(0, id);
    if (all.length > maxBuzzed) all.removeRange(maxBuzzed, all.length);
    await write(buzzedKey, jsonEncode(all));
  }

  /// Logout / role change: every card goes.
  Future<void> clearAll() async {
    _shown.clear();
    _lastPost.clear();
    _tripMoved322.clear();
    _ended322.clear();
    await cards.cancelAll();
  }

  Future<void> refresh() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _refreshOnce();
      } while (_again);
    } catch (error) {
      AppLogger.info('CHAT_REQ_CARD_307', detail: 'error=$error');
    } finally {
      _busy = false;
    }
  }

  /// Bundle 324: the chat key of a request - the saved key first (works with
  /// the server off), else the chat ref the row carries.
  @visibleForTesting
  static String chatKey324(ChatRequestRow221 r) {
    final saved = RequestScope324.chatKeyOf(r.id);
    if (saved.isNotEmpty) return saved;
    final p = ChatPick221.fromRef(r.chat);
    return p == null ? 'id:${r.id}' : RequestScope324.chatKeyOfPick(p);
  }

  /// Bundle 324 (2.1): the one row of a chat that gets the card: the one
  /// already on screen (so a card never jumps), else the furthest along.
  ChatRequestRow221 _onePerChat324(List<ChatRequestRow221> group) {
    if (group.length == 1) return group.first;
    for (final r in group) {
      if (_shown.containsKey(r.id)) return r;
    }
    final live = RequestStep307.liveOrder(group);
    if (live.isNotEmpty) return live.first;
    final sorted = [...group]..sort((a, b) => b.madeAt.compareTo(a.madeAt));
    return sorted.first;
  }

  /// Bundle 324: how many requests each chat has (the "2 requests" note).
  Map<String, int> _counts324 = const {};

  Future<void> _refreshOnce() async {
    if (!await isOwner()) {
      if (_shown.isNotEmpty) await clearAll();
      return;
    }
    final all324 = [for (final r in await mine()) if (r.action == 'get_chat') r];
    // Bundle 324 (2.1/2.2): ONE card per chat. The 17 Nov 18:47/18:53 pair
    // drew two cards for the same chat; the row the owner sees is the one
    // furthest along (Ready first), never both.
    final byChat324 = <String, List<ChatRequestRow221>>{};
    for (final r in all324) {
      (byChat324[chatKey324(r)] ??= []).add(r);
    }
    final counts324 = {for (final e in byChat324.entries) e.key: e.value.length};
    final rows = <ChatRequestRow221>[
      for (final e in byChat324.entries) _onePerChat324(e.value),
    ];
    _counts324 = counts324;
    final buzzed = await _buzzedIds();
    final now = _clock();
    final want = <String, (ChatRequestRow221, RequestStep307)>{};
    final files = files317?.call() ?? const <String, FileTrip317>{};
    for (final r in rows) {
      final st = RequestStep307.of(r);
      // Bundle 317 (G7): a Ready card stays while its files come (even
      // after the chat was opened); when all are here it goes once opened.
      final trip = files[r.id];
      var keep = st.step == Step307.ready && trip != null && trip.total > 0 && !trip.stopped && !r.closed &&
              (trip.active || !r.opened)
          ? true
          : switch (st.step) {
        Step307.waiting || Step307.sent || Step307.reached || Step307.coming => true,
        // Ready: until opened / closed; not again after a restart once it buzzed.
        Step307.ready => !r.opened && !r.closed && (_shown.containsKey(r.id) || !buzzed.contains(r.id)),
        // No messages: once, and only for a card that was running here.
        Step307.empty => _shown.containsKey(r.id) && !_emptyShown.contains(r.id),
              Step307.cancelled => false,
            };
      // Bundle 322 (S5): a card ended by the backstop stays away until its
      // numbers move again.
      if (keep && _ended322.containsKey(r.id) && trip != null) {
        final e = _ended322[r.id]!;
        if (e.$1 == trip.here && e.$2 == trip.coming) {
          keep = false;
        } else {
          // Numbers moved: it may come back.
          _ended322.remove(r.id);
        }
      }
      if (keep) want[r.id] = (r, st);
    }
    // Bundle 322 (S5): a files card whose numbers never move cannot outlive
    // its work - after [cardStuckAfter322] it is ended here with the words
    // "N files not available" (the same words 321 uses for a missing file).
    if (cardStuckAfter322 > Duration.zero) {
      for (final id in want.keys.toList()) {
        final (r, st) = want[id]!;
        final trip = files[id];
        final working = st.step == Step307.ready && trip != null && trip.total > 0 && !trip.stopped && trip.active;
        if (!working) {
          _tripMoved322.remove(id);
          continue;
        }
        final seen = _tripMoved322[id];
        if (seen == null || seen.$1 != trip.here || seen.$2 != trip.coming) {
          _tripMoved322[id] = (trip.here, trip.coming, now);
          continue;
        }
        if (now.difference(seen.$3) < cardStuckAfter322) continue;
        _tripMoved322.remove(id);
        _ended322[id] = (trip.here, trip.coming);
        want.remove(id);
        _shown.remove(id);
        _lastPost.remove(id);
        final missing = trip.wanted - trip.here;
        AppLogger.info('CHAT_REQ_CARD_307',
            detail: 'cancel reason=stuck30 id=${_short322(id)} here=${trip.here}/${trip.wanted} missing=$missing');
        await cards.cancel({'request_id': id,
            ..._summary(want.values.where((w) => w.$2.step != Step307.empty), files, counts324)});
      }
    }
    // Gone / cancelled / opened -> remove.
    final summary = _summary(want.values.where((w) => w.$2.step != Step307.empty), files, counts324);
    for (final id in _shown.keys.toList()) {
      if (want.containsKey(id)) continue;
      _shown.remove(id);
      _lastPost.remove(id);
      _tripMoved322.remove(id);
      // Bundle 322 (S7): every drop leaves a line with its reason (the 17 Nov
      // stuck card was invisible in the logs: no CHAT_REQ_CARD line at all).
      AppLogger.info('CHAT_REQ_CARD_307', detail: 'drop id=${_short322(id)} reason=${_dropReason322(id, rows, files)}');
      await cards.cancel({'request_id': id, ...summary});
    }
    var wait = Duration.zero;
    for (final MapEntry(key: id, value: (r, st)) in want.entries) {
      final trip = files[id];
      final args = st.step == Step307.ready && trip != null && trip.total > 0 && !trip.stopped
          ? filesArgs317(r, st, trip, now,
              requests324: _counts324[chatKey324(r)] ?? 1)
          : _args(r, st, now, requests324: _counts324[chatKey324(r)] ?? 1);
      final sig = jsonEncode(args);
      if (_shown[id] == sig) continue;
      final last = _lastPost[id];
      if (last != null && now.difference(last) < minGap) {
        final left = minGap - now.difference(last);
        if (wait == Duration.zero || left < wait) wait = left;
        continue;
      }
      // Bundle 318 (K7): "Up to date" never buzzes (posted once, goes by itself).
      // Bundle 324 (1.3): ONE buzz per card - the "Chat ready" buzz of 317,
      // kept where it is: it comes when the chat is ready, not when the last
      // file lands (a 61 MB chat would buzz minutes later, and 317's own test
      // pins this). Never twice: the buzzed list below + setOnlyAlertOnce.
      final buzz = st.step == Step307.ready && !st.upToDate && !buzzed.contains(id);
      final once318 = st.step == Step307.ready && st.upToDate && !buzzed.contains(id);
      _shown[id] = sig;
      _lastPost[id] = now;
      if (st.step == Step307.empty) {
        _emptyShown.add(id);
        _shown.remove(id); // Android drops it after 10 s; nothing left to update.
      }
      // Bundle 322 (S7): one line per card change, ≤ 1/s (see [minGap]).
      final tripShow = files[id];
      AppLogger.info('CHAT_REQ_CARD_307',
          detail: 'show id=${_short322(id)} step=${args['step']} '
              'here=${tripShow?.here ?? 0}/${tripShow?.wanted ?? 0} shown=${_shown.length} buzz=$buzz');
      await cards.show({...args, 'buzz': buzz, ...summary});
      if (buzz || once318) await _rememberBuzz(id);
    }
    if (wait > Duration.zero) {
      _later?.cancel();
      _later = Timer(wait, kick);
    }
  }

  /// Bundle 322 (S7): the last 6 characters of a request id - enough to
  /// follow one card in a log, never the whole id.
  static String _short322(String id) => id.length > 6 ? id.substring(id.length - 6) : id;

  /// Bundle 322 (S7): why a card went - the words the log needs.
  static String _dropReason322(String id, List<ChatRequestRow221> rows, Map<String, FileTrip317> files) {
    ChatRequestRow221? row;
    for (final r in rows) {
      if (r.id == id) row = r;
    }
    if (row == null) return 'gone';
    if (row.closed) return 'closed';
    if (row.opened) return 'opened';
    final f = files[id];
    if (f != null && f.total > 0 && !f.stopped && f.done) return 'done';
    return switch (RequestStep307.of(row).step) {
      Step307.cancelled => 'cancelled',
      Step307.empty => 'empty',
      Step307.ready => 'done',
      _ => 'gone',
    };
  }

  static Map<String, Object?> _summary(Iterable<(ChatRequestRow221, RequestStep307)> live,
      [Map<String, FileTrip317> files = const {}, Map<String, int>? counts324]) {
    final list = live.toList();
    return {
      'summary_count': list.length,
      // Bundle 321 (N1/N3): "3 chats" + each card's own one line.
      'summary_title': L.t.nChats321(list.length),
      'summary_lines': [for (final (r, st) in list) cardTitle321(r, st, files[r.id], counts324?[chatKey324(r)] ?? 1)],
    };
  }

  /// Bundle 317 (G7): the summary line of a Ready request while files come:
  /// "Files 3/13" / "Waiting · files 3/13" / "All files here".
  @visibleForTesting
  static String? filesLine317(RequestStep307 st, FileTrip317? f) {
    if (st.step != Step307.ready || f == null || f.total <= 0 || f.stopped) return null;
    if (f.done) return L.t.allFilesHere317;
    return f.waiting ? '${L.t.filesWaitTitle317} \u00b7 ${f.here}/${f.wanted}' : L.t.filesShort317(f.here, f.wanted);
  }

  /// Bundle 314 (3): the tracker stops rocking this long after "made".
  static const Duration rockFor314 = Duration(minutes: 10);

  /// Bundle 314 (3, USER PICK): "made" in this phone's clock. The server
  /// stamps a request with the PC clock; when that clock is wrong
  /// ([ServerClock255.wrong] = server minus phone) the card said "2h" for a
  /// request made a minute ago (16 Nov). A request made on this phone
  /// offline has this phone's own time.
  @visibleForTesting
  static int madeOnPhoneClock314(ChatRequestRow221 r) {
    final made = DateTime.tryParse(r.madeAt)?.millisecondsSinceEpoch ?? 0;
    final wrong = ServerClock255.wrong.value;
    if (made == 0 || r.offline || wrong == null) return made;
    return made - wrong.inMilliseconds;
  }

  static String _title(ChatRequestRow221 r) => r.label.isEmpty ? L.t.chat : r.label;

  /// Bundle 321 (N1, USER PICK B "minimal"): the card is ONE line - the chat
  /// + "3/7", "waiting" or a green check (Android colours the check). No text
  /// line, no buttons: the bar and the colour say the rest; tap opens the chat
  /// and Stop is inside the chat. Same words on every Android version.
  static const String tick321 = '\u2713';

  @visibleForTesting
  static String cardTitle321(ChatRequestRow221 r, RequestStep307 st, [FileTrip317? f, int requests324 = 1]) {
    // Bundle 324 (2.1): one card per chat - when the chat has more than one
    // request the card says so instead of drawing a second card.
    final more = requests324 > 1 ? ' \u00b7 ${L.t.nRequests324(requests324)}' : '';
    final n = _title(r);
    if (st.step == Step307.ready && f != null && f.total > 0 && !f.stopped) {
      // Bundle 336: nothing can come says exactly that.
      if (f.none336) return '$n \u00b7 ${L.t.nothingToSend336}$more';
      if (f.done) return f.gone + f.tooBig > 0 ? '$n \u00b7 ${f.here}/${f.total}$more' : '$n $tick321$more';
      // Bundle 324 (2.6): never `0/6` - nothing is here yet, so it says
      // "waiting" until the first asked file lands.
      if (f.waiting || f.here <= 0) return '$n \u00b7 ${L.t.waitingShort321}$more';
      return '$n \u00b7 ${f.here}/${f.wanted}$more';
    }
    return switch (st.step) {
      // Bundle 325: a waiting ask says so; it has not left this phone yet.
      Step307.waiting => '$n \u00b7 ${L.t.waiting325}$more',
      Step307.sent || Step307.reached => '$n \u00b7 ${L.t.waitingShort321}$more',
      Step307.coming => '$n \u00b7 ${st.short}$more',
      Step307.ready when r.newOnly318 && st.upToDate => '$n \u00b7 ${L.t.upToDate318}',
      Step307.ready when r.newOnly318 && r.newCount318 > 0 => '$n \u00b7 ${L.t.nNew318(r.newCount318)} $tick321',
      Step307.ready => '$n $tick321$more',
      Step307.empty => '$n \u00b7 ${L.t.noMessages}',
      Step307.cancelled => '$n \u00b7 ${L.t.cancelled}',
    };
  }

  static List<String> namesOf(ChatRequestRow221 r) =>
      r.label.contains(' & ') ? r.label.split(' & ') : [_title(r)];

  /// Bundle 317 (G7): the card after "Chat ready" while files come (mock
  /// `trips_mock.html`): Chat ready · files coming / waiting / all here.
  @visibleForTesting
  static Map<String, Object?> filesArgs317(ChatRequestRow221 r, RequestStep307 st, FileTrip317 f, DateTime now,
      {int requests324 = 1}) {
    final base = _args(r, st, now, requests324: requests324);
    // Bundle 336: nothing can come -> its own step, never `0/6`.
    final step = f.none336
        ? 'files_none'
        : (f.done ? 'files_done' : (f.waiting ? 'files_wait' : 'files'));
    return {
      ...base,
      'step': step,
      'progress': (f.fill * 100).round(),
      'title': cardTitle321(r, st, f, requests324),
      'short': f.done ? '' : '${f.here}/${f.wanted}',
      'when': base['when'],
      'rock_until': 0,
      'files_swipe': f.waitingLong,
      'files_none': f.none336,
      'from_name': f.from.isNotEmpty ? f.from : base['from_name'],
      ...f.toArgs(),
    };
  }

  /// The words + numbers of one card (the signature; `buzz` is added later).
  static Map<String, Object?> _args(ChatRequestRow221 r, RequestStep307 st, DateTime now, {int requests324 = 1}) {
    final made = madeOnPhoneClock314(r);
    final waiting = st.step == Step307.sent || st.step == Step307.reached;
    return {
      'request_id': r.id,
      'step': st.step.name,
      'progress': st.progress.round(),
      'title': cardTitle321(r, st, null, requests324),
      'names': namesOf(r),
      'from_name': r.fromName,
      'short': st.short,
      // Ready moves to the top of the group (newest time).
      'when': st.step == Step307.ready ? 0 : made,
      // Bundle 314 (3, pick B): the tracker rocks while Sent / Reached, for
      // at most [rockFor314] after the request was made (Android 16+).
      'rock_until': waiting && made > 0 ? made + rockFor314.inMilliseconds : 0,
      'channel_name': L.t.chatRequestsChannel307,
      'ready_channel_name': L.t.chatReady307,
      // Bundle 318 (K7): new-only words (mock repeat_mock.html B).
      if (r.newOnly318) ...newOnlyArgs318(r, st),
    };
  }

  /// Bundle 318 (K7): a "Get new messages only" card: "Asking for new
  /// messages" while asking, "Up to date · no new messages" (step
  /// `up_to_date`: green, silent, not ongoing, goes by itself) or
  /// "Chat ready · 12 new" (one buzz, like Ready).
  @visibleForTesting
  static Map<String, Object?> newOnlyArgs318(ChatRequestRow221 r, RequestStep307 st) {
    // Bundle 321 (N1): the one line comes from cardTitle321 (waiting / Up to date / 12 new).
    if (st.step != Step307.ready) return const {};
    if (st.upToDate) return {'step': 'up_to_date', 'when': 0};
    return const {};
  }
}
