import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';

final class ChatState extends Equatable {
  final Device device;
  final String localDeviceId;
  final List<Message> messages;
  final List<PickedFile> pendingAttachments;
  final Map<String, List<MessageReaction>> reactions;
  final bool isLoading, isSending;
  final String? error;
  const ChatState(
      {required this.device,
      required this.localDeviceId,
      this.messages = const [],
      this.pendingAttachments = const [],
      this.reactions = const {},
      this.isLoading = true,
      this.isSending = false,
      this.error});
  ChatState copyWith(
          {Device? device,
          List<Message>? messages,
          List<PickedFile>? pendingAttachments,
          Map<String, List<MessageReaction>>? reactions,
          bool? isLoading,
          bool? isSending,
          String? error,
          bool clearError = false}) =>
      ChatState(
          device: device ?? this.device,
          localDeviceId: localDeviceId,
          messages: messages ?? this.messages,
          pendingAttachments: pendingAttachments ?? this.pendingAttachments,
          reactions: reactions ?? this.reactions,
          isLoading: isLoading ?? this.isLoading,
          isSending: isSending ?? this.isSending,
          error: clearError ? null : (error ?? this.error));
  @override
  List<Object?> get props => [
        device,
        localDeviceId,
        messages,
        pendingAttachments,
        reactions,
        isLoading,
        isSending,
        error
      ];
}

final class ChatBloc extends Cubit<ChatState> {
  final MessagingRepositoryContract repository;
  final String localDeviceId;
  late final StreamSubscription<Message> _subscription;
  late final StreamSubscription<MessageReaction> _reactionSubscription;
  ChatBloc({required this.repository, required Device device})
      : localDeviceId = repository.localDeviceId,
        super(ChatState(
            device: device, localDeviceId: repository.localDeviceId)) {
    _subscription = repository.incoming.listen(_onIncoming);
    _reactionSubscription = repository.reactionIncoming.listen(_onReaction);
  }
  Device get device => state.device;
  List<Message> get messages => state.messages;
  List<PickedFile> get pendingAttachments => state.pendingAttachments;
  bool get isLoading => state.isLoading;
  bool get isSending => state.isSending;
  String? get error => state.error;
  List<MessageReaction> reactionsFor(String messageId) => state.reactions[messageId] ?? const [];
  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final messages = await repository.history(state.device.id);
      if (isClosed) return;
      final reactionMap = <String, List<MessageReaction>>{};
      for (final message in messages) {
        reactionMap[message.id] = await repository.reactions(message.id);
      }
      emit(state.copyWith(messages: messages, reactions: reactionMap, isLoading: false));
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: cleanBlocError(e), isLoading: false));
    }
  }

  void addPendingAttachments(List<PickedFile> files) {
    if (isClosed || files.isEmpty) return;
    emit(state
        .copyWith(pendingAttachments: [...state.pendingAttachments, ...files]));
  }

  void removePendingAttachment(int index) {
    if (isClosed || index < 0 || index >= state.pendingAttachments.length) return;
    final next = [...state.pendingAttachments]..removeAt(index);
    emit(state.copyWith(pendingAttachments: next));
  }

  Future<void> send(String body) async {
    final text = body.trim();
    if (isClosed || (text.isEmpty && state.pendingAttachments.isEmpty) || state.isSending) return;
    final attachments = List<PickedFile>.from(state.pendingAttachments);
    emit(state.copyWith(
        pendingAttachments: const [], isSending: true, clearError: true));
    try {
      await repository.send(state.device.id, text, attachments: attachments);
      if (isClosed) return;
      await load();
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
            pendingAttachments: [...attachments, ...state.pendingAttachments],
            error: cleanBlocError(e)));
      }
    } finally {
      if (!isClosed) emit(state.copyWith(isSending: false));
    }
  }

  Future<void> react(String messageId, String emoji) async {
    if (isClosed || messageId.isEmpty || emoji.trim().isEmpty) return;
    try {
      await repository.react(state.device.id, messageId, emoji);
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: cleanBlocError(e)));
    }
  }

  void _onReaction(MessageReaction reaction) {
    if (isClosed) return;
    final current = [...(state.reactions[reaction.messageId] ?? const <MessageReaction>[])];
    final index = current.indexWhere((item) => item.reactorId == reaction.reactorId);
    if (index >= 0) current[index] = reaction; else current.add(reaction);
    final next = {...state.reactions, reaction.messageId: current};
    emit(state.copyWith(reactions: next));
  }

  void updatePresence(Map<String, dynamic> event) {
    if (event['device_id']?.toString() != state.device.id) return;
    final d = Device.fromJson({
      'id': state.device.id,
      'name': state.device.name,
      'platform': state.device.platform,
      'created_at': state.device.createdAt,
      'last_seen_at':
          event['last_seen_at']?.toString() ?? state.device.lastSeenAt,
      'network_status': event['network_status'],
      'server_connected': event['server_connected'] == true,
      'wifi_direct_connected': event['wifi_direct_connected'] == true,
      'status_updated_at': event['status_updated_at']?.toString() ?? ''
    });
    if (!isClosed) emit(state.copyWith(device: d));
  }

  void clearError() {
    if (!isClosed && state.error != null) emit(state.copyWith(clearError: true));
  }

  void _onIncoming(Message m) {
    final matches =
        (m.senderId == state.device.id && m.recipientId == localDeviceId) ||
            (m.recipientId == state.device.id && m.senderId == localDeviceId);
    if (!matches) return;
    final next = [...state.messages];
    final i = next.indexWhere((x) => x.id == m.id);
    if (i < 0)
      next.add(m);
    else
      next[i] = m;
    if (!isClosed) emit(state.copyWith(messages: next));
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _reactionSubscription.cancel();
    return super.close();
  }
}
