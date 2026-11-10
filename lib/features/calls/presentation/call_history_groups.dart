import 'package:locallink/core/models/call.dart';

/// Bundle 171: calls that become ONE row in the Calls list.
///
/// [calls] are newest first; [latest] is what the row shows.
class CallGroup {
  final List<CallRecord> calls;
  const CallGroup(this.calls);

  CallRecord get latest => calls.first;
  int get count => calls.length;
}

/// Bundle 174: an incoming call I never answered is MISSED - also old
/// history saved as a normal ended / cancelled call with 0 seconds.
/// Calls I declined, failed calls and outgoing calls are never missed.
bool isMissedIncoming(CallRecord call, String selfId) {
  if (call.isOutgoing(selfId)) return false;
  switch (call.status) {
    case 'missed':
    case 'ringing':
      return true;
    case 'rejected':
    case 'failed':
    case 'connected':
    case 'busy':
      return false;
  }
  return call.answeredAt == null && call.durationSeconds <= 0;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Bundle 171 (WhatsApp style): calls with the same person that come one
/// after another on the same day share one row.
///
/// * A call with someone else in between starts a new row.
/// * A new day starts a new row.
/// * Bundle 255 B5 (replaces 174's "missed is always alone"): missed
///   calls back to back join ONE red row "Sajjad (3)". A missed call never
///   joins an answered or outgoing call.
///
/// [history] must be newest first (as stored). The order is kept.
List<CallGroup> groupCallHistory(
  List<CallRecord> history, {
  required String selfId,
  required bool Function(CallRecord call) isMissed,
}) {
  final groups = <CallGroup>[];
  List<CallRecord>? current;
  for (final call in history) {
    final last = current?.last;
    final joins = last != null &&
        last.peerId(selfId) == call.peerId(selfId) &&
        call.peerId(selfId).isNotEmpty &&
        _sameDay(last.startedAt, call.startedAt) &&
        isMissed(last) == isMissed(call);
    if (joins) {
      current!.add(call);
    } else {
      current = <CallRecord>[call];
      groups.add(CallGroup(current));
    }
  }
  return groups;
}
