import 'package:flutter/widgets.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';

abstract interface class CallGateway {
  Stream<CallSession?> get sessionStream;
  Stream<List<CallRecord>> get historyStream;
  CallSession? get session;
  String? get selfDeviceId;
  void start();
  Future<void> syncHistory();
  Future<List<CallRecord>> history();
  Future<void> startCall(Device device);
  Future<void> acceptIncoming();
  Future<void> rejectIncoming({String reason = 'rejected'});
  Future<void> endCall({String reason = 'hangup'});
  Future<void> toggleMute();
  Future<void> toggleVideo();
  Future<void> switchCamera();
  Future<void> toggleSpeaker();
  void onAppLifecycleState(AppLifecycleState state);
  Future<void> dispose();
}
