import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';

final class ChatState extends Equatable {
  final Device device;
  final String localDeviceId;
  final List<Message> messages;
  final List<PickedFile> pendingAttachments;
  final bool isLoading, isSending;
  final String? error;
  const ChatState(
      {required this.device,
      required this.localDeviceId,
      this.messages = const [],
      this.pendingAttachments = const [],
      this.isLoading = true,
      this.isSending = false,
      this.error});
  ChatState copyWith(
          {Device? device,
          List<Message>? messages,
          List<PickedFile>? pendingAttachments,
          bool? isLoading,
          bool? isSending,
          String? error,
          bool clearError = false}) =>
      ChatState(
          device: device ?? this.device,
          localDeviceId: localDeviceId,
          messages: messages ?? this.messages,
          pendingAttachments: pendingAttachments ?? this.pendingAttachments,
          isLoading: isLoading ?? this.isLoading,
          isSending: isSending ?? this.isSending,
          error: clearError ? null : (error ?? this.error));
  @override
  List<Object?> get props => [
        device,
        localDeviceId,
        messages,
        pendingAttachments,
        isLoading,
        isSending,
        error
      ];
}

final class ChatBloc extends Cubit<ChatState> {
  final MessagingRepositoryContract repository;
  final String localDeviceId;
  late final StreamSubscription<Message> _subscription;
  ChatBloc({required this.repository, required Device device})
      : localDeviceId = repository.localDeviceId,
        super(ChatState(
            device: device, localDeviceId: repository.localDeviceId)) {
    _subscription = repository.incoming.listen(_onIncoming);
  }
  Device get device => state.device;
  List<Message> get messages => state.messages;
  List<PickedFile> get pendingAttachments => state.pendingAttachments;
  bool get isLoading => state.isLoading;
  bool get isSending => state.isSending;
  String? get error => state.error;
  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      emit(state.copyWith(
          messages: await repository.history(state.device.id),
          isLoading: false));
    } catch (e) {
      emit(state.copyWith(error: cleanBlocError(e), isLoading: false));
    }
  }

  void addPendingAttachments(List<PickedFile> files) {
    if (files.isEmpty) return;
    emit(state
        .copyWith(pendingAttachments: [...state.pendingAttachments, ...files]));
  }

  void removePendingAttachment(int index) {
    if (index < 0 || index >= state.pendingAttachments.length) return;
    final next = [...state.pendingAttachments]..removeAt(index);
    emit(state.copyWith(pendingAttachments: next));
  }

  Future<void> send(String body) async {
    final text = body.trim();
    if ((text.isEmpty && state.pendingAttachments.isEmpty) || state.isSending)
      return;
    final attachments = List<PickedFile>.from(state.pendingAttachments);
    emit(state.copyWith(
        pendingAttachments: const [], isSending: true, clearError: true));
    try {
      await repository.send(state.device.id, text, attachments: attachments);
      await load();
    } catch (e) {
      emit(state.copyWith(
          pendingAttachments: [...attachments, ...state.pendingAttachments],
          error: cleanBlocError(e)));
    } finally {
      emit(state.copyWith(isSending: false));
    }
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
    emit(state.copyWith(device: d));
  }

  void clearError() {
    if (state.error != null) emit(state.copyWith(clearError: true));
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
    emit(state.copyWith(messages: next));
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
