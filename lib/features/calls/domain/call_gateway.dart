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

  /// Bundle 93: WhatsApp-style audio→video switch consent (see CallSession).
  Future<void> acceptVideoSwitch(); // enable our camera for this call
  Future<void> declineVideoSwitch(); // stay audio-only, suppress re-asks
  Future<void> switchCamera();
  Future<void> toggleSpeaker();
  void onAppLifecycleState(AppLifecycleState state);

  /// Bundle 146: notification Accept asks the app to show the call screen
  /// for a live call (it is no longer 'ringing' by then).
  Stream<String> get callScreenRequests;
  String? get requestedCallScreenId;
  void clearCallScreenRequest(String callId);

  /// Bundle 146: an Accept arrived for a call that no longer exists.
  Stream<String> get callUnavailableNotices;
  String? takeCallUnavailableNotice();
  Future<void> dispose();
}
