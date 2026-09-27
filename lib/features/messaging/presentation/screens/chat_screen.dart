import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/bloc/file_transfer_bloc.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/presentation/widgets/chat_composer.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_bubble.dart';
import 'package:locallink/features/messaging/presentation/widgets/pending_attachment_strip.dart';
import 'package:locallink/core/widgets/device_status_indicator.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';

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
  late final FileTransferBloc _transferController;

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
    if (!mounted || widget.initialMessageId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final index = widget.controller.messages.indexWhere(
        (message) =>
            message.id == widget.initialMessageId ||
            (widget.initialAttachmentId != null &&
                message.attachments.any(
                  (attachment) => attachment.id == widget.initialAttachmentId,
                )),
      );
      if (index < 0) return;
      final offset = index * 92.0;
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }


  Future<void> _pickFiles() async {
    try {
      final picked = await _transferController.pickFiles(allowMultiple: true);
      if (!mounted || picked.isEmpty) return;
      widget.controller.addPendingAttachments(picked);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(error))),
      );
    }
  }

  Future<void> _send() async {
    final body = _textController.text.trim();
    if (body.isEmpty && widget.controller.pendingAttachments.isEmpty) return;
    _textController.clear();
    await widget.controller.send(body);
  }

  Future<void> _startCall() async {
    final callback = widget.onStartCall;
    if (callback == null) return;
    try {
      await callback(widget.controller.device);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(error))),
      );
    }
  }

  String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '').trim();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    widget.notifications?.setActiveDirectConversation(null);
    widget.controller.close();
    _transferController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final device = controller.device;

    return LocalLinkBlocBuilder(bloc: widget.controller, builder: (context, state) => Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(child: Text(device.name)),
            DeviceStatusIndicator(device: device, showLabel: false),
          ],
        ),
        actions: [
          if (widget.onStartCall != null)
            IconButton(
              onPressed: _startCall,
              icon: const Icon(Icons.call),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: controller.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: controller.messages.length,
                    itemBuilder: (_, index) {
                      final message = controller.messages[index];
                      return MessageBubble(
                        message: message,
                        isMine: message.senderId == controller.localDeviceId,
                        files: widget.files,
                      );
                    },
                  ),
          ),
          PendingAttachmentStrip(
            attachments: controller.pendingAttachments,
            onRemove: controller.removePendingAttachment,
          ),
          ChatComposer(
            controller: _textController,
            isSending: controller.isSending,
            onPickAttachments: _pickFiles,
            onSend: _send,
          ),
        ],
      ),
    ));
  }
}
