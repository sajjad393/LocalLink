import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/device_status_indicator.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/features/files/bloc/file_transfer_bloc.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/presentation/widgets/chat_composer.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_bubble.dart';
import 'package:locallink/features/messaging/presentation/widgets/pending_attachment_strip.dart';
import 'package:locallink/features/messaging/data/services/voice_note_service.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';

class ChatScreen extends StatefulWidget {
  final ChatBloc controller;
  final FileTransferRepositoryContract files;
  final Future<void> Function(Device device)? onStartCall;
  final LocalLinkNotificationService? notifications;
  final String? initialMessageId;
  final String? initialAttachmentId;

  const ChatScreen({
    super.key,
    required this.controller,
    required this.files,
    this.onStartCall,
    this.notifications,
    this.initialMessageId,
    this.initialAttachmentId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _searching = false;
  late final FileTransferBloc _transferController;
  final _voiceNotes = VoiceNoteService();
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _transferController = FileTransferBloc(repository: widget.files);
    widget.notifications?.setActiveDirectConversation(widget.controller.device.id);
    unawaited(_load());
  }

  Future<void> _load() async {
    await widget.controller.load();
    if (!mounted) return;
    await widget.notifications?.markDirectConversationRead(widget.controller.device.id);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToInitial());
  }

  void _scrollToInitial() {
    if (!mounted || !_scrollController.hasClients) return;
    final messageId = widget.initialMessageId;
    if (messageId == null) {
      _scrollToBottom(animated: false);
      return;
    }
    final index = widget.controller.messages.indexWhere(
      (message) => message.id == messageId ||
          (widget.initialAttachmentId != null &&
              message.attachments.any((attachment) => attachment.id == widget.initialAttachmentId)),
    );
    if (index < 0) return;
    final offset = (index * 88.0).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      offset,
      duration: LocalLinkMotion.standard,
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottom({required bool animated}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (!animated) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(target, duration: LocalLinkMotion.quick, curve: Curves.easeOut);
  }

  Future<void> _pickFiles() async {
    try {
      final picked = await _transferController.pickFiles(allowMultiple: true);
      if (!mounted || picked.isEmpty) return;
      widget.controller.addPendingAttachments(picked);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
    }
  }

  Future<void> _toggleVoiceNote() async {
    if (_recording) {
      try {
        final file = await _voiceNotes.stop();
        if (!mounted) return;
        setState(() => _recording = false);
        widget.controller.addPendingAttachments([file]);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice note ready to send')));
      } catch (error) {
        if (mounted) { setState(() => _recording = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error)))); }
      }
      return;
    }
    try {
      await _voiceNotes.record();
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
    }
  }

  Future<void> _send() async {
    final body = _textController.text.trim();
    if (body.isEmpty && widget.controller.pendingAttachments.isEmpty) return;
    _textController.clear();
    await widget.controller.send(body);
    if (mounted) _scrollToBottom(animated: true);
  }

  Future<void> _startCall() async {
    final callback = widget.onStartCall;
    if (callback == null) return;
    try {
      await callback(widget.controller.device);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
    }
  }

  String _cleanError(Object error) => error.toString().replaceFirst('Exception: ', '').trim();

  void _startSearch() {
    setState(() {
      _searching = true;
      _searchController.clear();
    });
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _searchController.clear();
    });
  }

  String _presenceLabel(Device device) {
    if (device.wifiDirectConnected) return 'Available · Wi-Fi Direct';
    if (device.serverConnected || device.lanAvailable) return 'Available · Local Wi-Fi';
    if (device.meshAvailable) return 'Available nearby';
    if (device.networkStatus == DeviceNetworkStatus.unknown) return 'Status unavailable';
    return 'Offline';
  }

  Future<void> _showMessageActions(String body, String messageId) async {
    const quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in quickReactions)
                    IconButton(
                      tooltip: 'React $emoji',
                      onPressed: () => Navigator.pop(sheetContext, emoji),
                      icon: Text(emoji, style: const TextStyle(fontSize: 28)),
                    ),
                ],
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy message'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: body));
                  if (sheetContext.mounted) Navigator.pop(sheetContext, 'copy');
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 'copy') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied')));
      return;
    }
    await widget.controller.react(messageId, selected);
  }

  Future<void> _showConversationInfo() async {
    final device = widget.controller.device;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(device.name.isEmpty ? 'Conversation' : device.name),
        content: Text(_presenceLabel(device)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    widget.notifications?.setActiveDirectConversation(null);
    widget.controller.close();
    if (_recording) { unawaited(_voiceNotes.cancel()); }
    _transferController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<ChatBloc, ChatState>(
      bloc: widget.controller,
      builder: (context, state) {
        final device = state.device;
        final searchQuery = _searchController.text.trim().toLowerCase();
        final visibleMessages = searchQuery.isEmpty
            ? state.messages
            : state.messages.where((message) {
                return message.body.toLowerCase().contains(searchQuery) ||
                    message.attachments.any((attachment) => attachment.originalName.toLowerCase().contains(searchQuery));
              }).toList();
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            leading: _searching
                ? IconButton(
                    tooltip: 'Close search',
                    onPressed: _closeSearch,
                    icon: const Icon(Icons.arrow_back),
                  )
                : null,
            title: _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search messages',
                      filled: false,
                      border: InputBorder.none,
                    ),
                  )
                : Row(
                    children: [
                      AccountAvatar(name: device.name, radius: 20),
                      const SizedBox(width: LocalLinkSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(device.name.isEmpty ? 'LocalLink user' : device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(_presenceLabel(device), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
            actions: _searching
                ? []
                : [
                    DeviceStatusIndicator(device: device, showLabel: false),
                    IconButton(
                      tooltip: 'Search messages',
                      onPressed: _startSearch,
                      icon: const Icon(Icons.search),
                    ),
                    if (widget.onStartCall != null)
                      IconButton(tooltip: 'Call', onPressed: _startCall, icon: const Icon(Icons.call_outlined)),
                    PopupMenuButton<String>(
                      tooltip: 'Conversation options',
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'info', child: Text('Conversation info')),
                      ],
                      onSelected: (value) {
                        if (value == 'info') _showConversationInfo();
                      },
                    ),
                  ],
          ),
          body: Column(
            children: [
              if (state.error != null)
                LocalLinkInlineError(message: state.error!, onRetry: () => widget.controller.load()),
              Expanded(
                child: state.isLoading
                    ? const LocalLinkLoadingView(message: 'Loading messages…')
                    : visibleMessages.isEmpty
                        ? LocalLinkEmptyView(
                            icon: searchQuery.isEmpty ? Icons.forum_outlined : Icons.search_off,
                            title: searchQuery.isEmpty ? 'Start the conversation' : 'No messages found',
                            message: searchQuery.isEmpty
                                ? 'Send a message, photo or file to begin chatting privately.'
                                : 'Try a different word or phrase.',
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.lg),
                            itemCount: visibleMessages.length,
                            itemBuilder: (_, index) {
                              final message = visibleMessages[index];
                              final showDate = index == 0 || !_sameDay(visibleMessages[index - 1].createdAt, message.createdAt);
                              return Column(
                                children: [
                                  if (showDate) _DateDivider(date: message.createdAt),
                                  MessageBubble(
                                    message: message,
                                    isMine: message.senderId == state.localDeviceId,
                                    files: widget.files,
                                    reactions: state.reactions[message.id] ?? const [],
                                    onLongPress: () => _showMessageActions(message.body, message.id),
                                  ),
                                ],
                              );
                            },
                          ),
              ),
              PendingAttachmentStrip(
                attachments: state.pendingAttachments,
                onRemove: widget.controller.removePendingAttachment,
              ),
              ChatComposer(
                controller: _textController,
                isSending: state.isSending,
                onPickAttachments: _pickFiles,
                onSend: _send,
                onVoiceNote: _toggleVoiceNote,
                isRecording: _recording,
              ),
            ],
          ),
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = now.year == date.year && now.month == date.month && now.day == date.day
        ? 'Today'
        : '${date.day}/${date.month}/${date.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LocalLinkSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.md, vertical: LocalLinkSpacing.xs),
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
      ),
    );
  }
}
