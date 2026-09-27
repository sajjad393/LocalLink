import 'package:equatable/equatable.dart';

enum CallNotificationActionType { accept, reject }

class CallNotificationAction extends Equatable {
  final CallNotificationActionType type;
  final String callId;
  final String callerId;

  const CallNotificationAction({
    required this.type,
    required this.callId,
    required this.callerId,
  });

  factory CallNotificationAction.fromMap(Map<dynamic, dynamic> map) {
    final action = map['action']?.toString() ?? '';
    final callId = map['call_id']?.toString().trim() ?? '';
    final callerId = map['caller_id']?.toString().trim() ?? '';
    if (callId.isEmpty || callerId.isEmpty) {
      throw const FormatException('Invalid call notification action');
    }
    final type = switch (action) {
      'accept' => CallNotificationActionType.accept,
      'reject' => CallNotificationActionType.reject,
      _ => throw const FormatException('Unknown call notification action'),
    };
    return CallNotificationAction(type: type, callId: callId, callerId: callerId);
  }

  @override
  List<Object?> get props => [type, callId, callerId];
}
