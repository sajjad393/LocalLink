import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group_extras.dart';
import 'package:locallink/core/models/message_envelope.dart';
class LocalGroup {
  final String id;
  final String name;
  final String ownerId;
  final String createdAt;

  /// Bundle G2: info, photo and settings from the server.
  final String description;
  final int photoVersion;

  /// "all" | "admins" - who may change name, photo and description.
  final String editInfo;

  /// "all" | "admins" - "admins" = announcement group.
  final String sendMessages;

  /// "all" | "admins" - who may add people.
  final String addMembers;
  final String createdBy;

  /// Local only: "active", "removed" (an admin removed me) or "left".
  /// Not active = read only + "Delete group" (mock 25).
  final String state;

  /// Bundle G3 (local only): "server" (made on the server), "nearby" (made
  /// on a phone, not on the server yet) or "both". Not "server" = the group
  /// has a signed group card and also works Nearby without internet.
  final String origin;

  /// Bundle G3: version of the signed group card (0 = no card).
  final int cardVersion;

  const LocalGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    this.description = '',
    this.photoVersion = 0,
    this.editInfo = 'admins',
    this.sendMessages = 'all',
    this.addMembers = 'admins',
    this.createdBy = '',
    this.state = 'active',
    this.origin = 'server',
    this.cardVersion = 0,
  });

  bool get isActive => state == 'active';

  /// Bundle G3: works Nearby (has a group card).
  bool get worksNearby => origin != 'server' && cardVersion > 0;

  /// Bundle G3: not on the server yet (server calls are skipped).
  bool get nearbyOnly => origin == 'nearby';

  static String _setting(Object? v, String fallback) {
    final s = v?.toString() ?? '';
    return s == 'all' || s == 'admins' ? s : fallback;
  }

  factory LocalGroup.fromJson(Map<String, dynamic> j) => LocalGroup(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        ownerId: j['owner_id']?.toString() ?? '',
        createdAt: j['created_at']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        photoVersion: int.tryParse(j['photo_version']?.toString() ?? '') ?? 0,
        editInfo: _setting(j['edit_info'], 'admins'),
        sendMessages: _setting(j['send_messages'], 'all'),
        addMembers: _setting(j['add_members'], 'admins'),
        createdBy: j['created_by']?.toString() ?? '',
        state: (j['state']?.toString() ?? '').isEmpty
            ? 'active'
            : j['state'].toString(),
        origin: (j['origin']?.toString() ?? '').isEmpty
            ? 'server'
            : j['origin'].toString(),
        cardVersion: int.tryParse(j['card_version']?.toString() ?? '') ?? 0,
      );

  LocalGroup copyWith({
    String? name,
    String? ownerId,
    String? description,
    int? photoVersion,
    String? editInfo,
    String? sendMessages,
    String? addMembers,
    String? state,
    String? origin,
    int? cardVersion,
  }) =>
      LocalGroup(
        id: id,
        name: name ?? this.name,
        ownerId: ownerId ?? this.ownerId,
        createdAt: createdAt,
        description: description ?? this.description,
        photoVersion: photoVersion ?? this.photoVersion,
        editInfo: editInfo ?? this.editInfo,
        sendMessages: sendMessages ?? this.sendMessages,
        addMembers: addMembers ?? this.addMembers,
        createdBy: createdBy,
        state: state ?? this.state,
        origin: origin ?? this.origin,
        cardVersion: cardVersion ?? this.cardVersion,
      );

  /// Server columns only (the local [state] is never overwritten by these).
  Map<String, dynamic> toServerRow() => {
        'id': id,
        'name': name,
        'owner_id': ownerId,
        'created_at': createdAt,
        'description': description,
        'photo_version': photoVersion,
        'edit_info': editInfo,
        'send_messages': sendMessages,
        'add_members': addMembers,
        'created_by': createdBy,
      };
}

class GroupMember {
  final String groupId, deviceId, role, joinedAt, name;

  /// Bundle G2: who added this member ('' = created the group).
  final String addedBy;

  /// Bundle G2: the account (for "Add friend"); '' when not known.
  final String userId;
  const GroupMember({required this.groupId,required this.deviceId,required this.role,required this.joinedAt,required this.name,this.addedBy='',this.userId=''});
  bool get isAdmin => role == 'owner' || role == 'admin';
  factory GroupMember.fromJson(Map<String,dynamic> j)=>GroupMember(groupId:j['group_id']?.toString()??'',deviceId:j['device_id']?.toString()??'',role:j['role']?.toString()??'member',joinedAt:j['joined_at']?.toString()??'',name:_memberName276(j),addedBy:j['added_by']?.toString()??'',userId:j['user_id']?.toString()??'');
}

class GroupMessage {
  final String id, groupId, senderId, body, createdAt;
  final int serverSeq;
  final List<Attachment> attachments;

  /// Bundle G3: a member's phone got it Nearby (✓ without the server).
  final bool nearbySent;
  const GroupMessage({required this.id,required this.groupId,required this.senderId,required this.body,required this.createdAt,this.serverSeq=0,this.attachments=const [],this.nearbySent=false});

  /// Bundle G3: still waiting (clock): not on the server and no member
  /// phone got it Nearby yet.
  bool get notSentYet => serverSeq == 0 && !nearbySent;
  /// Bundle 197a: see Message.text.
  MessageEnvelope get envelope => MessageEnvelope.of(body);
  /// Bundle G5b: a poll reads as "📊 Poll: question" (Chats, quotes,
  /// copy, search, notifications); the bubble draws the poll itself.
  String get text {
    final p = GroupPoll.parse(body);
    if (p != null) return p.preview;
    // Bundle G6: a locked message this phone can't open yet.
    if (body.startsWith('llsk:v1:')) return '🔒 Waiting for this message';
    return envelope.text;
  }
  GroupPoll? get poll => GroupPoll.parse(body);
  ReplyRef? get replyTo => envelope.reply;
  bool get forwarded => envelope.forwarded;
  DateTime get createdTime => DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  factory GroupMessage.fromJson(Map<String,dynamic> j)=>GroupMessage(id:j['id']?.toString()??'',groupId:j['group_id']?.toString()??'',senderId:j['sender_id']?.toString()??'',body:j['body']?.toString()??'',createdAt:j['created_at']?.toString()??'',serverSeq:int.tryParse(j['server_seq']?.toString()??'')??0,attachments:(j['attachments'] as List? ?? []).map((e)=>Attachment.fromJson(Map<String,dynamic>.from(e as Map))).toList(),nearbySent:j['nearby_sent']==1||j['nearby_sent']==true);
}

/// Bundle 276: a member's saved name is never a phone's default name
/// ("My Android Phone (1a2b)"); then the username, else '' (resolved later).
String _memberName276(Map<String, dynamic> j) {
  final n = j['name']?.toString().trim() ?? '';
  if (n.isNotEmpty && !isDefaultPhoneLabel255(n)) return n;
  final u = (j['username']?.toString().trim() ?? '').replaceFirst(RegExp(r'^@+'), '');
  if (u.isNotEmpty && !isDefaultPhoneLabel255(u)) return u;
  return '';
}
