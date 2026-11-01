import 'dart:async';

import 'package:locallink/core/services/app_logger.dart';

/// Bundle 194: the automatic first message after YOU add a friend.
const String kFriendHelloText = 'Hello 👋';

/// Bundle 194: why a Hello is sent or skipped (also the log word).
enum FriendHelloDecision {
  send('sent'),
  skipSelf('self'),
  skipNoDevice('no_device'),
  skipBlocked('blocked'),
  skipChatHasMessages('chat_has_messages'),
  skipRecentlySent('already_sent'),
  skipMutualOtherSends('mutual_other_sends');

  const FriendHelloDecision(this.word);
  final String word;
}

/// Bundle 195a: what to do with an incoming "Hello 👋".
enum IncomingHelloAction {
  /// A normal message notification.
  normal,

  /// No notification: the "X added you" notice was just shown.
  silent,

  /// Show "X added you as a friend" (Remove / Block) instead of the message:
  /// the Hello came from someone new before their friend link.
  friendNotice,
}

/// Bundle 194: one "I added this person" event (Nearby / online / profile).
class FriendAddedByMe {
  const FriendAddedByMe({
    required this.userId,
    required this.deviceId,
    required this.displayName,
    required this.source,
    this.mutual = false,
  });

  final String userId;
  final String deviceId;
  final String displayName;

  /// nearby | online | profile
  final String source;

  /// Both phones tapped Add at the same time (Nearby).
  final bool mutual;
}

/// Bundle 194: pure rules (unit tested).
class FriendHelloPolicy {
  FriendHelloPolicy._();

  /// A Hello sent this recently is never sent again (retries, packet copies,
  /// app restarts). Later, Q5 applies: a new Hello only when the chat is empty.
  static const int recentMs = 10 * 60 * 1000;

  /// The other phone tapped Add within this window = both added at once.
  static const int mutualWindowMs = 2 * 60 * 1000;

  /// An incoming Hello this soon after the "X added you" notice comes in
  /// silently (one notice only).
  static const int noticeSilenceMs = 3 * 60 * 1000;

  /// A contact that a received message auto-added this recently still
  /// counts as NEW for the "X added you" notice.
  static const int autoAddGraceMs = 5 * 60 * 1000;

  static FriendHelloDecision decide({
    required String myUserId,
    required String peerUserId,
    required String peerDeviceId,
    required String myDeviceId,
    required bool blocked,
    required bool chatHasMessages,
    required int nowMs,
    int? lastSentAtMs,
    int? peerTappedAtMs,
  }) {
    if (peerDeviceId.trim().isEmpty) return FriendHelloDecision.skipNoDevice;
    if ((peerUserId.isNotEmpty && peerUserId == myUserId) ||
        peerDeviceId == myDeviceId) {
      return FriendHelloDecision.skipSelf;
    }
    if (blocked) return FriendHelloDecision.skipBlocked;
    if (lastSentAtMs != null &&
        nowMs - lastSentAtMs >= 0 &&
        nowMs - lastSentAtMs < recentMs) {
      return FriendHelloDecision.skipRecentlySent;
    }
    if (chatHasMessages) return FriendHelloDecision.skipChatHasMessages;
    // Both tapped Add: only the phone with the smaller account id sends.
    if (peerTappedAtMs != null &&
        nowMs - peerTappedAtMs >= 0 &&
        nowMs - peerTappedAtMs < mutualWindowMs &&
        myUserId.isNotEmpty &&
        peerUserId.isNotEmpty &&
        myUserId.compareTo(peerUserId) > 0) {
      return FriendHelloDecision.skipMutualOtherSends;
    }
    return FriendHelloDecision.send;
  }

  /// The incoming message is the friend Hello right after the notice.
  static bool silenceIncoming({
    required String body,
    required int nowMs,
    int? noticeAtMs,
  }) {
    if (body.trim() != kFriendHelloText) return false;
    if (noticeAtMs == null) return false;
    final age = nowMs - noticeAtMs;
    return age >= 0 && age < noticeSilenceMs;
  }

  /// Bundle 195a: a Hello from someone new counts for this long.
  static const int helloFromNewMs = 2 * 60 * 1000;

  static IncomingHelloAction incomingHelloAction({
    required String body,
    required int nowMs,
    int? noticeAtMs,
    int? helloFromNewAtMs,
  }) {
    if (body.trim() != kFriendHelloText) return IncomingHelloAction.normal;
    if (silenceIncoming(body: body, nowMs: nowMs, noticeAtMs: noticeAtMs)) {
      return IncomingHelloAction.silent;
    }
    if (helloFromNewAtMs != null) {
      final age = nowMs - helloFromNewAtMs;
      if (age >= 0 && age < helloFromNewMs) {
        return IncomingHelloAction.friendNotice;
      }
    }
    return IncomingHelloAction.normal;
  }

  /// "X added you" must still show when the only reason they look like an
  /// old friend is that their Hello arrived first and auto-added them.
  static bool treatAsNewFriend({
    required bool wasContact,
    required int nowMs,
    int? autoAddedAtMs,
  }) {
    if (!wasContact) return true;
    if (autoAddedAtMs == null) return false;
    final age = nowMs - autoAddedAtMs;
    return age >= 0 && age < autoAddGraceMs;
  }
}

/// Bundle 194: short in-memory notes shared by pairing, directory, messages
/// and notifications (nothing here is saved; a restart forgets it).
class FriendAddMemory {
  FriendAddMemory._();

  static final Map<String, int> _noticeAt = <String, int>{};
  static final Map<String, int> _autoAddedAt = <String, int>{};
  static final Map<String, int> _peerTappedAt = <String, int>{};
  static int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  static void _put(Map<String, int> m, String key) {
    final k = key.trim();
    if (k.isEmpty) return;
    if (m.length > 200) m.clear();
    m[k] = now();
  }

  /// "X added you as a friend" was shown here for this phone.
  static void noteNotice(String deviceId) => _put(_noticeAt, deviceId);
  static int? noticeAt(String deviceId) => _noticeAt[deviceId.trim()];

  /// A received message auto-added this user as a contact.
  static void noteAutoAdded(String userId) => _put(_autoAddedAt, userId);
  static int? autoAddedAt(String userId) => _autoAddedAt[userId.trim()];
  static void clearAutoAdded(String userId) => _autoAddedAt.remove(userId.trim());

  /// The other phone tapped Add (its pair request arrived here).
  static void notePeerTapped(String deviceId) => _put(_peerTappedAt, deviceId);
  static int? peerTappedAt(String deviceId) => _peerTappedAt[deviceId.trim()];

  static bool silenceIncomingHello(String senderDeviceId, String body) =>
      FriendHelloPolicy.silenceIncoming(
          body: body, nowMs: now(), noticeAtMs: noticeAt(senderDeviceId));

  /// Bundle 195a: a Hello came from someone who was NOT a friend yet.
  static final Map<String, ({int at, String userId, String name})>
      _helloFromNew = <String, ({int at, String userId, String name})>{};

  static void noteHelloFromNew(String deviceId,
      {required String userId, String name = ''}) {
    final k = deviceId.trim();
    if (k.isEmpty || userId.trim().isEmpty) return;
    if (_helloFromNew.length > 100) _helloFromNew.clear();
    _helloFromNew[k] = (at: now(), userId: userId.trim(), name: name.trim());
  }

  static ({int at, String userId, String name})? helloFromNew(
          String deviceId) =>
      _helloFromNew[deviceId.trim()];

  static IncomingHelloAction incomingHelloAction(
      String senderDeviceId, String body) {
    final fromNew = helloFromNew(senderDeviceId);
    return FriendHelloPolicy.incomingHelloAction(
        body: body,
        nowMs: now(),
        noticeAtMs: noticeAt(senderDeviceId),
        helloFromNewAtMs: fromNew?.at);
  }

  static void resetForTest() {
    _helloFromNew.clear();
    _noticeAt.clear();
    _autoAddedAt.clear();
    _peerTappedAt.clear();
    now = () => DateTime.now().millisecondsSinceEpoch;
  }
}

/// Bundle 194: the app registers how to open a chat / show a short toast.
/// Nothing registered (tests, closed-app engine) = nothing opens.
class FriendChatOpener {
  FriendChatOpener._();

  static Future<bool> Function(String deviceId, String displayName)? open;
  static void Function(String text)? toast;

  static Future<bool> openChat(String deviceId, String displayName,
      {required String reason}) async {
    var opened = false;
    try {
      final handler = open;
      if (handler != null) opened = await handler(deviceId, displayName);
    } catch (_) {
      opened = false;
    }
    AppLogger.info('FRIEND_ADD_OPEN_CHAT',
        detail: 'to=${_id6(deviceId)} reason=$reason '
            'opened=${opened ? 'y' : 'n'}');
    return opened;
  }
}

String _id6(String id) {
  final t = id.trim();
  return t.length <= 6 ? (t.isEmpty ? '-' : t) : t.substring(t.length - 6);
}

/// Bundle 194: sends the one automatic "Hello 👋" and opens the chat.
class FriendHelloService {
  FriendHelloService({
    required Future<String?> Function(String key) readSetting,
    required Future<void> Function(String key, String value) writeSetting,
    required Future<bool> Function(String deviceId) chatHasMessages,
    required Future<bool> Function(String userId, String deviceId) isBlocked,
    required Future<bool> Function(String userId) isFriend,
    required Future<void> Function(String deviceId, String body) send,
    required String Function() myUserId,
    required String Function() myDeviceId,
    Duration delay = const Duration(seconds: 3),
  })  : _readSetting = readSetting,
        _writeSetting = writeSetting,
        _chatHasMessages = chatHasMessages,
        _isBlocked = isBlocked,
        _isFriend = isFriend,
        _send = send,
        _myUserId = myUserId,
        _myDeviceId = myDeviceId,
        _delay = delay;

  /// Set by AppDependencies; screens use it (null in widget tests).
  static FriendHelloService? instance;

  final Future<String?> Function(String key) _readSetting;
  final Future<void> Function(String key, String value) _writeSetting;
  final Future<bool> Function(String deviceId) _chatHasMessages;
  final Future<bool> Function(String userId, String deviceId) _isBlocked;
  final Future<bool> Function(String userId) _isFriend;
  final Future<void> Function(String deviceId, String body) _send;
  final String Function() _myUserId;
  final String Function() _myDeviceId;
  final Duration _delay;

  /// Users with a Hello waiting / being sent right now (retries, copies).
  final Set<String> _inFlight = <String>{};

  static String settingKey(String userId) => 'friend_hello_sent:$userId';

  /// Is this person already my friend (before an Add tap)?
  Future<bool> isFriend(String userId) async {
    if (userId.trim().isEmpty) return false;
    try {
      return await _isFriend(userId.trim());
    } catch (_) {
      return false;
    }
  }

  /// Already-friend Add tap: no add, no toast, no Hello - open the chat.
  Future<bool> openExistingChat({
    required String deviceId,
    required String displayName,
    required String source,
  }) {
    AppLogger.info('FRIEND_ADD_TAP',
        detail: 'source=$source already=y to=${_id6(deviceId)}');
    return FriendChatOpener.openChat(deviceId, displayName,
        reason: 'already_friend');
  }

  /// The add I started worked: open the chat now, Hello a moment later.
  Future<FriendHelloDecision?> addedByMe(FriendAddedByMe e,
      {bool openChat = true}) async {
    final key = e.userId.trim().isNotEmpty ? e.userId.trim() : e.deviceId;
    if (key.isEmpty || !_inFlight.add(key)) return null; // copy / retry
    try {
      if (openChat && e.deviceId.trim().isNotEmpty) {
        final opened = await FriendChatOpener.openChat(
            e.deviceId, e.displayName,
            reason: 'new_friend');
        if (!opened) {
          final name = e.displayName.isEmpty ? 'Friend' : e.displayName;
          FriendChatOpener.toast?.call('$name added');
        }
      }
      // The friend link goes out first; their Hello (both tapped) can land.
      if (_delay > Duration.zero) await Future<void>.delayed(_delay);
      final decision = await _decide(e);
      AppLogger.info('FRIEND_HELLO',
          detail: 'action=${decision == FriendHelloDecision.send ? 'sent' : 'skip'} '
              'reason=${decision.word} to=${_id6(e.deviceId)} '
              'source=${e.source} mutual=${e.mutual ? 'y' : 'n'}');
      if (decision != FriendHelloDecision.send) return decision;
      // Saved BEFORE sending: a crash / swipe can never cause a second Hello.
      await _writeSetting(settingKey(key),
          '${FriendAddMemory.now()}');
      await _send(e.deviceId, kFriendHelloText);
      return decision;
    } catch (error) {
      AppLogger.warning('FRIEND_HELLO_FAILED',
          detail: 'to=${_id6(e.deviceId)} error=$error');
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<FriendHelloDecision> _decide(FriendAddedByMe e) async {
    final key = e.userId.trim().isNotEmpty ? e.userId.trim() : e.deviceId;
    int? lastSent;
    try {
      lastSent = int.tryParse((await _readSetting(settingKey(key))) ?? '');
    } catch (_) {}
    var blocked = false;
    try {
      blocked = await _isBlocked(e.userId, e.deviceId);
    } catch (_) {}
    var hasMessages = true; // unknown: never risk a Hello in a busy chat
    try {
      hasMessages = await _chatHasMessages(e.deviceId);
    } catch (_) {}
    return FriendHelloPolicy.decide(
      myUserId: _myUserId(),
      peerUserId: e.userId,
      peerDeviceId: e.deviceId,
      myDeviceId: _myDeviceId(),
      blocked: blocked,
      chatHasMessages: hasMessages,
      nowMs: FriendAddMemory.now(),
      lastSentAtMs: lastSent,
      peerTappedAtMs: FriendAddMemory.peerTappedAt(e.deviceId),
    );
  }
}
