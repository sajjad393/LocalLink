enum CallTransportMode {
  auto,
  offlineMesh,
}

extension CallTransportModeX on CallTransportMode {
  String get wireName => switch (this) {
        CallTransportMode.auto => 'auto',
        CallTransportMode.offlineMesh => 'offline_mesh',
      };

  bool get isLocalOnly => true;
}
