import 'dart:async';
import 'dart:convert';

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

  /// [bySender]: Bundle 208 (E7) - the sender pressed X (no auto ask).
  void markCancelled(String messageId, {bool bySender = false}) {
    if (messageId.isEmpty) return;
    if (bySender) _senderStopped.add(messageId);
    if (isCancelled(messageId)) return;
    cancelled.value = {...cancelled.value, messageId};
  }

  // ---- Bundle 208 (E2): who stopped a file -------------------------------

  /// Settings key for the files I stopped with X (kept after a restart).
  static const String stoppedKey = 'media_stopped_by_me_v1';
  static const int maxStopped = 300;

  final List<String> _stoppedByMe = <String>[];
  final Set<String> _senderStopped = <String>{};
  Future<void> Function(String key, String value)? _write;

  /// File ids I stopped with X: never downloaded again by itself.
  bool stoppedByMe(String fileId) =>
      fileId.isNotEmpty && _stoppedByMe.contains(baseId(fileId));

  /// Message ids whose sender pressed X (this run only).
  bool stoppedBySender(String messageId) => _senderStopped.contains(messageId);

  /// A group file travels as `<fileId>.g<8hex>`.
  static String baseId(String id) {
    final m = RegExp(r'^(.+)\.g[0-9a-f]{8}$').firstMatch(id);
    return m == null ? id : m.group(1)!;
  }

  Future<void> loadStops({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _write = write;
    try {
      final raw = await read(stoppedKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      _stoppedByMe
        ..clear()
        ..addAll(list.map((e) => e.toString()).where((e) => e.isNotEmpty));
    } catch (_) {}
  }

  /// I pressed X on a file coming to me.
  void stopByMe(String fileId) {
    final id = baseId(fileId);
    if (id.isEmpty) return;
    _stoppedByMe.remove(id);
    _stoppedByMe.add(id);
    while (_stoppedByMe.length > maxStopped) {
      _stoppedByMe.removeAt(0);
    }
    _saveStops();
  }

  /// I tapped "Tap to download": the file may come again by itself.
  void clearStops(String messageId, String fileId) {
    _senderStopped.remove(messageId);
    if (_stoppedByMe.remove(baseId(fileId))) _saveStops();
  }

  void _saveStops() {
    final write = _write;
    if (write == null) return;
    unawaited(write(stoppedKey, jsonEncode(_stoppedByMe)).catchError((Object _) {}));
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
    _stoppedByMe.clear();
    _senderStopped.clear();
    _write = null;
  }
}
