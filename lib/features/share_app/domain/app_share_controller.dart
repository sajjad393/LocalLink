// Bundle 210: Share LinkUp - the steps of the Share screen.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/share_app/data/apk_share_server.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/share_address_picker.dart';
import 'package:locallink/features/share_app/domain/wifi_qr.dart';

enum ShareStage {
  /// Reading the APK and the battery.
  checking,

  /// Battery 10% or less (not charging): "Share anyway?".
  batteryLow,

  /// Turning the Wi-Fi on.
  starting,

  /// QR 1: join the Wi-Fi.
  step1,

  /// QR 2: download.
  step2,

  /// Own phone hotspot is on: only QR 2 (friend joins that hotspot).
  ownHotspot,

  /// LinkUp Wi-Fi didn't start but this phone is on a Wi-Fi router: QR 2
  /// with the router address (friend on the same Wi-Fi).
  sameWifi,

  /// Something failed; see [AppShareController.reason].
  failed,

  /// Sharing ended; see [AppShareController.reason] (`idle`, `stopped`, …).
  stopped,

  /// This copy can't be shared (installed in parts).
  cantShare,
}

typedef ApkShareServerFactory = ApkShareServer Function(
    ApkInfo apk, String ownerName);

class AppShareController extends ChangeNotifier {
  static const int lowBattery = 10;

  final AppShareNative native;
  final String ownerName;
  final ApkShareServerFactory serverFactory;
  final Duration statusEvery;
  final Duration notifyGap;

  /// Bundle 223 (E): look for the download address up to [addressWait],
  /// checking every [addressEvery]; the QR then appears by itself.
  final Duration addressWait;
  final Duration addressEvery;

  AppShareController({
    required this.native,
    required this.ownerName,
    ApkShareServerFactory? serverFactory,
    this.statusEvery = const Duration(seconds: 5),
    this.notifyGap = const Duration(milliseconds: 300),
    this.addressWait = const Duration(seconds: 10),
    this.addressEvery = const Duration(seconds: 2),
  }) : serverFactory = serverFactory ??
            ((apk, name) => ApkShareServer(
                  apkPath: apk.path,
                  apkSize: apk.size,
                  version: apk.version,
                  ownerName: name,
                ));

  ShareStage _stage = ShareStage.checking;
  String? _reason;
  ApkInfo? _apk;
  ApkShareServer? _server;
  ShareStart? _hotspot;
  String? _ip;
  List<ShareAddress> _choices = const <ShareAddress>[];
  bool _batteryAccepted = false;
  bool _weStartedHotspot = false;
  bool _disposed = false;
  bool _busy = false;
  Timer? _statusTimer;
  Timer? _notifyTimer;
  int _run = 0;
  // Bundle 223 (E): looking for the address in the background.
  Timer? _ipTimer;
  bool _lookingIp = false;
  bool _ipGaveUp = false;
  bool _ipChecking = false;
  int _ipTicks = 0;

  ShareStage get stage => _stage;
  String? get reason => _reason;
  ApkInfo? get apk => _apk;
  String get ssid => _hotspot?.ssid ?? '';
  String get password => _hotspot?.password ?? '';
  bool get reusedHotspot => _hotspot?.reused == true;
  String? get ip => _ip;
  int? get port => _server?.port;
  List<ShareAddress> get ipChoices => _choices;

  /// Bundle 223 (E): "Getting the download address..." (spinner).
  bool get lookingForIp => _ip == null && _lookingIp;

  /// Bundle 223 (E): 10 s and nothing: every address + Try again + Gateway tip.
  bool get ipGaveUp => _ip == null && _ipGaveUp;
  List<SharePhone> get phones => _server?.phones ?? const <SharePhone>[];
  bool get sharing =>
      _server?.running == true &&
      (_stage == ShareStage.step1 ||
          _stage == ShareStage.step2 ||
          _stage == ShareStage.ownHotspot ||
          _stage == ShareStage.sameWifi);

  String get wifiQr => wifiQrText(
      ssid: ssid, password: password, type: _hotspot?.qrType ?? 'WPA');
  String? get downloadUrl =>
      (_ip == null || port == null) ? null : shareDownloadUrl(_ip!, port!);
  String? get downloadLabel =>
      (_ip == null || port == null) ? null : shareDownloadLabel(_ip!, port!);
  String get sizeLabel => shareSizeLabel(_apk?.size ?? 0);

  void _set(ShareStage s, {String? reason}) {
    _stage = s;
    _reason = reason;
    _notifyNow();
  }

  void _notifyNow() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    if (!_disposed) notifyListeners();
  }

  /// Many small server changes (each chunk) → at most one redraw per gap.
  void _notifySoon() {
    if (_disposed || _notifyTimer != null) return;
    _notifyTimer = Timer(notifyGap, () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  /// Start (or start again after a stop / failure).
  Future<void> start() async {
    if (_disposed || _busy) return;
    if (_server != null || _weStartedHotspot) await stop('restart');
    if (_disposed) return;
    _busy = true;
    final run = ++_run;
    try {
      await _start(run);
    } finally {
      if (run == _run) _busy = false;
    }
  }

  bool _stale(int run) => _disposed || run != _run;

  Future<void> _start(int run) async {
    _set(ShareStage.checking);
    final apk = await native.apkInfo();
    if (_stale(run)) return;
    _apk = apk;
    if (!apk.ok || apk.path.isEmpty || apk.size <= 0) {
      _set(ShareStage.failed, reason: apk.reason ?? 'apk_missing');
      return;
    }
    if (apk.split) {
      _set(ShareStage.cantShare, reason: 'split');
      return;
    }
    if (!_batteryAccepted) {
      final b = await native.battery();
      if (_stale(run)) return;
      if (!b.charging && b.level >= 0 && b.level <= lowBattery) {
        _set(ShareStage.batteryLow);
        return;
      }
    }
    _set(ShareStage.starting);
    // 1. The page first (needs no Wi-Fi).
    final server = serverFactory(apk, ownerName);
    server.onChange = _onServerChange;
    server.onIdle = () => unawaited(stop('idle'));
    try {
      await server.start();
    } on ShareServerException catch (e) {
      await server.stop();
      if (_stale(run)) return;
      _set(ShareStage.failed, reason: e.reason);
      return;
    } catch (_) {
      await server.stop();
      if (_stale(run)) return;
      _set(ShareStage.failed, reason: 'port_busy');
      return;
    }
    if (_stale(run)) {
      await server.stop();
      return;
    }
    _server = server;
    // 2. The Wi-Fi.
    final hs = await native.startShare();
    if (_stale(run)) {
      if (hs.ok) await native.stopShare('left');
      return;
    }
    if (hs.ok) {
      _weStartedHotspot = true;
      _hotspot = hs;
      _ip = pickShareIp(nativeIp: hs.ip, list: hs.addresses);
      _choices = _ip == null ? shareIpChoices(hs.addresses) : const [];
      if (_ip == null && _choices.isEmpty) {
        // Look once more (Android may add the address a bit later).
        final more = await native.addresses();
        if (_stale(run)) return;
        final noRouter = more.wifiIp == null;
        _ip = pickShareIp(list: more.list, noRouter: noRouter);
        _choices = _ip == null
            ? shareIpChoices(more.list, noRouter: noRouter)
            : const [];
      }
      AppLogger.info('SHARE_APP',
          detail: 'ready reused=${hs.reused} ip_found=${_ip != null} '
              'port=${server.port}');
      if (_ip != null) _logPicked(_ip!, hs.addresses);
      await native.keepScreenOn(true);
      _startStatusChecks();
      // Bundle 223 (E): still no address -> keep looking (step 2 shows a
      // spinner, then every address + Try again; never an empty list).
      if (_ip == null) _startIpLook(run);
      _set(ShareStage.step1);
      return;
    }
    // 3. No LinkUp Wi-Fi: maybe the friend can still reach us.
    final addrs = await native.addresses();
    if (_stale(run)) return;
    if (hs.reason == 'own_hotspot') {
      _ip = pickTetherIp(addrs.list);
      if (_ip != null) {
        await native.keepScreenOn(true);
        _set(ShareStage.ownHotspot, reason: 'own_hotspot');
        return;
      }
    } else if (addrs.wifiIp != null) {
      _ip = addrs.wifiIp;
      await native.keepScreenOn(true);
      _set(ShareStage.sameWifi, reason: hs.reason);
      return;
    }
    await _closeServer();
    _set(ShareStage.failed, reason: hs.reason ?? 'error');
  }

  void _onServerChange() {
    if (_disposed) return;
    // The first download moves Step 1 to Step 2 by itself.
    if (_stage == ShareStage.step1 &&
        (_server?.phones.isNotEmpty ?? false)) {
      _stage = ShareStage.step2;
      _notifyNow();
      return;
    }
    _notifySoon();
  }

  /// Bundle 223 (E): check every [addressEvery] up to [addressWait].
  void _startIpLook(int run) {
    _ipTimer?.cancel();
    _lookingIp = true;
    _ipGaveUp = false;
    _ipTicks = 0;
    _ipTimer = Timer.periodic(addressEvery, (_) => unawaited(_ipCheck(run)));
  }

  void _stopIpLook() {
    _ipTimer?.cancel();
    _ipTimer = null;
    _lookingIp = false;
  }

  Future<void> _ipCheck(int run) async {
    if (_stale(run) || !_lookingIp || _ipChecking) return;
    _ipChecking = true;
    try {
      _ipTicks++;
      // Tick count, not a stopwatch (also right under fake time in tests).
      final ms = _ipTicks * addressEvery.inMilliseconds;
      ShareAddresses a;
      try {
        a = await native.addresses();
      } catch (_) {
        a = const ShareAddresses();
      }
      if (_stale(run) || !_lookingIp) return;
      final ip = pickShareIp(list: a.list, noRouter: a.wifiIp == null);
      if (ip != null) {
        _stopIpLook();
        _ip = ip;
        _choices = const [];
        final iface = a.list
            .firstWhere((x) => x.ip == ip,
                orElse: () => const ShareAddress(iface: '?', ip: ''))
            .iface;
        AppLogger.info('SHARE_APP',
            detail: 'ip_wait found=$ip ms=$ms iface=$iface');
        _logPicked(ip, a.list);
        _notifyNow();
        return;
      }
      if (ms >= addressWait.inMilliseconds) {
        _stopIpLook();
        _ipGaveUp = true;
        _choices = shareIpAll(a.list);
        AppLogger.info('SHARE_APP',
            detail: 'ip_none ms=$ms list=${shareIpListForLog(a.list)}');
        _notifyNow();
      }
    } finally {
      _ipChecking = false;
    }
  }

  /// Bundle 223 (E, Q12): which address went into the QR.
  void _logPicked(String ip, List<ShareAddress> list) {
    final iface = list
        .firstWhere((x) => x.ip == ip,
            orElse: () => const ShareAddress(iface: '?', ip: ''))
        .iface;
    AppLogger.info('SHARE_APP', detail: 'ip_picked ip=$ip iface=$iface');
  }

  /// Bundle 223 (E): "Try again" on step 2.
  void retryIp() {
    if (_disposed || !sharing || _ip != null) return;
    _startIpLook(_run);
    _notifyNow();
    unawaited(_ipCheck(_run));
  }

  void _startStatusChecks() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(statusEvery, (_) async {
      if (_disposed || !sharing || !_weStartedHotspot) return;
      final on = await native.shareStillOn();
      if (!on && !_disposed && sharing) {
        AppLogger.info('SHARE_APP', detail: 'wifi stopped by android');
        await stop('stopped');
      }
    });
  }

  /// "Share anyway" on the low-battery card.
  Future<void> shareAnyway() async {
    _batteryAccepted = true;
    await start();
  }

  void goToStep(int step) {
    if (_stage != ShareStage.step1 && _stage != ShareStage.step2) return;
    _set(step == 2 ? ShareStage.step2 : ShareStage.step1);
  }

  /// The user picked the address by hand (rare).
  void chooseIp(String ip) {
    _stopIpLook(); // Bundle 223 (E)
    _ipGaveUp = false;
    _ip = ip;
    _choices = const [];
    AppLogger.info('SHARE_APP', detail: 'ip_picked ip=$ip iface=by_hand');
    _notifyNow();
  }

  Future<void> _closeServer() async {
    final s = _server;
    _server = null;
    if (s != null) {
      s.onChange = null;
      s.onIdle = null;
      await s.stop();
    }
  }

  /// Stops sharing: page off, Wi-Fi off (only ours), screen may sleep.
  /// [reason]: `user`, `idle`, `stopped`, `left`, `app_closed`.
  Future<void> stop(String reason) async {
    _run++;
    _busy = false;
    _statusTimer?.cancel();
    _statusTimer = null;
    _stopIpLook(); // Bundle 223 (E)
    _ipGaveUp = false;
    final hadServer = _server != null;
    final hadHotspot = _weStartedHotspot;
    _weStartedHotspot = false;
    await _closeServer();
    if (hadHotspot) await native.stopShare(reason);
    if (hadServer || hadHotspot) {
      await native.keepScreenOn(false);
      AppLogger.info('SHARE_APP', detail: 'stop reason=$reason');
    }
    _hotspot = null;
    _ip = null;
    _choices = const [];
    if (!_disposed) _set(ShareStage.stopped, reason: reason);
  }

  @override
  void dispose() {
    if (_disposed) return;
    unawaited(stop('left'));
    _disposed = true;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _stopIpLook();
    super.dispose();
  }
}
