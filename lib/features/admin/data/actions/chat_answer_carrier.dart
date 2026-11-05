import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/admin_action_card.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';

/// Bundle 221: answer parts travel like the 220 cards - to the server when
/// online, and phone to phone (Wi-Fi Direct / same router / mesh) to every
/// linked phone, friends or not. A carrier says "I carry parts 1-40 of 80"
/// (its `have` list), never "stop". Only the server or the admin's phone
/// sends the real stop: a signed `answer_ack` with `all:true`. A partial ack
/// tells carriers which parts the admin side already has, so the next phone
/// only brings the missing ones.
class HeldPart {
  final String answerId;
  final int part;
  final int of;
  final String actionId;
  final String device; // the phone that built the answer
  final String replyTo; // 'server' or the admin phone's device id
  final bool isFile;
  final SignedBlob blob;
  final bool own;
  final String at;

  const HeldPart({
    required this.answerId,
    required this.part,
    required this.of,
    required this.actionId,
    required this.device,
    required this.replyTo,
    required this.isFile,
    required this.blob,
    required this.own,
    required this.at,
  });

  int get size => blob.body.length + blob.sig.length;

  /// Reads a part blob (no signature check here). Null = not a part.
  static HeldPart? fromBlob(SignedBlob blob, {bool own = false, String at = ''}) {
    if (blob.body.length > ChatAnswerCarrier.maxPartBytes) return null;
    final f = blob.fields;
    if (f == null || f['kind'] != 'admin_answer_part' || f['v'] != 1) return null;
    String s(String k) => f[k]?.toString() ?? '';
    int n(String k) => f[k] is int ? f[k] as int : int.tryParse(s(k)) ?? 0;
    final p = HeldPart(
      answerId: s('answer_id'),
      part: n('part'),
      of: n('of'),
      actionId: s('action_id'),
      device: s('device'),
      replyTo: s('reply_to'),
      isFile: f['is_file'] == true,
      blob: blob,
      own: own,
      at: at,
    );
    if (p.answerId.isEmpty || p.actionId.isEmpty || p.device.isEmpty) return null;
    if (p.of < 1 || p.of > ChatAnswerRules.maxParts || p.part < 1 || p.part > p.of) return null;
    if (ChatAnswerBuilder.sha256Hex(s('data')) != s('sha256')) return null;
    return p;
  }
}

/// A checked ack (server- or admin-signed).
class AnswerAck {
  final String answerId;
  final String actionId;
  final Set<int> have;
  final int of;
  final bool all;
  final String at;
  final Map<String, dynamic> raw; // {body, sig, cert?} as it travels

  const AnswerAck({
    required this.answerId,
    required this.actionId,
    required this.have,
    required this.of,
    required this.all,
    required this.at,
    required this.raw,
  });

  static Map<String, dynamic>? fieldsOf(Object? raw) {
    if (raw is! Map) return null;
    try {
      final f = jsonDecode(raw['body']?.toString() ?? '');
      if (f is! Map || f['kind'] != 'answer_ack' || f['v'] != 1) return null;
      return Map<String, dynamic>.from(f);
    } catch (_) {
      return null;
    }
  }

  static String newBody({
    required String answerId,
    required String actionId,
    required Set<int> have,
    required int of,
    required DateTime at,
  }) =>
      jsonEncode({
        'v': 1,
        'kind': 'answer_ack',
        'answer_id': answerId,
        'action_id': actionId,
        'have': PartRanges.write(have),
        'of': of,
        'all': of > 0 && have.length >= of,
        'at': at.toUtc().toIso8601String(),
      });
}

/// "1-40,42" <-> {1..40, 42}.
abstract final class PartRanges {
  static Set<int> read(String s, {int max = ChatAnswerRules.maxParts}) {
    final out = <int>{};
    for (final piece in s.split(',')) {
      final t = piece.trim();
      if (t.isEmpty) continue;
      final ab = t.split('-');
      final a = int.tryParse(ab.first.trim()) ?? 0;
      final b = ab.length > 1 ? int.tryParse(ab[1].trim()) ?? 0 : a;
      if (a < 1 || b < a || b > max) continue;
      for (var i = a; i <= b; i++) {
        out.add(i);
      }
    }
    return out;
  }

  static String write(Iterable<int> parts) {
    final list = parts.toSet().toList()..sort();
    final out = <String>[];
    var i = 0;
    while (i < list.length) {
      var j = i;
      while (j + 1 < list.length && list[j + 1] == list[j] + 1) {
        j++;
      }
      out.add(i == j ? '${list[i]}' : '${list[i]}-${list[j]}');
      i = j + 1;
    }
    return out.join(',');
  }
}

/// Where parts, acks and stops are kept (SQL on the phone).
abstract class AnswerPartStore {
  Future<bool> put(HeldPart p); // false when it was there already
  Future<List<HeldPart>> parts({String? answerId});
  Future<void> remove(String answerId, Iterable<int> parts);

  /// Drops the parts of an answer except the ones kept for [keepFor].
  Future<void> dropAnswer(String answerId, {String keepFor = ''});
  Future<void> stop(String answerId, String actionId, String at);
  Future<Set<String>> stops();
  Future<void> saveAck(AnswerAck ack);
  Future<Map<String, AnswerAck>> acks();
}

class MemoryAnswerPartStore implements AnswerPartStore {
  final Map<String, HeldPart> _parts = <String, HeldPart>{};
  final Map<String, String> _stops = <String, String>{};
  final Map<String, AnswerAck> _acks = <String, AnswerAck>{};

  @override
  Future<bool> put(HeldPart p) async {
    final k = '${p.answerId}#${p.part}';
    if (_parts.containsKey(k)) return false;
    _parts[k] = p;
    return true;
  }

  @override
  Future<List<HeldPart>> parts({String? answerId}) async => [
        for (final p in _parts.values)
          if (answerId == null || p.answerId == answerId) p,
      ];

  @override
  Future<void> remove(String answerId, Iterable<int> parts) async {
    for (final n in parts) {
      _parts.remove('$answerId#$n');
    }
  }

  @override
  Future<void> dropAnswer(String answerId, {String keepFor = ''}) async =>
      _parts.removeWhere((_, p) =>
          p.answerId == answerId && (keepFor.isEmpty || p.replyTo != keepFor));

  @override
  Future<void> stop(String answerId, String actionId, String at) async =>
      _stops[answerId] = at;

  @override
  Future<Set<String>> stops() async => _stops.keys.toSet();

  @override
  Future<void> saveAck(AnswerAck ack) async => _acks[ack.answerId] = ack;

  @override
  Future<Map<String, AnswerAck>> acks() async => Map.of(_acks);
}

/// The phone endpoints (device auth).
abstract class ChatAnswerServer {
  /// Uploads parts; returns the server's signed acks (`{body, sig}`).
  Future<List<Map<String, dynamic>>> upload({
    required List<SignedBlob> parts,
    required List<String> have,
    required String signingKey,
  });

  /// Parts of this admin phone's own (offline) requests.
  Future<({List<SignedBlob> parts, bool more})> fetch(Map<String, String> have);
}

class HttpChatAnswerServer implements ChatAnswerServer {
  HttpChatAnswerServer({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceToken,
    http.Client? client,
  }) : _client = BuildHeaderClient(client ?? http.Client());

  final String Function() baseUrl;
  final String Function() deviceId;
  final String Function() deviceToken;
  final http.Client _client;

  Map<String, String> get _device => {
        'Authorization': 'Bearer ${deviceToken()}',
        'X-Device-ID': deviceId(),
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) {
    final base = baseUrl();
    if (base.isEmpty) throw Exception('no server');
    return Uri.parse('$base$path');
  }

  Map<String, dynamic> _ok(http.Response r) {
    if (r.statusCode != 200) throw Exception('server ${r.statusCode}');
    final d = jsonDecode(r.body);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  @override
  Future<List<Map<String, dynamic>>> upload({
    required List<SignedBlob> parts,
    required List<String> have,
    required String signingKey,
  }) async {
    final r = await _client
        .post(_uri('/api/v1/admin-actions/answers'),
            headers: _device,
            body: jsonEncode({
              'parts': [for (final b in parts) b.toJson()],
              'have': have,
              'signing_key': signingKey,
            }))
        .timeout(const Duration(seconds: 40));
    return [
      for (final a in (_ok(r)['acks'] as List? ?? const []))
        if (a is Map) Map<String, dynamic>.from(a),
    ];
  }

  @override
  Future<({List<SignedBlob> parts, bool more})> fetch(Map<String, String> have) async {
    final r = await _client
        .post(_uri('/api/v1/admin-actions/answers/fetch'),
            headers: _device, body: jsonEncode({'have': have}))
        .timeout(const Duration(seconds: 60));
    final body = _ok(r);
    return (
      parts: [
        for (final b in (body['parts'] as List? ?? const []))
          if (SignedBlob.fromJson(b) case final SignedBlob s) s,
      ],
      more: body['more'] == true,
    );
  }
}

/// Progress the Admin actions list shows (only confirmed parts).
typedef AnswerProgress = ({int have, int of, bool all});

class ChatAnswerCarrier {
  static const int maxPartBytes = 64 * 1024;
  static const int capOthers = 20 * 1024 * 1024;
  static const int perMeeting = 40;
  static const int perMeetingAdmin = 400;
  static const int uploadBatchBytes = 6 * 1024 * 1024;
  static const Duration haveEvery = Duration(seconds: 60);

  static ChatAnswerCarrier? instance;

  /// Confirmed parts per request (action id), for Admin actions:
  /// "40 of 80 parts · the rest is on the way".
  static final ValueNotifier<Map<String, AnswerProgress>> progress =
      ValueNotifier<Map<String, AnswerProgress>>(const {});

  /// True while a chat request's answer is still coming (Pending tab).
  static bool partsPending(String actionId) {
    final p = progress.value[actionId];
    return p != null && !p.all;
  }

  final AnswerPartStore store;
  final String Function() selfDeviceId;
  final Future<void> Function(String peerId, Map<String, dynamic> payload) send;
  final Stream<Map<String, dynamic>> events;
  final Future<List<String>> Function() linkedPeers;
  final String? Function() serverKey;
  final Set<String> Function() endedCerts;
  final Future<bool> Function(String body, String sig, String key) verify;
  final Future<String> Function(String device) signingKeyOf;
  final Future<String> Function() signingKey;
  final ChatAnswerServer? server;
  final bool Function()? serverOnline;

  /// Admin phone only: signs an ack and gives `{body, sig, cert}` (null when
  /// this phone has no usable admin cert).
  final Future<Map<String, dynamic>?> Function(String body)? signAdminAck;

  /// True on a phone with a usable admin cert (it fetches its own answers).
  final Future<bool> Function()? isAdminPhone;

  /// Admin phone: a new part of an answer meant for this phone arrived.
  final void Function(String actionId)? onMine;
  final void Function()? onChanged;
  final DateTime Function() _clock;

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _timer;
  bool _uploading = false;
  final Map<String, DateTime> _haveSentAt = <String, DateTime>{};

  ChatAnswerCarrier({
    required this.store,
    required this.selfDeviceId,
    required this.send,
    required this.events,
    required this.linkedPeers,
    required this.serverKey,
    required this.endedCerts,
    required this.verify,
    required this.signingKeyOf,
    required this.signingKey,
    this.server,
    this.serverOnline,
    this.signAdminAck,
    this.isAdminPhone,
    this.onMine,
    this.onChanged,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  String _now() => _clock().toUtc().toIso8601String();

  void _changed() {
    unawaited(refreshProgress().catchError((_) {}));
    onChanged?.call();
  }

  /// Recounts [progress] from the acks + the parts this admin phone holds.
  Future<void> refreshProgress() async {
    final ids = <String>{
      for (final a in (await store.acks()).values) a.actionId,
      for (final p in await store.parts()) if (_isMine(p)) p.actionId,
    }..remove('');
    final out = <String, AnswerProgress>{};
    for (final id in ids) {
      final p = await progressOf(id);
      if (p != null) out[id] = p;
    }
    progress.value = out;
  }

  void start() {
    _sub ??= events.listen((e) => unawaited(handleEvent(e).catchError((_) {})));
    _timer ??= Timer.periodic(haveEvery, (_) => unawaited(tick().catchError((_) {})));
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick() async {
    for (final peer in await linkedPeers()) {
      await sendHave(peer);
    }
    await syncWithServer();
  }

  bool _isMine(HeldPart p) => p.replyTo.isNotEmpty && p.replyTo == selfDeviceId();

  // --------------------------------------------------------------- the target

  /// The target phone built an answer: keep it until the stop and send it.
  Future<void> addOwn(List<ChatAnswerPart> parts, {required String replyTo, bool isFile = false}) async {
    final at = _now();
    for (final p in parts) {
      final h = HeldPart.fromBlob(p.blob, own: true, at: at);
      if (h != null) await store.put(h);
    }
    AppLogger.info('ADMIN_ANSWER_BUILT',
        detail: 'parts=${parts.length} file=$isFile to=${replyTo == 'server' ? 'server' : 'admin_phone'}');
    _changed();
    unawaited(syncWithServer().catchError((_) {}));
    for (final peer in await linkedPeers().catchError((_) => <String>[])) {
      unawaited(sendHave(peer, force: true).catchError((_) {}));
    }
  }

  // -------------------------------------------------------------- taking

  /// A part from a phone or the server. True when kept.
  Future<bool> takePart(SignedBlob blob, {String from = ''}) async {
    final p = HeldPart.fromBlob(blob, at: _now());
    if (p == null) return false;
    if ((await store.stops()).contains(p.answerId) && !_isMine(p)) return false;
    final acks = await store.acks();
    final ack = acks[p.answerId];
    if (ack != null && (ack.all || ack.have.contains(p.part)) && !_isMine(p)) return false;
    if (p.device != selfDeviceId()) {
      final key = await signingKeyOf(p.device).catchError((_) => '');
      if (key.isNotEmpty && !await verify(blob.body, blob.sig, key)) {
        AppLogger.warning('ADMIN_ANSWER_BAD_SIG', detail: 'from=$from');
        return false;
      }
    }
    if (!_isMine(p)) {
      // A full file only goes to the admin's phone (or the server).
      if (p.isFile) return false;
      final held = await store.parts();
      final others = held.where((h) => !h.own && !_isMine(h)).fold<int>(0, (n, h) => n + h.size);
      if (others + p.size > capOthers) {
        AppLogger.info('ADMIN_ANSWER_CAP_FULL', detail: 'held=$others');
        return false;
      }
    }
    final added = await store.put(p);
    if (!added) return false;
    if (_isMine(p)) {
      onMine?.call(p.actionId);
      await _ackMine(p.answerId);
    }
    _changed();
    return true;
  }

  /// Admin phone: signs what it has; `all` = the real stop.
  Future<void> _ackMine(String answerId) async {
    final sign = signAdminAck;
    if (sign == null) return;
    final mine = (await store.parts(answerId: answerId)).where(_isMine).toList();
    if (mine.isEmpty) return;
    final have = {for (final p in mine) p.part};
    final of = mine.first.of;
    final body = AnswerAck.newBody(
        answerId: answerId, actionId: mine.first.actionId, have: have, of: of, at: _clock());
    final raw = await sign(body).catchError((_) => null);
    if (raw == null) return;
    final ack = await checkAck(raw);
    if (ack == null) return;
    await _applyAck(ack);
    // Tell the phones near me now (so they stop / skip these parts).
    if (ack.all || have.length % 20 == 0) {
      for (final peer in await linkedPeers().catchError((_) => <String>[])) {
        unawaited(send(peer, {'type': ChatAnswerRules.partsType, 'op': 'acks', 'acks': [ack.raw]})
            .catchError((_) {}));
      }
    }
  }

  /// Server ack `{body, sig}` (server key) or admin-phone ack
  /// `{body, sig, cert}` (cert signed by the server, not ended, Owner).
  Future<AnswerAck?> checkAck(Object? raw) async {
    final f = AnswerAck.fieldsOf(raw);
    if (f == null || raw is! Map) return null;
    final key = serverKey();
    if (key == null || key.isEmpty) return null;
    final body = raw['body'].toString();
    final sig = raw['sig']?.toString() ?? '';
    final certBlob = SignedBlob.fromJson(raw['cert']);
    if (certBlob == null) {
      if (!await verify(body, sig, key)) return null;
    } else {
      if (!await verify(certBlob.body, certBlob.sig, key)) return null;
      final cert = AdminCert.fromBlob(certBlob);
      if (cert == null || endedCerts().contains(cert.certId)) return null;
      if (!AdminActionRules.roleCan(cert.role, 'get_chat')) return null;
      if (!await verify(body, sig, cert.signingKey)) return null;
    }
    String s(String k) => f[k]?.toString() ?? '';
    final of = f['of'] is int ? f['of'] as int : int.tryParse(s('of')) ?? 0;
    final have = PartRanges.read(s('have'));
    return AnswerAck(
      answerId: s('answer_id'),
      actionId: s('action_id'),
      have: have,
      of: of,
      all: f['all'] == true || (of > 0 && have.length >= of),
      at: s('at'),
      raw: {
        'body': body,
        'sig': sig,
        if (certBlob != null) 'cert': certBlob.toJson(),
      },
    );
  }

  Future<bool> takeAck(Object? raw) async {
    final ack = await checkAck(raw);
    if (ack == null || ack.answerId.isEmpty) return false;
    final old = (await store.acks())[ack.answerId];
    if (old != null && (old.all || (!ack.all && old.have.length >= ack.have.length))) return false;
    await _applyAck(ack);
    return true;
  }

  Future<void> _applyAck(AnswerAck ack) async {
    final old = (await store.acks())[ack.answerId];
    if (old == null || ack.all || ack.have.length >= old.have.length) await store.saveAck(ack);
    if (ack.all) {
      await store.stop(ack.answerId, ack.actionId, _now());
      await store.dropAnswer(ack.answerId, keepFor: selfDeviceId());
      AppLogger.info('ADMIN_ANSWER_STOP', detail: 'parts=${ack.of}');
    } else {
      final held = await store.parts(answerId: ack.answerId);
      await store.remove(ack.answerId,
          [for (final p in held) if (ack.have.contains(p.part) && !_isMine(p)) p.part]);
    }
    _changed();
  }

  // ------------------------------------------------------------ phone frames

  /// "I carry parts 1-40 of 80" for every answer + the acks I know.
  Future<Map<String, dynamic>> haveFrame() async {
    final held = await store.parts();
    final by = <String, List<HeldPart>>{};
    for (final p in held) {
      (by[p.answerId] ??= <HeldPart>[]).add(p);
    }
    final acks = await store.acks();
    return {
      'type': ChatAnswerRules.partsType,
      'op': 'have',
      'answers': {
        for (final e in by.entries)
          e.key: {
            'action': e.value.first.actionId,
            'of': e.value.first.of,
            'have': PartRanges.write(e.value.map((p) => p.part)),
          },
      },
      'acks': [for (final a in acks.values.take(100)) a.raw],
    };
  }

  Future<void> sendHave(String peer, {bool force = false}) async {
    final last = _haveSentAt[peer];
    if (!force && last != null && _clock().difference(last) < const Duration(seconds: 30)) return;
    _haveSentAt[peer] = _clock();
    await send(peer, await haveFrame());
  }

  /// Same event shape the 220 service reads (`message` with a JSON
  /// `payload` string + `sender_id`; `peer_connected` with `peer_id`).
  Future<void> handleEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();
    if (type == 'peer_connected') {
      final peer = event['peer_id']?.toString() ?? '';
      if (peer.isNotEmpty) await sendHave(peer, force: true);
      return;
    }
    if (type != 'message') return;
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains(ChatAnswerRules.partsType)) return;
    Map<String, dynamic> msg;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return;
      msg = Map<String, dynamic>.from(d);
    } catch (_) {
      return;
    }
    if (msg['type'] != ChatAnswerRules.partsType) return;
    final from = event['sender_id']?.toString() ?? '';
    if (from.isEmpty || from == selfDeviceId()) return;
    await handleFrame(msg, from: from);
  }

  Future<void> handleFrame(Map<String, dynamic> msg, {required String from}) async {
    for (final a in (msg['acks'] as List? ?? const []).take(200)) {
      await takeAck(a);
    }
    switch (msg['op']) {
      case 'parts':
        for (final b in (msg['parts'] as List? ?? const []).take(5)) {
          final blob = SignedBlob.fromJson(b);
          if (blob != null) await takePart(blob, from: from);
        }
      case 'have':
        final answers = msg['answers'];
        if (from.isNotEmpty) {
          await _sendMissing(from, answers is Map ? Map<String, dynamic>.from(answers) : const {});
        }
    }
  }

  /// Sends the peer parts it lacks and the admin side doesn't have yet
  /// (one part per frame, up to 40 per meeting; all for the admin phone).
  Future<int> _sendMissing(String peer, Map<String, dynamic> theirs) async {
    final held = await store.parts();
    final acks = await store.acks();
    final stops = await store.stops();
    var sent = 0;
    final byAnswer = <String, List<HeldPart>>{};
    for (final p in held) {
      if (stops.contains(p.answerId) && !p.own) continue;
      final ack = acks[p.answerId];
      if (ack != null && (ack.all || ack.have.contains(p.part))) continue;
      (byAnswer[p.answerId] ??= <HeldPart>[]).add(p);
    }
    for (final e in byAnswer.entries) {
      final their = theirs[e.key];
      final has = their is Map ? PartRanges.read(their['have']?.toString() ?? '') : <int>{};
      final toAdmin = e.value.first.replyTo == peer;
      // A full file: only to the admin's phone.
      if (e.value.first.isFile && !toAdmin) continue;
      final limit = toAdmin ? perMeetingAdmin : perMeeting;
      final list = e.value.where((p) => !has.contains(p.part)).toList()
        ..sort((a, b) => a.part.compareTo(b.part));
      for (final p in list) {
        if (sent >= limit) break;
        try {
          await send(peer, {'type': ChatAnswerRules.partsType, 'op': 'parts', 'parts': [p.blob.toJson()]});
          sent++;
        } catch (_) {
          return sent; // link gone: the next meeting goes on
        }
      }
    }
    if (sent > 0) AppLogger.info('ADMIN_ANSWER_PARTS_SENT', detail: 'parts=$sent');
    return sent;
  }

  // ------------------------------------------------------------------ server

  Future<void> syncWithServer() async {
    final srv = server;
    if (srv == null || _uploading || !(serverOnline?.call() ?? true)) return;
    _uploading = true;
    try {
      final held = await store.parts();
      final acks = await store.acks();
      final stops = await store.stops();
      final send = <SignedBlob>[];
      var size = 0;
      final ids = <String>{};
      for (final p in held) {
        if (_isMine(p)) continue;
        ids.add(p.answerId);
        if (stops.contains(p.answerId)) continue;
        final ack = acks[p.answerId];
        if (ack != null && (ack.all || ack.have.contains(p.part))) continue;
        if (size + p.size > uploadBatchBytes || send.length >= 200) continue;
        size += p.size;
        send.add(p.blob);
      }
      if (send.isNotEmpty || ids.isNotEmpty) {
        final got = await srv.upload(parts: send, have: ids.toList(), signingKey: await signingKey());
        for (final a in got) {
          await takeAck(a);
        }
        if (send.isNotEmpty) AppLogger.info('ADMIN_ANSWER_UPLOADED', detail: 'parts=${send.length}');
      }
      if (signAdminAck != null && (await isAdminPhone?.call() ?? false)) await _fetchMine(srv);
    } catch (error) {
      AppLogger.info('ADMIN_ANSWER_SERVER_LATER', detail: '$error');
    } finally {
      _uploading = false;
    }
  }

  /// Admin phone: parts of its own offline requests kept by the server.
  Future<void> _fetchMine(ChatAnswerServer srv) async {
    for (var round = 0; round < 10; round++) {
      final mine = (await store.parts()).where(_isMine);
      final have = <String, Set<int>>{};
      for (final p in mine) {
        (have[p.answerId] ??= <int>{}).add(p.part);
      }
      final got = await srv.fetch({for (final e in have.entries) e.key: PartRanges.write(e.value)});
      for (final b in got.parts) {
        await takePart(b, from: 'server');
      }
      if (!got.more || got.parts.isEmpty) break;
    }
  }

  // ------------------------------------------------------------------- views

  /// Confirmed parts of the best answer of a card (server / admin phone).
  Future<AnswerProgress?> progressOf(String actionId) async {
    AnswerProgress? best;
    for (final a in (await store.acks()).values) {
      if (a.actionId != actionId) continue;
      if (best == null || a.all || a.have.length > best.have) {
        best = (have: a.all ? a.of : a.have.length, of: a.of, all: a.all);
      }
    }
    if (best == null) {
      // The admin's phone counts what it holds itself.
      final mine = (await store.parts()).where((p) => p.actionId == actionId && _isMine(p));
      final by = <String, Set<int>>{};
      var of = 0;
      for (final p in mine) {
        (by[p.answerId] ??= <int>{}).add(p.part);
        of = p.of;
      }
      if (by.isNotEmpty) {
        final n = by.values.map((s) => s.length).reduce((a, b) => a > b ? a : b);
        best = (have: n, of: of, all: n >= of);
      }
    }
    return best;
  }

  /// "I carry 1-40 of 80" lines for the carrier's own view (logs / tests).
  Future<Map<String, String>> carrying() async {
    final by = <String, List<HeldPart>>{};
    for (final p in await store.parts()) {
      (by[p.answerId] ??= <HeldPart>[]).add(p);
    }
    return {
      for (final e in by.entries)
        e.key: '${PartRanges.write(e.value.map((p) => p.part))} of ${e.value.first.of}',
    };
  }
}
