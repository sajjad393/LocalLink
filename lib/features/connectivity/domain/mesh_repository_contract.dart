abstract interface class MeshRepositoryContract {
  Stream<Map<String, dynamic>> get events;
  Future<Map<String, dynamic>> topology();
  Future<void> flushQueue();
  Future<void> send({required String recipientId, required Map<String, dynamic> payload});
}
