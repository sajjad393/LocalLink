import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/server_reach.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';

export 'package:locallink/features/connectivity/data/models/discovered_server.dart';

/// One UDP socket used by the server search (a seam for tests).
abstract class DiscoverySocket {
  void send(List<int> data, InternetAddress to, int port);
  Stream<(List<int>, InternetAddress)> get replies;
  void close();
}

class _RawDiscoverySocket implements DiscoverySocket {
  _RawDiscoverySocket(this._socket) {
    _socket.broadcastEnabled = true;
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram == null) return;
      _out.add((datagram.data, datagram.address));
    }, onError: (Object e) {
      // Bundle 207 (N1): "Network is unreachable" also comes through the
      // socket stream. Nothing found from this socket, quietly.
      if (!_out.isClosed) _out.addError(e);
    }, cancelOnError: true);
  }

  final RawDatagramSocket _socket;
  final _out = StreamController<(List<int>, InternetAddress)>.broadcast();

  @override
  void send(List<int> data, InternetAddress to, int port) =>
      DiscoveryService.checkSent(_socket.send(data, to, port));

  @override
  Stream<(List<int>, InternetAddress)> get replies => _out.stream;

  @override
  void close() {
    _socket.close();
    unawaited(_out.close());
  }
}

/// Bundle 256 A1 + A2: the LinkUp server search.
///
/// 10 Nov (TECNO): ONE packet to 255.255.255.255, 3 s, no log -> the phone
/// made a phone-only account while the server was on the same Wi-Fi. Now:
/// * asks 3 times (0 s, 1 s, 2.5 s), up to [timeout] (5 s) in total;
/// * sends to 255.255.255.255 AND to the Wi-Fi subnet broadcast (x.y.z.255),
///   from any address and from the Wi-Fi address itself;
/// * stops right after the first answer (300 ms for a second server);
/// * Wi-Fi connected but no address yet -> waits up to 5 s first;
///   Wi-Fi known off -> no wait, no search;
/// * logs `SERVER_SEARCH start / try / found / none reason=...`.
class DiscoveryService {
  /// Bundle 265 (C1): `RawDatagramSocket.send` returns 0 when nothing left
  /// the phone - count it as a send error, not as a sent packet.
  @visibleForTesting
  static void checkSent(int bytes) {
    if (bytes <= 0) throw const SocketException('not sent');
  }

  static const int discoveryPort = 45454;
  static const String request = 'LOCLINK_DISCOVER_V1';

  /// When the 3 asks go out (only those inside the timeout).
  static const List<Duration> askAt = [
    Duration.zero,
    Duration(seconds: 1),
    Duration(milliseconds: 2500),
  ];

  /// After the first answer, wait this long for a second server.
  static const Duration afterFirst = Duration(milliseconds: 300);

  DiscoveryService({
    Future<List<String>> Function()? localAddresses,
    bool? Function()? wifiOn,
    Future<DiscoverySocket> Function(InternetAddress bindTo)? bind,
    this.wifiWait = const Duration(seconds: 5),
    this.wifiPoll = const Duration(milliseconds: 500),
  })  : _localAddresses = localAddresses ?? wifiAddresses,
        _wifiOn = wifiOn ?? (() => ServerReach.instance.wifi),
        _bind = bind ?? _bindRaw;

  final Future<List<String>> Function() _localAddresses;
  final bool? Function() _wifiOn;
  final Future<DiscoverySocket> Function(InternetAddress bindTo) _bind;
  final Duration wifiWait;
  final Duration wifiPoll;

  static Future<DiscoverySocket> _bindRaw(InternetAddress at) async =>
      _RawDiscoverySocket(await RawDatagramSocket.bind(at, 0));

  /// Private IPv4 addresses of this phone that can reach a LAN server
  /// (Wi-Fi Direct `p2p*` and mobile data interfaces left out).
  static Future<List<String>> wifiAddresses() async {
    try {
      final list = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      return [
        for (final i in list)
          if (!_skipInterface(i.name))
            for (final a in i.addresses)
              if (isPrivateIpv4(a.address)) a.address,
      ];
    } catch (_) {
      return const <String>[];
    }
  }

  static bool _skipInterface(String name) {
    final n = name.toLowerCase();
    return n.startsWith('p2p') ||
        n.startsWith('rmnet') ||
        n.startsWith('ccmni') ||
        n.startsWith('dummy') ||
        n.startsWith('tun');
  }

  static bool isPrivateIpv4(String value) {
    final p = value.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((x) => x == null || x < 0 || x > 255)) return false;
    final a = p[0]!, b = p[1]!;
    return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  /// Bundle 264 (A1): test-only server address (GitHub emulator run). Empty
  /// in every normal build, so phones search exactly as before.
  static const String testServerIp264 =
      String.fromEnvironment('LINKUP_TEST_SERVER_IP');

  /// Bundle 264 (A2): where the search asks. The test address is added only
  /// when it is set and private.
  static Set<String> targets264(List<String> addresses,
      {String testIp = testServerIp264}) {
    final ip = testIp.trim();
    return <String>{
      '255.255.255.255',
      for (final a in addresses) subnetBroadcast(a),
      if (ip.isNotEmpty && isPrivateIpv4(ip)) ip,
    };
  }

  /// "192.168.18.88" -> "192.168.18.255" (home Wi-Fi is /24 almost always).
  static String subnetBroadcast(String address) {
    final p = address.split('.');
    return p.length == 4 ? '${p[0]}.${p[1]}.${p[2]}.255' : '255.255.255.255';
  }

  Future<List<DiscoveredServer>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final started = DateTime.now();
    final wifi = _wifiOn();
    if (wifi == false) {
      AppLogger.info('SERVER_SEARCH', detail: 'none reason=no_wifi wait_ms=0');
      return const <DiscoveredServer>[];
    }
    var addresses = await _localAddresses();
    if (addresses.isEmpty) {
      // A2: Wi-Fi on (or not known) but no address yet - wait for it.
      final until = started.add(wifiWait);
      while (addresses.isEmpty && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(wifiPoll);
        addresses = await _localAddresses();
      }
      if (addresses.isEmpty) {
        AppLogger.info('SERVER_SEARCH',
            detail: 'none reason=${wifi == true ? 'wifi_not_ready' : 'no_wifi'} '
                'wait_ms=${DateTime.now().difference(started).inMilliseconds}');
        return const <DiscoveredServer>[];
      }
    }

    final targets = targets264(addresses); // Bundle 264 (A3)
    AppLogger.info('SERVER_SEARCH',
        detail: 'start addrs=${addresses.length} targets=${targets.length} '
            'timeout_ms=${timeout.inMilliseconds}');

    final sockets = <DiscoverySocket>[];
    final subs = <StreamSubscription<(List<int>, InternetAddress)>>[];
    final found = <String, DiscoveredServer>{};
    final done = Completer<void>();
    final timers = <Timer>[];
    var socketErrors = 0;
    var sends = 0;

    void finish() {
      if (!done.isCompleted) done.complete();
    }

    void onReply((List<int>, InternetAddress) r) {
      try {
        final decoded = jsonDecode(utf8.decode(r.$1));
        if (decoded is! Map) return;
        final server = DiscoveredServer.fromJson(Map<String, dynamic>.from(decoded), r.$2);
        if (server.hostIgnored) {
          AppLogger.info('SERVER_SEARCH',
              detail: 'host_ignored from=${r.$2.address}');
        }
        if (found.isEmpty) {
          AppLogger.info('SERVER_SEARCH',
              detail: 'found addr=${server.address} '
                  'ms=${DateTime.now().difference(started).inMilliseconds}');
          timers.add(Timer(afterFirst, finish));
        }
        found[server.address] = server;
      } catch (_) {
        // Ignore unrelated UDP packets on the same port.
      }
    }

    try {
      // Any address (as before) + each Wi-Fi address (the packet leaves
      // through Wi-Fi even when Android says "Wi-Fi has no internet").
      for (final at in <InternetAddress>[
        InternetAddress.anyIPv4,
        for (final a in addresses) InternetAddress(a),
      ]) {
        try {
          final s = await _bind(at);
          sockets.add(s);
          subs.add(s.replies.listen(onReply, onError: (Object _) => socketErrors++));
        } catch (_) {
          socketErrors++;
        }
      }
      if (sockets.isEmpty) {
        AppLogger.info('SERVER_SEARCH', detail: 'none reason=socket_error');
        return const <DiscoveredServer>[];
      }

      final data = utf8.encode(request);
      var n = 0;
      void ask() {
        if (done.isCompleted) return;
        n++;
        var ok = 0;
        for (final s in sockets) {
          for (final t in targets) {
            try {
              s.send(data, InternetAddress(t), discoveryPort);
              ok++;
            } on SocketException {
              // Bundle 201 (E1): no network (Wi-Fi off) = nothing, no error.
              socketErrors++;
            } catch (_) {
              socketErrors++;
            }
          }
        }
        sends += ok;
        AppLogger.info('SERVER_SEARCH', detail: 'try n=$n sent=$ok');
      }

      for (final at in askAt) {
        if (at >= timeout) continue;
        if (at == Duration.zero) {
          ask();
        } else {
          timers.add(Timer(at, ask));
        }
      }
      timers.add(Timer(timeout, finish));
      await done.future;
    } finally {
      for (final t in timers) {
        t.cancel();
      }
      for (final s in subs) {
        await s.cancel();
      }
      for (final s in sockets) {
        try {
          s.close();
        } catch (_) {}
      }
    }

    if (found.isEmpty) {
      AppLogger.info('SERVER_SEARCH',
          detail: 'none reason=${sends == 0 ? 'socket_error' : 'no_answer'} '
              'errors=$socketErrors ms=${DateTime.now().difference(started).inMilliseconds}');
    }
    return found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
