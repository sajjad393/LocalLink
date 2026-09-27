import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/calls/data/transport/call_transport_selection_policy.dart';

void main() {
  test('local transport modes have stable wire names', () {
    expect(CallTransportMode.auto.wireName, 'auto');
    expect(CallTransportMode.offlineMesh.wireName, 'offline_mesh');
    expect(CallTransportMode.auto.isLocalOnly, isTrue);
    expect(CallTransportMode.offlineMesh.isLocalOnly, isTrue);
  });

  test('AUTO selects the local mesh transport when a local route exists', () {
    expect(
      CallTransportSelectionPolicy.select(
        localRouteAvailable: true,
      ),
      CallTransportMode.offlineMesh,
    );
  });

  test('AUTO never falls back to Internet when the local route is missing', () {
    expect(
      () => CallTransportSelectionPolicy.select(
        localRouteAvailable: false,
      ),
      throwsStateError,
    );
  });

  test('offline mesh rejects selection when the local route is missing', () {
    expect(
      () => CallTransportSelectionPolicy.select(
        localRouteAvailable: false,
      ),
      throwsStateError,
    );
  });
}
