import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';

/// Bundle 172: ghost calls after a cancel.
///
/// A call invite can wait in the send queue while the other phone is away.
/// After the caller cancels, the "call ended" message can arrive FIRST (it
/// is newer, so it is due sooner) and the old invite later — the other
/// phone then rang, and answering started the sound on both phones.
///
/// Three small rules stop that:
///  * the caller answers "that call is over" to a late ring/answer
///    ([shouldReplyCallOver]) and never starts the sound for a call that is
///    already over;
///  * the receiver remembers ended calls ([EndedCallMemory]) so a late
///    invite for one of them never rings;
///  * invites leave the send queue after [inviteQueueLifetime].

/// How long a call invite (and its "ringing" reply) may wait in the send
/// queue. A phone rings for about a minute, so an older invite is useless.
const Duration inviteQueueLifetime = Duration(seconds: 60);

/// Wire field read by the native send queue (milliseconds). It sits outside
/// the lock so the queue can see it; it holds no private data.
const String queueLifetimeField = MessageSealService.queueLifetimeField;

/// Should a late `call_accept` / ringing `call_invite_ack` for [callId] get
/// a "call is over" reply? [live] is this phone's current call (or null).
///
/// * No call, or a different call → yes (that call is not happening).
/// * The same call still going → no (normal path).
/// * The same call already over and never answered here (cancelled,
///   timed out, declined, failed) → yes.
/// * The same call over after it was answered (a normal hang-up) → no;
///   the usual end messages already cover it.
bool shouldReplyCallOver({required CallSession? live, required String callId}) {
  if (callId.trim().isEmpty) return false;
  if (live == null || live.id != callId) return true;
  if (live.direction != CallDirection.outgoing) return false;
  if (!live.isFinished) return false;
  return live.answeredAt == null;
}

/// Bundle 172: call ids this phone knows are over (memory only, up to a
/// day, at most [max] ids). A late invite for one of them never rings.
class EndedCallMemory {
  EndedCallMemory({
    this.keep = const Duration(hours: 24),
    this.max = 256,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration keep;
  final int max;
  final DateTime Function() _clock;
  final Map<String, DateTime> _ended = <String, DateTime>{};

  int get length => _ended.length;

  void remember(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return;
    _prune();
    _ended.remove(id);
    _ended[id] = _clock();
    while (_ended.length > max) {
      _ended.remove(_ended.keys.first);
    }
  }

  bool contains(String callId) {
    final id = callId.trim();
    if (id.isEmpty) return false;
    _prune();
    return _ended.containsKey(id);
  }

  void _prune() {
    final now = _clock();
    _ended.removeWhere((_, at) => now.difference(at) > keep);
  }
}
