import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/bloc/file_transfer_bloc.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/groups/bloc/group_chat_bloc.dart';
import 'package:locallink/features/groups/presentation/screens/group_details_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_composer.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_bubble.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';

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
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _pending = <PickedFile>[];
  late final FileTransferBloc _transferController;

  @override
  void initState() {
    super.initState();
    _transferController = FileTransferBloc(repository: widget.files);
    _controller = GroupChatBloc(
      repository: widget.messaging,
      group: widget.group,
      localDeviceId: widget.localDeviceId,
    );
    widget.notifications?.setActiveGroupConversation(widget.group.id);
    unawaited(_load());
  }

  Future<void> _load() async {
    await _controller.load();
    if (!mounted) return;
    await widget.notifications?.markGroupConversationRead(widget.group.id);
    if (!mounted || widget.initialMessageId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final index = _controller.messages.indexWhere(
        (message) =>
            message.id == widget.initialMessageId ||
            (widget.initialAttachmentId != null &&
                message.attachments.any(
                  (attachment) => attachment.id == widget.initialAttachmentId,
                )),
      );
      if (index < 0) return;
      final offset = index * 100.0;
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickFiles() async {
    try {
      final files = await _transferController.pickFiles(allowMultiple: true);
      if (mounted && files.isNotEmpty) {
        setState(() => _pending.addAll(files));
      }
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
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
    } catch (e) {
      if (mounted) {
        setState(() => _pending.addAll(files));
      }
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    widget.notifications?.setActiveGroupConversation(null);
    _controller.close();
    _messageController.dispose();
    _scrollController.dispose();
    _transferController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder(bloc: _controller, builder: (context, state) => Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          IconButton(
            tooltip: 'Group details',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupDetailsScreen(
                  group: widget.group,
                  localDeviceId: widget.localDeviceId,
                  groups: widget.groups,
                ),
              ),
            ),
            icon: const Icon(Icons.group),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_controller.error != null)
            MaterialBanner(
              content: Text(_controller.error.toString().replaceFirst('Exception: ', '')),
              actions: [
                TextButton(onPressed: _controller.load, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: _controller.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _controller.messages.length,
                    itemBuilder: (_, index) {
                      final message = _controller.messages[index];
                      return GroupMessageBubble(
                        message: message,
                        isMine: _controller.isMine(message),
                        files: widget.files,
                      );
                    },
                  ),
          ),
          GroupComposer(
            controller: _messageController,
            pending: _pending,
            isSending: _controller.isSending,
            onPick: _pickFiles,
            onRemove: (index) => setState(() => _pending.removeAt(index)),
            onSend: _send,
          ),
        ],
      ),
    ));
  }
}
