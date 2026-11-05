import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';

/// Bundle 212: the server calls the service needs (see
/// `admin_block_server.dart` for the real one).
abstract class AdminBlockServer {
  /// `GET /api/v1/trust` → the server signing key.
  Future<String> trustKey();

  /// `POST /api/v1/admin/offline-cert` with the admin sign-in.
  Future<SignedBlob> offlineCert(
      {required String adminToken,
      required String deviceId,
      required String signingKey});

  /// `POST /api/v1/admin-blocks/sync` → all current records + ended notes.
  /// Throws [AdminBlockUnauthorized] when this phone's account can't use
  /// device calls (for example it is blocked).
  Future<({List<SignedBlob> records, List<SignedBlob> ended})> sync(
      List<SignedBlob> records);

  /// `POST /api/v1/admin-blocks/mine` → this account's own record.
  Future<SignedBlob?> mine();
}

class AdminBlockUnauthorized implements Exception {
  const AdminBlockUnauthorized();
}

/// The admin sign-in the service needs to fetch the offline key.
typedef AdminSignIn = ({String token, String role, String username});

/// What the admin screens show for one record.
class AdminBlockEntry {
  final AdminBlockRecord record;
  final String source; // me | nearby | server
  final bool serverDone;
  final int reached;
  final String receivedAt;

  const AdminBlockEntry({
    required this.record,
    required this.source,
    required this.serverDone,
    required this.reached,
    required this.receivedAt,
  });
}

/// Panel status line (A6).
enum AdminBlockReadiness { ready, needServer, notOwner, noTrust }

/// Bundle 212: admin block / unblock of any user, with no internet.
///
/// - Records are signed (admin phone key + server-signed cert) and not
///   secret, so they travel as plain one-step frames between linked phones
///   (local Wi-Fi, Wi-Fi Direct, mesh links; also strangers' and blocked
///   phones' relay links) and each phone passes a new record on one step.
/// - Digest every 60 s and when a phone links: the other phone pushes what
///   this one is missing (max 1 digest per phone per 30 s).
/// - "Got it" notes go back hop to hop so the admin phone counts phones.
/// - Server sync on connect and every 10 min; newest wins everywhere.
class AdminBlockService {
  AdminBlockService({
    required this.read,
    required this.write,
    required this.selfDeviceId,
    required this.selfUserId,
    required this.signingKey,
    required this.sign,
    required this.send,
    required this.events,
    required this.linkedPeers,
    this.server,
    this.adminSignIn,
    this.onBlockedChanged,
    this.onSelfChanged,
    this.onServerSaved,
    Future<bool> Function(String body, String sig, String key)? verify,
    DateTime Function()? clock,
    AdminBlockBook? book,
  })  : verify = verify ?? ed25519Verify,
        _clock = clock ?? DateTime.now,
        book = book ?? AdminBlockBook.instance;

  static const String recordsKey = 'admin_blocks_v1';
  static const String endedKey = 'admin_certs_ended_v1';
  static const String trustKeySetting = 'server_trust_key';
  static const String certKey = 'admin_offline_cert_v1';

  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final String Function() selfDeviceId;
  final String Function() selfUserId;
  final Future<String> Function() signingKey;
  final Future<String> Function(String body) sign;
  final Future<void> Function(String peerId, Map<String, dynamic> payload) send;
  final Stream<Map<String, dynamic>> events;
  final Future<List<String>> Function() linkedPeers;
  final AdminBlockServer? server;
  final Future<AdminSignIn?> Function()? adminSignIn;
  final void Function()? onBlockedChanged;
  final void Function(bool blocked, AdminBlockRecord? record)? onSelfChanged;
  final void Function(String name)? onServerSaved;
  final Future<bool> Function(String body, String sig, String key) verify;
  final DateTime Function() _clock;
  final AdminBlockBook book;

  static AdminBlockService? instance;

  final Map<String, _Kept> _kept = <String, _Kept>{};
  final Map<String, String> _ended = <String, String>{}; // cert id → note
  final Map<String, DateTime> _digestSentAt = <String, DateTime>{};
  final Map<String, DateTime> _digestTakenAt = <String, DateTime>{};
  final Map<String, String> _recordFrom = <String, String>{}; // id → peer
  final Set<String> _gotSeen = <String>{};
  String? _serverKey;
  SignedBlob? _cert;
  bool _loaded = false;
  bool _started = false;
  bool? _selfWas;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _digestTimer;
  Timer? _serverTimer;
  bool _syncBusy = false;

  String? get serverKey => _serverKey;
  SignedBlob? get cert => _cert;

  /// Bundle 213: the version rule uses the same trust (ended keys, cert).
  Set<String> get endedCertIds => _ended.keys.toSet();
  Future<SignedBlob?> usableCert() async {
    await load();
    return _usableCert();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _serverKey = _nonEmpty(await read(trustKeySetting));
    final certRaw = await read(certKey);
    if (certRaw != null && certRaw.isNotEmpty) {
      try {
        _cert = SignedBlob.fromJson(jsonDecode(certRaw));
      } catch (_) {}
    }
    try {
      final raw = await read(endedKey);
      if (raw != null && raw.isNotEmpty) {
        for (final n in (jsonDecode(raw) as List)) {
          final blob = SignedBlob.fromJson(n);
          final id = blob?.fields?['cert_id']?.toString() ?? '';
          if (blob != null && id.isNotEmpty) _ended[id] = jsonEncode(blob);
        }
      }
    } catch (_) {}
    try {
      final raw = await read(recordsKey);
      if (raw != null && raw.isNotEmpty) {
        for (final row in (jsonDecode(raw) as List).whereType<Map>()) {
          final blob = SignedBlob.fromJson(row['blob']);
          final record = blob == null ? null : AdminBlockRecord.fromBlob(blob);
          if (record == null) continue;
          _kept[record.targetUserId] = _Kept(
            record,
            source: row['source']?.toString() ?? 'nearby',
            serverDone: row['server_done'] == true,
            reached: {
              for (final p in (row['reached'] as List? ?? const []))
                p.toString()
            },
            receivedAt: row['received_at']?.toString() ?? '',
          );
        }
      }
    } catch (_) {}
    book.setSelf(userId: selfUserId(), deviceId: selfDeviceId());
    book.replaceAll(_kept.values.map((k) => k.record));
    _selfWas = book.selfBlocked;
  }

  /// Starts listening + the timers (main app and the no-screen engine).
  Future<void> start() async {
    await load();
    if (_started) return;
    _started = true;
    instance = this;
    _sub = events.listen((e) => unawaited(handleEvent(e).catchError((_) {})));
    _digestTimer = Timer.periodic(AdminBlockRules.digestEvery,
        (_) => unawaited(sendDigests().catchError((_) {})));
    _serverTimer = Timer.periodic(AdminBlockRules.serverEvery,
        (_) => unawaited(syncWithServer().catchError((_) {})));
    unawaited(Future<void>.delayed(const Duration(seconds: 6), () async {
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

  // ------------------------------------------------------------ the screens

  List<AdminBlockEntry> get entries => [
        for (final k in _kept.values)
          AdminBlockEntry(
            record: k.record,
            source: k.source,
            serverDone: k.serverDone,
            reached: k.reached.length,
            receivedAt: k.receivedAt,
          ),
      ]..sort((a, b) => b.record.at.compareTo(a.record.at));

  AdminBlockEntry? entryFor(String id) {
    for (final e in entries) {
      if (e.record.targetUserId == id || e.record.targetDevices.contains(id)) {
        return e;
      }
    }
    return null;
  }

  /// A6: can this phone block offline right now?
  Future<AdminBlockReadiness> readiness() async {
    await load();
    final signIn = await adminSignIn?.call();
    if (signIn != null && signIn.role.isNotEmpty && signIn.role != 'owner') {
      return AdminBlockReadiness.notOwner;
    }
    if (_serverKey == null) return AdminBlockReadiness.noTrust;
    final cert = await _usableCert();
    return cert == null ? AdminBlockReadiness.needServer : AdminBlockReadiness.ready;
  }

  Future<SignedBlob?> _usableCert() async {
    final c = _cert;
    if (c == null) return null;
    final signIn = await adminSignIn?.call();
    if (signIn == null) {
      // Signed out of Admin: the key goes with the sign-in.
      _cert = null;
      await write(certKey, '');
      return null;
    }
    final parsed = AdminCert.fromBlob(c);
    if (parsed == null || _ended.containsKey(parsed.certId)) return null;
    if (parsed.deviceId != selfDeviceId()) return null;
    if (parsed.signingKey != await signingKey()) return null;
    return c;
  }

  /// Blocks or unblocks [targetUserId] for everyone. Throws a short message
  /// when this phone can't sign blocks (not ready, own account).
  Future<AdminBlockRecord> setBlocked({
    required String targetUserId,
    required List<String> targetDevices,
    required String targetName,
    required bool block,
  }) async {
    await load();
    final me = {selfUserId(), selfDeviceId()}..remove('');
    if (me.contains(targetUserId) || targetDevices.any(me.contains)) {
      throw StateError("You can't block your own account.");
    }
    final cert = await _usableCert();
    if (cert == null) {
      throw StateError('Connect to the server once to turn on offline blocking.');
    }
    final signIn = await adminSignIn?.call();
    final old = _kept[targetUserId]?.record;
    final devices = <String>{
      ...targetDevices,
      ...?old?.targetDevices,
    }.where((d) => d.isNotEmpty).toList()
      ..sort();
    final body = AdminBlockRecord.newBody(
      id: _newId(),
      targetUserId: targetUserId,
      targetDevices: devices,
      targetName: targetName,
      action: block ? 'block' : 'unblock',
      seq: (old?.seq ?? 0) + 1,
      at: _clock(),
      by: signIn?.username ?? '',
      cert: cert,
    );
    final blob = SignedBlob(body: body, sig: await sign(body));
    final record = AdminBlockRecord.fromBlob(blob)!;
    await _accept(record, source: 'me');
    AppLogger.info('ADMIN_BLOCK_MADE',
        detail: 'action=${record.action} seq=${record.seq} '
            'target=${_tail(targetUserId)}');
    unawaited(_spread([record], except: '').catchError((_) {}));
    unawaited(syncWithServer().catchError((_) {}));
    return record;
  }

  // -------------------------------------------------------------- receiving

  /// Checks and keeps [record] when it is valid and newer. True when kept.
  Future<bool> offer(AdminBlockRecord record, {required String source}) async {
    await load();
    final reason = await AdminBlockRules.check(record,
        serverKey: _serverKey, endedCerts: _ended.keys.toSet(), verify: verify);
    if (reason != null) {
      AppLogger.warning('ADMIN_BLOCK_REJECT',
          detail: 'reason=$reason id=${_tail(record.id)} from=$source');
      return false;
    }
    if (!AdminBlockRules.newer(record, _kept[record.targetUserId]?.record)) {
      final same = _kept[record.targetUserId]?.record.id == record.id;
      if (same && source == 'server') await _markServerDone(record.id);
      return false;
    }
    await _accept(record, source: source);
    return true;
  }

  Future<void> _accept(AdminBlockRecord record, {required String source}) async {
    final old = _kept[record.targetUserId];
    _kept[record.targetUserId] = _Kept(
      record,
      source: source,
      serverDone: source == 'server',
      reached: <String>{},
      receivedAt: _clock().toUtc().toIso8601String(),
    );
    if (old != null && old.record.id == record.id) {
      _kept[record.targetUserId]!.reached.addAll(old.reached);
    }
    _trim();
    await _saveRecords();
    book.put(record);
    onBlockedChanged?.call();
    _checkSelf();
  }

  void _checkSelf() {
    final now = book.selfBlocked;
    if (_selfWas == now) return;
    final was = _selfWas;
    _selfWas = now;
    if (was == null && !now) return;
    AppLogger.warning('ADMIN_BLOCK_SELF', detail: 'blocked=$now');
    onSelfChanged?.call(now, book.selfRecord);
  }

  void _trim() {
    if (_kept.length <= AdminBlockRules.maxRecords) return;
    // Keep blocks first, then the newest unblocks.
    final list = _kept.values.toList()
      ..sort((a, b) {
        if (a.record.isBlock != b.record.isBlock) {
          return a.record.isBlock ? -1 : 1;
        }
        return b.record.at.compareTo(a.record.at);
      });
    _kept
      ..clear()
      ..addEntries(list
          .take(AdminBlockRules.maxRecords)
          .map((k) => MapEntry(k.record.targetUserId, k)));
  }

  Future<void> _saveRecords() => write(
      recordsKey,
      jsonEncode([
        for (final k in _kept.values)
          {
            'blob': k.record.blob.toJson(),
            'source': k.source,
            'server_done': k.serverDone,
            'reached': k.reached.take(500).toList(),
            'received_at': k.receivedAt,
          },
      ]));

  Future<void> _saveEnded() => write(endedKey,
      jsonEncode([for (final n in _ended.values) jsonDecode(n)]));

  Future<bool> _takeEnded(SignedBlob note) async {
    final id = await AdminBlockRules.endedCertId(note,
        serverKey: _serverKey, verify: verify);
    if (id == null || _ended.containsKey(id)) return false;
    _ended[id] = jsonEncode(note.toJson());
    if (_ended.length > 500) _ended.remove(_ended.keys.first);
    await _saveEnded();
    AppLogger.info('ADMIN_BLOCK_KEY_ENDED', detail: 'cert=${_tail(id)}');
    final mine = _cert == null ? null : AdminCert.fromBlob(_cert!);
    if (mine != null && mine.certId == id) {
      _cert = null;
      await write(certKey, '');
    }
    return true;
  }

  // -------------------------------------------------------------- spreading

  /// One event from the transport ('message' with a JSON payload, or a
  /// phone that just linked).
  Future<void> handleEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();
    if (type == 'peer_connected') {
      final peer = event['peer_id']?.toString() ?? '';
      if (peer.isNotEmpty) await sendDigestTo(peer);
      return;
    }
    if (type != 'message') return;
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains('admin_block_')) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      msg = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final kind = msg['type']?.toString();
    if (!AdminBlockRules.isFrameType(kind)) return;
    // Who sent it: the link layer's sender, never a field they wrote.
    final from = event['sender_id']?.toString() ?? '';
    if (from.isEmpty || from == selfDeviceId()) return;
    await load();
    switch (kind) {
      case AdminBlockRules.digestType:
        await _onDigest(from, msg);
      case AdminBlockRules.recordsType:
        await _onRecords(from, msg);
      case AdminBlockRules.gotType:
        await _onGot(from, msg);
    }
  }

  Map<String, dynamic> digest() {
    final items = [
      for (final k in _kept.values)
        {'t': k.record.targetUserId, 's': k.record.seq, 'i': k.record.id},
    ]..sort((a, b) => '${a['t']}'.compareTo('${b['t']}'));
    final ended = _ended.keys.toList()..sort();
    return {
      'type': AdminBlockRules.digestType,
      'h': _hash(items, ended),
      'items': items.take(AdminBlockRules.maxRecords).toList(),
      'ended': ended.take(500).toList(),
    };
  }

  String _hash(List<Map<String, Object>> items, List<String> ended) {
    final text = '${items.map((e) => '${e['t']}:${e['s']}:${e['i']}').join(',')}|${ended.join(',')}';
    var h = 0x811c9dc5;
    for (final c in utf8.encode(text)) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  Future<void> sendDigests() async {
    await load();
    if (_kept.isEmpty && _ended.isEmpty) return;
    List<String> peers;
    try {
      peers = await linkedPeers();
    } catch (_) {
      return;
    }
    for (final p in peers) {
      await sendDigestTo(p);
    }
  }

  Future<void> sendDigestTo(String peer) async {
    await load();
    if (peer.isEmpty || peer == selfDeviceId()) return;
    final now = _clock();
    final last = _digestSentAt[peer];
    if (last != null && now.difference(last) < AdminBlockRules.digestGap) {
      return;
    }
    _digestSentAt[peer] = now;
    if (_digestSentAt.length > 300) _digestSentAt.remove(_digestSentAt.keys.first);
    try {
      await send(peer, digest());
    } catch (_) {}
  }

  Future<void> _onDigest(String from, Map<String, dynamic> msg) async {
    final now = _clock();
    final last = _digestTakenAt[from];
    if (last != null && now.difference(last) < AdminBlockRules.digestGap) {
      return;
    }
    _digestTakenAt[from] = now;
    if (_digestTakenAt.length > 300) _digestTakenAt.remove(_digestTakenAt.keys.first);
    final mine = digest();
    if (mine['h'] == msg['h']) return;
    final theirs = <String, (int, String)>{};
    for (final it in (msg['items'] as List? ?? const []).whereType<Map>()) {
      final t = it['t']?.toString() ?? '';
      final s = it['s'] is int ? it['s'] as int : int.tryParse('${it['s']}') ?? 0;
      if (t.isNotEmpty) theirs[t] = (s, it['i']?.toString() ?? '');
    }
    final theirEnded = {
      for (final e in (msg['ended'] as List? ?? const [])) e.toString()
    };
    final missing = <AdminBlockRecord>[
      for (final k in _kept.values)
        if (_theyNeed(k.record, theirs[k.record.targetUserId])) k.record,
    ];
    final endedMissing = [
      for (final e in _ended.entries)
        if (!theirEnded.contains(e.key)) e.value,
    ];
    if (missing.isNotEmpty || endedMissing.isNotEmpty) {
      await _sendRecords(from, missing, endedMissing);
    }
    // They have something newer: send my digest so they push it to me.
    var theyHaveMore = theirEnded.any((e) => !_ended.containsKey(e));
    for (final e in theirs.entries) {
      final k = _kept[e.key];
      if (k == null || e.value.$1 > k.record.seq) theyHaveMore = true;
    }
    if (theyHaveMore) await sendDigestTo(from);
  }

  bool _theyNeed(AdminBlockRecord r, (int, String)? theirs) {
    if (theirs == null) return true;
    if (r.seq != theirs.$1) return r.seq > theirs.$1;
    return r.id != theirs.$2 && r.id.compareTo(theirs.$2) > 0;
  }

  Future<void> _sendRecords(String peer, List<AdminBlockRecord> records,
      [List<String> ended = const []]) async {
    final frames = <List<Map<String, dynamic>>>[
      for (var i = 0; i < records.length; i += AdminBlockRules.maxPerFrame)
        [
          for (final r in records.sublist(
              i, min(records.length, i + AdminBlockRules.maxPerFrame)))
            r.blob.toJson(),
        ],
    ];
    if (frames.isEmpty && ended.isEmpty) return;
    if (frames.isEmpty) frames.add(const <Map<String, dynamic>>[]);
    for (var j = 0; j < frames.length; j++) {
      try {
        await send(peer, <String, dynamic>{
          'type': AdminBlockRules.recordsType,
          'records': frames[j],
          if (j == 0 && ended.isNotEmpty)
            'ended': [for (final e in ended) jsonDecode(e)],
        });
      } catch (_) {}
    }
    if (records.isNotEmpty) {
      AppLogger.info('ADMIN_BLOCK_SPREAD',
          detail: 'to=${_tail(peer)} n=${records.length}');
    }
  }

  Future<void> _spread(List<AdminBlockRecord> records, {required String except}) async {
    List<String> peers;
    try {
      peers = await linkedPeers();
    } catch (_) {
      return;
    }
    for (final p in peers) {
      if (p == except || p == selfDeviceId()) continue;
      await _sendRecords(p, records);
    }
  }

  Future<void> _onRecords(String from, Map<String, dynamic> msg) async {
    var endedNew = false;
    for (final n in (msg['ended'] as List? ?? const [])) {
      final blob = SignedBlob.fromJson(n);
      if (blob != null && await _takeEnded(blob)) endedNew = true;
    }
    final fresh = <AdminBlockRecord>[];
    for (final raw in (msg['records'] as List? ?? const [])
        .take(AdminBlockRules.maxPerFrame)) {
      final blob = SignedBlob.fromJson(raw);
      final record = blob == null ? null : AdminBlockRecord.fromBlob(blob);
      if (record == null) {
        AppLogger.warning('ADMIN_BLOCK_REJECT', detail: 'reason=bad_record from=${_tail(from)}');
        continue;
      }
      if (await offer(record, source: 'nearby')) {
        fresh.add(record);
        _recordFrom[record.id] = from;
        if (_recordFrom.length > 500) _recordFrom.remove(_recordFrom.keys.first);
      }
    }
    if (fresh.isNotEmpty) {
      try {
        await send(from, {
          'type': AdminBlockRules.gotType,
          'ids': [for (final r in fresh) r.id],
          'phone': selfDeviceId(),
        });
      } catch (_) {}
      await _spread(fresh, except: from);
    }
    if (endedNew) {
      // Pass the "key ended" notes on too.
      final notes = _ended.values.toList();
      List<String> peers = const [];
      try {
        peers = await linkedPeers();
      } catch (_) {}
      for (final p in peers) {
        if (p == from) continue;
        await _sendRecords(p, const [], notes);
      }
    }
  }

  Future<void> _onGot(String from, Map<String, dynamic> msg) async {
    final phone = msg['phone']?.toString() ?? '';
    if (phone.isEmpty) return;
    final ids = [for (final i in (msg['ids'] as List? ?? const [])) i.toString()]
        .take(AdminBlockRules.maxPerFrame);
    var changed = false;
    for (final id in ids) {
      final key = '$id|$phone';
      if (!_gotSeen.add(key)) continue;
      if (_gotSeen.length > 2000) _gotSeen.remove(_gotSeen.first);
      _Kept? kept;
      for (final k in _kept.values) {
        if (k.record.id == id) kept = k;
      }
      if (kept == null) continue;
      if (kept.source == 'me') {
        if (kept.reached.add(phone)) changed = true;
        AppLogger.info('ADMIN_BLOCK_GOT',
            detail: 'id=${_tail(id)} phone=${_tail(phone)} n=${kept.reached.length}');
        continue;
      }
      // Back one step toward the admin phone.
      final back = _recordFrom[id];
      if (back != null && back != from) {
        try {
          await send(back, {
            'type': AdminBlockRules.gotType,
            'ids': [id],
            'phone': phone,
          });
        } catch (_) {}
      }
    }
    if (changed) {
      await _saveRecords();
      book.touch(); // repaint "Reached N phones"
    }
  }

  // ----------------------------------------------------------------- server

  /// Saves the server key the first time; a different key later is kept
  /// out (TRUST_KEY_CHANGED) - a precaution; Reset setup clears it.
  Future<void> pinTrust() async {
    final s = server;
    if (s == null) return;
    await load();
    final key = await s.trustKey();
    if (key.isEmpty) return;
    if (_serverKey == null) {
      _serverKey = key;
      await write(trustKeySetting, key);
      AppLogger.info('TRUST_KEY_SAVED', detail: 'key=${_tail(key)}');
    } else if (_serverKey != key) {
      AppLogger.warning('TRUST_KEY_CHANGED',
          detail: 'kept=${_tail(_serverKey!)} new=${_tail(key)}');
    }
  }

  /// A5: the admin offline key for this phone (online, signed in, owner).
  Future<bool> ensureCert() async {
    final s = server;
    final signIn = await adminSignIn?.call();
    if (s == null || signIn == null || signIn.role != 'owner') return false;
    await load();
    if (await _usableCert() != null) return true;
    try {
      final blob = await s.offlineCert(
          adminToken: signIn.token,
          deviceId: selfDeviceId(),
          signingKey: await signingKey());
      final key = _serverKey;
      if (key == null || !await verify(blob.body, blob.sig, key)) {
        AppLogger.warning('TRUST_CERT', detail: 'result=bad_sig');
        return false;
      }
      _cert = blob;
      await write(certKey, jsonEncode(blob.toJson()));
      AppLogger.info('TRUST_CERT', detail: 'result=saved');
      return true;
    } catch (error) {
      AppLogger.warning('TRUST_CERT', detail: 'result=failed error=$error');
      return false;
    }
  }

  /// G4: send my records, take the server's (newest wins). A blocked
  /// account can't use device calls, so it reads only its own record.
  Future<void> syncWithServer() async {
    final s = server;
    if (s == null || _syncBusy) return;
    _syncBusy = true;
    try {
      await load();
      try {
        await pinTrust();
      } catch (_) {
        return; // server not reachable
      }
      unawaited(ensureCert().catchError((_) => false));
      try {
        final mineToSend = [for (final k in _kept.values) k.record.blob];
        final out = await s.sync(mineToSend);
        for (final n in out.ended) {
          await _takeEnded(n);
        }
        final fresh = <AdminBlockRecord>[];
        for (final blob in out.records) {
          final r = AdminBlockRecord.fromBlob(blob);
          if (r != null && await offer(r, source: 'server')) fresh.add(r);
        }
        // Mine that the server now has (same id) are done.
        final have = {for (final b in out.records) AdminBlockRecord.fromBlob(b)?.id};
        for (final k in _kept.values.toList()) {
          if (!k.serverDone && have.contains(k.record.id)) {
            await _markServerDone(k.record.id);
          }
        }
        if (fresh.isNotEmpty) await _spread(fresh, except: '');
        AppLogger.info('ADMIN_BLOCK_SERVER_SYNC',
            detail: 'sent=${mineToSend.length} got=${out.records.length} new=${fresh.length}');
      } on AdminBlockUnauthorized {
        final own = await s.mine();
        final r = own == null ? null : AdminBlockRecord.fromBlob(own);
        if (r != null && await offer(r, source: 'server')) {
          await _spread([r], except: '');
        }
        AppLogger.info('ADMIN_BLOCK_SERVER_SYNC', detail: 'mode=mine');
      }
    } catch (error) {
      AppLogger.warning('ADMIN_BLOCK_SERVER_SYNC', detail: 'failed error=$error');
    } finally {
      _syncBusy = false;
    }
  }

  Future<void> _markServerDone(String id) async {
    for (final k in _kept.values) {
      if (k.record.id != id || k.serverDone) continue;
      k.serverDone = true;
      await _saveRecords();
      if (k.source == 'me') {
        onServerSaved?.call(k.record.targetName);
      }
      book.touch();
    }
  }

  static String? _nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;

  static String _tail(String s) => s.length <= 6 ? s : s.substring(s.length - 6);

  String _newId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

class _Kept {
  final AdminBlockRecord record;
  final String source;
  bool serverDone;
  final Set<String> reached;
  final String receivedAt;

  _Kept(this.record,
      {required this.source,
      required this.serverDone,
      required this.reached,
      required this.receivedAt});
}

/// Ed25519 check with base64url (no padding) key and signature.
Future<bool> ed25519Verify(String body, String sig, String key) async {
  try {
    final pub = _unb64(key);
    final s = _unb64(sig);
    if (pub.length != 32 || s.length != 64) return false;
    return await Ed25519().verify(utf8.encode(body),
        signature: Signature(s,
            publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)));
  } catch (_) {
    return false;
  }
}

List<int> _unb64(String v) {
  var t = v.trim();
  while (t.length % 4 != 0) {
    t += '=';
  }
  return base64Url.decode(t);
}
