// Bundle 210: the tiny web server that gives LinkUp to a nearby phone.
//
// Serves ONLY two things: the page (`/`) and the installed APK
// (`/LinkUp.apk`). Read only. No chats, contacts or other files.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/share_app/data/apk_share_page.dart';

class ShareServerException implements Exception {
  final String reason;
  const ShareServerException(this.reason);
  @override
  String toString() => 'ShareServerException($reason)';
}

/// One phone that asked for the APK (by its address).
class SharePhone {
  final int number;
  final String address;
  final int total;
  final DateTime startedAt;

  /// Highest byte reached (a resumed download continues it).
  int upTo = 0;
  int active = 0;
  DateTime? doneAt;

  SharePhone({
    required this.number,
    required this.address,
    required this.total,
    required this.startedAt,
  });

  bool get done => doneAt != null;
  double get progress => total <= 0 ? 0 : (upTo / total).clamp(0.0, 1.0);
  Duration? get took => doneAt?.difference(startedAt);
}

/// A parsed `Range: bytes=...` (inclusive [start]..[end]).
class ByteRange {
  final int start;
  final int end;
  const ByteRange(this.start, this.end);
  int get length => end - start + 1;
}

/// Null = no/ignored Range header (send everything).
/// Throws [RangeError] when the range can't be served (→ 416).
ByteRange? parseRange(String? header, int size) {
  if (header == null || header.trim().isEmpty) return null;
  final h = header.trim();
  if (!h.startsWith('bytes=')) return null;
  final spec = h.substring(6).split(',').first.trim();
  final dash = spec.indexOf('-');
  if (dash < 0) throw RangeError('bad range');
  final a = spec.substring(0, dash).trim();
  final b = spec.substring(dash + 1).trim();
  if (size <= 0) throw RangeError('empty file');
  if (a.isEmpty) {
    // Last N bytes.
    final n = int.tryParse(b);
    if (n == null || n <= 0) throw RangeError('bad suffix');
    final start = n >= size ? 0 : size - n;
    return ByteRange(start, size - 1);
  }
  final start = int.tryParse(a);
  if (start == null || start < 0 || start >= size) {
    throw RangeError('start out of file');
  }
  var end = b.isEmpty ? size - 1 : (int.tryParse(b) ?? -1);
  if (end < start) throw RangeError('end before start');
  if (end >= size) end = size - 1;
  return ByteRange(start, end);
}

class ApkShareServer {
  static const int maxDownloads = 3;
  static const int firstPort = 8080;
  static const int lastPort = 8089;

  final String apkPath;
  final int apkSize;
  final String version;
  final String ownerName;

  /// No download running and none started for this long → [onIdle].
  final Duration idleLimit;
  final Duration tick;
  final DateTime Function() now;

  /// Something changed (a phone, its %).
  void Function()? onChange;

  /// The idle limit was reached (the owner stops sharing).
  void Function()? onIdle;

  HttpServer? _server;
  Timer? _ticker;
  DateTime _lastActivity;
  int _activeDownloads = 0;
  bool _idleSent = false;
  final Map<String, SharePhone> _phones = <String, SharePhone>{};
  final Set<Future<dynamic>> _sending = <Future<dynamic>>{};

  ApkShareServer({
    required this.apkPath,
    required this.apkSize,
    required this.version,
    required this.ownerName,
    this.idleLimit = const Duration(minutes: 10),
    this.tick = const Duration(seconds: 5),
    DateTime Function()? now,
  })  : now = now ?? DateTime.now,
        _lastActivity = (now ?? DateTime.now)();

  int? get port => _server?.port;
  bool get running => _server != null;
  int get activeDownloads => _activeDownloads;

  @visibleForTesting
  set activeDownloadsForTest(int value) => _activeDownloads = value;

  /// Phones in arrival order.
  List<SharePhone> get phones {
    final l = _phones.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return List.unmodifiable(l);
  }

  /// Binds 0.0.0.0 on 8080..8089. Throws [ShareServerException] `port_busy`.
  Future<int> start({
    int from = firstPort,
    int to = lastPort,
    InternetAddress? address,
  }) async {
    if (_server != null) return _server!.port;
    for (var p = from; p <= to; p++) {
      try {
        final s = await HttpServer.bind(address ?? InternetAddress.anyIPv4, p);
        s.idleTimeout = const Duration(seconds: 60);
        s.autoCompress = false;
        _server = s;
        _lastActivity = now();
        _idleSent = false;
        s.listen(_handle, onError: (Object _) {}, cancelOnError: false);
        _ticker = Timer.periodic(tick, (_) => checkIdle());
        AppLogger.info('SHARE_APP', detail: 'server port=$p');
        return p;
      } on SocketException {
        continue;
      }
    }
    throw const ShareServerException('port_busy');
  }

  /// True (once) when nothing is downloading and nothing started for
  /// [idleLimit]; then [onIdle] runs.
  bool checkIdle() {
    if (_server == null || _idleSent) return false;
    if (_activeDownloads > 0) return false;
    if (now().difference(_lastActivity) < idleLimit) return false;
    _idleSent = true;
    AppLogger.info('SHARE_APP', detail: 'idle');
    onIdle?.call();
    return true;
  }

  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    _sending.clear();
    final s = _server;
    _server = null;
    _activeDownloads = 0;
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (_) {}
    }
  }

  void _touch() => _lastActivity = now();

  static String _short(String address) {
    final i = address.lastIndexOf('.');
    return i < 0 ? address : address.substring(i);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final method = req.method.toUpperCase();
      if (method != 'GET' && method != 'HEAD') {
        res.statusCode = HttpStatus.methodNotAllowed;
        res.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await res.close();
        return;
      }
      final path = req.uri.path;
      if (path == '/' || path == '/index.html') {
        _touch();
        await _page(res, method == 'HEAD');
        return;
      }
      if (path == shareApkPath) {
        await _apk(req, res, method == 'HEAD');
        return;
      }
      res.statusCode = HttpStatus.found;
      res.headers.set(HttpHeaders.locationHeader, '/');
      await res.close();
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _page(HttpResponse res, bool head) async {
    final body = buildSharePage(
        ownerName: ownerName, version: version, sizeBytes: apkSize);
    res.headers.contentType = ContentType.html;
    AppLogger.info('SHARE_APP', detail: 'get page');
    if (head) {
      res.headers.contentLength = -1;
      await res.close();
      return;
    }
    res.write(body);
    await res.close();
  }

  Future<void> _apk(HttpRequest req, HttpResponse res, bool head) async {
    _touch();
    final file = File(apkPath);
    if (!await file.exists()) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    ByteRange? range;
    try {
      range = parseRange(req.headers.value(HttpHeaders.rangeHeader), apkSize);
    } on RangeError {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$apkSize');
      await res.close();
      return;
    }
    res.headers.set(HttpHeaders.contentTypeHeader,
        'application/vnd.android.package-archive');
    res.headers.set('Content-Disposition',
        'attachment; filename="${shareApkFileName(version)}"');
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final start = range?.start ?? 0;
    final end = range?.end ?? apkSize - 1;
    if (range != null) {
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(
          HttpHeaders.contentRangeHeader, 'bytes $start-$end/$apkSize');
    }
    res.contentLength = end - start + 1;
    if (head) {
      await res.close();
      return;
    }
    if (_activeDownloads >= maxDownloads) {
      res.statusCode = HttpStatus.serviceUnavailable;
      res.headers.set(HttpHeaders.retryAfterHeader, '60');
      res.headers.contentType = ContentType.html;
      res.headers.removeAll('Content-Disposition');
      res.headers.removeAll(HttpHeaders.contentRangeHeader);
      final busy = buildBusyPage();
      res.contentLength = -1;
      res.write(busy);
      await res.close();
      return;
    }
    final address = req.connectionInfo?.remoteAddress.address ?? '?';
    final phone = _phones.putIfAbsent(
        address,
        () => SharePhone(
              number: _phones.length + 1,
              address: address,
              total: apkSize,
              startedAt: now(),
            ));
    phone.active++;
    _activeDownloads++;
    AppLogger.info('SHARE_APP',
        detail: 'apk start phone=${phone.number} from=$start '
            'ip=${_short(address)}');
    onChange?.call();
    var pos = start;
    // addStream pauses the file while the phone is slow, so the count is
    // what really went to the socket (nothing big is kept in memory).
    final counted = file.openRead(start, end + 1).map((chunk) {
      pos += chunk.length;
      if (pos > phone.upTo) phone.upTo = pos;
      _touch();
      onChange?.call();
      return chunk;
    });
    final sending = res.addStream(counted);
    _sending.add(sending);
    try {
      await sending;
      await res.close();
    } catch (_) {
      // The phone went away; Chrome can resume with Range.
    } finally {
      _sending.remove(sending);
      phone.active--;
      if (_activeDownloads > 0) _activeDownloads--;
      if (phone.upTo >= apkSize && phone.doneAt == null) {
        phone.doneAt = now();
        AppLogger.info('SHARE_APP',
            detail: 'apk done phone=${phone.number} '
                'ms=${phone.took?.inMilliseconds}');
      }
      _touch();
      onChange?.call();
    }
  }
}
