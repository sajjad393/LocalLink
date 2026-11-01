import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/message_delete_book.dart';
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
  StreamSubscription<String>? _deletedSubscription;
  Timer? _peerTimer;

  /// Refreshes `state.device` from the cached directory row; presence
  /// updates land there asynchronously.
  Future<void> refreshPeer() async {
    if (isClosed) return;
    try {
      final fresh = await repository.peer(state.device.id);
      if (fresh == null || isClosed) return;
      final cur = state.device;
      // name excluded from the equality chain below until now — a nickname
      // change alone must still refresh the header.
      // Bundle 131: presenceLocalAt joins the chain. Without it a steady-
      // state peer (flags unchanged) kept the OPEN-TIME stamp, so the
      // app-bar status could still decay to "Offline" mid-chat even though
      // the cached row (and the Chats list, bundle 130) had already healed.
      if (fresh.name == cur.name &&
          fresh.networkStatus == cur.networkStatus &&
          fresh.serverConnected == cur.serverConnected &&
          fresh.wifiDirectConnected == cur.wifiDirectConnected &&
          fresh.lanAvailable == cur.lanAvailable &&
          fresh.meshAvailable == cur.meshAvailable &&
          fresh.presenceLocalAt == cur.presenceLocalAt &&
          fresh.lastSeenAt == cur.lastSeenAt) return;
      emit(state.copyWith(device: fresh));
    } catch (_) {}
  }
  ChatBloc({required this.repository, required Device device})
      : localDeviceId = repository.localDeviceId,
        super(ChatState(
            device: device, localDeviceId: repository.localDeviceId)) {
    _subscription = repository.incoming.listen(_onIncoming);
    _reactionSubscription = repository.reactionIncoming.listen(_onReaction);
    // Bundle 197a: a deleted message (for me, for everyone, Clear chat)
    // disappears from the open chat at once.
    try {
      _deletedSubscription = repository.deletedMessageIds.listen(_onDeleted);
    } catch (_) {}
    // Presence pipeline does not push into the chat bloc — poll the cached
    // peer row every few seconds so the app-bar status line stays live.
    _peerTimer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(refreshPeer()));
    unawaited(refreshPeer());
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
      // Cache-first: paint what's already on disk instantly, then fold in the
      // synced copy when history() resolves. Empty conversations behave as
      // before (the shimmer still covers the initial remote fetch).
      final cached = await repository.cachedHistory(state.device.id);
      if (!isClosed && cached.isNotEmpty) {
        emit(state.copyWith(messages: cached, isLoading: true));
      }
      final messages = await repository.history(state.device.id);
      if (isClosed) return;
      final reactionMap = <String, List<MessageReaction>>{};
      for (final message in messages) {
        reactionMap[message.id] = await repository.reactions(message.id);
      }
      emit(state.copyWith(messages: messages, reactions: reactionMap, isLoading: false));
    } catch (e) {
      if (isClosed) return;
      // Bundle 132 (A/C): a dead server is NOT an error state for the user.
      // If the cache painted (A) the thread stays; if the conversation is
      // simply unreachable-but-empty (C) the friendly empty view shows. The
      // background sync/flush pipelines retry on their own — the red inline
      // error is reserved for real failures while the server IS reachable.
      if (state.messages.isNotEmpty || !repository.isServerConnected) {
        emit(state.copyWith(isLoading: false, clearError: true));
        return;
      }
      emit(state.copyWith(error: cleanBlocError(e), isLoading: false));
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

  Future<void> send(String body, {ReplyRef? reply}) async {
    final text = body.trim();
    if (isClosed || (text.isEmpty && state.pendingAttachments.isEmpty) || state.isSending) return;
    final attachments = List<PickedFile>.from(state.pendingAttachments);
    emit(state.copyWith(
        pendingAttachments: const [], isSending: true, clearError: true));
    try {
      // Bundle 197a: a reply carries the quote inside the body envelope.
      final wire = MessageEnvelope.build(text: text, reply: reply);
      await repository.send(state.device.id, wire, attachments: attachments);
      if (reply != null) {
        AppLogger.info('MESSAGE_REPLY_SENT',
            detail: 'to=${_short(reply.id)} kind=${reply.kind}');
      }
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

  /// Bundle 162 (4.6): Resend from the failed-message sheet.
  Future<bool> resendFailed(String messageId) async {
    if (isClosed || messageId.isEmpty) return false;
    try {
      return await repository.resendFailed(messageId);
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: cleanBlocError(e)));
      return false;
    }
  }

  /// Bundle 162 (4.6): Delete from the failed-message sheet.
  Future<void> deleteFailed(String messageId) async {
    if (isClosed || messageId.isEmpty) return;
    try {
      await repository.deleteFailed(messageId);
      if (isClosed) return;
      emit(state.copyWith(
          messages: state.messages
              .where((m) => m.id != messageId)
              .toList(growable: false)));
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: cleanBlocError(e)));
    }
  }

  static String _short(String id) =>
      id.length > 8 ? id.substring(id.length - 8) : id;

  /// Bundle 197a: Delete for me (one or many).
  Future<void> deleteForMe(List<String> ids) async {
    if (isClosed || ids.isEmpty) return;
    try {
      for (final id in ids) {
        await repository.deleteForMe(id);
      }
      _dropLocal(ids.toSet());
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: cleanBlocError(e)));
    }
  }

  /// Bundle 197a: Delete for everyone. The 5 minutes are checked again
  /// now; false = too late for at least one (nothing changed for those).
  Future<bool> deleteForEveryone(List<String> ids) async {
    if (isClosed || ids.isEmpty) return false;
    var all = true;
    final done = <String>{};
    try {
      for (final id in ids) {
        final ok = await repository.deleteForEveryone(state.device.id, id);
        if (ok) {
          done.add(id);
        } else {
          all = false;
        }
      }
    } catch (e) {
      all = false;
      if (!isClosed) emit(state.copyWith(error: cleanBlocError(e)));
    }
    _dropLocal(done);
    return all;
  }

  /// Bundle 197a: Clear chat from the ⋮ pop-up (the row stays).
  Future<void> clearChat() async {
    if (isClosed) return;
    try {
      await repository.clearChat(state.device.id, keepRow: true);
      if (isClosed) return;
      // My unsent messages stay (they are still sending).
      final kept = state.messages
          .where((m) =>
              m.senderId == localDeviceId &&
              const {'queued', 'sending', 'pending'}.contains(m.status))
          .toList(growable: false);
      emit(state.copyWith(messages: kept));
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: cleanBlocError(e)));
    }
  }

  void _onDeleted(String id) => _dropLocal({id});

  void _dropLocal(Set<String> ids) {
    if (isClosed || ids.isEmpty) return;
    if (!state.messages.any((m) => ids.contains(m.id))) return;
    final next = {...state.reactions}..removeWhere((k, _) => ids.contains(k));
    emit(state.copyWith(
        messages: state.messages
            .where((m) => !ids.contains(m.id))
            .toList(growable: false),
        reactions: next));
  }

  void _onReaction(MessageReaction reaction) {
    if (isClosed) return;
    final current = [...(state.reactions[reaction.messageId] ?? const <MessageReaction>[])];
    final index = current.indexWhere((item) => item.reactorId == reaction.reactorId);
    if (index >= 0) current[index] = reaction; else current.add(reaction);
    final next = {...state.reactions, reaction.messageId: current};
    emit(state.copyWith(reactions: next));
  }

  void clearError() {
    if (!isClosed && state.error != null) emit(state.copyWith(clearError: true));
  }

  void _onIncoming(Message m) {
    final matches =
        (m.senderId == state.device.id && m.recipientId == localDeviceId) ||
            (m.recipientId == state.device.id && m.senderId == localDeviceId);
    if (!matches) return;
    if (MessageEnvelope.isControl(m.body)) return; // Bundle 198: never a bubble
    if (MessageDeleteBook.instance.isDeleted(m.id)) return; // Bundle 197a
    final next = [...state.messages];
    final i = next.indexWhere((x) => x.id == m.id);
    if (i < 0) {
      // Bundle 144: insert at its created time (same order as the stored
      // history: created_at, id), so a late photo/voice note appears where it
      // was sent. Scans from the end: usually zero steps.
      var at = next.length;
      while (at > 0 && _sortsAfter(next[at - 1], m)) {
        at--;
      }
      next.insert(at, m);
    } else {
      next[i] = m;
    }
    if (!isClosed) emit(state.copyWith(messages: next));
  }

  static bool _sortsAfter(Message a, Message b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c > 0 || (c == 0 && a.id.compareTo(b.id) > 0);
  }

  @override
  Future<void> close() async {
    _peerTimer?.cancel();
    await _subscription.cancel();
    await _reactionSubscription.cancel();
    await _deletedSubscription?.cancel();
    return super.close();
  }
}
