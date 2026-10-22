import 'package:locallink/core/models/call.dart';

abstract interface class CallRepositoryContract {
  Future<List<CallRecord>> history();
  Future<List<CallRecord>> syncHistory();
  Future<Map<String, String>> loadDeviceNames();

  /// Resolves a peer's display label as the person-known profile nickname:
  /// directory display_name, else username. Returns null when nothing is
  /// known yet — callers must show a generic "Unknown user" style fallback
  /// and MUST NOT surface device names or raw device/user ids.
  Future<String?> labelForPeer(String id);
}
