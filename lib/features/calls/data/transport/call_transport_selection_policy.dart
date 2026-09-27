import 'call_transport_mode.dart';

/// Local-only call transport selection. LAN and Wi-Fi Direct are physical
/// links underneath the same native mesh call transport.
final class CallTransportSelectionPolicy {
  const CallTransportSelectionPolicy._();

  static CallTransportMode select({required bool localRouteAvailable}) {
    if (!localRouteAvailable) {
      throw StateError('No local LAN, Wi-Fi Direct, or mesh route is available');
    }
    return CallTransportMode.offlineMesh;
  }
}
