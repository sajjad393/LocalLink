import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';

/// Bundle 295 (C): a phone that HOSTED the Nearby group when its Wi-Fi
/// Direct went off for a moment makes its group again at once when it comes
/// back (< 10 s off). Before: plan idle -> 20 s search -> create, 29 s on
/// the ZTE (13 Nov 19:15:12 -> 19:15:41); the friends found it 30 s later.
///
/// Only when the planner has nothing to do ('idle'): a join, a LAN link, a
/// foreign group or a held create always win. One try per off time.
class HostRehost295 {
  /// Off longer than this = a real stop (the old way: plan again).
  static const int maxOffMs = 10 * 1000;

  /// The re-create may run this long after Wi-Fi Direct is back.
  static const int windowMs = 15 * 1000;

  /// The group-lost report may come just before the "off" report.
  static const int hostLeftSlackMs = 3 * 1000;

  int _hostOffAt = 0;
  int _hostLeftAt = 0;
  int _until = 0;

  /// This phone stopped being the host (any reason).
  void hostLeft(int now) => _hostLeftAt = now;

  /// Wi-Fi Direct went off; [wasHost] = this phone hosts the group now.
  void p2pOff({required bool wasHost, required int now}) {
    final justLeft = _hostLeftAt > 0 && now >= _hostLeftAt && now - _hostLeftAt <= hostLeftSlackMs;
    _hostOffAt = wasHost || justLeft ? now : 0;
    _until = 0;
  }

  /// Wi-Fi Direct is back. True = make the group again now.
  bool p2pOn(int now) {
    final at = _hostOffAt;
    _hostOffAt = 0;
    if (at <= 0 || now < at || now - at >= maxOffMs) return false;
    _until = now + windowMs;
    return true;
  }

  bool pending(int now) => _until > 0 && now < _until;

  void used() => _until = 0;

  /// The plan to run: [plan], or a create when a re-host is pending and the
  /// planner is idle with no group of our own.
  NearbyGroupAction choose(NearbyGroupAction plan, {required int now, required NearbyGroupRole role, required bool hasGroup}) {
    if (!pending(now) || hasGroup || role != NearbyGroupRole.none) return plan;
    if (plan.kind != NearbyGroupActionKind.none || plan.reason != 'idle') return plan;
    return const NearbyGroupAction.create(reason);
  }

  static const String reason = 'rehost_p2p';
}
