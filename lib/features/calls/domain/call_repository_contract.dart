import 'package:locallink/core/models/call.dart';

abstract interface class CallRepositoryContract {
  Future<List<CallRecord>> history();
  Future<List<CallRecord>> syncHistory();
  Future<Map<String, String>> loadDeviceNames();
}
