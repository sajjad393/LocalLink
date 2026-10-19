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

  /// Which path this copy of the message traveled, in-memory only (Bundle
  /// 52C): 'direct' (LAN/Wi-Fi Direct/mesh) or 'server'. Null for history
  /// reloaded from the local DB and for outgoing echo rows — no claim is
  /// shown rather than a wrong one.
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
        attachments: (json['attachments'] as List? ?? []).map((e) => Attachment.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );

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
