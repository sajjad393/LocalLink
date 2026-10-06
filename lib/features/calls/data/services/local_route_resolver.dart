import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

export 'package:locallink/features/connectivity/domain/local_route.dart';

/// Compatibility facade for call code while route selection moves to the
/// shared connectivity policy.
final class LocalRouteResolver {
  final LocalRoutePolicyService _policy;

  LocalRouteResolver(PeerTransportContract transport)
      : _policy = LocalRoutePolicyService(transport);

  Future<LocalRouteResult> resolve(String peerId) => _policy.resolve(peerId);
}
