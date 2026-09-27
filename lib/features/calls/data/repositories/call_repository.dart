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
    try {
      final devices = await api.devices();
      return {
        for (final device in devices) device.id: device.name,
      };
    } catch (_) {
      return const {};
    }
  }
}
