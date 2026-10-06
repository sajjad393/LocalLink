class MessageReaction {
  final String messageId;
  final String reactorId;
  final String emoji;
  final DateTime createdAt;

  const MessageReaction({required this.messageId, required this.reactorId, required this.emoji, required this.createdAt});

  factory MessageReaction.fromJson(Map<String, dynamic> json) => MessageReaction(
    messageId: json['message_id']?.toString() ?? '',
    reactorId: json['reactor_id']?.toString() ?? '',
    emoji: json['emoji']?.toString() ?? '',
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {'message_id': messageId, 'reactor_id': reactorId, 'emoji': emoji, 'created_at': createdAt.toUtc().toIso8601String()};
}
