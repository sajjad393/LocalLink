import 'dart:async';
import 'dart:io';

import 'package:locallink/features/connectivity/data/models/network_snapshot.dart';

/// Polls OS network interfaces so connectivity can react to local-network changes
/// without requiring an additional connectivity plugin.
class NetworkMonitorService {
  final Duration pollInterval;
  final _changes = StreamController<NetworkSnapshot>.broadcast();
  Timer? _timer;
  NetworkSnapshot _current = const NetworkSnapshot.empty();
  bool _running = false;

  NetworkMonitorService({
    this.pollInterval = const Duration(seconds: 5),
  });

  Stream<NetworkSnapshot> get changes => _changes.stream;
  NetworkSnapshot get current => _current;

  Future<NetworkSnapshot> snapshot() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final names = interfaces.map((e) => e.name).toList()..sort();
    final addresses = <String>[];
    for (final interface in interfaces) {
      addresses.addAll(interface.addresses.map((address) => address.address));
    }
    addresses.sort();
    return NetworkSnapshot(
      interfaceNames: names,
      ipv4Addresses: addresses,
    );
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _poll(forceEmit: true);
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  Future<void> _poll({bool forceEmit = false}) async {
    if (!_running) return;
    try {
      final next = await snapshot();
      final changed = !_current.sameNetworkAs(next);
      _current = next;
      if (forceEmit || changed) _changes.add(next);
    } catch (_) {
      // Network interfaces can disappear during Wi-Fi transitions.
    }
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    await stop();
    await _changes.close();
  }
}
