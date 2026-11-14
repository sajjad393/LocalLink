import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static ChatRequestNotifier307? instance;
  static const String buzzedKey = 'chat_req_ready_buzzed_307';
  static const Duration minGap = Duration(seconds: 1);
  static const int maxBuzzed = 100;

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

  Future<void> _refreshOnce() async {
    if (!await isOwner()) {
      if (_shown.isNotEmpty) await clearAll();
      return;
    }
    final rows = [for (final r in await mine()) if (r.action == 'get_chat') r];
    final buzzed = await _buzzedIds();
    final now = _clock();
    final want = <String, (ChatRequestRow221, RequestStep307)>{};
    for (final r in rows) {
      final st = RequestStep307.of(r);
      final keep = switch (st.step) {
        Step307.sent || Step307.reached || Step307.coming => true,
        // Ready: until opened / closed; not again after a restart once it buzzed.
        Step307.ready => !r.opened && !r.closed && (_shown.containsKey(r.id) || !buzzed.contains(r.id)),
        // No messages: once, and only for a card that was running here.
        Step307.empty => _shown.containsKey(r.id) && !_emptyShown.contains(r.id),
        Step307.cancelled => false,
      };
      if (keep) want[r.id] = (r, st);
    }
    // Gone / cancelled / opened -> remove.
    final summary = _summary(want.values.where((w) => w.$2.step != Step307.empty));
    for (final id in _shown.keys.toList()) {
      if (want.containsKey(id)) continue;
      _shown.remove(id);
      _lastPost.remove(id);
      await cards.cancel({'request_id': id, ...summary});
    }
    var wait = Duration.zero;
    for (final MapEntry(key: id, value: (r, st)) in want.entries) {
      final args = _args(r, st, now);
      final sig = jsonEncode(args);
      if (_shown[id] == sig) continue;
      final last = _lastPost[id];
      if (last != null && now.difference(last) < minGap) {
        final left = minGap - now.difference(last);
        if (wait == Duration.zero || left < wait) wait = left;
        continue;
      }
      final buzz = st.step == Step307.ready && !buzzed.contains(id);
      _shown[id] = sig;
      _lastPost[id] = now;
      if (st.step == Step307.empty) {
        _emptyShown.add(id);
        _shown.remove(id); // Android drops it after 10 s; nothing left to update.
      }
      await cards.show({...args, 'buzz': buzz, ...summary});
      if (buzz) await _rememberBuzz(id);
    }
    if (wait > Duration.zero) {
      _later?.cancel();
      _later = Timer(wait, kick);
    }
  }

  static Map<String, Object?> _summary(Iterable<(ChatRequestRow221, RequestStep307)> live) {
    final list = live.toList();
    final ready = list.where((w) => w.$2.step == Step307.ready).length;
    return {
      'summary_count': list.length,
      'summary_title': L.t.chatRequestsSummary307(list.length, ready),
      'summary_lines': [for (final (r, st) in list) '${_title(r)} \u00b7 ${st.chip}'],
    };
  }

  static String _title(ChatRequestRow221 r) => r.label.isEmpty ? L.t.chat : r.label;

  static List<String> namesOf(ChatRequestRow221 r) =>
      r.label.contains(' & ') ? r.label.split(' & ') : [_title(r)];

  /// The words + numbers of one card (the signature; `buzz` is added later).
  static Map<String, Object?> _args(ChatRequestRow221 r, RequestStep307 st, DateTime now) {
    final made = DateTime.tryParse(r.madeAt)?.millisecondsSinceEpoch ?? 0;
    return {
      'request_id': r.id,
      'step': st.step.name,
      'progress': st.progress.round(),
      'title': st.big,
      'text': st.sub,
      'sub_text': _title(r),
      'names': namesOf(r),
      'short': st.short,
      // Ready moves to the top of the group (newest time).
      'when': st.step == Step307.ready ? 0 : made,
      'open_label': L.t.openChat307,
      'channel_name': L.t.chatRequestsChannel307,
      'ready_channel_name': L.t.chatReady307,
    };
  }
}
