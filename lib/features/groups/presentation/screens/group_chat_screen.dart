import 'dart:async';

import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/features/files/bloc/file_transfer_bloc.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/bloc/group_chat_bloc.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/screens/group_details_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_composer.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_bubble.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';

class GroupChatScreen extends StatefulWidget {
  final LocalGroup group;
  final String localDeviceId;
  final GroupMessagingRepositoryContract messaging;
  final GroupRepositoryContract groups;
  final FileTransferRepositoryContract files;
  final LocalLinkNotificationService? notifications;
  final String? initialMessageId;
  final String? initialAttachmentId;

  const GroupChatScreen({
    super.key,
    required this.group,
    required this.localDeviceId,
    required this.messaging,
    required this.groups,
    required this.files,
    this.notifications,
    this.initialMessageId,
    this.initialAttachmentId,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  late final GroupChatBloc _controller;
  late final FileTransferBloc _transferController;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _pending = <PickedFile>[];
  Map<String, String> _memberNames = const {};

  @override
  void initState() {
    super.initState();
    _transferController = FileTransferBloc(repository: widget.files);
    _controller = GroupChatBloc(repository: widget.messaging, group: widget.group, localDeviceId: widget.localDeviceId);
    widget.notifications?.setActiveGroupConversation(widget.group.id);
    unawaited(_load());
  }

  Future<void> _load() async {
    await Future.wait([
      _controller.load(),
      _loadMemberNames(),
    ]);
    if (!mounted) return;
    await widget.notifications?.markGroupConversationRead(widget.group.id);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (widget.initialMessageId == null) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadMemberNames() async {
    try {
      final members = await widget.groups.listMembers(widget.group.id);
      final map = <String, String>{};
      for (final member in members) {
        final label = member.name.trim().isEmpty ? 'Group member' : member.name.trim();
        map[member.deviceId] = label;
      }
      if (mounted) setState(() => _memberNames = map);
    } catch (_) {
      // The chat remains usable even when member metadata is temporarily unavailable.
    }
  }

  Future<void> _pickFiles() async {
    try {
      final files = await _transferController.pickFiles(allowMultiple: true);
      if (mounted && files.isNotEmpty) setState(() => _pending.addAll(files));
    } catch (error) {
      _showMessage(_cleanError(error));
    }
  }

  Future<void> _send() async {
    final body = _messageController.text.trim();
    if ((body.isEmpty && _pending.isEmpty) || _controller.isSending) return;
    final files = List<PickedFile>.from(_pending);
    _messageController.clear();
    setState(() => _pending.clear());
    try {
      await _controller.send(body, attachments: files);
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: LocalLinkMotion.quick, curve: Curves.easeOut);
      }
    } catch (error) {
      if (mounted) setState(() => _pending.addAll(files));
      _showMessage(_cleanError(error));
    }
  }

  Future<void> _showMessageActions(GroupMessage message) async {
    const emojis=['👍','❤️','😂','😮','😢','🙏'];
    final selected=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[for(final emoji in emojis)IconButton(tooltip:'React $emoji',onPressed:()=>Navigator.pop(c,emoji),icon:Text(emoji,style:const TextStyle(fontSize:28)))]))));
    if(mounted&&selected!=null)await _controller.react(message.id,selected);
  }

  String _cleanError(Object error) => error.toString().replaceFirst('Exception: ', '').trim();

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _senderName(GroupMessage message) {
    if (_controller.isMine(message)) return 'You';
    return _memberNames[message.senderId] ?? 'Group member';
  }

  @override
  void dispose() {
    widget.notifications?.setActiveGroupConversation(null);
    _controller.close();
    _transferController.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<GroupChatBloc, GroupChatState>(
      bloc: _controller,
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                child: const Icon(Icons.groups_rounded),
              ),
              const SizedBox(width: LocalLinkSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${_memberNames.length} members', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Group info',
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupDetailsScreen(group: widget.group, localDeviceId: widget.localDeviceId, groups: widget.groups),
                ),
              ),
              icon: const Icon(Icons.info_outline),
            ),
          ],
        ),
        body: Column(
          children: [
            if (state.error != null)
              LocalLinkInlineError(message: _cleanError(state.error!), onRetry: _controller.load),
            Expanded(
              child: state.isLoading
                  ? const LocalLinkLoadingView(message: 'Loading group messages…')
                  : state.messages.isEmpty
                      ? const LocalLinkEmptyView(
                          icon: Icons.groups_outlined,
                          title: 'Start the group conversation',
                          message: 'Send a message or share a file with everyone in this group.',
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.lg),
                          itemCount: state.messages.length,
                          itemBuilder: (_, index) {
                            final message = state.messages[index];
                            final parsed = DateTime.tryParse(message.createdAt)?.toLocal();
                            final previous = index == 0 ? null : DateTime.tryParse(state.messages[index - 1].createdAt)?.toLocal();
                            final showDate = parsed != null && (previous == null || previous.day != parsed.day || previous.month != parsed.month || previous.year != parsed.year);
                            return Column(
                              children: [
                                if (showDate)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: LocalLinkSpacing.md),
                                    child: Chip(label: Text('${parsed.day}/${parsed.month}/${parsed.year}')),
                                  ),
                                GestureDetector(
                                  onLongPress: () => _showMessageActions(message),
                                  child: GroupMessageBubble(
                                    message: message,
                                    isMine: _controller.isMine(message),
                                    files: widget.files,
                                    senderName: _senderName(message),
                                    reactions: state.reactions[message.id] ?? const [],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
            GroupComposer(
              controller: _messageController,
              pending: _pending,
              isSending: state.isSending,
              onPick: _pickFiles,
              onRemove: (index) => setState(() => _pending.removeAt(index)),
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}
