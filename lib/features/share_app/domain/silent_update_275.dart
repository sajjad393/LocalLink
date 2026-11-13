import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/share_app/data/apk_share_page.dart' show shareApkPath;
import 'package:locallink/features/share_app/data/app_latest_server_299.dart';
import 'package:locallink/features/share_app/domain/update_request_service.dart';

/// Bundle 275: native install helpers (channel `locallink/app_share`).
/// Separate from [AppShareNative] so the 210 fakes stay as they are.
class UpdateInstallNative275 {
  const UpdateInstallNative275();
  static const MethodChannel _ch = MethodChannel('locallink/app_share');

  /// `<cache>/update275` (made if missing), '' when unknown.
  Future<String> updateDir() async {
    try {
      return (await _ch.invokeMethod<String>('updateDir275')) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Size must match and the file must be a `com.sajjad.linkup` APK.
  Future<String?> checkApk(String path, int size) async {
    try {
      final r = await _ch.invokeMapMethod<String, Object?>('checkApk275', {'path': path, 'size': size});
      if (r?['ok'] == true) return null;
      return r?['reason']?.toString() ?? 'bad_apk';
    } catch (_) {
      return 'check_fail';
    }
  }

  Future<bool> canInstall() async {
    try {
      return (await _ch.invokeMethod<bool>('canInstall275')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android's "Install unknown apps" page for LinkUp (only on a user tap).
  Future<bool> openInstallSettings() async {
    try {
      return (await _ch.invokeMethod<bool>('openInstallSettings275')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's own "Update" screen (it always asks the user).
  Future<bool> installApk(String path) async {
    try {
      return (await _ch.invokeMethod<bool>('installApk275', {'path': path})) ?? false;
    } catch (_) {
      return false;
    }
  }
}

enum SilentStage275 { idle, getting, nextPhone, ready, none }

/// Bundle 275 (U-1 / U-3): the old phone's quiet update.
///
/// A nearby phone has a newer build -> ONE popup opens by itself and starts:
/// no list, no names. The best phone (newest build) is asked; no answer in
/// 60 s or a quiet "not now" -> the next phone, by itself. The file comes
/// INSIDE LinkUp (no browser) into the app's cache, size + package are
/// checked, then Install opens Android's own update screen.
///
/// Popup max once per new build per day (Cancel = not again today).
/// Auto delete: on the new version's first start, on Cancel / fail, and any
/// file older than 24 h at start.
class SilentUpdate275 extends ChangeNotifier {
  SilentUpdate275({
    required this.requests,
    required this.read,
    required this.write,
    UpdateInstallNative275? native,
    this.download,
    DateTime Function()? clock,
    this.minBuild,
    this.server,
    this.hashFile,
    this.appBuild,
  })  : native = native ?? const UpdateInstallNative275(),
        _clock = clock ?? DateTime.now;

  static SilentUpdate275? instance;

  /// Opens the popup (set by the app at start). Called once per run.
  static void Function(SilentUpdate275 s)? showPopup;

  /// First start of the new version after a nearby update (one short toast).
  static void Function()? onUpdated;

  static const String gateKey = 'update275_popup'; // '<build>|<yyyy-mm-dd>'
  static const String fileKey = 'update275_apk'; // '<path>|<build>'
  static const Duration oldFile = Duration(hours: 24);

  final UpdateRequestService requests;
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final UpdateInstallNative275 native;
  final int Function()? minBuild;

  /// Downloads [url] into [path]; tests replace it.
  final Future<void> Function(String url, String path, int size, void Function(int got) progress)? download;
  final DateTime Function() _clock;

  /// Bundle 299 (C): the LinkUp server is asked first; nearby phones are
  /// the fallback (no server, no APK there, or a bad file).
  final AppLatestSource299? server;

  /// sha256 (hex) of a file; tests replace it.
  final Future<String> Function(String path)? hashFile;

  /// This app's build (tests replace it; default [AppBuild.sent], like phones).
  final int Function()? appBuild;

  /// The server is asked at most every 6 h (plus after a reconnect / the
  /// Update button); in between the last answer is used.
  static const Duration serverEvery = Duration(hours: 6);
  DateTime? _serverAt;
  ServerApk299? _serverApk;

  SilentStage275 _stage = SilentStage275.idle;
  int _target = 0;
  String _version = '';
  int _size = 0;
  int _got = 0;
  String? _path;
  bool _cancelled = false;
  bool needsAllow = false;
  int _run = 0;

  SilentStage275 get stage => _stage;
  int get target => _target;
  String get version => _version;
  int get size => _size;
  int get got => _got;
  String? get path => _path;
  bool get running => _stage == SilentStage275.getting || _stage == SilentStage275.nextPhone;

  /// Bundle 299 (C): true while the file comes from the LinkUp server
  /// (http://<server>/linkup) instead of a nearby phone. The server is
  /// tried first; nearby phones stay the fallback (no server / no Wi-Fi).
  bool fromServer = false;

  /// Bundle 299: tests / shots set a stage directly.
  @visibleForTesting
  void debugShow(SilentStage275 stage, {String version = '', int size = 0, int got = 0, bool server = false}) {
    _version = version;
    _size = size;
    _got = got;
    fromServer = server;
    _setStage(stage);
  }

  static String _day(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  /// Bundle 299: the app reconnected to the server -> ask it again.
  void serverAgain() => _serverAt = null;

  /// The server's APK when it is newer than this app, else null.
  Future<ServerApk299?> _serverNewer(bool manual) async {
    final src = server;
    if (src == null) return null;
    final now = _clock();
    final at = _serverAt;
    if (manual || at == null || now.difference(at) >= serverEvery || now.isBefore(at)) {
      try {
        _serverApk = await src.latest();
        _serverAt = now;
      } catch (e) {
        // Server not reached: try again next time; phones are used now.
        AppLogger.info('APP_UPDATE_SERVER', detail: 'unreachable=${e.runtimeType}');
        return null;
      }
    }
    final apk = _serverApk;
    if (apk == null) return null;
    final mine = appBuild?.call() ?? AppBuild.sent;
    if (apk.build <= mine || apk.build < (minBuild?.call() ?? 0)) return null;
    if (src.fileUrl(apk).isEmpty) return null;
    return apk;
  }

  /// Auto check (timer / new peer build). [manual] = the Update button.
  Future<bool> check({bool manual = false}) async {
    if (running || _stage == SilentStage275.ready) {
      if (manual) showPopup?.call(this);
      return false;
    }
    if (!manual && (UpdateRequestService.inCall?.call() ?? false)) return false;
    final fromSrv = await _serverNewer(manual);
    if (fromSrv != null) {
      if (running || _stage == SilentStage275.ready) return false;
      final gate = '${fromSrv.build}|${_day(_clock())}';
      if (!manual) {
        String? last;
        try {
          last = await read(gateKey);
        } catch (_) {}
        if (last == gate) return false;
      }
      try {
        await write(gateKey, gate);
      } catch (_) {}
      _target = fromSrv.build;
      _version = fromSrv.version;
      AppLogger.info('APP_UPDATE_SERVER', detail: 'popup build=${fromSrv.build} manual=$manual');
      _cancelled = false;
      needsAllow = false;
      fromServer = true;
      _setStage(SilentStage275.getting);
      showPopup?.call(this);
      unawaited(_runServer(fromSrv));
      return true;
    }
    fromServer = false;
    final list = await requests.candidates(minBuild: minBuild?.call() ?? 0);
    if (list.isEmpty) {
      if (manual) {
        _setStage(SilentStage275.none);
        showPopup?.call(this);
      }
      return false;
    }
    final top = list.first.build;
    final gate = '$top|${_day(_clock())}';
    if (!manual) {
      String? last;
      try {
        last = await read(gateKey);
      } catch (_) {}
      if (last == gate) return false;
    }
    try {
      await write(gateKey, gate);
    } catch (_) {}
    _target = top;
    _version = list.first.version;
    AppLogger.info('APP_UPDATE_SILENT', detail: 'popup build=$top phones=${list.length} manual=$manual');
    _cancelled = false;
    needsAllow = false;
    _setStage(SilentStage275.getting);
    showPopup?.call(this);
    unawaited(_runAll(list));
    return true;
  }

  /// Bundle 299: from the server; a failure falls back to nearby phones.
  Future<void> _runServer(ServerApk299 apk) async {
    final run = ++_run;
    final url = server!.fileUrl(apk);
    final ok = await _fetchUrl(url, apk.size, apk.version, apk.build, sha256: apk.sha256);
    if (_cancelled || run != _run || ok) return;
    AppLogger.info('APP_UPDATE_SERVER', detail: 'fallback=phones');
    fromServer = false;
    _setStage(SilentStage275.nextPhone);
    final list = await requests.candidates(minBuild: minBuild?.call() ?? 0);
    if (_cancelled || run != _run) return;
    if (list.isEmpty) {
      AppLogger.info('APP_UPDATE_SILENT', detail: 'none');
      _setStage(SilentStage275.none);
      return;
    }
    await _runAll(list, startNext: true);
  }

  Future<void> _runAll(List<UpdateCandidate> list, {bool startNext = false}) async {
    final run = ++_run;
    var first = !startNext;
    for (final c in list) {
      if (_cancelled || run != _run) return;
      if (!first) _setStage(SilentStage275.nextPhone);
      first = false;
      requests.forget(c.peerId);
      final offer = await _askOne(c.peerId);
      if (_cancelled || run != _run) return;
      if (offer == null) continue;
      _setStage(SilentStage275.getting);
      if (await _fetch(offer, c.build)) return;
    }
    if (_cancelled || run != _run) return;
    AppLogger.info('APP_UPDATE_SILENT', detail: 'none');
    _setStage(SilentStage275.none);
  }

  /// Asks one phone; the offer, or null (not now / no answer / failed).
  Future<UpdateOffer?> _askOne(String peer) async {
    if (!await requests.ask(peer)) return null;
    final done = Completer<UpdateOffer?>();
    void look() {
      if (done.isCompleted) return;
      final o = requests.offer;
      if (o != null && o.peerId == peer && !o.qr && o.url.isNotEmpty) {
        done.complete(o);
        return;
      }
      final st = requests.statusOf(peer);
      if (_cancelled ||
          st == null ||
          st == AskStatus.notNow ||
          st == AskStatus.noAnswer ||
          st == AskStatus.failed ||
          st == AskStatus.qr) {
        done.complete(null);
      }
    }

    requests.addListener(look);
    addListener(look);
    look();
    // The service marks "no answer" after 60 s; this is only a backstop.
    final r =
        await done.future.timeout(UpdateRequestService.answerWait + const Duration(seconds: 5), onTimeout: () => null);
    requests.removeListener(look);
    removeListener(look);
    return r;
  }

  Future<bool> _fetch(UpdateOffer o, int build) {
    final url = Uri.parse(o.url).resolve(shareApkPath.substring(1)).toString();
    return _fetchUrl(url, o.size, o.version, build);
  }

  /// Downloads [url] (size limit), checks [sha256] when given (server file),
  /// then size + package; ready or false (file deleted).
  Future<bool> _fetchUrl(String url, int size, String version, int build, {String? sha256}) async {
    final dir = await native.updateDir();
    if (dir.isEmpty) return false;
    final file = '$dir/LinkUp-$build.apk';
    _size = size;
    _got = 0;
    if (version.isNotEmpty) _version = version;
    notifyListeners();
    try {
      await (download ?? _httpDownload)(url, file, size, (g) {
        _got = g;
        notifyListeners();
      });
      if (_cancelled) {
        await _delete(file, 'cancel');
        return true;
      }
      if (sha256 != null) {
        final got = await (hashFile ?? _sha256Of)(file);
        if (got.toLowerCase() != sha256.toLowerCase()) {
          AppLogger.warning('APP_UPDATE_SERVER', detail: 'sha=mismatch');
          await _delete(file, 'sha');
          return false;
        }
      }
      final bad = await native.checkApk(file, size);
      if (bad != null) {
        AppLogger.warning('APP_UPDATE_SILENT', detail: 'check=$bad');
        await _delete(file, 'bad');
        return false;
      }
      _path = file;
      try {
        await write(fileKey, '$file|$build');
      } catch (_) {}
      needsAllow = !await native.canInstall();
      AppLogger.info('APP_UPDATE_SILENT',
          detail: 'ready size=$size allow=${needsAllow ? 'needed' : 'ok'} from=${sha256 != null ? 'server' : 'phone'}');
      _setStage(SilentStage275.ready);
      showPopup?.call(this); // re-opens if it was swiped away
      return true;
    } catch (e) {
      AppLogger.warning('APP_UPDATE_SILENT', detail: 'download_fail=${e.runtimeType}');
      await _delete(file, 'fail');
      return false;
    }
  }

  static Future<String> _sha256Of(String path) async {
    final d = await crypto.sha256.bind(File(path).openRead()).first;
    return d.toString();
  }

  static Future<void> _httpDownload(String url, String path, int size, void Function(int got) progress) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('status ${res.statusCode}');
      sink = File(path).openWrite();
      var got = 0;
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        got += chunk.length;
        if (size > 0 && got > size) throw const HttpException('too big');
        sink.add(chunk);
        progress(got);
      }
      await sink.flush();
      if (size > 0 && got != size) throw const HttpException('size');
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  /// Install tapped: first time Android's allow page, then its update screen.
  Future<void> install() async {
    final p = _path;
    if (p == null) return;
    if (!await native.canInstall()) {
      needsAllow = true;
      notifyListeners();
      AppLogger.info('APP_UPDATE_SILENT', detail: 'allow_page');
      await native.openInstallSettings();
      return;
    }
    needsAllow = false;
    notifyListeners();
    final ok = await native.installApk(p);
    AppLogger.info('APP_UPDATE_SILENT', detail: 'installer=${ok ? 'open' : 'fail'}');
  }

  /// Cancel / Later: stops, deletes the file. Not again for this build today.
  Future<void> cancel() async {
    _cancelled = true;
    _run++;
    requests.cancel();
    final p = _path;
    _path = null;
    if (p != null) await _delete(p, 'cancel');
    AppLogger.info('APP_UPDATE_SILENT', detail: 'cancel');
    _setStage(SilentStage275.idle);
  }

  /// OK on "Could not get it now".
  void close() {
    if (_stage == SilentStage275.none) _setStage(SilentStage275.idle);
  }

  void _setStage(SilentStage275 s) {
    _stage = s;
    notifyListeners();
  }

  Future<void> _delete(String path, String why) async {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      AppLogger.info('APP_UPDATE_APK_DELETED', detail: 'why=$why');
    } catch (_) {}
    try {
      await write(fileKey, '');
    } catch (_) {}
  }

  /// At app start: the new version runs -> delete the downloaded file; any
  /// leftover older than 24 h too. True when this start is the first one
  /// after an update from a nearby phone.
  static Future<bool> cleanAtStart({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    UpdateInstallNative275 native = const UpdateInstallNative275(),
    String? dirOverride,
    DateTime? now,
  }) async {
    var updated = false;
    try {
      final mark = (await read(fileKey)) ?? '';
      final bar = mark.lastIndexOf('|');
      if (bar > 0) {
        final path = mark.substring(0, bar);
        final build = int.tryParse(mark.substring(bar + 1)) ?? 0;
        if (build > 0 && kAppBuild >= build) {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
          await write(fileKey, '');
          updated = true;
          AppLogger.info('APP_UPDATE_APK_DELETED', detail: 'why=installed');
        }
      }
    } catch (_) {}
    try {
      final dir = dirOverride ?? await native.updateDir();
      if (dir.isNotEmpty && Directory(dir).existsSync()) {
        final t = now ?? DateTime.now();
        for (final e in Directory(dir).listSync()) {
          if (e is! File) continue;
          if (t.difference(e.lastModifiedSync()) > oldFile) {
            e.deleteSync();
            AppLogger.info('APP_UPDATE_APK_DELETED', detail: 'why=old');
          }
        }
      }
    } catch (_) {}
    return updated;
  }

  @visibleForTesting
  static void resetForTest() {
    instance = null;
    showPopup = null;
    onUpdated = null;
  }
}
