import 'package:flutter/foundation.dart';

typedef MediaTransferAction = Future<bool> Function(
    String messageId, String attachmentId);

/// Bundle 174 (6): what the chat bubble's transfer circle can ask for.
///
/// The messaging service plugs in the real actions at start-up. The bubble
/// only talks to this, so it never needs the network code.
///
/// * [cancelSend]   - sender pressed X on its own photo/video. The bubble
///                    then shows "Not sent - tap to retry".
/// * [cancelReceive]- receiver pressed X. The bubble then shows
///                    "Tap to download".
/// * [requestResend]- receiver tapped "Tap to download" on a nearby file:
///                    asks the sender's phone to send it again.
class MediaTransferActions {
  MediaTransferActions._();

  static final MediaTransferActions instance = MediaTransferActions._();

  MediaTransferAction? cancelSend;
  MediaTransferAction? cancelReceive;
  MediaTransferAction? requestResend;

  /// Message ids whose incoming media was cancelled (by either side). The
  /// bubble shows "Tap to download" for these. Cleared when bytes move again.
  final ValueNotifier<Set<String>> cancelled =
      ValueNotifier<Set<String>>(const <String>{});

  bool isCancelled(String messageId) => cancelled.value.contains(messageId);

  void markCancelled(String messageId) {
    if (messageId.isEmpty || isCancelled(messageId)) return;
    cancelled.value = {...cancelled.value, messageId};
  }

  void clearCancelled(String messageId) {
    if (!isCancelled(messageId)) return;
    cancelled.value = {...cancelled.value}..remove(messageId);
  }

  @visibleForTesting
  void resetForTest() {
    cancelSend = null;
    cancelReceive = null;
    requestResend = null;
    cancelled.value = const <String>{};
  }
}
