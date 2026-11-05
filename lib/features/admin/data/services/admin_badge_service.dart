import 'dart:async';
import 'dart:convert';

import 'package:locallink/core/services/server_reach.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart'
    show ed25519Verify;

/// Bundle 214: `GET /api/v1/admin-badges` (device sign-in).
abstract class AdminBadgeServer {
  Future<List<SignedBlob>> fetch();
}

/// Bundle 214: the crown cards for everyone, with no internet.
///
/// - Server-signed cards (no secrets) travel as plain one-step frames
///   between linked phones, like the 212 block records and the 213 rule.
/// - `admin_badge_digest` when a phone links and every 60 s (max once per
///   phone per 30 s); the phone with newer cards pushes them
///   (`admin_badge_records`, max 20 per frame); each phone passes new
///   cards one step on.
/// - Server: at start (+8 s), on connect, on the `admin_badge_changed`
///   push and every 10 min. Newest wins everywhere (seq, time, id).
class AdminBadgeService {
  AdminBadgeService({
    required this.read,
    required this.write,
    required this.selfDeviceId,
    required this.selfUserId,
    required this.send,
    required this.events,
    required this.linkedPeers,
    required this.serverKey,
    this.server,
    this.deviceOwners,
    Future<bool> Function(String body, String sig, String key)? verify,
    DateTime Function()? clock,
    AdminBadgeBook? book,
  })  : verify = verify ?? ed25519Verify,
        _clock = clock ?? DateTime.now,
        book = book ?? AdminBadgeBook.instance;

  static const String cardsKey = 'admin_badges_v1';

  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final String Function() selfDeviceId;
  final String Function() selfUserId;
  final Future<void> Function(String peerId, Map<String, dynamic> payload) send;
  final Stream<Map<String, dynamic>> events;
  final Future<List<String>> Function() linkedPeers;
  final String? Function() serverKey;
  final AdminBadgeServer? server;

  /// Phones of these accounts from saved profiles (phone id → account id).
  final Future<Map<String, String>> Function(Set<String> userIds)? deviceOwners;
  final Future<bool> Function(String body, String sig, String key) verify;
  final DateTime Function() _clock;
  final AdminBadgeBook book;

  static AdminBadgeService? instance;

  final Map<String, AdminBadge> _cards = <String, AdminBadge>{};
  final Map<String, DateTime> _digestSentAt = <String, DateTime>{};
  final Map<String, DateTime> _digestTakenAt = <String, DateTime>{};
  bool _loaded = false;
  bool _started = false;
  bool _syncBusy = false;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _digestTimer;
  Timer? _serverTimer;

  Iterable<AdminBadge> get cards => _cards.values;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await read(cardsKey);
      if (raw != null && raw.isNotEmpty) {
        for (final row in (jsonDecode(raw) as List)) {
          final blob = SignedBlob.fromJson(row);
          final b = blob == null ? null : AdminBadge.fromBlob(blob);
          if (b != null && AdminBadges.newer(b, _cards[b.userId])) {
            _cards[b.userId] = b;
          }
        }
      }
    } catch (_) {}
    book.setSelf(userId: selfUserId(), deviceId: selfDeviceId());
    book.replaceAll(_cards.values);
    unawaited(refreshDevices().catchError((Object _) {}));
  }

  /// Starts listening and the timers (main app and the no-screen engine).
  Future<void> start() async {
    await load();
    if (_started) return;
    _started = true;
    instance = this;
    _sub = events.listen((e) => unawaited(handleEvent(e).catchError((_) {})));
    _digestTimer = Timer.periodic(AdminBadges.digestEvery, (_) {
      unawaited(sendDigests().catchError((_) {}));
      unawaited(refreshDevices().catchError((Object _) {}));
    });
    _serverTimer = Timer.periodic(AdminBadges.serverEvery,
        (_) => unawaited(syncWithServer().catchError((_) {})));
    unawaited(Future<void>.delayed(const Duration(seconds: 8), () async {
      if (!_started) return;
      await syncWithServer();
      await sendDigests();
    }).catchError((_) {}));
  }

  Future<void> dispose() async {
    _digestTimer?.cancel();
    _serverTimer?.cancel();
    await _sub?.cancel();
    _started = false;
    if (identical(instance, this)) instance = null;
  }

  /// The account on this phone changed (sign in as someone else).
  void selfChanged() =>
      book.setSelf(userId: selfUserId(), deviceId: selfDeviceId());

  // -------------------------------------------------------------- receiving

  /// Checks and keeps [blob] when it is a real, newer card.
  Future<bool> offer(SignedBlob blob, {required String from}) async {
    await load();
    final badge = AdminBadge.fromBlob(blob);
    if (badge == null) {
      AppLogger.warning('ADMIN_BADGE_REJECT', detail: 'reason=bad_card from=${_tail(from)}');
      return false;
    }
    final reason = await AdminBadges.check(badge, serverKey: serverKey(), verify: verify);
    if (reason != null) {
      AppLogger.warning('ADMIN_BADGE_REJECT', detail: 'reason=$reason from=${_tail(from)}');
      return false;
    }
    if (!AdminBadges.newer(badge, _cards[badge.userId])) return false;
    _cards[badge.userId] = badge;
    _trim();
    await _save();
    book.put(badge);
    AppLogger.info('ADMIN_BADGE_TAKEN',
        detail: 'user=${_tail(badge.userId)} on=${badge.on} role=${badge.role} '
            'seq=${badge.seq} from=${_tail(from)}');
    unawaited(refreshDevices().catchError((Object _) {}));
    // Passed on one step (never back to the phone it came from).
    await _spread([badge], except: from);
    return true;
  }

  void _trim() {
    if (_cards.length <= AdminBadges.maxCards) return;
    // Removed-admin cards go first, oldest first.
    final list = _cards.values.toList()
      ..sort((a, b) {
        if (a.on != b.on) return a.on ? 1 : -1;
        return a.at.compareTo(b.at);
      });
    for (final b in list.take(_cards.length - AdminBadges.maxCards)) {
      _cards.remove(b.userId);
    }
    book.replaceAll(_cards.values);
  }

  Future<void> _save() => write(
      cardsKey, jsonEncode([for (final b in _cards.values) b.blob.toJson()]));

  Future<void> refreshDevices() async {
    final hook = deviceOwners;
    if (hook == null) return;
    final users = book.adminUserIds;
    if (users.isEmpty) {
      book.setDevices(const <String, String>{});
      return;
    }
    book.setDevices(await hook(users));
  }

  /// One event from the transport.
  Future<void> handleEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();
    if (type == 'peer_connected') {
      final peer = event['peer_id']?.toString() ?? '';
      if (peer.isNotEmpty) await sendDigestTo(peer);
      return;
    }
    if (type != 'message') return;
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains('admin_badge_')) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      msg = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final kind = msg['type']?.toString();
    if (!AdminBadges.isFrameType(kind)) return;
    // The link layer's sender, never a field they wrote.
    final from = event['sender_id']?.toString() ?? '';
    if (from.isEmpty || from == selfDeviceId()) return;
    await load();
    if (kind == AdminBadges.digestType) {
      await _onDigest(from, msg);
    } else {
      for (final x in (msg['records'] as List? ?? const []).take(AdminBadges.maxPerFrame)) {
        final blob = SignedBlob.fromJson(x);
        if (blob != null) await offer(blob, from: from);
      }
    }
  }

  Map<String, dynamic> digest() {
    final items = [
      for (final b in _cards.values) {'u': b.userId, 's': b.seq, 'i': b.id},
    ]..sort((a, b) => '${a['u']}'.compareTo('${b['u']}'));
    return {
      'type': AdminBadges.digestType,
      'h': _hash(items),
      'items': items.take(AdminBadges.maxCards).toList(),
    };
  }

  String _hash(List<Map<String, Object>> items) {
    final text = items.map((e) => '${e['u']}:${e['s']}:${e['i']}').join(',');
    var h = 0x811c9dc5;
    for (final c in utf8.encode(text)) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  Future<void> sendDigests() async {
    await load();
    for (final p in await _linked()) {
      await sendDigestTo(p);
    }
  }

  Future<void> sendDigestTo(String peer, {bool force = false}) async {
    await load();
    if (peer.isEmpty || peer == selfDeviceId()) return;
    final now = _clock();
    final last = _digestSentAt[peer];
    if (!force && last != null && now.difference(last) < AdminBadges.digestGap) return;
    _digestSentAt[peer] = now;
    if (_digestSentAt.length > 300) _digestSentAt.remove(_digestSentAt.keys.first);
    try {
      await send(peer, digest());
    } catch (_) {}
  }

  Future<void> _onDigest(String from, Map<String, dynamic> msg) async {
    final now = _clock();
    final last = _digestTakenAt[from];
    if (last != null && now.difference(last) < AdminBadges.digestGap) return;
    _digestTakenAt[from] = now;
    if (_digestTakenAt.length > 300) _digestTakenAt.remove(_digestTakenAt.keys.first);
    final mine = digest();
    if (mine['h'] == msg['h']) return;
    final theirs = <String, (int, String)>{};
    for (final it in (msg['items'] as List? ?? const []).whereType<Map>()) {
      final u = it['u']?.toString() ?? '';
      final s = it['s'] is int ? it['s'] as int : int.tryParse('${it['s']}') ?? 0;
      if (u.isNotEmpty) theirs[u] = (s, it['i']?.toString() ?? '');
    }
    final missing = [
      for (final b in _cards.values)
        if (_theyNeed(b, theirs[b.userId])) b,
    ];
    if (missing.isNotEmpty) await _sendCards(from, missing);
    // They have something newer: my digest makes them push it.
    final theyHaveNewer = theirs.entries.any((e) {
      final m = _cards[e.key];
      return m == null || e.value.$1 > m.seq || (e.value.$1 == m.seq && e.value.$2 != m.id);
    });
    if (theyHaveNewer) await sendDigestTo(from, force: true);
  }

  bool _theyNeed(AdminBadge b, (int, String)? theirs) {
    if (theirs == null) return true;
    if (b.seq != theirs.$1) return b.seq > theirs.$1;
    if (b.id == theirs.$2) return false;
    return b.id.compareTo(theirs.$2) > 0;
  }

  Future<void> _sendCards(String peer, List<AdminBadge> cards) async {
    for (var i = 0; i < cards.length; i += AdminBadges.maxPerFrame) {
      final part = cards.skip(i).take(AdminBadges.maxPerFrame);
      try {
        await send(peer, {
          'type': AdminBadges.recordsType,
          'records': [for (final b in part) b.blob.toJson()],
        });
      } catch (_) {}
    }
  }

  Future<void> _spread(List<AdminBadge> cards, {required String except}) async {
    for (final p in await _linked()) {
      if (p == except || p == selfDeviceId()) continue;
      await _sendCards(p, cards);
    }
    AppLogger.info('ADMIN_BADGE_SPREAD', detail: 'n=${cards.length}');
  }

  Future<List<String>> _linked() async {
    try {
      return await linkedPeers();
    } catch (_) {
      return const <String>[];
    }
  }

  // ----------------------------------------------------------------- server

  Future<void> syncWithServer() async {
    final s = server;
    if (s == null || _syncBusy) return;
    // Bundle 223 (L, N): no server address / no network -> skip quietly.
    if (ServerReach.instance.shouldSkip('admin_badges')) return;
    _syncBusy = true;
    try {
      await load();
      final list = await s.fetch();
      var fresh = 0;
      for (final blob in list) {
        if (await offer(blob, from: 'server')) fresh++;
      }
      AppLogger.info('ADMIN_BADGE_SERVER_SYNC', detail: 'got=${list.length} new=$fresh');
    } catch (e) {
      ServerReach.instance.noteFailure(e); // Bundle 223 (L)
      AppLogger.warning('ADMIN_BADGE_SERVER_SYNC', detail: 'failed error=$e');
    } finally {
      _syncBusy = false;
    }
  }

  static String _tail(String s) => s.length <= 6 ? s : s.substring(s.length - 6);
}
