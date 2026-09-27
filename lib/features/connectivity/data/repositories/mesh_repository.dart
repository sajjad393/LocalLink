import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/connectivity/domain/mesh_repository_contract.dart';

final class MeshRepository implements MeshRepositoryContract {
  final PeerTransportContract transport;

  MeshRepository({required this.transport});

  @override
  Stream<Map<String, dynamic>> get events => transport.events;

  @override
  Future<Map<String, dynamic>> topology() => transport.topology();

  @override
  Future<void> flushQueue() => transport.flushQueue();

  @override
  Future<void> send({required String recipientId, required Map<String, dynamic> payload}) =>
      transport.send(recipientId: recipientId, payload: payload);
}
