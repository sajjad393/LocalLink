import 'dart:async';

import 'package:flutter/services.dart';

import 'package:locallink/core/notifications/notification_action.dart';

/// Native notification boundary. It never sends a message or call itself.
final class LocalLinkNotificationPlatform {
  static const MethodChannel _channel =
      MethodChannel('locallink/notifications');
  static const EventChannel _actionsChannel =
      EventChannel('locallink/notification_actions');

  final StreamController<LocalLinkNotificationAction> _actions =
      StreamController<LocalLinkNotificationAction>.broadcast();
  StreamSubscription<dynamic>? _nativeActionSubscription;
  bool _disposed = false;

  LocalLinkNotificationPlatform() {
    _nativeActionSubscription = _actionsChannel.receiveBroadcastStream().listen(
      (event) {
        if (_disposed || event is! Map) return;
        try {
          _actions.add(LocalLinkNotificationAction.fromMap(event));
        } catch (_) {
          // Invalid or stale notification intents are ignored at the boundary.
        }
      },
      onError: (_) {},
    );
  }

  Stream<LocalLinkNotificationAction> get actions => _actions.stream;

  Future<void> initialize() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('initialize');
    } catch (_) {}
  }

  Future<void> requestPermission() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } catch (_) {}
  }

  Future<bool> notificationsEnabled() async {
    if (_disposed) return false;
    try {
      return await _channel.invokeMethod<bool>('notificationsEnabled') ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<void> openSystemSettings() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {}
  }

  Future<void> showMessage({
    required int notificationId,
    required String conversationType,
    required String conversationId,
    required String messageId,
    required String senderId,
    required String recipientId,
    required String title,
    required String body,
    required String summary,
    required String publicTitle,
    required String publicBody,
    required String initials,
    String? avatarPath,
    String? imagePath,
    String? attachmentId,
    required int unreadCount,
    required bool silent,
    required int visibility,
  }) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('showMessage', {
        'notification_id': notificationId,
        'conversation_type': conversationType,
        'conversation_id': conversationId,
        'message_id': messageId,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'title': title,
        'body': body,
        'summary': summary,
        'public_title': publicTitle,
        'public_body': publicBody,
        'initials': initials,
        'avatar_path': avatarPath,
        'image_path': imagePath,
        'attachment_id': attachmentId,
        'unread_count': unreadCount,
        'silent': silent,
        'visibility': visibility,
      });
    } catch (_) {}
  }

  Future<void> showSummary({
    required int notificationId,
    required String conversationType,
    required String conversationId,
    required String title,
    required String body,
    required bool silent,
    required int visibility,
  }) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('showSummary', {
        'notification_id': notificationId,
        'conversation_type': conversationType,
        'conversation_id': conversationId,
        'title': title,
        'body': body,
        'silent': silent,
        'visibility': visibility,
      });
    } catch (_) {}
  }

  Future<void> showSystem({
    required int notificationId,
    required String title,
    required String body,
    required bool silent,
  }) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('showSystem', {
        'notification_id': notificationId,
        'title': title,
        'body': body,
        'silent': silent,
      });
    } catch (_) {}
  }

  Future<void> cancelNotification(int notificationId) async {
    if (_disposed) return;
    if (notificationId <= 0) return;
    try {
      await _channel.invokeMethod<void>('cancel', {
        'notification_id': notificationId,
      });
    } catch (_) {}
  }

  Future<void> cancelAllMessages() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('cancelMessages');
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _channel.invokeMethod<void>('cancelMessages');
    } catch (_) {}
    await _nativeActionSubscription?.cancel();
    await _actions.close();
  }
}
