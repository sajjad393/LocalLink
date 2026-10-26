abstract interface class PeerTransportContract {
  Stream<Map<String, dynamic>> get events;
  bool get isStarted;

  Future<void> configure({
    required String deviceId,
    required bool connected,
    required bool groupOwner,
    String? groupOwnerAddress,
    required List<String> knownPeers,
  });

  Future<void> updateKnownPeers(List<String> peerIds);

  /// Bundle 108: fire a signed identity exchange packet at a locally visible
  /// peer over the LAN beacon channel (pre-trust; only pair packets fly).
  Future<void> sendPairPayload({
    required String nodeId,
    required String kind,
    required String body,
  });
  Future<Map<String, dynamic>> topology();
  Future<void> flushQueue();
  Future<void> resume();
  Future<void> clearStorage();
  Future<void> broadcast(Map<String, dynamic> payload);
  Future<void> send({required String recipientId, required Map<String, dynamic> payload});
  Future<void> sendFile({required String recipientId, required String filePath, required String fileId, required String messageId, required String fileName, required String contentType});
  Future<void> cancelFile(String fileId);
  Future<void> stop();
  Future<void> dispose();
}
