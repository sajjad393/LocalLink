// Bundle 223 Phase 2 (C, H): no uncaught socket errors; every try has a
// 10 s ready limit; "network back" redials a hanging try at once.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/services/websocket_service.dart';

bool _logged(String e) => AppLogFile.instance.pendingForTest
    .any((l) => l.contains('|$e|') || l.endsWith('|$e'));

List<String> _lines(String e) => AppLogFile.instance.pendingForTest
    .where((l) => l.contains('|$e|') || l.endsWith('|$e'))
    .toList();

/// A loopback WebSocket server. [sendReady] false = it never says `ready`.
Future<(HttpServer, List<WebSocket>)> _server({required bool sendReady}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <WebSocket>[];
  server.listen((req) async {
    final ws = await WebSocketTransformer.upgrade(req);
    sockets.add(ws);
    if (sendReady) {
      ws.add(jsonEncode({'type': 'ready', 'created_at': DateTime.now().toUtc().toIso8601String()}));
    }
    ws.listen((_) {}, onError: (_) {});
  });
  return (server, sockets);
}

Future<void> _waitFor(bool Function() ok, {int ms = 3000}) async {
  for (var i = 0; i < ms ~/ 20; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  setUp(() => AppLogFile.instance.resetForTest());

  test('223-7 a connect to a closed port gives no uncaught error; the stream error is logged', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final uncaught = <Object>[];
    final svc = WebSocketService();
    await runZonedGuarded(() async {
      try {
        await svc.connect('ws://127.0.0.1:$port/ws');
      } catch (_) {
        // connect() reports the failure to its caller; that is fine.
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }, (e, _) => uncaught.add(e));
    svc.dispose();
    expect(uncaught, isEmpty, reason: 'ready / sink.done errors must be caught');
    expect(_logged('WS_STREAM_ERROR') || _logged('WS_OPEN_FAILED'), isTrue);
  });

  test('223-8 source: ready and sink.done are both handled', () {
    final s = File('lib/core/services/websocket_service.dart').readAsStringSync();
    expect(s, contains('channel.ready.then<void>((_) {}, onError: (Object _) {})'));
    expect(s, contains('channel.sink.done.then<void>((_) {}, onError: (Object _) {})'));
  });

  test('223-19 a try that never gets ready is closed after the limit and a retry is scheduled', () async {
    final (server, sockets) = await _server(sendReady: false);
    final svc = WebSocketService()..retryReadyLimit = const Duration(milliseconds: 300);
    final sw = Stopwatch()..start();
    try {
      await svc.connect('ws://127.0.0.1:${server.port}/ws');
    } catch (_) {}
    sw.stop();
    expect(_lines('WS_RETRY_TIMEOUT').single, contains('after_ms=300'));
    expect(_logged('WS_RECONNECT_SCHEDULED'), isTrue);
    expect(sw.elapsedMilliseconds, lessThan(5000), reason: 'not the 8 s / 65 s wait');
    expect(svc.isConnected, isFalse);
    svc.dispose();
    for (final s in sockets) {
      await s.close();
    }
    await server.close(force: true);
  });

  test('223-20 networkBack() replaces a hanging try at once and resets the back-off', () async {
    final (server, sockets) = await _server(sendReady: false);
    final svc = WebSocketService()..retryReadyLimit = const Duration(milliseconds: 300);
    try {
      await svc.connect('ws://127.0.0.1:${server.port}/ws');
    } catch (_) {}
    expect(_logged('WS_RECONNECT_SCHEDULED'), isTrue);
    svc.retryReadyLimit = const Duration(seconds: 30); // the next try hangs
    svc.networkBack(); // nothing hanging: dial now instead of waiting 3 s
    await _waitFor(() => sockets.length >= 2);
    expect(sockets.length, 2);
    svc.networkBack(); // this one hangs: dropped, a new try starts
    await _waitFor(() => sockets.length >= 3);
    expect(sockets.length, 3);
    final back = _lines('WS_NETWORK_BACK');
    expect(back, hasLength(2));
    expect(back.last, contains('hanging=true'));
    svc.dispose();
    for (final s in sockets) {
      await s.close();
    }
    await server.close(force: true);
  });

  test('223-20b networkBack() does nothing while connected; ready cancels the limit', () async {
    final (server, sockets) = await _server(sendReady: true);
    final svc = WebSocketService()..retryReadyLimit = const Duration(milliseconds: 200);
    await svc.connect('ws://127.0.0.1:${server.port}/ws');
    expect(svc.isConnected, isTrue);
    svc.networkBack();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(_logged('WS_NETWORK_BACK'), isFalse);
    expect(_logged('WS_RETRY_TIMEOUT'), isFalse);
    expect(svc.isConnected, isTrue);
    expect(sockets, hasLength(1));
    svc.dispose();
    for (final s in sockets) {
      await s.close();
    }
    await server.close(force: true);
  });

  test('223-20c source: the messaging service calls networkBack on network up', () {
    final s = File('lib/features/messaging/data/services/reliable_messaging_service.dart').readAsStringSync();
    final part = s.substring(s.indexOf("if (eventType == 'network_changed')"));
    expect(part.substring(0, 400), contains('socket.networkBack()'));
  });
}
