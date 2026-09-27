import 'package:locallink/core/models/attachment.dart';
class LocalGroup {
  final String id;
  final String name;
  final String ownerId;
  final String createdAt;
  const LocalGroup({required this.id, required this.name, required this.ownerId, required this.createdAt});
  factory LocalGroup.fromJson(Map<String,dynamic> j)=>LocalGroup(id:j['id']?.toString()??'',name:j['name']?.toString()??'',ownerId:j['owner_id']?.toString()??'',createdAt:j['created_at']?.toString()??'');
}

class GroupMember {
  final String groupId, deviceId, role, joinedAt, name;
  const GroupMember({required this.groupId,required this.deviceId,required this.role,required this.joinedAt,required this.name});
  factory GroupMember.fromJson(Map<String,dynamic> j)=>GroupMember(groupId:j['group_id']?.toString()??'',deviceId:j['device_id']?.toString()??'',role:j['role']?.toString()??'member',joinedAt:j['joined_at']?.toString()??'',name:j['name']?.toString()??'');
}

class GroupMessage {
  final String id, groupId, senderId, body, createdAt;
  final int serverSeq;
  final List<Attachment> attachments;
  const GroupMessage({required this.id,required this.groupId,required this.senderId,required this.body,required this.createdAt,this.serverSeq=0,this.attachments=const []});
  factory GroupMessage.fromJson(Map<String,dynamic> j)=>GroupMessage(id:j['id']?.toString()??'',groupId:j['group_id']?.toString()??'',senderId:j['sender_id']?.toString()??'',body:j['body']?.toString()??'',createdAt:j['created_at']?.toString()??'',serverSeq:int.tryParse(j['server_seq']?.toString()??'')??0,attachments:(j['attachments'] as List? ?? []).map((e)=>Attachment.fromJson(Map<String,dynamic>.from(e as Map))).toList());
}
