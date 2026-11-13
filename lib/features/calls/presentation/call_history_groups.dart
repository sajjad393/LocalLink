import 'package:locallink/core/models/call.dart';

/// Bundle 171: calls that become ONE row in the Calls list.
///
/// [calls] are newest first; [latest] is what the row shows.
/// Bundle 285: [missed] = how many of them are missed calls (shown red
/// inside the row as "· 2 missed").
class CallGroup {
  final List<CallRecord> calls;
  final int missed;
  const CallGroup(this.calls, {this.missed = 0});

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

/// Bundle 285 (replaces 171's "one after another" and 255 B5): ONE row
/// per person per day. Every call with that person on that day is inside
/// it (missed ones too, counted in [CallGroup.missed]); the row sits where
/// the person's newest call of that day is and shows that call.
///
/// * A new day starts a new row.
/// * A call with no known person stays alone.
///
/// [history] must be newest first (as stored). No call is lost and the
/// order inside a row is kept.
List<CallGroup> groupCallHistory(
  List<CallRecord> history, {
  required String selfId,
  required bool Function(CallRecord call) isMissed,
}) {
  final rows = <List<CallRecord>>[];
  final byKey = <String, List<CallRecord>>{};
  for (final call in history) {
    final peer = call.peerId(selfId);
    if (peer.isEmpty) {
      rows.add(<CallRecord>[call]);
      continue;
    }
    final d = call.startedAt;
    final key = '$peer|${d.year}-${d.month}-${d.day}';
    final row = byKey[key];
    if (row != null) {
      row.add(call);
    } else {
      final fresh = <CallRecord>[call];
      byKey[key] = fresh;
      rows.add(fresh);
    }
  }
  return [
    for (final row in rows) CallGroup(row, missed: row.where(isMissed).length),
  ];
}
