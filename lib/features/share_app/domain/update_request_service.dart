import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/share_app/data/apk_share_server.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/share_address_picker.dart';

/// A phone near me that has a newer LinkUp.
class UpdateCandidate {
  final String peerId;
  final String name;
  final String version;
  final int build;
  const UpdateCandidate(
      {required this.peerId,
      required this.name,
      required this.version,
      required this.build});
}

/// Someone asked this phone for the new LinkUp.
class UpdateAsk {
  final String peerId;
  final String name;
  final List<String> ips;
  final int build;
  const UpdateAsk(
      {required this.peerId,
      required this.name,
      required this.ips,
      required this.build});
}

/// What the other phone sent back.
class UpdateOffer {
  final String peerId;
  final String name;
  final String version;
  final int size;
  final String url; // '' when [qr]
  final bool qr;
  const UpdateOffer(
      {required this.peerId,
      required this.name,
      required this.version,
      required this.size,
      required this.url,
      required this.qr});
}

enum AskStatus { asking, notNow, noAnswer, sharing, qr, failed }

/// Bundle 213 (E): "Update" gets the new app from a nearby phone.
///
/// Ali taps Ask next to Sumaira → `app_update_request` (one step) →
/// Sumaira sees "Ali wants the new LinkUp" → Share → her phone serves the
/// app (the 210 download page) on the Wi-Fi both phones are on →
/// `app_update_offer` with the address → Ali's phone opens it by itself.
/// No shared Wi-Fi (mesh only): Sumaira's phone opens the 210 QR screen.
class UpdateRequestService extends ChangeNotifier {
  UpdateRequestService({
    required this.send,
    required this.events,
    required this.selfDeviceId,
    required this.myName,
    required this.peerName,
    required this.peerBuilds,
    AppShareNative? native,
    this.startServer,
    this.openUri,
    DateTime Function()? clock,
  })  : native = native ?? const MethodChannelAppShareNative(),
        _clock = clock ?? DateTime.now;

  static const String requestType = 'app_update_request';
  static const String answerType = 'app_update_answer';
  static const String offerType = 'app_update_offer';
  static const Duration askGap = Duration(minutes: 2);
  static const Duration answerWait = Duration(seconds: 60);

  static bool isFrameType(String? t) =>
      t == requestType || t == answerType || t == offerType;

  static UpdateRequestService? instance;

  /// The app shows "X wants the new LinkUp" (true = Share). Null result or
  /// no hook = not now.
  static Future<bool?> Function(UpdateAsk ask, ApkInfo apk, ShareBattery battery)? confirm;

  /// No shared Wi-Fi: the app opens the 210 Share LinkUp (QR) screen.
  static void Function(String ownerName)? openShareScreen;

  final Future<void> Function(String peerId, Map<String, dynamic> payload) send;
  final Stream<Map<String, dynamic>> events;
  final String Function() selfDeviceId;
  final String Function() myName;
  final Future<String> Function(String peerId) peerName;

  /// Linked phones' builds (from the version service): id → (build, version, seen).
  final Map<String, ({int build, String version, DateTime at})> Function() peerBuilds;
  final AppShareNative native;

  /// Serves the app on [ip]; returns the address (tests replace it).
  final Future<String> Function(ApkInfo apk, String ip, String ownerName)? startServer;

  /// Opens the address in the browser (tests replace it).
  final Future<void> Function(String url)? openUri;
  final DateTime Function() _clock;

  final Map<String, DateTime> _askedAt = <String, DateTime>{};
  final Map<String, DateTime> _askedMeAt = <String, DateTime>{};
  final Map<String, AskStatus> _status = <String, AskStatus>{};
  final Map<String, Timer> _waits = <String, Timer>{};
  UpdateOffer? _offer;
  final Set<String> _opened = <String>{};
  bool _dialogOpen = false;
  ApkShareServer? _server;
  StreamSubscription<Map<String, dynamic>>? _sub;
  final Map<String, String> _names = <String, String>{};

  UpdateOffer? get offer => _offer;
  AskStatus? statusOf(String peerId) => _status[peerId];
  String nameOf(String peerId) => _names[peerId] ?? 'Nearby phone';

  void start() {
    if (_sub != null) return;
    instance = this;
    _sub = events.listen((e) => unawaited(handleEvent(e).catchError((_) {})));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    for (final t in _waits.values) {
      t.cancel();
    }
    _waits.clear();
    await _server?.stop();
    _server = null;
    if (identical(instance, this)) instance = null;
  }

  /// Phones near me (seen in the last 10 min) with a newer build.
  Future<List<UpdateCandidate>> candidates({int minBuild = 0}) async {
    final now = _clock();
    final need = minBuild > AppBuild.sent ? minBuild : AppBuild.sent + 1;
    final out = <UpdateCandidate>[];
    for (final e in peerBuilds().entries) {
      if (e.value.build < need) continue;
      if (now.difference(e.value.at) > const Duration(minutes: 10)) continue;
      final name = await _name(e.key);
      out.add(UpdateCandidate(
          peerId: e.key, name: name, version: e.value.version, build: e.value.build));
    }
    out.sort((a, b) => b.build != a.build ? b.build.compareTo(a.build) : a.name.compareTo(b.name));
    return out;
  }

  Future<String> _name(String id) async {
    final known = _names[id];
    if (known != null) return known;
    var name = '';
    try {
      name = (await peerName(id)).trim();
    } catch (_) {}
    if (name.isEmpty) name = 'Nearby phone';
    _names[id] = name;
    return name;
  }

  /// Ask. False when asked this phone less than 2 min ago.
  Future<bool> ask(String peerId) async {
    final now = _clock();
    final last = _askedAt[peerId];
    // Max one ask per phone per 2 min (a failed send can be tried again).
    if (last != null &&
        now.difference(last) < askGap &&
        _status[peerId] != AskStatus.failed) {
      return false;
    }
    _askedAt[peerId] = now;
    var ips = <String>[];
    try {
      final a = await native.addresses();
      ips = <String>{
        if (a.wifiIp != null && a.wifiIp!.isNotEmpty) a.wifiIp!,
        for (final x in a.list)
          if (isPrivateV4(x.ip)) x.ip,
      }.toList();
    } catch (_) {}
    _status[peerId] = AskStatus.asking;
    notifyListeners();
    try {
      await send(peerId, {
        'type': requestType,
        'name': myName(),
        'ips': ips.take(8).toList(),
        'build': AppBuild.sent,
      });
    } catch (e) {
      _status[peerId] = AskStatus.failed;
      notifyListeners();
      return false;
    }
    AppLogger.info('APP_UPDATE_ASK', detail: 'to=${_tail(peerId)} ips=${ips.length}');
    _waits[peerId]?.cancel();
    _waits[peerId] = Timer(answerWait, () {
      _waits.remove(peerId);
      if (_status[peerId] == AskStatus.asking) {
        _status[peerId] = AskStatus.noAnswer;
        AppLogger.info('APP_UPDATE_NO_ANSWER', detail: 'from=${_tail(peerId)}');
        notifyListeners();
      }
    });
    return true;
  }

  void cancel() {
    for (final e in _status.entries.toList()) {
      if (e.value == AskStatus.asking) _status.remove(e.key);
    }
    for (final t in _waits.values) {
      t.cancel();
    }
    _waits.clear();
    notifyListeners();
  }

  void clearOffer() {
    _offer = null;
    notifyListeners();
  }

  Future<void> openOffer() async {
    final o = _offer;
    if (o == null || o.url.isEmpty) return;
    await _open(o.url);
  }

  Future<void> _open(String url) async {
    try {
      if (openUri != null) {
        await openUri!(url);
      } else {
        await const MethodChannel('locallink/voice_notes')
            .invokeMethod<Object?>('open_uri', {'uri': url, 'mime': ''});
      }
      AppLogger.info('APP_UPDATE_OPEN', detail: 'ok');
    } catch (e) {
      AppLogger.warning('APP_UPDATE_OPEN', detail: 'fail=$e');
    }
  }

  // ------------------------------------------------------------- receiving

  Future<void> handleEvent(Map<String, dynamic> event) async {
    if (event['type']?.toString() != 'message') return;
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains('app_update_')) return;
    Map<String, dynamic> msg;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return;
      msg = Map<String, dynamic>.from(d);
    } catch (_) {
      return;
    }
    final kind = msg['type']?.toString();
    if (!isFrameType(kind)) return;
    final from = event['sender_id']?.toString() ?? '';
    if (from.isEmpty || from == selfDeviceId()) return;
    switch (kind) {
      case requestType:
        await _onRequest(from, msg);
      case answerType:
        _onAnswer(from, msg);
      case offerType:
        await _onOffer(from, msg);
    }
  }

  Future<void> _onRequest(String from, Map<String, dynamic> msg) async {
    final build = msg['build'] is int ? msg['build'] as int : int.tryParse('${msg['build']}') ?? 0;
    final now = _clock();
    final last = _askedMeAt[from];
    if (_dialogOpen || (last != null && now.difference(last) < askGap)) return;
    if (build >= kAppBuild) {
      await _answer(from, false, 'not_newer');
      return;
    }
    _askedMeAt[from] = now;
    final name = (msg['name']?.toString() ?? '').trim();
    final ask = UpdateAsk(
      peerId: from,
      name: name.isEmpty ? await _name(from) : name,
      ips: [for (final x in (msg['ips'] as List? ?? const [])) '$x'].take(8).toList(),
      build: build,
    );
    AppLogger.info('APP_UPDATE_ASKED', detail: 'from=${_tail(from)}');
    ApkInfo apk;
    try {
      apk = await native.apkInfo();
    } catch (_) {
      apk = const ApkInfo(ok: false, path: '', size: 0, version: '', split: false, reason: 'error');
    }
    if (!apk.ok) {
      await _answer(from, false, apk.reason ?? 'no_apk');
      return;
    }
    ShareBattery battery;
    try {
      battery = await native.battery();
    } catch (_) {
      battery = const ShareBattery(charging: false, level: 100);
    }
    final hook = confirm;
    bool? yes;
    if (hook != null) {
      _dialogOpen = true;
      try {
        yes = await hook(ask, apk, battery);
      } catch (_) {
        yes = null;
      } finally {
        _dialogOpen = false;
      }
    }
    if (yes != true) {
      await _answer(from, false, 'not_now');
      return;
    }
    await share(ask, apk);
  }

  /// Share tapped: serve the app on the Wi-Fi the asker is on, or the QR.
  Future<void> share(UpdateAsk ask, ApkInfo apk) async {
    String? ip;
    try {
      final a = await native.addresses();
      ip = sameNetworkIp(
          mine: [
            if (a.wifiIp != null) a.wifiIp!,
            for (final x in a.list) x.ip,
          ],
          theirs: ask.ips);
    } catch (_) {}
    final version = apk.version.isEmpty ? kAppVersion : apk.version;
    if (ip == null) {
      AppLogger.info('APP_UPDATE_SHARE', detail: 'way=qr');
      await _sendOffer(ask.peerId, {'qr': true, 'version': version, 'size': apk.size});
      openShareScreen?.call(myName());
      return;
    }
    try {
      final url = startServer != null
          ? await startServer!(apk, ip, myName())
          : await _serve(apk, ip, version);
      AppLogger.info('APP_UPDATE_SHARE', detail: 'way=wifi');
      await _sendOffer(ask.peerId, {'url': url, 'version': version, 'size': apk.size});
    } catch (e) {
      AppLogger.warning('APP_UPDATE_SHARE', detail: 'fail=$e');
      await _sendOffer(ask.peerId, {'qr': true, 'version': version, 'size': apk.size});
      openShareScreen?.call(myName());
    }
  }

  Future<String> _serve(ApkInfo apk, String ip, String version) async {
    var server = _server;
    if (server == null || !server.running) {
      server = ApkShareServer(
          apkPath: apk.path, apkSize: apk.size, version: version, ownerName: myName());
      server.onIdle = () {
        unawaited(server!.stop());
        if (identical(_server, server)) _server = null;
      };
      _server = server;
    }
    final port = await server.start();
    return 'http://$ip:$port/';
  }

  Future<void> _sendOffer(String to, Map<String, dynamic> fields) async {
    try {
      await send(to, {'type': offerType, 'name': myName(), ...fields});
    } catch (_) {}
  }

  Future<void> _answer(String to, bool ok, String reason) async {
    try {
      await send(to, {'type': answerType, 'ok': ok, 'reason': reason});
    } catch (_) {}
  }

  void _onAnswer(String from, Map<String, dynamic> msg) {
    if (_status[from] != AskStatus.asking) return;
    if (msg['ok'] == true) return;
    _waits.remove(from)?.cancel();
    _status[from] = msg['reason'] == 'not_now' ? AskStatus.notNow : AskStatus.failed;
    AppLogger.info('APP_UPDATE_ANSWER', detail: 'from=${_tail(from)} reason=${msg['reason']}');
    notifyListeners();
  }

  Future<void> _onOffer(String from, Map<String, dynamic> msg) async {
    // Only from a phone I asked.
    if (!_askedAt.containsKey(from)) return;
    _waits.remove(from)?.cancel();
    final url = msg['url']?.toString() ?? '';
    final qr = msg['qr'] == true || url.isEmpty;
    if (!qr && !_safeUrl(url)) return;
    final name = (msg['name']?.toString() ?? '').trim();
    if (name.isNotEmpty) _names[from] = name;
    _offer = UpdateOffer(
      peerId: from,
      name: name.isEmpty ? await _name(from) : name,
      version: msg['version']?.toString() ?? '',
      size: msg['size'] is int ? msg['size'] as int : 0,
      url: qr ? '' : url,
      qr: qr,
    );
    _status[from] = qr ? AskStatus.qr : AskStatus.sharing;
    AppLogger.info('APP_UPDATE_OFFER', detail: 'from=${_tail(from)} qr=$qr');
    notifyListeners();
    // The download opens by itself (once per address).
    if (!qr && _opened.add(url)) await _open(url);
  }

  /// Only a plain local address of a phone (http://10.x / 192.168.x / ...).
  static bool _safeUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'http' || u.host.isEmpty) return false;
    return isPrivateV4(u.host);
  }

  /// My address on the same /24 as one of [theirs] (same Wi-Fi, same
  /// hotspot or same Wi-Fi Direct group), else null.
  static String? sameNetworkIp({required List<String> mine, required List<String> theirs}) {
    String net(String ip) {
      final p = ip.split('.');
      return p.length == 4 ? '${p[0]}.${p[1]}.${p[2]}' : '';
    }

    final want = {for (final t in theirs) if (isPrivateV4(t)) net(t)};
    for (final m in mine) {
      if (!isPrivateV4(m)) continue;
      if (want.contains(net(m)) && !theirs.contains(m)) return m;
    }
    return null;
  }

  static String _tail(String id) => id.length <= 6 ? id : id.substring(id.length - 6);

  @visibleForTesting
  static void resetHooksForTest() {
    confirm = null;
    openShareScreen = null;
    instance = null;
  }
}
