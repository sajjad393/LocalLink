import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/message_delete_book.dart';
import 'dart:async';import 'package:equatable/equatable.dart';import 'package:flutter_bloc/flutter_bloc.dart';import 'package:locallink/core/models/attachment.dart';import 'package:locallink/core/models/group.dart';import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
final class GroupChatState extends Equatable{final LocalGroup group;final String localDeviceId;final List<GroupMessage> messages;final Map<String,List<MessageReaction>> reactions;final bool isLoading,isSending;final Object? error;const GroupChatState({required this.group,required this.localDeviceId,this.messages=const [],this.reactions=const {},this.isLoading=false,this.isSending=false,this.error});GroupChatState copyWith({List<GroupMessage>? messages,Map<String,List<MessageReaction>>? reactions,bool? isLoading,bool? isSending,Object? error,bool clearError=false})=>GroupChatState(group:group,localDeviceId:localDeviceId,messages:messages??this.messages,reactions:reactions??this.reactions,isLoading:isLoading??this.isLoading,isSending:isSending??this.isSending,error:clearError?null:(error??this.error));@override List<Object?>get props=>[group,localDeviceId,messages,reactions,isLoading,isSending,error.toString()];}
final class GroupChatBloc extends Cubit<GroupChatState>{final GroupMessagingRepositoryContract repository;late final StreamSubscription<GroupMessage> _incoming;late final StreamSubscription<MessageReaction> _reactionIncoming;StreamSubscription<String>? _deletedSub;GroupChatBloc({required this.repository,required LocalGroup group,required String localDeviceId}):super(GroupChatState(group:group,localDeviceId:localDeviceId)){_incoming=repository.incoming.listen(_onIncoming);_reactionIncoming=repository.reactionIncoming.listen(_onReaction);try{_deletedSub=repository.deletedMessageIds.listen((id)=>_dropLocal({id}));}catch(_){}}List<GroupMessage> get messages=>state.messages;bool get isLoading=>state.isLoading;bool get isSending=>state.isSending;Object? get error=>state.error;bool isMine(GroupMessage m)=>m.senderId==state.localDeviceId;Future<void> load()async{if(isClosed)return;emit(state.copyWith(isLoading:true,clearError:true));try{final messages=await repository.history(state.group.id);if(isClosed)return;final reactionMap=<String,List<MessageReaction>>{};for(final m in messages){reactionMap[m.id]=await repository.reactions(m.id);}emit(state.copyWith(messages:messages,reactions:reactionMap,isLoading:false));}catch(e){if(!isClosed)emit(state.copyWith(error:e,isLoading:false));}}Future<GroupMessage> send(String body,{List<PickedFile> attachments=const [],ReplyRef? reply})async{if(isClosed)throw StateError('Conversation is closed');if(state.isSending)throw StateError('A message is already being sent');if(body.trim().isEmpty&&attachments.isEmpty)throw const FormatException('Message or attachment required');emit(state.copyWith(isSending:true,clearError:true));try{final m=await repository.send(state.group.id,MessageEnvelope.build(text:body.trim(),reply:reply),attachments:attachments);if(isClosed)return m;_upsert(m);return m;}catch(e){if(!isClosed)emit(state.copyWith(error:e));rethrow;}finally{if(!isClosed)emit(state.copyWith(isSending:false));}}Future<void> react(String messageId,String emoji)async{if(isClosed||messageId.isEmpty||emoji.isEmpty)return;try{await repository.react(state.group.id,messageId,emoji);}catch(e){if(!isClosed)emit(state.copyWith(error:e));}}void _onReaction(MessageReaction r){if(isClosed)return;final list=[...(state.reactions[r.messageId]??const <MessageReaction>[])];final i=list.indexWhere((x)=>x.reactorId==r.reactorId);if(i>=0)list[i]=r;else list.add(r);emit(state.copyWith(reactions:{...state.reactions,r.messageId:list}));}void _onIncoming(GroupMessage m){if(isClosed||m.groupId!=state.group.id)return;if(MessageDeleteBook.instance.isDeleted(m.id))return;_upsert(m);}void _upsert(GroupMessage m){final next=[...state.messages];final i=next.indexWhere((x)=>x.id==m.id);if(i<0)next.add(m);else next[i]=m;if(!isClosed)emit(state.copyWith(messages:next));}
  // Bundle 197a: delete for me / for everyone, clear chat.
  Future<void> deleteForMe(List<String> ids) async {
    if (isClosed || ids.isEmpty) return;
    try {
      for (final id in ids) {
        await repository.deleteForMe(id);
      }
      _dropLocal(ids.toSet());
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: e));
    }
  }

  /// False = too late for at least one message.
  Future<bool> deleteForEveryone(List<String> ids) async {
    if (isClosed || ids.isEmpty) return false;
    var all = true;
    final done = <String>{};
    try {
      for (final id in ids) {
        if (await repository.deleteForEveryone(state.group.id, id)) {
          done.add(id);
        } else {
          all = false;
        }
      }
    } catch (e) {
      all = false;
      if (!isClosed) emit(state.copyWith(error: e));
    }
    _dropLocal(done);
    return all;
  }

  Future<void> clearChat() async {
    if (isClosed) return;
    try {
      await repository.clearChat(state.group.id);
      if (isClosed) return;
      // My unsent messages (not acked by the server yet) stay.
      emit(state.copyWith(
          messages: state.messages
              .where((m) => isMine(m) && m.serverSeq == 0)
              .toList(growable: false)));
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: e));
    }
  }

  void _dropLocal(Set<String> ids) {
    if (isClosed || ids.isEmpty) return;
    if (!state.messages.any((m) => ids.contains(m.id))) return;
    final next = {...state.reactions}..removeWhere((k, _) => ids.contains(k));
    emit(state.copyWith(
        messages: state.messages.where((m) => !ids.contains(m.id)).toList(growable: false),
        reactions: next));
  }

  @override
  Future<void> close() async {
    await _incoming.cancel();
    await _reactionIncoming.cancel();
    await _deletedSub?.cancel();
    return super.close();
  }
}
