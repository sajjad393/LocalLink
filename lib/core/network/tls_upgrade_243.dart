import 'dart:async';

import 'package:locallink/core/network/tls_pin_243.dart';
import 'package:locallink/core/security/security_policy.dart';
import 'package:locallink/core/security/server_proof_231.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';

typedef TlsProbe243 = Future<bool> Function(String host, int port, String sha);
typedef HttpProbe243 = Future<bool> Function(Uri httpBase);

/// Bundle 243 (audit S3 part B): moves this phone to HTTPS when the server
/// offers it, and back to HTTP if HTTPS stops working.
///
/// Every [tick] (20 s after start, then every 15 min):
/// * pin active: nothing while the WebSocket is up. Socket down and HTTPS
///   fails but HTTP answers -> the pin is turned off (`fallback_http`).
/// * pin not active: asks the pairing info (v2). Only a proof signed by the
///   server key this phone ALREADY pinned (bundle 231) is used - a phone
///   must have reached the server once before. Then HTTPS is tried with
///   that certificate hash; only when it answers is the pin turned on.
/// A changed certificate is taken only through a new signed proof; a
/// certificate that doesn't match the pin is refused by
/// [PinnedHttpOverrides243] (then HTTPS fails and the phone falls back).
class TlsUpgrade243 {
  TlsUpgrade243({
    required this.serverAddress,
    required this.pairingInfo,
    required this.read,
    required this.write,
    required this.socketUp,
    this.onHttpsOn,
    TlsProbe243? probeTls,
    HttpProbe243? probeHttp,
  })  : _probeTls = probeTls ?? probeTls243,
        _probeHttp = probeHttp ?? _defaultHttpProbe;

  final String? Function() serverAddress;
  final Future<PairingInfo> Function() pairingInfo;
  final TlsRead243 read;
  final TlsWrite243 write;
  final bool Function() socketUp;

  /// Bundle 255 D1: called after a tick that leaves HTTPS on ('on' / 'ok'),
  /// so a live socket still on plain ws:// can move to wss://.
  final void Function()? onHttpsOn;
  final TlsProbe243 _probeTls;
  final HttpProbe243 _probeHttp;

  Timer? _timer;
  bool _busy = false;
  final Set<String> _logged = {};

  void start() {
    _timer?.cancel();
    Timer(const Duration(seconds: 20), () => unawaited(tick()));
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => unawaited(tick()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _once(String key, String detail) {
    if (_logged.add(key)) AppLogger.info('TLS_243', detail: detail);
  }

  /// Returns what it did (for logs and tests).
  Future<String> tick() async {
    if (_busy) return 'busy';
    _busy = true;
    try {
      final r = await _tick();
      if (r == 'on' || r == 'ok') onHttpsOn?.call();
      return r;
    } catch (e) {
      _once('error', 'result=error');
      return 'error';
    } finally {
      _busy = false;
    }
  }

  Future<String> _tick() async {
    final raw = serverAddress()?.trim() ?? '';
    if (raw.isEmpty) {
      TlsPin243.clearMemory();
      return 'no_server';
    }
    final Uri httpBase;
    try {
      httpBase = SecurityPolicy.normalizeServerUri(raw, tls243: false);
    } catch (_) {
      return 'bad_address';
    }
    final host = httpBase.host.toLowerCase();

    if (TlsPin243.active && TlsPin243.host == host) {
      if (socketUp()) return 'ok';
      if (await _probeTls(host, TlsPin243.port, TlsPin243.sha)) return 'ok';
      if (await _probeHttp(httpBase)) {
        await TlsPin243.save(write,
            host: host, port: TlsPin243.port, sha: TlsPin243.sha, active: false);
        AppLogger.warning('TLS_243', detail: 'result=fallback_http port=${TlsPin243.port}');
        return 'fallback_http';
      }
      return 'server_away';
    }

    if (TlsPin243.active && TlsPin243.host != host) {
      // The server got a new address: HTTP to the new one until the next
      // signed proof pins it again.
      await TlsPin243.save(write,
          host: TlsPin243.host, port: TlsPin243.port, sha: TlsPin243.sha, active: false);
    }

    final PairingInfo info;
    try {
      info = await pairingInfo();
    } catch (_) {
      return 'server_away';
    }
    if (info.proofVersion != 2 || info.tlsPort <= 0 || !TlsPin243.validSha(info.tlsCertSha256)) {
      _once('no_tls', 'result=server_no_tls');
      return 'server_no_tls';
    }
    if (!info.proofOk) return 'bad_proof';
    final pinned = (await read(ServerProof231.trustKeySetting))?.trim() ?? '';
    if (pinned.isEmpty || pinned != info.serverKey) {
      _once('no_pin', 'result=wait_key_pin');
      return 'wait_key_pin';
    }
    if (await ServerProof231.check(info, read: read) != null) return 'bad_proof';
    final sha = info.tlsCertSha256.toLowerCase();
    if (!await _probeTls(host, info.tlsPort, sha)) {
      _once('probe_${info.tlsPort}', 'result=probe_failed port=${info.tlsPort}');
      return 'probe_failed';
    }
    final changed = TlsPin243.sha.isNotEmpty && TlsPin243.sha != sha;
    await TlsPin243.save(write,
        host: host, port: info.tlsPort, sha: sha, active: true, httpPort: httpBase.port);
    AppLogger.info('TLS_243',
        detail: 'result=on url=https://$host:${info.tlsPort} sha=${TlsPin243.tail(sha)}'
            '${changed ? ' cert_changed=signed' : ''}');
    return 'on';
  }

  static Future<bool> _defaultHttpProbe(Uri httpBase) async {
    // Plain HTTP health check, used only to decide the fallback.
    return probeHttpHealth243(httpBase);
  }
}
