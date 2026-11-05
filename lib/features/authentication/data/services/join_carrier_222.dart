import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';

/// Bundle 222 (section 9): nearby phones carry an offline account's
/// registration to the server.
///
/// * Her phone (account made offline, never on the server) makes ONE join
///   box: her name, the PBKDF2 hash + salt she already keeps for offline
///   sign-in (the real password never travels), the hash of her recovery
///   code, her phone id and keys. It is signed with her phone key and then
///   locked for the server (llaa1 box to the server's join key), so a
///   carrier can neither read nor change it.
/// * Every phone passes boxes on (frame `account_join`, one step at a time,
///   like the 220/221 frames). Any phone with the server uploads them
///   (`POST /api/v1/auth/join-relay`). Same box twice = same answer.
/// * The server-signed answer travels back the same way. Carriers drop the
///   box when they see its answer. Her phone checks the server signature,
///   opens her session token (locked to her identity key) and runs the
///   normal 218 "after the server said yes" steps.
/// * The join key: from the server itself (`GET /api/v1/trust`), or for a
///   phone that was never online, the same server-signed note from TWO
///   different phones. It is used only for the join box.
///
/// No time limit (Pending until achieved); boxes and answers are kept up to
/// 60 days, at most 200 boxes per phone. Logs never hold a hash or token.
abstract final class JoinRules222 {
  static const String frameType = 'account_join';
  static const int maxBoxes = 200;
  static const int maxBoxLen = 12 * 1024;
  static const Duration keep = Duration(days: 60);
  static const int perFrame = 10;

  static const String keySetting = 'join_key_222';
  static const String keyOffersSetting = 'join_key_offers_222';
  static const String mineSetting = 'join_mine_222';

  /// sha256 hex of the formatted (ABCDE-FGHIJ-KLMNO-PQRST) uppercase code,
  /// the same as the server's `tokenHash(code)`.
  static String recoveryHash(String code) {
    final raw = code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    final formatted = raw.length == 20
        ? '${raw.substring(0, 5)}-${raw.substring(5, 10)}-${raw.substring(10, 15)}-${raw.substring(15)}'
        : code.trim();
    return hash.sha256.convert(utf8.encode(formatted)).toString();
  }

  /// Standard or url base64 (with or without padding) → base64url, no pad.
  static String b64url(String v) {
    return v.trim().replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  }
}

/// What her phone knows about its own offline account (null = nothing to
/// carry: already on the server, or no offline account).
class JoinMine222 {
  final String username;
  final String displayName;
  final String offlineUserId;
  final String deviceId;
  final String deviceName;
  final String hardwareFp;
  final String pwdSalt;
  final String pwdHash;
  final int iterations;
  final String recoveryCode;
  final String pairingCode;

  const JoinMine222({
    required this.username,
    required this.displayName,
    required this.offlineUserId,
    required this.deviceId,
    required this.deviceName,
    required this.hardwareFp,
    required this.pwdSalt,
    required this.pwdHash,
    required this.iterations,
    required this.recoveryCode,
    this.pairingCode = '',
  });

  /// Changes when anything the server needs changes → a new box.
  String get stamp => hash.sha256
      .convert(utf8.encode([username, displayName, deviceId, pwdSalt, pwdHash, '$iterations',
        JoinRules222.recoveryHash(recoveryCode), pairingCode].join('|')))
      .toString()
      .substring(0, 16);
}

/// The answer her phone takes (token already opened).
class JoinTaken222 {
  final String status; // joined | linked | renamed | already
  final String username;
  final String userId;
  final String deviceId;
  final String token;
  final String expiresAt;
  final String server;
  const JoinTaken222({
    required this.status,
    required this.username,
    required this.userId,
    required this.deviceId,
    required this.token,
    required this.expiresAt,
    required this.server,
  });
}

/// Rows of table `join_boxes_222` (LocalStore) or memory in tests.
abstract class JoinBoxStore222 {
  Future<List<Map<String, Object?>>> rows();
  Future<void> put(Map<String, Object?> row);
  Future<void> delete(List<String> ids);
  Future<String?> readSetting(String key);
  Future<void> writeSetting(String key, String value);
}

class SqlJoinBoxStore222 implements JoinBoxStore222 {
  SqlJoinBoxStore222(this.store);
  final LocalStore store;
  @override
  Future<List<Map<String, Object?>>> rows() => store.joinBoxRows222();
  @override
  Future<void> put(Map<String, Object?> row) => store.putJoinBoxRow222(row);
  @override
  Future<void> delete(List<String> ids) => store.deleteJoinBoxRows222(ids);
  @override
  Future<String?> readSetting(String key) => store.readSetting(key);
  @override
  Future<void> writeSetting(String key, String value) => store.writeSetting(key, value);
}

class MemoryJoinBoxStore222 implements JoinBoxStore222 {
  final Map<String, Map<String, Object?>> data = {};
  final Map<String, String> settings = {};
  @override
  Future<List<Map<String, Object?>>> rows() async => [for (final r in data.values) Map.of(r)];
  @override
  Future<void> put(Map<String, Object?> row) async => data['${row['box_id']}'] = Map.of(row);
  @override
  Future<void> delete(List<String> ids) async => ids.forEach(data.remove);
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
}

/// The server's part (real HTTP in app_dependencies, fakes in tests).
abstract class JoinServer222 {
  /// `GET /api/v1/trust` → `{server_key, join_key, join_note:{body,sig}}`.
  Future<Map<String, dynamic>?> trust();

  /// `POST /api/v1/auth/join-relay` → the signed answer `{body, sig}`.
  Future<Map<String, dynamic>> upload(String boxId, String box);
}

/// Her own waiting card (U-3) and the admin sheet (U-2).
class JoinStatus222 {
  final bool waiting; // her box exists, no answer yet
  final bool noKey; // offline account but no join key yet
  final int carriers; // phones that said they have her box
  final String firstCarrier;
  final String sentAt;
  const JoinStatus222({
    this.waiting = false,
    this.noKey = false,
    this.carriers = 0,
    this.firstCarrier = '',
    this.sentAt = '',
  });
}

class JoinCarrier222 {
  JoinCarrier222({
    required this.store,
    required this.selfDeviceId,
    required this.send,
    required this.events,
    required this.linkedPeers,
    required this.verify,
    required this.sign,
    required this.signingKey,
    required this.identityKey,
    required this.openBox,
    required this.lockBox,
    required this.mine,
    required this.onTaken,
    this.server,
    this.serverOnline,
    this.serverUrl,
    this.pinnedServerKey,
    this.peerName,
    this.onChanged,
    DateTime Function()? clock,
    Random? random,
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  static JoinCarrier222? instance;

  /// Bumped on every change (her card, Admin → Users).
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  final JoinBoxStore222 store;
  final String Function() selfDeviceId;
  final Future<void> Function(String peerId, Map<String, dynamic> payload) send;
  final Stream<Map<String, dynamic>>? events;
  final Future<List<String>> Function() linkedPeers;
  final Future<bool> Function(String body, String sig, String key) verify;
  final Future<String> Function(String body) sign;
  final Future<String> Function() signingKey;
  final Future<String> Function() identityKey;

  /// Opens a box locked to this phone's identity key (null = not for me).
  final Future<List<int>?> Function(String box) openBox;

  /// llaa1 box to [key] (the server's join key).
  final Future<String> Function(String key, List<int> plain) lockBox;

  /// Her own offline account, or null.
  final Future<JoinMine222?> Function() mine;

  /// Her phone: the server said yes (token opened). Runs the 218 steps.
  final Future<void> Function(JoinTaken222 taken) onTaken;

  final JoinServer222? server;
  final bool Function()? serverOnline;
  final String Function()? serverUrl;
  final String? Function()? pinnedServerKey;
  final Future<String> Function(String deviceId)? peerName;
  final void Function()? onChanged;
  final DateTime Function() _clock;
  final Random _random;

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _timer;
  bool _busy = false;
  bool _taking = false;
  final Map<String, DateTime> _haveSentAt = {};

  String _now() => _clock().toUtc().toIso8601String();

  void _changed() {
    changes.value++;
    onChanged?.call();
  }

  void start() {
    _sub ??= events?.listen((e) => unawaited(handleEvent(e).catchError((Object _) {})));
    _timer ??= Timer.periodic(const Duration(seconds: 60), (_) => unawaited(tick().catchError((Object _) {})));
    unawaited(tick().catchError((Object _) {}));
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
  }

  // ------------------------------------------------------------ join key

  /// `{body, sig, server_key, join_key, server}` once trusted.
  Future<Map<String, dynamic>?> joinKey() async {
    final raw = await store.readSetting(JoinRules222.keySetting);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _noteBody(String body) {
    try {
      final m = jsonDecode(body);
      if (m is! Map || m['kind'] != 'join_key') return null;
      final out = Map<String, dynamic>.from(m);
      if ('${out['server_key'] ?? ''}'.isEmpty || '${out['join_key'] ?? ''}'.isEmpty) return null;
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _saveKey(String body, String sig, String server) async {
    final b = _noteBody(body);
    if (b == null) return false;
    final old = await joinKey();
    if (old != null && old['body'] == body && (server.isEmpty || old['server'] == server)) return false;
    await store.writeSetting(
        JoinRules222.keySetting,
        jsonEncode({
          'body': body,
          'sig': sig,
          'server_key': b['server_key'],
          'join_key': b['join_key'],
          'server': server.isNotEmpty ? server : (old?['server'] ?? ''),
        }));
    AppLogger.info('JOIN_KEY_SAVED');
    return true;
  }

  /// From the server (this phone is online).
  Future<void> refreshKey() async {
    final s = server;
    if (s == null || !(serverOnline?.call() ?? false)) return;
    final t = await s.trust();
    final note = t?['join_note'];
    if (note is! Map) return;
    final body = '${note['body'] ?? ''}';
    final sig = '${note['sig'] ?? ''}';
    final key = '${t?['server_key'] ?? ''}';
    final b = _noteBody(body);
    if (b == null || key.isEmpty || b['server_key'] != key) return;
    final pinned = pinnedServerKey?.call() ?? '';
    if (pinned.isNotEmpty && pinned != key) return;
    if (!await verify(body, sig, key)) return;
    if (await _saveKey(body, sig, serverUrl?.call() ?? '')) unawaited(_makeMine());
  }

  /// From a nearby phone: trusted at once if it checks against the server
  /// key this phone already pinned; otherwise only when a SECOND phone
  /// hands the very same signed note (and server address).
  Future<void> _takeKeyOffer(Map<String, dynamic> msg, String from) async {
    final note = msg['note'];
    if (note is! Map) return;
    final body = '${note['body'] ?? ''}';
    final sig = '${note['sig'] ?? ''}';
    final srv = '${msg['server'] ?? ''}'.trim();
    final b = _noteBody(body);
    if (b == null || body.length > 2048 || srv.length > 300) return;
    if (!await verify(body, sig, '${b['server_key']}')) return; // must at least be self-consistent
    final pinned = pinnedServerKey?.call() ?? '';
    if (pinned.isNotEmpty) {
      if (pinned != b['server_key']) return;
      if (await _saveKey(body, sig, srv)) unawaited(_makeMine());
      return;
    }
    final have = await joinKey();
    if (have != null) return; // already trusted one; never replaced by peers alone
    Map<String, dynamic> offers = {};
    try {
      final raw = await store.readSetting(JoinRules222.keyOffersSetting);
      if (raw != null && raw.isNotEmpty) offers = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    final id = hash.sha256.convert(utf8.encode('$body|$sig|$srv')).toString().substring(0, 24);
    final from0 = (offers[id] as List?)?.map((e) => '$e').toSet() ?? <String>{};
    from0.add(from);
    offers[id] = from0.take(8).toList();
    if (offers.length > 20) offers.remove(offers.keys.first);
    await store.writeSetting(JoinRules222.keyOffersSetting, jsonEncode(offers));
    if (from0.length >= 2) {
      AppLogger.info('JOIN_KEY_FROM_PHONES', detail: 'n=${from0.length}');
      if (await _saveKey(body, sig, srv)) unawaited(_makeMine());
    }
  }

  // ------------------------------------------------------------- her box

  Future<Map<String, dynamic>?> _mineInfo() async {
    final raw = await store.readSetting(JoinRules222.mineSetting);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMine(Map<String, dynamic> m) =>
      store.writeSetting(JoinRules222.mineSetting, jsonEncode(m));

  String _newId() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    return 'jb_${b.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<void>? _making;

  /// Makes (or remakes after a name / password change) her one box. One at
  /// a time (a key and a tick can arrive together).
  Future<void> _makeMine() => _making ??= _makeMine0().whenComplete(() => _making = null);

  Future<void> _makeMine0() async {
    final me = await mine();
    final info = await _mineInfo();
    if (me == null) {
      if (info != null && info['done'] != true) {
        // On the server by herself: stop sending her box.
        await store.delete(['${info['box_id']}']);
        await _writeMine({...info, 'done': true});
      }
      return;
    }
    if (info != null && info['stamp'] == me.stamp && info['done'] != true) return;
    final key = await joinKey();
    if (key == null) return;
    final boxId = _newId();
    final body = jsonEncode({
      'v': 1,
      'box_id': boxId,
      'username': me.username.trim().toLowerCase(),
      'display_name': me.displayName,
      'offline_user_id': me.offlineUserId,
      'device_id': me.deviceId,
      'device_name': me.deviceName,
      'platform': 'android',
      'hardware_fp': me.hardwareFp,
      'pwd_salt': JoinRules222.b64url(me.pwdSalt),
      'pwd_hash': JoinRules222.b64url(me.pwdHash),
      'iterations': me.iterations,
      'recovery_hash': JoinRules222.recoveryHash(me.recoveryCode),
      'identity_key': await identityKey(),
      'signing_key': await signingKey(),
      'pairing_code': me.pairingCode,
      'made_at': _now(),
    });
    final sealed = jsonEncode({'body': body, 'sig': await sign(body)});
    final box = await lockBox('${key['join_key']}', utf8.encode(sealed));
    if (box.length > JoinRules222.maxBoxLen) {
      AppLogger.info('JOIN_BOX_TOO_BIG');
      return;
    }
    if (info != null && '${info['box_id'] ?? ''}'.isNotEmpty) await store.delete(['${info['box_id']}']);
    await store.put({
      'box_id': boxId,
      'from_device': me.deviceId,
      'box': box,
      'made_at': _now(),
      'got_at': _now(),
      'status': 'mine',
      'answer': '',
      'extra': '',
    });
    await _writeMine({'box_id': boxId, 'stamp': me.stamp, 'made_at': _now(), 'carriers': <String>[], 'done': false});
    AppLogger.info('JOIN_BOX_MADE');
    _changed();
    for (final p in await linkedPeers()) {
      unawaited(sendHave(p, force: true).catchError((Object _) {}));
    }
  }

  /// Her card: waiting / carried by N phones.
  Future<JoinStatus222> status() async {
    final me = await mine();
    if (me == null) return const JoinStatus222();
    final info = await _mineInfo();
    if (info == null || info['done'] == true || info['stamp'] != me.stamp) {
      return JoinStatus222(noKey: await joinKey() == null);
    }
    final carriers = (info['carriers'] as List? ?? const []).map((e) => '$e').toList();
    var first = '';
    if (carriers.isNotEmpty) {
      try {
        first = await (peerName?.call(carriers.first) ?? Future.value(''));
      } catch (_) {}
    }
    return JoinStatus222(
        waiting: true, carriers: carriers.length, firstCarrier: first, sentAt: '${info['made_at'] ?? ''}');
  }

  /// Admin sheet: does this phone carry a box from [deviceId]?
  Future<bool> carriesFrom(String deviceId) async =>
      (await store.rows()).any((r) => r['from_device'] == deviceId && r['status'] == 'carry');

  // ------------------------------------------------------------- frames

  Future<List<Map<String, Object?>>> _live() async {
    final rows = await store.rows();
    final cut = _clock().toUtc().subtract(JoinRules222.keep);
    final old = <String>[];
    final live = <Map<String, Object?>>[];
    for (final r in rows) {
      final at = DateTime.tryParse('${r['got_at'] ?? ''}');
      if (r['status'] != 'mine' && at != null && at.isBefore(cut)) {
        old.add('${r['box_id']}');
      } else {
        live.add(r);
      }
    }
    if (old.isNotEmpty) await store.delete(old);
    return live;
  }

  /// `{type, op:'have', boxes:[ids], answers:[ids], note?, server?}`.
  Future<Map<String, dynamic>> haveFrame() async {
    final rows = await _live();
    final key = await joinKey();
    return {
      'type': JoinRules222.frameType,
      'op': 'have',
      'boxes': [for (final r in rows) if ('${r['box']}'.isNotEmpty && '${r['answer']}'.isEmpty) r['box_id']],
      'answers': [for (final r in rows) if ('${r['answer']}'.isNotEmpty) r['box_id']],
      if (key != null) 'note': {'body': key['body'], 'sig': key['sig']},
      if (key != null && '${key['server'] ?? ''}'.isNotEmpty) 'server': key['server'],
    };
  }

  Future<void> sendHave(String peer, {bool force = false}) async {
    final last = _haveSentAt[peer];
    if (!force && last != null && _clock().difference(last) < const Duration(seconds: 30)) return;
    _haveSentAt[peer] = _clock();
    await send(peer, await haveFrame());
  }

  /// `message` with a JSON `payload` + `sender_id`; `peer_connected`.
  Future<void> handleEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();
    if (type == 'peer_connected') {
      final peer = event['peer_id']?.toString() ?? '';
      if (peer.isNotEmpty) await sendHave(peer, force: true);
      return;
    }
    if (type != 'message') return;
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains(JoinRules222.frameType)) return;
    Map<String, dynamic> msg;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return;
      msg = Map<String, dynamic>.from(d);
    } catch (_) {
      return;
    }
    if (msg['type'] != JoinRules222.frameType) return;
    final from = event['sender_id']?.toString() ?? '';
    if (from.isEmpty || from == selfDeviceId()) return;
    await handleFrame(msg, from: from);
  }

  Future<void> handleFrame(Map<String, dynamic> msg, {required String from}) async {
    switch (msg['op']) {
      case 'have':
        if (msg['note'] is Map) {
          await _takeKeyOffer(msg, from);
        }
        await _answerHave(msg, from);
      case 'boxes':
        await _takeBoxes(msg['boxes'] as List? ?? const [], from);
      case 'answers':
        await _takeAnswers(msg['answers'] as List? ?? const [], from);
    }
  }

  Future<void> _answerHave(Map<String, dynamic> msg, String from) async {
    final theirBoxes = (msg['boxes'] as List? ?? const []).map((e) => '$e').toSet();
    final theirAnswers = (msg['answers'] as List? ?? const []).map((e) => '$e').toSet();
    // Her phone counts who carries her box.
    final info = await _mineInfo();
    final myBox = '${info?['box_id'] ?? ''}';
    if (info != null && info['done'] != true && myBox.isNotEmpty && theirBoxes.contains(myBox)) {
      final c = (info['carriers'] as List? ?? const []).map((e) => '$e').toList();
      if (!c.contains(from)) {
        c.add(from);
        await _writeMine({...info, 'carriers': c.take(50).toList()});
        AppLogger.info('JOIN_BOX_CARRIED', detail: 'from=${_short(from)} n=${c.length}');
        _changed();
      }
    }
    final rows = await _live();
    final answers = [
      for (final r in rows)
        if ('${r['answer']}'.isNotEmpty && !theirAnswers.contains('${r['box_id']}')) r['answer']
    ];
    final boxes = [
      for (final r in rows)
        if ('${r['box']}'.isNotEmpty &&
            '${r['answer']}'.isEmpty &&
            !theirBoxes.contains('${r['box_id']}') &&
            !theirAnswers.contains('${r['box_id']}'))
          {'box_id': r['box_id'], 'from': r['from_device'], 'box': r['box']}
    ];
    for (var i = 0; i < answers.length; i += JoinRules222.perFrame) {
      await send(from, {
        'type': JoinRules222.frameType,
        'op': 'answers',
        'answers': [for (final a in answers.skip(i).take(JoinRules222.perFrame)) jsonDecode('$a')],
      });
    }
    for (var i = 0; i < boxes.length; i += JoinRules222.perFrame) {
      await send(from, {
        'type': JoinRules222.frameType,
        'op': 'boxes',
        'boxes': boxes.skip(i).take(JoinRules222.perFrame).toList(),
      });
    }
  }

  Future<void> _takeBoxes(List list, String from) async {
    final rows = await _live();
    final known = {for (final r in rows) '${r['box_id']}'};
    var carried = rows.where((r) => r['status'] == 'carry').length;
    var got = 0;
    for (final b in list.whereType<Map>().take(JoinRules222.perFrame * 2)) {
      final id = '${b['box_id'] ?? ''}'.trim();
      final box = '${b['box'] ?? ''}';
      final dev = '${b['from'] ?? ''}'.trim();
      if (id.isEmpty || id.length > 128 || known.contains(id)) continue;
      if (box.length < 80 || box.length > JoinRules222.maxBoxLen || !_b64urlChars.hasMatch(box)) continue;
      if (dev == selfDeviceId()) continue;
      if (carried >= JoinRules222.maxBoxes) break;
      await store.put({
        'box_id': id,
        'from_device': dev,
        'box': box,
        'made_at': _now(),
        'got_at': _now(),
        'status': 'carry',
        'answer': '',
        'extra': jsonEncode({'via': from}),
      });
      known.add(id);
      carried++;
      got++;
    }
    if (got > 0) {
      AppLogger.info('JOIN_BOX_GOT', detail: 'from=${_short(from)} n=$got');
      _changed();
      // Tell the sender (and her phone through it) that this phone has them.
      try {
        await sendHave(from, force: true);
      } catch (_) {}
      unawaited(uploadAll().catchError((Object _) {}));
    }
  }

  /// A server-signed answer: checked with the join note's server key.
  Future<Map<String, dynamic>?> _checkAnswer(Object? a) async {
    if (a is! Map) return null;
    final body = '${a['body'] ?? ''}';
    final sig = '${a['sig'] ?? ''}';
    if (body.isEmpty || body.length > 8192) return null;
    final key = await joinKey();
    final serverKey = pinnedServerKey?.call() ?? '';
    final k = serverKey.isNotEmpty ? serverKey : '${key?['server_key'] ?? ''}';
    if (k.isEmpty) return null;
    if (!await verify(body, sig, k)) return null;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(body) as Map);
      if (m['kind'] != 'join_answer' || '${m['box_id'] ?? ''}'.isEmpty) return null;
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<void> _takeAnswers(List list, String from) async {
    var n = 0;
    for (final a in list.take(JoinRules222.perFrame * 2)) {
      if (await _keepAnswer(a)) n++;
    }
    if (n > 0) _changed();
  }

  /// Keeps a checked answer (drops the box it answers) and, on her phone,
  /// takes it. Returns true when it was new.
  Future<bool> _keepAnswer(Object? a) async {
    final m = await _checkAnswer(a);
    if (m == null) return false;
    final id = '${m['box_id']}';
    final rows = await store.rows();
    final row = rows.where((r) => r['box_id'] == id).firstOrNull;
    if (row != null && '${row['answer']}'.isNotEmpty) return false;
    final info = await _mineInfo();
    final mineNow = info != null && info['box_id'] == id;
    await store.put({
      'box_id': id,
      'from_device': '${m['device_id'] ?? row?['from_device'] ?? ''}',
      'box': '', // the box is not needed any more
      'made_at': '${row?['made_at'] ?? _now()}',
      'got_at': _now(),
      'status': mineNow ? 'mine' : 'done',
      'answer': jsonEncode({'body': (a as Map)['body'], 'sig': a['sig']}),
      'extra': '${row?['extra'] ?? ''}',
    });
    if (mineNow || '${m['device_id']}' == selfDeviceId()) await _take(m);
    return true;
  }

  Future<void> _take(Map<String, dynamic> m) async {
    if (_taking) return;
    final status = '${m['status'] ?? ''}';
    if (status == 'refused') {
      AppLogger.info('JOIN_RELAY_DONE', detail: 'status=refused reason=${m['reason'] ?? ''}');
      final info = await _mineInfo();
      if (info != null) await _writeMine({...info, 'refused': '${m['reason'] ?? ''}'});
      return;
    }
    if (await mine() == null) return; // already on the server by herself
    final tokenBox = '${m['token_box'] ?? ''}';
    if (tokenBox.isEmpty) return;
    _taking = true;
    try {
      final plain = await openBox(tokenBox);
      if (plain == null) return;
      final t = Map<String, dynamic>.from(jsonDecode(utf8.decode(plain)) as Map);
      if ('${t['device_id']}' != selfDeviceId() || '${t['token'] ?? ''}'.isEmpty) return;
      final key = await joinKey();
      AppLogger.info('JOIN_ANSWER_TAKEN', detail: 'status=$status');
      await onTaken(JoinTaken222(
        status: status,
        username: '${m['username'] ?? t['username'] ?? ''}',
        userId: '${m['user_id'] ?? t['user_id'] ?? ''}',
        deviceId: selfDeviceId(),
        token: '${t['token']}',
        expiresAt: '${t['expires_at'] ?? ''}',
        server: '${key?['server'] ?? ''}',
      ));
      final info = await _mineInfo();
      if (info != null) await _writeMine({...info, 'done': true, 'status': status});
      _changed();
    } catch (_) {
      AppLogger.info('JOIN_ANSWER_BAD');
    } finally {
      _taking = false;
    }
  }

  // ------------------------------------------------------------- upload

  Future<void> uploadAll() async {
    final s = server;
    if (s == null || !(serverOnline?.call() ?? false) || _busy) return;
    _busy = true;
    try {
      final rows = await _live();
      var sent = 0;
      for (final r in rows) {
        if ('${r['box']}'.isEmpty || '${r['answer']}'.isNotEmpty) continue;
        if (r['status'] == 'mine') continue; // her own phone online = normal register
        if (sent >= 30) break;
        final id = '${r['box_id']}';
        try {
          final answer = await s.upload(id, '${r['box']}');
          sent++;
          AppLogger.info('JOIN_RELAY_UPLOADED', detail: 'box=${_short(id)}');
          final m = await _checkAnswer(answer);
          AppLogger.info('JOIN_RELAY_DONE', detail: 'status=${m?['status'] ?? 'bad'}');
          if (m != null) await _keepAnswer(answer);
        } catch (e) {
          AppLogger.info('JOIN_RELAY_FAIL', detail: 'box=${_short(id)} reason=${_reason(e)}');
          if ('$e'.contains('BAD_JOIN_BOX')) {
            await store.delete([id]);
          }
          if ('$e'.contains('429')) break;
        }
      }
      if (sent > 0) {
        _changed();
        for (final p in await linkedPeers()) {
          unawaited(sendHave(p, force: true).catchError((Object _) {}));
        }
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> tick() async {
    if (serverOnline?.call() ?? false) {
      try {
        await refreshKey();
      } catch (_) {}
      await uploadAll();
    }
    await _makeMine();
  }

  static final RegExp _b64urlChars = RegExp(r'^[A-Za-z0-9_-]+$');
  static String _short(String id) => id.length <= 8 ? id : id.substring(id.length - 8);
  static String _reason(Object e) {
    final t = '$e';
    for (final c in ['BAD_JOIN_BOX', 'RATE_LIMIT', '401', '429', 'Timeout']) {
      if (t.contains(c)) return c;
    }
    return 'other';
  }
}

/// The real server calls (`internal/httpapi/join_relay_222.go`, `trust.go`).
class HttpJoinServer222 implements JoinServer222 {
  HttpJoinServer222({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceToken,
    http.Client? client,
  }) : _client = BuildHeaderClient(client ?? http.Client());

  final String Function() baseUrl;
  final String Function() deviceId;
  final String Function() deviceToken;
  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<Map<String, dynamic>?> trust() async {
    if (baseUrl().isEmpty) return null;
    final r = await _client.get(Uri.parse('${baseUrl()}/api/v1/trust')).timeout(_timeout);
    if (r.statusCode != 200) return null;
    final d = jsonDecode(r.body);
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  @override
  Future<Map<String, dynamic>> upload(String boxId, String box) async {
    if (baseUrl().isEmpty) throw Exception('no server');
    final r = await _client
        .post(Uri.parse('${baseUrl()}/api/v1/auth/join-relay'),
            headers: {
              'Authorization': 'Bearer ${deviceToken()}',
              'X-Device-ID': deviceId(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'box_id': boxId, 'box': box}))
        .timeout(_timeout);
    if (r.statusCode != 200) {
      var code = '';
      try {
        code = '${(jsonDecode(r.body) as Map)['error_code'] ?? ''}';
      } catch (_) {}
      throw Exception('join-relay ${r.statusCode} $code');
    }
    final d = jsonDecode(r.body);
    final a = d is Map ? d['answer'] : null;
    if (a is! Map) throw Exception('join-relay no answer');
    return Map<String, dynamic>.from(a);
  }
}
