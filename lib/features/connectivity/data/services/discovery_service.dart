import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:locallink/features/connectivity/data/models/discovered_server.dart';

export 'package:locallink/features/connectivity/data/models/discovered_server.dart';

class DiscoveryService {
  static const int discoveryPort = 45454;
  static const String request = 'LOCLINK_DISCOVER_V1';

  Future<List<DiscoveredServer>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final found = <String, DiscoveredServer>{};
    final completer = Completer<void>();
    Timer? timer;

    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        final decoded = jsonDecode(utf8.decode(datagram.data));
        if (decoded is! Map) return;
        final server = DiscoveredServer.fromJson(
          Map<String, dynamic>.from(decoded),
          datagram.address,
        );
        found[server.address] = server;
      } catch (_) {
        // Ignore unrelated UDP broadcasts on the same port.
      }
    });

    try {
      socket.send(
        utf8.encode(request),
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
      timer = Timer(timeout, finish);
      await completer.future;
    } finally {
      timer?.cancel();
      socket.close();
    }

    return found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
