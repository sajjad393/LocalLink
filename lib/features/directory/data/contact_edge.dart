import 'dart:convert';

/// One signed contact-relationship event propagated over the local gossip
/// mesh so that "A added B" (or "A removed B") reaches B even when neither
/// phone has LAN/internet access to the account server. Application on the
/// receiving side is last-writer-wins on the embedded timestamp — relays may
/// replay envelopes, so a stale replay must never resurrect a deleted edge.
/// This file is pure Dart: no store, no crypto service, decision logic only.
class ContactEdge {
  final String op; // 'add' | 'remove'
  final String fromUserId;
  final String fromDeviceId;
  final String toUserId;
  final int edgeTs; // sender-claimed epoch millis of the LOCAL action

  const ContactEdge({
    required this.op,
    required this.fromUserId,
    required this.fromDeviceId,
    required this.toUserId,
    required this.edgeTs,
  });

  static const opAdd = 'add';
  static const opRemove = 'remove';

  bool get isValid =>
      (op == opAdd || op == opRemove) &&
      fromUserId.isNotEmpty &&
      fromUserId != toUserId &&
      toUserId.isNotEmpty &&
      edgeTs > 0;

  /// Canonical serialization for signing/verifying: fixed key order, no
  /// whitespace — both endpoints rebuild the exact same bytes.
  String canonical() =>
      'contact-edge|v1|$op|$fromUserId|$fromDeviceId|$toUserId|$edgeTs';

  Map<String, dynamic> toMap() => <String, dynamic>{
        'op': op,
        'from_user_id': fromUserId,
        'from_device_id': fromDeviceId,
        'to_user_id': toUserId,
        'edge_ts': edgeTs,
      };

  static ContactEdge? fromWire(Map<String, dynamic> message) {
    final edge = ContactEdge(
      op: message['op']?.toString() ?? '',
      fromUserId: message['from_user_id']?.toString() ?? '',
      fromDeviceId: message['from_device_id']?.toString() ?? '',
      toUserId: message['to_user_id']?.toString() ?? '',
      edgeTs: int.tryParse(message['edge_ts']?.toString() ?? '') ?? 0,
    );
    return edge.isValid ? edge : null;
  }

  static String encodeEdgeState(String op, int ts) => '$op|$ts';

  static (String, int)? decodeEdgeState(String raw) {
    final parts = raw.split('|');
    if (parts.length != 2) return null;
    if (parts[0] != opAdd && parts[0] != opRemove) return null;
    final ts = int.tryParse(parts[1]) ?? 0;
    return ts <= 0 ? null : (parts[0], ts);
  }

  /// LWW merge for an incoming edge. [localRaw] is this device's persisted
  /// edge state for the peer user ("op|ts" or null). Returns the op to apply
  /// ('add'/'remove'), or null when the incoming event must be ignored
  /// (older than/equal to what is already applied — blocks replay ghosts).
  static String? decideApply(ContactEdge incoming, String? localRaw) {
    if (!incoming.isValid) return null;
    final local = localRaw == null ? null : decodeEdgeState(localRaw);
    if (local == null) return incoming.op; // unknown edge → adopt
    if (incoming.edgeTs <= local.$2) return null;
    return incoming.op;
  }

  /// Encode the full gossip message (all stable fields as strings).
  String describe() => jsonEncode(toMap());
}
