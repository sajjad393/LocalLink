import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';

/// Bundle 313 (D): get chats back from friends' phones.
///
/// Uninstalling LinkUp deletes the chats on this phone, and the server only
/// gives back what went through the server. Chats that went over Local
/// Wi-Fi / mesh live on on the friend's phone - this gets them back from
/// there, phone to phone:
///
/// 1. me -> friend `restore_ask_313` {id, chats: ['d', gid, ...]}
/// 2. friend -> me `restore_ids_313` {id, chat, part, parts, ids} (pages)
/// 3. me -> friend `restore_want_313` {id, chat, ids (at most [wantBatch])}
/// 4. friend -> me `restore_msgs_313` {id, chat, items, last} - 3/4 repeat
/// 5. voice notes: `restore_file_313` {id, msg, file}; the friend pushes the
///    file with the normal nearby file push, one at a time.
///
/// Rules (TODO_313 D2): locked packets only (`sealed == true`, never a
/// stranger key), friends only, only the chat of the two phones (groups:
/// both members, from the asker's join date), never deleted / hidden rows,
/// never the giver's file paths, no notification / unread / receipts on
/// the asker's side. An old app ignores the unknown types.
class ChatRestore313 {
  ChatRestore313({
    required this.transport,
    required this.sendLocked,
    required this.store,
    required this.sealCapable,
    required this.isNear,
    this.allowFile,
    this.pushFile,
    this.batteryOk,
    this.nameOf,
    DateTime Function()? clock,
    this.gap = const Duration(milliseconds: 300),
  }) : _clock = clock ?? DateTime.now;

  static ChatRestore313? instance;

  static const String askType = 'restore_ask_313';
  static const String idsType = 'restore_ids_313';
  static const String wantType = 'restore_want_313';
  static const String msgsType = 'restore_msgs_313';
  static const String fileType = 'restore_file_313';

  /// The chat key of the 1-to-1 chat (groups use their group id).
  static const String direct = 'd';

  static const String untilKey = 'restore313_until';
  static const String doneKey = 'restore313_done';

  /// Automatic asking runs this long after a fresh setup.
  static const Duration armedFor = Duration(days: 30);

  /// A friend who did not finish is asked again after this.
  static const Duration retryAfter = Duration(minutes: 10);

  /// No answer for this long = the session stops (asked again later).
  static const Duration stepTimeout = Duration(seconds: 60);

  /// One giving session per asker per this long.
  static const Duration giveGap = Duration(minutes: 10);

  /// A giving session answers "want" / "file" this long.
  static const Duration giveFor = Duration(minutes: 30);

  /// A voice file that does not arrive in this long is skipped.
  static const Duration fileTimeout = Duration(seconds: 90);

  static const int idsPerPage = 300;
  static const int wantBatch = 50;
  static const int maxBytes = 24 * 1024;
  static const int maxPerChat = 5000;
  static const int maxFilesPerSession = 200;

  /// Events only (opened locked messages + link events).
  final PeerTransportContract transport;

  /// Sends inside the friend's lock ONLY (false = not sent, never plain).
  final Future<bool> Function(String to, Map<String, dynamic> payload) sendLocked;
  final RestoreStore313 store;
  final bool Function(String peerId) sealCapable;
  final bool Function(String peerId) isNear;

  /// Lets the voice file of [fileId] in (the nearby file gate).
  final Future<void> Function(String fileId)? allowFile;

  /// Giver: pushes the voice file of a message in our chat to [to].
  final Future<bool> Function(String messageId, String fileId, String to)? pushFile;
  final bool Function()? batteryOk;
  final String Function(String peerId)? nameOf;
  final DateTime Function() _clock;
  final Duration gap;

  /// What the Settings row shows.
  final ValueNotifier<Restore313Status> status = ValueNotifier(const Restore313Status.idle());

  /// One per friend when messages came back: Home shows a short toast and
  /// reads the chat list again (static: Home can open before the services).
  static final ValueNotifier<Restore313Done?> lastDone = ValueNotifier(null);

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _watch;
  bool _started = false;
  int _seq = 0;

  // ------------------------------------------------------------ asker state
  final List<String> _queue = <String>[];
  _Ask? _ask;
  final Map<String, DateTime> _lastTry = <String, DateTime>{};
  Map<String, Set<String>> _done = <String, Set<String>>{};
  int _armedUntil = 0;
  final List<_File> _files = <_File>[];
  _File? _fileNow;

  // ------------------------------------------------------------ giver state
  final Map<String, _Give> _gives = <String, _Give>{};

  bool get armed => _armedUntil > _clock().millisecondsSinceEpoch;

  @visibleForTesting
  bool get busy => _ask != null;

  /// Called once at app start, right after the database opens and BEFORE
  /// any sync / sign-in can save messages: the first time the 313 code runs
  /// on a phone with NO messages at all (a fresh install) automatic asking
  /// is armed for [armedFor]. A normal update (messages there) is not.
  /// Returns true when it armed now.
  static Future<bool> armAtLaunch(RestoreStore313 store, {DateTime? now}) async {
    final saved = await store.readSetting(untilKey);
    if (saved != null && saved.isNotEmpty) return false;
    final empty = !await store.hasAnyMessage();
    final until = empty ? (now ?? DateTime.now()).add(armedFor).millisecondsSinceEpoch : 0;
    await store.writeSetting(untilKey, '$until');
    if (empty) await store.writeSetting(doneKey, '{}');
    AppLogger.info('RESTORE313_ARM', detail: 'armed=${empty ? 'y' : 'n'}');
    return empty;
  }

  Future<void> start() async {
    _armedUntil = int.tryParse(await store.readSetting(untilKey) ?? '') ?? 0;
    _done = _readDone(await store.readSetting(doneKey));
    if (_started) return;
    _started = true;
    _sub = transport.events.listen(onEvent, onError: (Object _) {});
    _watch = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  Future<void> stop() async {
    _started = false;
    await _sub?.cancel();
    _sub = null;
    _watch?.cancel();
    _watch = null;
  }

  static Map<String, Set<String>> _readDone(String? raw) {
    try {
      final d = jsonDecode(raw ?? '{}');
      if (d is! Map) return <String, Set<String>>{};
      return {
        for (final e in d.entries)
          e.key.toString(): {if (e.value is List) for (final c in e.value as List) c.toString()},
      };
    } catch (_) {
      return <String, Set<String>>{};
    }
  }

  Future<void> _saveDone() =>
      store.writeSetting(doneKey, jsonEncode({for (final e in _done.entries) e.key: e.value.toList()..sort()}));

  // ------------------------------------------------------------- triggers

  /// Settings button: ask every friend who is near now. Returns how many
  /// friends were asked (0 = nobody near).
  Future<int> askNearbyFriends() async {
    final friends = await store.friendIds();
    var n = 0;
    for (final id in friends.toList()..sort()) {
      if (id == store.selfId || !isNear(id) || !sealCapable(id)) continue;
      if (_enqueue(id, manual: true)) n++;
    }
    if (n == 0 && _ask == null) {
      status.value = const Restore313Status(phase: Restore313Status.noneNear);
    } else if (_ask == null) {
      unawaited(_next());
    }
    return n;
  }

  bool _enqueue(String peer, {bool manual = false}) {
    if (peer.isEmpty || _queue.contains(peer) || _ask?.peer == peer) return false;
    if (!manual) {
      final last = _lastTry[peer];
      if (last != null && _clock().difference(last) < retryAfter) return false;
    }
    _queue.add(peer);
    if (status.value.phase == Restore313Status.idleP || status.value.phase == Restore313Status.noneNear) {
      status.value = const Restore313Status(phase: Restore313Status.waiting);
    }
    return true;
  }

  Future<void> _auto(String peer) async {
    if (!armed || peer.isEmpty || peer == store.selfId) return;
    if (_queue.contains(peer) || _ask?.peer == peer) return;
    final last = _lastTry[peer];
    if (last != null && _clock().difference(last) < retryAfter) return;
    if (!sealCapable(peer)) return;
    if (!(batteryOk?.call() ?? true)) return;
    final friends = await store.friendIds();
    if (!friends.contains(peer)) return;
    final chats = await _chatsWith(peer);
    final done = _done[peer] ?? const <String>{};
    if (chats.every(done.contains)) {
      // Nothing left with this friend: looked at again in 10 min (a new
      // shared group), not on every link event.
      _lastTry[peer] = _clock();
      return;
    }
    if (_enqueue(peer) && _ask == null) await _next();
  }

  Future<List<String>> _chatsWith(String peer) async =>
      // A copy first: the store may hand back a list that can't be sorted.
      [direct, ...([...await store.groupsWith(peer)]..sort())];

  // ------------------------------------------------------------- events

  /// Transport events (opened locked messages + link events).
  void onEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    switch (type) {
      case 'peer_connected':
      case 'peer_discovered':
      case 'route_recovered':
      case 'relay_connected':
        final peer = event['peer_id']?.toString() ?? '';
        unawaited(_auto(peer).catchError((Object e) {
          AppLogger.warning('RESTORE313_AUTO_FAILED', detail: '$e');
        }));
        return;
      case 'file_received':
        final f = _fileNow;
        if (f != null && event['file_id']?.toString() == f.fileId) {
          _fileNow = null;
          unawaited(_nextFile());
        }
        return;
      case 'message':
        break;
      default:
        return;
    }
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains('restore_')) return;
    if (event['sealed'] != true) {
      AppLogger.warning('RESTORE313_DROPPED', detail: 'why=not_sealed');
      return; // locked only
    }
    Map<String, dynamic> data;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return;
      data = Map<String, dynamic>.from(d);
    } catch (_) {
      return;
    }
    final t = data['type']?.toString() ?? '';
    if (!t.startsWith('restore_') || !t.endsWith('_313')) return;
    // A stranger key (not my friend's own saved key) never counts.
    if ((data['_locked_spk']?.toString() ?? '').isNotEmpty) {
      AppLogger.warning('RESTORE313_DROPPED', detail: 'why=stranger');
      return;
    }
    final from = data['sender_id']?.toString() ?? '';
    if (from.isEmpty || from == store.selfId) return;
    // One packet at a time, in the order they came.
    _chain = _chain.then((_) => handle(t, from, data)).catchError((Object e) {
      AppLogger.warning('RESTORE313_FAILED', detail: 'type=$t $e');
    });
  }

  Future<void> _chain = Future<void>.value();

  /// One opened packet ([from] = the proven sender).
  @visibleForTesting
  Future<void> handle(String type, String from, Map<String, dynamic> data) async {
    switch (type) {
      case askType:
        await _onAsk(from, data);
      case wantType:
        await _onWant(from, data);
      case fileType:
        await _onFile(from, data);
      case idsType:
        await _onIds(from, data);
      case msgsType:
        await _onMsgs(from, data);
    }
  }

  Future<bool> _send(String to, Map<String, dynamic> payload) async {
    // Locked only: a phone this one can't lock for gets nothing.
    if (!sealCapable(to)) {
      AppLogger.warning('RESTORE313_NOT_SENT', detail: 'why=not_sealed');
      return false;
    }
    try {
      final ok = await sendLocked(to, payload);
      if (!ok) AppLogger.warning('RESTORE313_NOT_SENT', detail: 'why=no_lock');
      return ok;
    } catch (e) {
      AppLogger.warning('RESTORE313_SEND_FAILED', detail: '$e');
      return false;
    }
  }

  Future<void> _pause() async {
    if (gap > Duration.zero) await Future<void>.delayed(gap);
  }

  // ================================================================ GIVER

  Future<void> _onAsk(String asker, Map<String, dynamic> data) async {
    final id = data['id']?.toString() ?? '';
    if (id.isEmpty) return;
    if (!(await store.friendIds()).contains(asker)) {
      AppLogger.warning('RESTORE313_REFUSED', detail: 'why=not_friend');
      return;
    }
    if (!(batteryOk?.call() ?? true)) {
      AppLogger.info('RESTORE313_REFUSED', detail: 'why=battery');
      return;
    }
    final now = _clock();
    final old = _gives[asker];
    if (old != null && old.id != id && now.difference(old.at) < giveGap) {
      AppLogger.info('RESTORE313_REFUSED', detail: 'why=too_soon');
      return;
    }
    if (old != null && old.id == id) return; // the same ask twice
    final asked = [
      if (data['chats'] is List)
        for (final c in (data['chats'] as List).take(200)) c.toString(),
    ];
    final self = store.selfId ?? '';
    final shared = (await store.groupsWith(asker)).toSet();
    final give = _Give(asker, id, now);
    _gives[asker] = give;
    for (final chat in asked) {
      List<Map<String, dynamic>> rows;
      if (chat == direct) {
        rows = [
          for (final m in await store.directChat(asker))
            if (_ends(m, self, asker)) m,
        ];
      } else if (shared.contains(chat)) {
        final since = DateTime.tryParse(await store.joinedAt(chat, asker) ?? '');
        rows = [
          for (final m in await store.groupChat(chat))
            if (m['group_id']?.toString() == chat &&
                (since == null || !(DateTime.tryParse(m['created_at']?.toString() ?? '')?.isBefore(since) ?? true)))
              m,
        ];
      } else {
        rows = const [];
      }
      if (rows.length > maxPerChat) rows = rows.sublist(rows.length - maxPerChat);
      final byId = <String, Map<String, dynamic>>{
        for (final m in rows)
          if ((m['id']?.toString() ?? '').isNotEmpty) m['id'].toString(): _clean(m),
      };
      give.chats[chat] = byId;
      final ids = byId.keys.toList();
      final parts = ids.isEmpty ? 1 : (ids.length + idsPerPage - 1) ~/ idsPerPage;
      for (var p = 0; p < parts; p++) {
        final page = ids.skip(p * idsPerPage).take(idsPerPage).toList();
        if (!await _send(asker, {'type': idsType, 'id': id, 'chat': chat, 'part': p, 'parts': parts, 'ids': page})) {
          return;
        }
        await _pause();
      }
    }
    AppLogger.info('RESTORE313_GIVE', detail: 'chats=${asked.length} '
        'n=${give.chats.values.fold<int>(0, (a, b) => a + b.length)}');
  }

  static bool _ends(Map<String, dynamic> m, String a, String b) {
    final s = m['sender_id']?.toString() ?? '';
    final r = m['recipient_id']?.toString() ?? '';
    return a.isNotEmpty && b.isNotEmpty && a != b && ((s == a && r == b) || (s == b && r == a));
  }

  /// The wire copy: never this phone's file paths, only the known fields.
  static Map<String, dynamic> _clean(Map<String, dynamic> m) {
    const keep = ['id', 'sender_id', 'recipient_id', 'group_id', 'body', 'created_at', 'status', 'delivered_at', 'server_seq'];
    return <String, dynamic>{
      for (final k in keep)
        if (m[k] != null) k: m[k],
      'attachments': [
        if (m['attachments'] is List)
          for (final a in m['attachments'] as List)
            if (a is Map) Map<String, dynamic>.from(a)..remove('local_path'),
      ],
    };
  }

  _Give? _session(String asker, Map<String, dynamic> data) {
    final g = _gives[asker];
    if (g == null || g.id != (data['id']?.toString() ?? '')) return null;
    if (_clock().difference(g.at) > giveFor) return null;
    return g;
  }

  Future<void> _onWant(String asker, Map<String, dynamic> data) async {
    final g = _session(asker, data);
    if (g == null) return;
    final chat = data['chat']?.toString() ?? '';
    final rows = g.chats[chat];
    if (rows == null) return;
    final ids = [
      if (data['ids'] is List)
        for (final e in (data['ids'] as List).take(wantBatch)) e.toString(),
    ];
    var page = <Map<String, dynamic>>[];
    var bytes = 0;
    final items = [for (final i in ids) if (rows[i] != null) rows[i]!];
    for (var i = 0; i < items.length; i++) {
      final size = utf8.encode(jsonEncode(items[i])).length;
      if (page.isNotEmpty && bytes + size > maxBytes) {
        await _send(asker, {'type': msgsType, 'id': g.id, 'chat': chat, 'items': page, 'last': false});
        await _pause();
        page = <Map<String, dynamic>>[];
        bytes = 0;
      }
      page.add(items[i]);
      bytes += size;
    }
    await _send(asker, {'type': msgsType, 'id': g.id, 'chat': chat, 'items': page, 'last': true});
  }

  Future<void> _onFile(String asker, Map<String, dynamic> data) async {
    final g = _session(asker, data);
    final push = pushFile;
    if (g == null || push == null) return;
    if (g.files >= maxFilesPerSession) return;
    final msg = data['msg']?.toString() ?? '';
    final file = data['file']?.toString() ?? '';
    final row = g.chats[direct]?[msg];
    if (row == null) return; // only a message of our 1-to-1 chat I gave
    final ok = [
      for (final a in row['attachments'] as List? ?? const [])
        if (a is Map && a['id']?.toString() == file && (a['content_type']?.toString() ?? '').startsWith('audio/')) a,
    ].isNotEmpty;
    if (!ok) return;
    g.files++;
    final pushed = await push(msg, file, asker);
    AppLogger.info('RESTORE313_FILE_GIVEN', detail: 'ok=$pushed');
  }

  // ================================================================ ASKER

  Future<void> _next() async {
    if (_ask != null) return;
    while (_queue.isNotEmpty) {
      final peer = _queue.removeAt(0);
      if (!sealCapable(peer)) continue;
      final chats = await _chatsWith(peer);
      final id = '${_clock().millisecondsSinceEpoch}-${_seq++}';
      final a = _Ask(peer, id, chats, _clock());
      _ask = a;
      _lastTry[peer] = _clock();
      _lastId[peer] = id;
      status.value = Restore313Status(phase: Restore313Status.getting, peer: _name(peer));
      if (await _send(peer, {'type': askType, 'id': id, 'chats': chats})) {
        AppLogger.info('RESTORE313_ASK', detail: 'chats=${chats.length}');
        return;
      }
      _ask = null;
    }
    if (status.value.phase == Restore313Status.waiting || status.value.phase == Restore313Status.getting) {
      status.value = const Restore313Status.idle();
    }
  }

  String _name(String peer) => nameOf?.call(peer) ?? '';

  void _tick() {
    final a = _ask;
    if (a != null && _clock().difference(a.last) > stepTimeout) {
      AppLogger.info('RESTORE313_TIMEOUT', detail: 'saved=${a.saved}');
      unawaited(_finish(a, complete: false));
    }
    final f = _fileNow;
    if (f != null && _clock().difference(f.at) > fileTimeout) {
      _fileNow = null;
      unawaited(_nextFile());
    }
  }

  _Ask? _mine(String from, Map<String, dynamic> data) {
    final a = _ask;
    if (a == null || a.peer != from || a.id != (data['id']?.toString() ?? '')) return null;
    return a;
  }

  Future<void> _onIds(String from, Map<String, dynamic> data) async {
    final a = _mine(from, data);
    if (a == null) return;
    final chat = data['chat']?.toString() ?? '';
    if (!a.chats.contains(chat)) return;
    final pull = a.pulls.putIfAbsent(chat, _Pull.new);
    if (pull.ready) return;
    a.last = _clock();
    final parts = int.tryParse(data['parts']?.toString() ?? '') ?? 0;
    final part = int.tryParse(data['part']?.toString() ?? '') ?? -1;
    if (parts < 1 || parts > maxPerChat ~/ idsPerPage + 2 || part < 0 || part >= parts) return;
    pull.parts = parts;
    pull.pages[part] = [
      if (data['ids'] is List)
        for (final e in (data['ids'] as List).take(idsPerPage)) e.toString(),
    ];
    if (pull.pages.length < parts) return;
    pull.ready = true;
    final all = [for (var p = 0; p < parts; p++) ...?pull.pages[p]];
    for (final id in all) {
      if (id.isEmpty) continue;
      if (pull.missingSet.contains(id)) continue;
      final have = chat == direct ? await store.hasDirect(id) : await store.hasGroup(id);
      if (!have) {
        pull.missing.add(id);
        pull.missingSet.add(id);
      }
    }
    a.total += pull.missing.length;
    _show(a);
    if (pull.missing.isEmpty) {
      pull.done = true;
      await _maybeFinish(a);
      return;
    }
    await _want(a, chat, pull);
  }

  Future<void> _want(_Ask a, String chat, _Pull pull) async {
    final batch = pull.missing.skip(pull.next).take(wantBatch).toList();
    pull.next += batch.length;
    await _send(a.peer, {'type': wantType, 'id': a.id, 'chat': chat, 'ids': batch});
  }

  Future<void> _onMsgs(String from, Map<String, dynamic> data) async {
    final a = _mine(from, data);
    if (a == null) return;
    final chat = data['chat']?.toString() ?? '';
    final pull = a.pulls[chat];
    if (pull == null || pull.done) return;
    a.last = _clock();
    final self = store.selfId ?? '';
    var savedHere = 0;
    for (final raw in (data['items'] as List? ?? const []).take(wantBatch)) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final id = m['id']?.toString() ?? '';
      // Only what I asked for, once.
      if (!pull.missingSet.contains(id) || !pull.got.add(id)) continue;
      final saved = chat == direct ? await _saveDirect(m, self, a.peer) : await _saveGroup(m, chat, self);
      if (saved) a.saved++;
      if (saved) savedHere++;
      a.got++;
    }
    // A group got older messages back: its chat list / screen reads again.
    if (savedHere > 0 && chat != direct) GroupChangeHub.instance.changed(chat);
    _show(a);
    if (data['last'] != true) return;
    if (pull.next < pull.missing.length) {
      await _want(a, chat, pull);
      return;
    }
    // Lost on the way: asked again once.
    final left = [for (final id in pull.missing) if (!pull.got.contains(id)) id];
    if (left.isNotEmpty && !pull.retried) {
      pull
        ..retried = true
        ..missing.addAll(left);
      await _want(a, chat, pull);
      return;
    }
    pull.done = true;
    await _maybeFinish(a);
  }

  Future<bool> _saveDirect(Map<String, dynamic> m, String self, String peer) async {
    if (!_ends(m, self, peer)) {
      AppLogger.warning('RESTORE313_ITEM_DROPPED', detail: 'why=ends');
      return false;
    }
    if (m['body'] is! String || DateTime.tryParse(m['created_at']?.toString() ?? '') == null) return false;
    final mine = m['sender_id'] == self;
    final st = m['status']?.toString() ?? '';
    // Their phone has it, so it reached them. Never "sending" again here.
    final status = mine && (st == 'read' || st == 'seen' || st == 'delivered') ? st : 'delivered';
    final wire = _clean(m)
      ..remove('group_id')
      ..['status'] = status;
    final isNew = await store.saveDirect(wire);
    if (isNew) {
      for (final att in wire['attachments'] as List) {
        final at = Map<String, dynamic>.from(att as Map);
        if ((at['content_type']?.toString() ?? '').startsWith('audio/') && (at['id']?.toString() ?? '').isNotEmpty) {
          _files.add(_File(peer, m['id'].toString(), at['id'].toString()));
        }
      }
    }
    return isNew;
  }

  Future<bool> _saveGroup(Map<String, dynamic> m, String chat, String self) async {
    if (m['group_id']?.toString() != chat) return false;
    if ((m['sender_id']?.toString() ?? '').isEmpty || m['body'] is! String) return false;
    if (DateTime.tryParse(m['created_at']?.toString() ?? '') == null) return false;
    final wire = _clean(m)
      ..remove('recipient_id')
      ..remove('status')
      ..remove('delivered_at');
    return store.saveGroup(wire, mine: m['sender_id'] == self);
  }

  void _show(_Ask a) {
    status.value = Restore313Status(phase: Restore313Status.getting, peer: _name(a.peer), got: a.got, total: a.total);
  }

  Future<void> _maybeFinish(_Ask a) async {
    if (a.chats.every((c) => a.pulls[c]?.done ?? false)) await _finish(a, complete: true);
  }

  Future<void> _finish(_Ask a, {required bool complete}) async {
    if (_ask != a) return;
    _ask = null;
    // Asked again (timeout) only 10 min after the LAST packet: the friend's
    // 10-min session gap has passed by then.
    _lastTry[a.peer] = _clock();
    if (complete) {
      (_done[a.peer] ??= <String>{}).addAll(a.chats);
      await _saveDone();
    }
    AppLogger.info('RESTORE313_DONE', detail: 'complete=$complete saved=${a.saved} total=${a.total}');
    if (a.saved > 0) lastDone.value = Restore313Done(_name(a.peer), a.saved, _seq++);
    status.value = Restore313Status(phase: Restore313Status.finished, peer: _name(a.peer), got: a.got, total: a.total);
    if (_fileNow == null) unawaited(_nextFile());
    await _next();
  }

  Future<void> _nextFile() async {
    while (_fileNow == null && _files.isNotEmpty) {
      final f = _files.removeAt(0);
      if (!sealCapable(f.peer)) continue;
      // The friend's giving session must still be open (30 min): the file
      // ask carries the id of the last session with that friend.
      final id = _lastId[f.peer] ?? '';
      if (id.isEmpty) continue;
      try {
        await allowFile?.call(f.fileId);
      } catch (_) {}
      f.at = _clock();
      _fileNow = f;
      if (!await _send(f.peer, {'type': fileType, 'id': id, 'msg': f.messageId, 'file': f.fileId})) {
        _fileNow = null;
      }
    }
  }

  /// The last session id per friend (a voice file ask carries it).
  final Map<String, String> _lastId = <String, String>{};
}

/// What the app needs from the phone's storage (tests use a fake).
abstract interface class RestoreStore313 {
  String? get selfId;

  /// Friends: contacts, not removed, not blocked.
  Future<Set<String>> friendIds();

  /// Any 1-to-1 or group message on this phone.
  Future<bool> hasAnyMessage();

  /// This phone's 1-to-1 chat with [peer], oldest first, wire maps
  /// (`Message.toJson`). Deleted / cleared rows are not in it.
  Future<List<Map<String, dynamic>>> directChat(String peer);
  Future<bool> hasDirect(String id);

  /// Saves a restored 1-to-1 message (read, no notification). True = new.
  Future<bool> saveDirect(Map<String, dynamic> wire);

  /// Active groups where this phone AND [peer] are members.
  Future<List<String>> groupsWith(String peer);
  Future<List<Map<String, dynamic>>> groupChat(String groupId);
  Future<String?> joinedAt(String groupId, String member);
  Future<bool> hasGroup(String id);

  /// Saves a restored group message (read). True = new.
  Future<bool> saveGroup(Map<String, dynamic> wire, {required bool mine});

  Future<String?> readSetting(String key);
  Future<void> writeSetting(String key, String value);
}

/// The Settings row.
@immutable
class Restore313Status {
  const Restore313Status({required this.phase, this.peer = '', this.got = 0, this.total = 0});
  const Restore313Status.idle() : this(phase: idleP);

  static const String idleP = 'idle';
  static const String waiting = 'waiting';
  static const String getting = 'getting';
  static const String finished = 'finished';
  static const String noneNear = 'none_near';

  final String phase;
  final String peer;
  final int got;
  final int total;

  @override
  bool operator ==(Object other) =>
      other is Restore313Status && other.phase == phase && other.peer == peer && other.got == got && other.total == total;

  @override
  int get hashCode => Object.hash(phase, peer, got, total);
}

@immutable
class Restore313Done {
  const Restore313Done(this.peer, this.count, this.seq);
  final String peer;
  final int count;
  final int seq;

  @override
  bool operator ==(Object other) => other is Restore313Done && other.seq == seq;

  @override
  int get hashCode => seq.hashCode;
}

class _Ask {
  _Ask(this.peer, this.id, this.chats, this.last);
  final String peer;
  final String id;
  final List<String> chats;
  DateTime last;
  final Map<String, _Pull> pulls = <String, _Pull>{};
  int total = 0;
  int got = 0;
  int saved = 0;
}

class _Pull {
  int parts = 0;
  final Map<int, List<String>> pages = <int, List<String>>{};
  final List<String> missing = <String>[];
  final Set<String> missingSet = <String>{};
  final Set<String> got = <String>{};
  int next = 0;
  bool retried = false;
  bool ready = false;
  bool done = false;
}

class _Give {
  _Give(this.asker, this.id, this.at);
  final String asker;
  final String id;
  final DateTime at;
  final Map<String, Map<String, Map<String, dynamic>>> chats = <String, Map<String, Map<String, dynamic>>>{};
  int files = 0;
}

class _File {
  _File(this.peer, this.messageId, this.fileId);
  final String peer;
  final String messageId;
  final String fileId;
  DateTime at = DateTime.fromMillisecondsSinceEpoch(0);
}
