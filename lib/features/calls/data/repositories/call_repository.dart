import 'package:locallink/features/calls/domain/call_repository_contract.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';

class CallRepository implements CallRepositoryContract {
  final LocalStore store;
  final LocalLinkApi api;
  final WebSocketService socket;

  const CallRepository({
    required this.store,
    required this.api,
    required this.socket,
  });

  @override
  Future<List<CallRecord>> history() => store.calls();

  @override
  Future<List<CallRecord>> syncHistory() async {
    try {
      if (socket.isConnected) {
        final localCalls = await store.calls();
        for (final call in localCalls.take(200)) {
          if (!call.status.isFinishedCallStatus) continue;
          try {
            await api.reconcileCall(call);
          } catch (_) {}
        }
      }

      final remote = await api.calls();
      for (final call in remote) {
        await store.saveCall(call);
      }
      return store.calls();
    } catch (_) {
      return store.calls();
    }
  }

  @override
  Future<Map<String, String>> loadDeviceNames() async {
    // Labels for call-history rows are profile nicknames resolved per peer.
    // The old implementation fed raw DEVICE names from the /devices
    // directory into people-facing rows, which is why call history showed
    // "My Android Phone (xxxx)". Unknown peers get no entry here; the UI
    // falls back to a generic label instead of an identifier.
    final ids = <String>{};
    try {
      for (final call in await store.calls()) {
        ids.addAll([call.callerId, call.calleeId]);
      }
    } catch (_) {
      return const {};
    }
    final labels = <String, String>{};
    for (final id in ids) {
      final label = await labelForPeer(id);
      if (label != null) labels[id] = label;
    }
    return labels;
  }

  @override
  Future<String?> labelForPeer(String id) async {
    try {
      return await store.peerDisplayName(id);
    } catch (_) {
      return null;
    }
  }
}
