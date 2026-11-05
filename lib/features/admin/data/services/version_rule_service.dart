import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/models/version_rule.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';

/// Bundle 213: the server calls (`internal/httpapi/version_rule.go`).
abstract class VersionRuleServer {
  /// `GET /api/v1/version-rule` (no sign-in) → the current rule or null.
  Future<SignedBlob?> fetch();

  /// `POST /api/v1/version-rule/sync` → the server's rule after mine.
  Future<SignedBlob?> sync(SignedBlob rule);
}

/// A build seen on a nearby phone.
class PeerBuild {
  final int build;
  final String version;
  final DateTime at;
  const PeerBuild(this.build, this.version, this.at);
}

/// Bundle 213: the admin's minimum app version, with no internet.
///
/// - One signed rule (like a 212 block record) travels as plain one-step
///   frames between linked phones and is passed on one step at a time.
/// - Each phone tells linked phones its build (`version_digest`, on link
///   and every 60 s, max once per phone per 30 s) with the rule it has;
///   the phone with the newer rule pushes it (`version_rule`).
/// - Server: read at start and every 10 min, and sent up when this phone
///   has a newer one. Newest wins everywhere (seq, time, id).
class VersionRuleService {
  VersionRuleService({
    required this.read,
    required this.write,
    required this.selfDeviceId,
    required this.send,
    required this.events,
    required this.linkedPeers,
    required this.serverKey,
    required this.endedCerts,
    required this.usableCert,
    required this.sign,
    this.adminSignIn,
    this.server,
    this.onDroppedChanged,
    this.onSelfStopped,
    Future<bool> Function(String body, String sig, String key)? verify,
    DateTime Function()? clock,
    VersionGuard? guard,
  })  : verify = verify ?? ed25519Verify,
        _clock = clock ?? DateTime.now,
        guard = guard ?? VersionGuard.instance;

  static const String ruleKey = 'version_rule_v1';
  static const String peersKey = 'peer_builds_v1';
  static const String pretendKey = 'pretend_old_build';
  static const String hiddenKey = 'version_warn_hidden_until';
  static const String notedKey = 'version_stop_noted';

  static const String digestType = 'version_digest';
  static const String ruleType = 'version_rule';
  static const Duration digestEvery = Duration(seconds: 60);
  static const Duration digestGap = Duration(seconds: 30);
  static const Duration serverEvery = Duration(minutes: 10);
  static const Duration keepPeers = Duration(days: 7);

  static bool isFrameType(String? t) => t == digestType || t == ruleType;

  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final String Function() selfDeviceId;
  final Future<void> Function(String peerId, Map<String, dynamic> payload) send;
  final Stream<Map<String, dynamic>> events;
  final Future<List<String>> Function() linkedPeers;
  final String? Function() serverKey;
  final Set<String> Function() endedCerts;
  final Future<SignedBlob?> Function() usableCert;
  final Future<String> Function(String body) sign;
  final Future<AdminSignIn?> Function()? adminSignIn;
  final VersionRuleServer? server;
  final void Function()? onDroppedChanged;
  final void Function(VersionRule rule)? onSelfStopped;
  final Future<bool> Function(String body, String sig, String key) verify;
  final DateTime Function() _clock;
  final VersionGuard guard;

  static VersionRuleService? instance;

  VersionRule? _rule;
  final Map<String, PeerBuild> _peers = <String, PeerBuild>{};
  final Map<String, DateTime> _linkedSince = <String, DateTime>{};
  final Map<String, DateTime> _digestSentAt = <String, DateTime>{};
  final Map<String, DateTime> _pushedAt = <String, DateTime>{};
  bool _isAdmin = false;
  bool _loaded = false;
  bool _started = false;
  bool _syncBusy = false;
  String _noted = '';
  bool _aboveAdminLogged = false;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _digestTimer;
  Timer? _tick;
  Timer? _serverTimer;

  VersionRule? get rule => _rule;
  Map<String, PeerBuild> get peerBuilds => Map.unmodifiable(_peers);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final pretend = await read(pretendKey);
    if (pretend != null) AppBuild.pretendOld = pretend == '1';
    try {
      final raw = await read(ruleKey);
      if (raw != null && raw.isNotEmpty) {
        final blob = SignedBlob.fromJson(jsonDecode(raw));
        _rule = blob == null ? null : VersionRule.fromBlob(blob);
      }
    } catch (_) {}
    try {
      final raw = await read(peersKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) {
          for (final e in map.entries) {
            final v = e.value;
            if (v is! Map) continue;
            final b = v['b'] is int ? v['b'] as int : int.tryParse('${v['b']}') ?? 0;
            final at = DateTime.tryParse('${v['at']}');
            if (b > 0 && at != null) {
              _peers['${e.key}'] = PeerBuild(b, '${v['v'] ?? ''}', at);
            }
          }
        }
      }
    } catch (_) {}
    guard.setWarnHiddenUntil(DateTime.tryParse(await read(hiddenKey) ?? ''));
    _noted = await read(notedKey) ?? '';
    await recompute(checkLinks: false);
  }

  /// Starts listening and the timers (main app and the no-screen engine).
  Future<void> start() async {
    await load();
    if (_started) return;
    _started = true;
    instance = this;
    AppBuild.onUpgradeRequired = onServerSaysOld;
    _sub = events.listen((e) => unawaited(handleEvent(e).catchError((_) {})));
    _digestTimer = Timer.periodic(
        digestEvery, (_) => unawaited(sendDigests().catchError((_) {})));
    _tick = Timer.periodic(
        const Duration(minutes: 1), (_) => unawaited(recompute().catchError((_) {})));
    _serverTimer = Timer.periodic(
        serverEvery, (_) => unawaited(syncWithServer().catchError((_) {})));
    unawaited(Future<void>.delayed(const Duration(seconds: 8), () async {
      await syncWithServer();
      await sendDigests();
    }).catchError((_) {}));
  }

  Future<void> dispose() async {
    _digestTimer?.cancel();
    _tick?.cancel();
    _serverTimer?.cancel();
    await _sub?.cancel();
    _started = false;
    if (identical(instance, this)) instance = null;
    if (AppBuild.onUpgradeRequired == onServerSaysOld) {
      AppBuild.onUpgradeRequired = null;
    }
  }

  // ------------------------------------------------------------ the screens

  /// Testers: report one build lower ("Pretend old build").
  Future<void> setPretendOld(bool value) async {
    AppBuild.pretendOld = value;
    await write(pretendKey, value ? '1' : '0');
    _digestSentAt.clear();
    AppLogger.info('VERSION_PRETEND_OLD', detail: 'on=$value build=${AppBuild.sent}');
    await recompute();
    unawaited(sendDigests().catchError((_) {}));
  }

  Future<void> hideWarnToday() async {
    guard.hideWarnToday();
    await write(hiddenKey, guard.warnHiddenUntil?.toIso8601String() ?? '');
  }

  /// Builds seen nearby in the last 7 days: build → (version, phones).
  Map<int, ({String version, int phones})> buildCounts() {
    final now = _clock();
    final out = <int, ({String version, int phones})>{};
    for (final p in _peers.values) {
      if (now.difference(p.at) > keepPeers) continue;
      final old = out[p.build];
      out[p.build] = (
        version: (old?.version.isNotEmpty ?? false) ? old!.version : p.version,
        phones: (old?.phones ?? 0) + 1
      );
    }
    return out;
  }

  /// Phones seen nearby (7 days) below [minBuild].
  int affects(int minBuild) => buildCounts()
      .entries
      .where((e) => e.key < minBuild)
      .fold(0, (n, e) => n + e.value.phones);

  /// Admin: sets the rule for everyone (works with no internet). Throws a
  /// short message when this phone can't sign it.
  Future<VersionRule> setRule({
    required int minBuild,
    required String minVersion,
    required String mode,
    int stopDays = 0,
    bool veryOld = false,
    bool remove = false,
  }) async {
    await load();
    if (!remove && (minBuild < 1 || minBuild > kAppBuild)) {
      throw StateError('Pick this phone\'s version or a lower one.');
    }
    final cert = await usableCert();
    if (cert == null) {
      throw StateError('Connect to the server once to turn on offline admin.');
    }
    final certInfo = AdminCert.fromBlob(cert);
    if (certInfo == null || certInfo.role != 'owner') {
      throw StateError('Only the owner admin can set the minimum version.');
    }
    final signIn = await adminSignIn?.call();
    final now = _clock();
    final stopAt = mode == 'stop' && !remove
        ? now.add(Duration(days: stopDays.clamp(0, 30)))
        : null;
    final body = VersionRule.newBody(
      id: _newId(),
      minBuild: remove ? 0 : minBuild,
      minVersion: remove ? '' : minVersion,
      mode: remove ? 'warn' : mode,
      stopAt: stopAt,
      veryOld: !remove && veryOld,
      seq: (_rule?.seq ?? 0) + 1,
      at: now,
      by: signIn?.username ?? '',
      cert: cert,
    );
    final blob = SignedBlob(body: body, sig: await sign(body));
    final rule = VersionRule.fromBlob(blob)!;
    await _accept(rule);
    AppLogger.info('VERSION_RULE_MADE',
        detail: 'min=${rule.minBuild} mode=${rule.mode} days=$stopDays '
            'very_old=${rule.veryOld} seq=${rule.seq}');
    unawaited(_spread(rule, except: '').catchError((_) {}));
    unawaited(syncWithServer().catchError((_) {}));
    return rule;
  }

  // -------------------------------------------------------------- receiving

  /// Checks and keeps [blob] when it is a valid, newer rule.
  Future<bool> offer(SignedBlob blob, {required String from}) async {
    await load();
    final rule = VersionRule.fromBlob(blob);
    if (rule == null) {
      AppLogger.warning('VERSION_RULE_REJECT', detail: 'reason=bad_rule from=${_tail(from)}');
      return false;
    }
    final reason = await VersionRules.check(rule,
        serverKey: serverKey(), endedCerts: endedCerts(), verify: verify);
    if (reason != null) {
      AppLogger.warning('VERSION_RULE_REJECT', detail: 'reason=$reason from=${_tail(from)}');
      return false;
    }
    if (!VersionRules.newer(rule, _rule)) return false;
    await _accept(rule);
    AppLogger.info('VERSION_RULE_TAKEN',
        detail: 'min=${rule.minBuild} mode=${rule.mode} seq=${rule.seq} from=${_tail(from)}');
    return true;
  }

  Future<void> _accept(VersionRule rule) async {
    _rule = rule;
    await write(ruleKey, jsonEncode(rule.blob.toJson()));
    _aboveAdminLogged = false;
    await recompute(checkLinks: false);
  }

  /// One event from the transport.
  Future<void> handleEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();
    if (type == 'peer_connected') {
      final peer = event['peer_id']?.toString() ?? '';
      if (peer.isNotEmpty) {
        _linkedSince.putIfAbsent(peer, _clock);
        await sendDigestTo(peer);
      }
      return;
    }
    if (type != 'message') return;
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains('version_')) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      msg = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final kind = msg['type']?.toString();
    if (!isFrameType(kind)) return;
    // The link layer's sender, never a field they wrote.
    final from = event['sender_id']?.toString() ?? '';
    if (from.isEmpty || from == selfDeviceId()) return;
    await load();
    if (kind == digestType) {
      await _onDigest(from, msg);
    } else {
      final blob = SignedBlob.fromJson(msg['rule']);
      if (blob != null && await offer(blob, from: from)) {
        await _spread(_rule!, except: from);
      }
    }
  }

  Map<String, dynamic> digest() => {
        'type': digestType,
        'b': AppBuild.sent,
        'v': kAppVersion,
        's': _rule?.seq ?? 0,
        'i': _rule?.id ?? '',
        'at': _rule?.at ?? '',
      };

  Future<void> sendDigests() async {
    await load();
    for (final p in await _linked()) {
      await sendDigestTo(p);
    }
  }

  Future<void> sendDigestTo(String peer, {bool force = false}) async {
    if (peer.isEmpty || peer == selfDeviceId()) return;
    final now = _clock();
    final last = _digestSentAt[peer];
    if (!force && last != null && now.difference(last) < digestGap) return;
    _digestSentAt[peer] = now;
    if (_digestSentAt.length > 300) _digestSentAt.remove(_digestSentAt.keys.first);
    try {
      await send(peer, digest());
    } catch (_) {}
  }

  Future<void> _onDigest(String from, Map<String, dynamic> msg) async {
    final b = msg['b'] is int ? msg['b'] as int : int.tryParse('${msg['b']}') ?? 0;
    final now = _clock();
    _linkedSince.putIfAbsent(from, () => now);
    if (b > 0) {
      final old = _peers[from];
      _peers[from] = PeerBuild(b, '${msg['v'] ?? ''}', now);
      if (old == null || old.build != b || now.difference(old.at) > const Duration(hours: 1)) {
        await _savePeers();
      }
      if (old?.build != b) await recompute(checkLinks: false);
    }
    final s = msg['s'] is int ? msg['s'] as int : int.tryParse('${msg['s']}') ?? 0;
    final i = msg['i']?.toString() ?? '';
    final mine = _rule;
    if (mine != null && _theyNeed(mine, s, i, msg['at']?.toString() ?? '')) {
      final last = _pushedAt[from];
      if (last == null || now.difference(last) >= digestGap) {
        _pushedAt[from] = now;
        if (_pushedAt.length > 300) _pushedAt.remove(_pushedAt.keys.first);
        try {
          await send(from, {'type': ruleType, 'rule': mine.blob.toJson()});
        } catch (_) {}
      }
    } else if (s > (mine?.seq ?? 0)) {
      // They have a newer rule: my digest makes them push it.
      await sendDigestTo(from, force: _pushedAt[from] == null);
    }
  }

  bool _theyNeed(VersionRule r, int s, String i, String at) {
    if (s == 0) return true;
    if (r.seq != s) return r.seq > s;
    if (r.id == i) return false;
    final ta = DateTime.tryParse(r.at);
    final tb = DateTime.tryParse(at);
    if (ta != null && tb != null && !ta.isAtSameMomentAs(tb)) return ta.isAfter(tb);
    return r.id.compareTo(i) > 0;
  }

  Future<void> _spread(VersionRule rule, {required String except}) async {
    for (final p in await _linked()) {
      if (p == except || p == selfDeviceId()) continue;
      try {
        await send(p, {'type': ruleType, 'rule': rule.blob.toJson()});
      } catch (_) {}
    }
    AppLogger.info('VERSION_RULE_SPREAD', detail: 'seq=${rule.seq}');
  }

  Future<List<String>> _linked() async {
    try {
      return await linkedPeers();
    } catch (_) {
      return const <String>[];
    }
  }

  // ----------------------------------------------------------------- state

  /// Works out this phone's state and the phones to drop (every minute,
  /// on a new rule and on a new build from a phone).
  Future<void> recompute({bool checkLinks = true}) async {
    final now = _clock();
    if (checkLinks) {
      final linked = (await _linked()).toSet();
      _linkedSince.removeWhere((k, _) => !linked.contains(k));
      for (final p in linked) {
        _linkedSince.putIfAbsent(p, () => now);
      }
    }
    _peers.removeWhere((_, p) => now.difference(p.at) > keepPeers);
    final rule = _rule;
    var mine = VersionRules.stateFor(rule, AppBuild.sent, now);
    if (rule != null && _isAdmin && rule.minBuild > kAppBuild) {
      // An admin phone is never stopped by a rule above its own version.
      if (!_aboveAdminLogged) {
        _aboveAdminLogged = true;
        AppLogger.warning('VERSION_RULE_ABOVE_ADMIN', detail: 'min=${rule.minBuild}');
      }
      mine = VersionState.ok;
    }
    final dropped = <String>{};
    final old = <String>{};
    if (rule != null && !rule.isRemove) {
      for (final e in _peers.entries) {
        if (e.value.build < rule.minBuild) old.add(e.key);
        if (VersionRules.stateFor(rule, e.value.build, now).kind ==
            VersionStateKind.stopped) {
          dropped.add(e.key);
        }
      }
      if (rule.veryOld) {
        for (final e in _linkedSince.entries) {
          if (_peers.containsKey(e.key)) continue;
          if (now.difference(e.value) >= VersionRules.veryOldAfter) {
            dropped.add(e.key);
            old.add(e.key);
          }
        }
      }
    }
    final droppedBefore = guard.droppedPeers;
    final wasStopped = guard.stopped;
    guard.update(rule: rule, state: mine, droppedPeers: dropped, oldPeers: old);
    if (droppedBefore.length != dropped.length || !droppedBefore.containsAll(dropped)) {
      AppLogger.info('VERSION_PEERS_DROPPED', detail: 'n=${dropped.length}');
      onDroppedChanged?.call();
    }
    if (guard.stopped && !wasStopped) {
      AppLogger.warning('VERSION_SELF_STOPPED',
          detail: 'build=${AppBuild.sent} min=${rule?.minBuild ?? 0}');
      if (rule != null && _noted != rule.id) {
        _noted = rule.id;
        await write(notedKey, rule.id);
        onSelfStopped?.call(rule);
      }
    }
  }

  // ---------------------------------------------------------------- server

  /// 426 from the server: this version is stopped there.
  void onServerSaysOld(String body) {
    AppLogger.warning('VERSION_SERVER_426', detail: body.length > 120 ? body.substring(0, 120) : body);
    guard.setServerSaysOld(true);
    unawaited(syncWithServer().catchError((_) {}));
  }

  Future<void> syncWithServer() async {
    final s = server;
    if (s == null || _syncBusy) return;
    _syncBusy = true;
    try {
      await load();
      final signIn = await adminSignIn?.call();
      _isAdmin = signIn != null;
      final theirs = await s.fetch();
      if (theirs != null) await offer(theirs, from: 'server');
      final mine = _rule;
      final theirRule = theirs == null ? null : VersionRule.fromBlob(theirs);
      if (mine != null && (theirRule == null || VersionRules.newer(mine, theirRule))) {
        final back = await s.sync(mine.blob);
        if (back != null) await offer(back, from: 'server');
        AppLogger.info('VERSION_RULE_SERVER_SYNC', detail: 'seq=${mine.seq}');
      }
      // The server answered: trust the rule again instead of the 426.
      if (guard.serverSaysOld &&
          VersionRules.stateFor(_rule, AppBuild.sent, _clock()).kind !=
              VersionStateKind.stopped) {
        guard.setServerSaysOld(false);
      }
      await recompute(checkLinks: false);
    } catch (e) {
      AppLogger.warning('VERSION_RULE_SERVER_FAIL', detail: '$e');
    } finally {
      _syncBusy = false;
    }
  }

  Future<void> _savePeers() => write(
      peersKey,
      jsonEncode({
        for (final e in _peers.entries)
          e.key: {'b': e.value.build, 'v': e.value.version, 'at': e.value.at.toUtc().toIso8601String()},
      }));

  static String _newId() {
    final r = Random.secure();
    return 'vr_${List.generate(12, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  static String _tail(String id) => id.length <= 6 ? id : id.substring(id.length - 6);
}
