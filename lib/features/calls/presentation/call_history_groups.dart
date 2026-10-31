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

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Bundle 171 (WhatsApp style): calls with the same person that come one
/// after another on the same day share one row.
///
/// * A call with someone else in between starts a new row.
/// * A new day starts a new row.
/// * Missed calls never hide inside other calls (and the other way round):
///   a change between missed / not missed starts a new row.
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
