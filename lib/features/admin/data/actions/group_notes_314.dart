import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as digest;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart' show SignedBlob;

/// Bundle 314 (1c): nearby group notes.
///
/// A group made on phones (not on the server) is invisible to the Owner, so
/// it could never be asked. Every member phone now sends a small SIGNED note
/// per phone-only group it is in: `{t, v, gid, name, members, made_at,
/// from, at}` - no messages, no keys. The Owner then sees "Study group ·
/// Nearby · 4 members" and can ask it like any group; the card goes to the
/// member phones of the note and a phone only answers for a group it is
/// really in (a fake note can't leak anything).
///
/// Where the note goes (each way on its own):
/// - the server, `POST /api/v1/admin/group-notes` (device sign-in). An old
///   server answers 404: the note is kept and tried again the next day;
/// - the Owner's phone, inside the Owner's lock only ([sendLocked], never
///   plain), when it is linked. The Owner's phones come from the crown
///   cards ([ownerPhones]).
///
/// Sent again when the name or the members change, otherwise at most once a
/// day. It runs while the app runs - also in the background while the
/// LinkUp keep-alive service holds the app (no new permission and no new
/// notification). Nothing is sent when the phone killed or force-stopped
/// the app, or keep-alive is off.
class GroupNotes314 {
  GroupNotes314({
    required this.selfDeviceId,
    required this.myGroups,
    required this.sign,
    required this.events,
    required this.read,
    required this.write,
    this.post,
    this.serverOnline,
    this.ownerPhones,
    this.canReach,
    this.sendLocked,
    this.isOwnerPhone,
    this.signingKeyOf,
    this.verify,
    this.groupChanges,
    DateTime Function()? clock,
    this.every = const Duration(minutes: 15),
  }) : _clock = clock ?? DateTime.now;

  static GroupNotes314? instance;

  static const String noteType = 'group_note_314';
  static const String packetType = 'group_notes_314';
  static const String sentKey = 'group_notes_sent_314';
  static const String gotKey = 'group_notes_got_314';

  /// Same note again at most this often (a change goes out at once).
  static const Duration resendAfter = Duration(hours: 24);

  /// An old server (404) is asked again after this.
  static const Duration oldServerWait = Duration(hours: 24);

  /// Notes kept on the Owner's phone this long.
  static const Duration keepFor = Duration(days: 60);
  static const int maxGot = 500;
  static const int maxMembers = 256;
  static const int maxPerPost = 50;
  static const int maxName = 100;

  final String Function() selfDeviceId;

  /// The phone-only groups this phone is in: `{id, name, members, made_at}`
  /// (members = phone ids, this phone included).
  final Future<List<Map<String, dynamic>>> Function() myGroups;

  /// Signs the exact body with this phone's signing key (base64url).
  final Future<String> Function(String body) sign;

  /// Transport events (opened locked messages + link events).
  final Stream<Map<String, dynamic>> events;
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;

  /// Server upload. Returns the HTTP status (200 = taken, 404 = old server).
  final Future<int> Function(List<SignedBlob> notes)? post;
  final bool Function()? serverOnline;

  /// The Owner's phones (crown cards + directory).
  final Future<List<String>> Function()? ownerPhones;

  /// The phone is linked now (nearby / mesh) - nothing is queued.
  final bool Function(String peerId)? canReach;

  /// Inside the peer's lock ONLY (false = not sent; never plain).
  final Future<bool> Function(String to, Map<String, dynamic> payload)? sendLocked;

  /// This phone is the Owner's: it keeps the notes it gets.
  final Future<bool> Function()? isOwnerPhone;
  final Future<String> Function(String deviceId)? signingKeyOf;
  final Future<bool> Function(String body, String sig, String key)? verify;
  final Stream<String>? groupChanges;
  final DateTime Function() _clock;
  final Duration every;

  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<String>? _changeSub;
  Timer? _timer;
  bool _started = false;
  bool _running = false;
  bool _again = false;
  Future<void> _chain = Future<void>.value();

  /// The reported groups changed (the Owner's lists read them again).
  final ValueNotifier<int> changed = ValueNotifier<int>(0);

  void start() {
    if (_started) return;
    _started = true;
    _sub = events.listen(onEvent, onError: (Object _) {});
    _changeSub = groupChanges?.listen((_) => kick(), onError: (Object _) {});
    _timer = Timer.periodic(every, (_) => kick());
    kick();
  }

  Future<void> stop() async {
    _started = false;
    await _sub?.cancel();
    await _changeSub?.cancel();
    _sub = null;
    _changeSub = null;
    _timer?.cancel();
    _timer = null;
  }

  /// Look again now (a group changed, the server came back, a peer linked).
  void kick() {
    if (_running) {
      _again = true;
      return;
    }
    unawaited(tick().catchError((Object e) {
      AppLogger.warning('GROUP_NOTE_TICK_FAILED', detail: '$e');
    }));
  }

  // ------------------------------------------------------------- sending

  /// The note body of one group (members sorted, so the same group gives
  /// the same body apart from `at`).
  @visibleForTesting
  static Map<String, dynamic> noteOf(Map<String, dynamic> g, String self, DateTime at) {
    final members = <String>{
      for (final m in (g['members'] as List? ?? const [])) m.toString().trim(),
    }.where((m) => m.isNotEmpty && m.length <= 128).toList()
      ..sort();
    var name = (g['name']?.toString() ?? '').trim();
    if (name.runes.length > maxName) name = String.fromCharCodes(name.runes.take(maxName));
    return {
      't': noteType,
      'v': 1,
      'gid': g['id']?.toString() ?? '',
      'name': name,
      'members': members.take(maxMembers).toList(),
      'made_at': g['made_at']?.toString() ?? '',
      'from': self,
      'at': at.toUtc().toIso8601String(),
    };
  }

  /// What a change is measured by: name + members + made_at.
  @visibleForTesting
  static String hashOf(Map<String, dynamic> note) => digest.sha256
      .convert(utf8.encode(jsonEncode([note['gid'], note['name'], note['members'], note['made_at']])))
      .toString()
      .substring(0, 16);

  Future<Map<String, dynamic>> _sent() async {
    try {
      final d = jsonDecode(await read(sentKey) ?? '{}');
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  bool _due(Map<String, dynamic>? last, String hash, DateTime now) {
    if (last == null || last['h'] != hash) return true;
    final at = DateTime.tryParse(last['at']?.toString() ?? '');
    return at == null || now.difference(at) >= resendAfter || now.isBefore(at.subtract(const Duration(hours: 1)));
  }

  /// One round: every due note to the server and to the Owner's phones.
  @visibleForTesting
  Future<void> tick() async {
    if (_running) return;
    _running = true;
    try {
      do {
        _again = false;
        await _round();
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<void> _round() async {
    final self = selfDeviceId();
    if (self.isEmpty) return;
    final now = _clock();
    final groups = await myGroups().catchError((_) => <Map<String, dynamic>>[]);
    final notes = <String, Map<String, dynamic>>{};
    for (final g in groups) {
      final n = noteOf(g, self, now);
      if ((n['gid'] as String).isEmpty || (n['name'] as String).isEmpty) continue;
      if (!(n['members'] as List).contains(self)) continue; // only a member reports
      notes[n['gid'] as String] = n;
    }
    final sent = await _sent();
    // Groups I left: forget them.
    sent.removeWhere((k, _) => !k.startsWith('_') && !notes.containsKey(k));
    if (notes.isEmpty) {
      await write(sentKey, jsonEncode(sent));
      return;
    }
    var dirty = false;

    // 1. The server.
    final up = post;
    final oldAt = DateTime.tryParse(sent['_old_server']?.toString() ?? '');
    final oldWait = oldAt != null && now.difference(oldAt) < oldServerWait && !now.isBefore(oldAt);
    if (up != null && (serverOnline?.call() ?? false) && !oldWait) {
      final due = [
        for (final n in notes.values)
          if (_due(_way(sent, n['gid'] as String, 's'), hashOf(n), now)) n,
      ];
      for (var i = 0; i < due.length; i += maxPerPost) {
        final batch = due.sublist(i, (i + maxPerPost).clamp(0, due.length));
        final blobs = [for (final n in batch) await _signed(n)];
        int status;
        try {
          status = await up(blobs);
        } catch (e) {
          AppLogger.info('GROUP_NOTE_SERVER_LATER', detail: '$e');
          break;
        }
        if (status == 404) {
          // An old server: keep the notes, ask again tomorrow.
          sent['_old_server'] = now.toUtc().toIso8601String();
          dirty = true;
          AppLogger.info('GROUP_NOTE_OLD_SERVER');
          break;
        }
        if (status != 200) break;
        sent.remove('_old_server');
        for (final n in batch) {
          _mark(sent, n, 's', now);
        }
        dirty = true;
        AppLogger.info('GROUP_NOTE_SERVER_SENT', detail: 'n=${batch.length}');
      }
    }

    // 2. The Owner's phones (locked only, linked now).
    final send = sendLocked;
    final owners = send == null ? const <String>[] : await (ownerPhones?.call() ?? Future.value(const <String>[]))
        .catchError((_) => const <String>[]);
    for (final owner in owners.toSet()) {
      if (owner.isEmpty || owner == self) continue;
      if (!(canReach?.call(owner) ?? false)) continue;
      final due = [
        for (final n in notes.values)
          // The Owner is in this group: it is on the Owner's phone already.
          if (!(n['members'] as List).contains(owner) && _due(_way(sent, n['gid'] as String, 'o:$owner'), hashOf(n), now))
            n,
      ];
      if (due.isEmpty) continue;
      final blobs = [for (final n in due.take(maxPerPost)) await _signed(n)];
      final ok = await send!(owner, {
        'type': packetType,
        'notes': [for (final b in blobs) b.toJson()],
      }).catchError((_) => false);
      if (!ok) continue;
      for (final n in due.take(maxPerPost)) {
        _mark(sent, n, 'o:$owner', now);
      }
      dirty = true;
      AppLogger.info('GROUP_NOTE_OWNER_SENT', detail: 'n=${blobs.length}');
    }
    if (dirty) await write(sentKey, jsonEncode(sent));
  }

  Map<String, dynamic>? _way(Map<String, dynamic> sent, String gid, String way) {
    final g = sent[gid];
    if (g is! Map) return null;
    final w = g[way];
    return w is Map ? Map<String, dynamic>.from(w) : null;
  }

  void _mark(Map<String, dynamic> sent, Map<String, dynamic> n, String way, DateTime now) {
    final gid = n['gid'] as String;
    final g = sent[gid] is Map ? Map<String, dynamic>.from(sent[gid] as Map) : <String, dynamic>{};
    g[way] = {'h': hashOf(n), 'at': now.toUtc().toIso8601String()};
    sent[gid] = g;
  }

  Future<SignedBlob> _signed(Map<String, dynamic> note) async {
    final body = jsonEncode(note);
    return SignedBlob(body: body, sig: await sign(body));
  }

  // ------------------------------------------------------------- receiving

  /// Transport events: locked `group_notes_314` packets for the Owner phone.
  void onEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    if (type == 'peer_connected' || type == 'route_recovered' || type == 'relay_connected') {
      kick();
      return;
    }
    if (type != 'message') return;
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains(packetType)) return;
    if (event['sealed'] != true) {
      AppLogger.warning('GROUP_NOTE_DROPPED', detail: 'why=not_sealed');
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
    if (data['type'] != packetType) return;
    if ((data['_locked_spk']?.toString() ?? '').isNotEmpty) {
      AppLogger.warning('GROUP_NOTE_DROPPED', detail: 'why=stranger');
      return;
    }
    final from = data['sender_id']?.toString() ?? '';
    if (from.isEmpty || from == selfDeviceId()) return;
    _chain = _chain.then<void>((_) async {
      await take(from, data['notes']);
    }).catchError((Object e) {
      AppLogger.warning('GROUP_NOTE_TAKE_FAILED', detail: '$e');
    });
  }

  /// Keeps the good notes of one packet ([from] = the proven sender).
  /// Returns how many were kept.
  @visibleForTesting
  Future<int> take(String from, Object? notes) async {
    if (!(await (isOwnerPhone?.call() ?? Future.value(false)).catchError((_) => false))) {
      AppLogger.info('GROUP_NOTE_DROPPED', detail: 'why=not_owner');
      return 0;
    }
    final got = await reported();
    final byId = {for (final g in got) g['id'].toString(): g};
    var kept = 0;
    final now = _clock();
    for (final raw in (notes is List ? notes : const []).take(maxPerPost)) {
      final blob = SignedBlob.fromJson(raw);
      if (blob == null || blob.body.length > 16 * 1024) continue;
      final n = blob.fields;
      if (n == null || n['t'] != noteType || n['v'] != 1) continue;
      final gid = n['gid']?.toString().trim() ?? '';
      final name = n['name']?.toString().trim() ?? '';
      final writer = n['from']?.toString().trim() ?? '';
      final members = <String>{
        for (final m in (n['members'] as List? ?? const [])) m.toString().trim(),
      }.where((m) => m.isNotEmpty && m.length <= 128).toList()
        ..sort();
      if (gid.isEmpty || gid.length > 128 || name.isEmpty || writer.isEmpty) continue;
      if (members.isEmpty || members.length > maxMembers || !members.contains(writer)) continue;
      final at = DateTime.tryParse(n['at']?.toString() ?? '');
      if (at == null || at.isAfter(now.add(const Duration(hours: 24)))) continue;
      final key = await (signingKeyOf?.call(writer) ?? Future.value('')).catchError((_) => '');
      if (key.isNotEmpty) {
        final ok = await (verify?.call(blob.body, blob.sig, key) ?? Future.value(false)).catchError((_) => false);
        if (!ok) {
          AppLogger.warning('GROUP_NOTE_DROPPED', detail: 'why=bad_sig');
          continue;
        }
      } else if (writer != from) {
        continue; // carried by another phone: wait for the writer's own key
      }
      final old = byId[gid];
      if (old != null && (old['at']?.toString() ?? '').compareTo(at.toUtc().toIso8601String()) >= 0) continue;
      byId[gid] = {
        'id': gid,
        'name': name.runes.length > maxName ? String.fromCharCodes(name.runes.take(maxName)) : name,
        'members': members,
        'made_at': n['made_at']?.toString() ?? '',
        'from': writer,
        'at': at.toUtc().toIso8601String(),
        'got_at': now.toUtc().toIso8601String(),
      };
      kept++;
    }
    if (kept > 0) {
      await _saveGot(byId.values.toList());
      changed.value++;
      AppLogger.info('GROUP_NOTE_KEPT', detail: 'n=$kept');
    }
    return kept;
  }

  /// The nearby groups members reported to this (Owner) phone:
  /// `{id, name, members, made_at, from, at}`. Old ones drop off.
  Future<List<Map<String, dynamic>>> reported() async {
    try {
      final d = jsonDecode(await read(gotKey) ?? '[]');
      final now = _clock();
      return [
        for (final x in (d is List ? d : const []))
          if (x is Map &&
              (x['id']?.toString() ?? '').isNotEmpty &&
              now.difference(DateTime.tryParse(x['got_at']?.toString() ?? '') ?? now) < keepFor)
            Map<String, dynamic>.from(x),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveGot(List<Map<String, dynamic>> list) async {
    list.sort((a, b) => '${b['got_at']}'.compareTo('${a['got_at']}'));
    await write(gotKey, jsonEncode(list.take(maxGot).toList()));
  }
}

/// Bundle 314 (1c): `POST /api/v1/admin/group-notes` with the phone's own
/// sign-in. Returns the status: 200 taken, 404 an old server, 401 signed out.
class HttpGroupNotes314 {
  HttpGroupNotes314({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceToken,
    http.Client? client,
  }) : _client = BuildHeaderClient(client ?? http.Client());

  final String Function() baseUrl;
  final String Function() deviceId;
  final String Function() deviceToken;
  final http.Client _client;

  Future<int> post(List<SignedBlob> notes) async {
    final base = baseUrl();
    final token = deviceToken();
    if (base.isEmpty || token.isEmpty) throw Exception('no server');
    final r = await _client
        .post(Uri.parse('$base/api/v1/admin/group-notes'),
            headers: {
              'Authorization': 'Bearer $token',
              'X-Device-ID': deviceId(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'notes': [for (final b in notes) b.toJson()]}))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode == 200) {
      try {
        final d = jsonDecode(r.body);
        if (d is Map && d['refused'] is Map && (d['refused'] as Map).isNotEmpty) {
          AppLogger.info('GROUP_NOTE_SERVER_REFUSED', detail: '${d['refused']}');
        }
      } catch (_) {}
    }
    return r.statusCode;
  }
}
