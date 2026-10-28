import 'dart:convert';

import 'package:locallink/core/models/attachment.dart';
class Message {
  final String id;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime createdAt;
  final String status;
  final String? deliveredAt;
  final int serverSeq;
  final List<Attachment> attachments;

  /// Which path this copy of the message traveled (Bundle 52C, extended by
  /// 132/G): 'server', 'wifi_direct', 'lan', or 'mesh'. Legacy value
  /// 'direct' (52C, pre-granular) still renders as Local Wi-Fi. Null for
  /// pre-132 history rows and outgoing echo rows — no claim rather than a
  /// wrong one. Persisted in the messages.channel column since DB v26.
  final String? channel;

  const Message({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    this.status = 'sent',
    this.deliveredAt,
    this.serverSeq = 0,
    this.attachments = const [],
    this.channel,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id']?.toString() ?? '',
        senderId: json['sender_id']?.toString() ?? '',
        recipientId: json['recipient_id']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        status: json['status']?.toString() ?? 'sent',
        deliveredAt: json['delivered_at']?.toString(),
        serverSeq: int.tryParse(json['server_seq']?.toString() ?? '') ?? 0,
        attachments: _attachmentsFrom(json['attachments']),
      );

  /// Bundle 142: tolerate `attachments` arriving as text (JSON string, or the
  /// pre-142 native Java toString() form from a phone not yet updated) instead
  /// of crashing the whole direct_message — the message is still saved and
  /// ACKed, so the sender stops its endless retry loop.
  static List<Attachment> _attachmentsFrom(Object? raw) {
    Object? value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const [];
      }
    }
    if (value is! List) return const [];
    final out = <Attachment>[];
    for (final e in value) {
      if (e is Map) {
        try {
          out.add(Attachment.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    }
    return out;
  }

  factory Message.fromDb(Map<String, dynamic> row) => Message(
        id: row['id']?.toString() ?? '',
        senderId: row['sender_id']?.toString() ?? '',
        recipientId: row['recipient_id']?.toString() ?? '',
        body: row['body']?.toString() ?? '',
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        status: row['status']?.toString() ?? 'sent',
        deliveredAt: row['delivered_at']?.toString(),
        serverSeq: int.tryParse(row['server_seq']?.toString() ?? '') ?? 0,
        attachments: const [],
        // Bundle 132 (G): the receive transport is persisted now, so the
        // chat thread can render Online / Wi-Fi Direct / Mesh / Local Wi-Fi
        // section dividers for history too. '' for pre-132 rows → no label.
        channel: (row['channel']?.toString() ?? '').isEmpty
            ? null
            : row['channel']?.toString(),
      );

  Message copyWithMessageAttachments(List<Attachment>? attachments) => Message(
        id: id, senderId: senderId, recipientId: recipientId, body: body, createdAt: createdAt,
        status: status, deliveredAt: deliveredAt, serverSeq: serverSeq,
        attachments: attachments ?? this.attachments, channel: channel,
      );

  Message copyWithChannel(String? value) => Message(
        id: id, senderId: senderId, recipientId: recipientId, body: body,
        createdAt: createdAt, status: status, deliveredAt: deliveredAt,
        serverSeq: serverSeq, attachments: attachments, channel: value,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'body': body,
        'created_at': createdAt.toUtc().toIso8601String(),
        'status': status,
        if (deliveredAt != null) 'delivered_at': deliveredAt,
        'server_seq': serverSeq,
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };
}
