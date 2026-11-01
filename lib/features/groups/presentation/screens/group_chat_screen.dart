import 'dart:async';

import 'package:locallink/features/storage/presentation/media_message_actions.dart';
import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/widgets/messenger_date_divider.dart';
import 'package:locallink/features/files/bloc/file_transfer_bloc.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/bloc/group_chat_bloc.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/screens/group_details_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_composer.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_bubble.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/message_delete_book.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';
import 'package:locallink/features/messaging/presentation/screens/forward_screen.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';

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

  /// Bundle 197a: reply bar, held bubble, Select mode, quote flash.
  GroupMessage? _replyTo;
  String? _heldId;
  final GlobalKey _heldKey = GlobalKey();
  final Set<String> _selected = <String>{};
  String? _flashId;
  String? _jumpId;
  final GlobalKey _jumpKey = GlobalKey();
  Timer? _flashTimer;

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
      if (mounted) showErrorToast(context, error: error);
    }
  }

  Future<void> _send() async {
    final body = _messageController.text.trim();
    if ((body.isEmpty && _pending.isEmpty) || _controller.isSending) return;
    final files = List<PickedFile>.from(_pending);
    _messageController.clear();
    setState(() => _pending.clear());
    final replyTo = _replyTo;
    if (replyTo != null) setState(() => _replyTo = null);
    try {
      await _controller.send(body,
          attachments: files,
          reply: replyTo == null ? null : _replyRefFor(replyTo));
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: LocalLinkMotion.quick, curve: Curves.easeOut);
      }
    } catch (error) {
      if (mounted) setState(() => _pending.addAll(files));
      if (mounted) showErrorToast(context, error: error);
    }
  }

  // ---------------------------------------------------------------------
  // Bundle 197a: message options (mock 20, 21) - same as the 1-to-1 chat.
  // ---------------------------------------------------------------------

  static ReplyRef _replyRefFor(GroupMessage m) => ReplyRef(
        id: m.id,
        from: m.senderId,
        snip: cutSnippet(m.text),
        kind: replyKindFor(m.attachments),
      );

  bool _notSentYet(GroupMessage m) => _controller.isMine(m) && m.serverSeq == 0;

  String _nameFor(String senderId) => senderId == widget.localDeviceId
      ? 'You'
      : (_memberNames[senderId] ?? 'Group member');

  void _toggleSelect(GroupMessage m) {
    setState(() {
      if (!_selected.remove(m.id)) _selected.add(m.id);
    });
  }

  List<GroupMessage> get _selectedMessages => _controller.messages
      .where((m) => _selected.contains(m.id))
      .toList(growable: false);

  Future<void> _showMessageActions(GroupMessage message) async {
    if (_selected.isNotEmpty) {
      _toggleSelect(message);
      return;
    }
    setState(() => _heldId = message.id);
    try {
      final result = await showMessageActionsSheet(
        context,
        mine: _controller.isMine(message),
        hasText: message.text.trim().isNotEmpty,
        canForward: !_notSentYet(message) &&
            !MediaMessageActions.hasRemoved(message.attachments),
        canSave: MediaMessageActions.savable(message.attachments,
                mine: _controller.isMine(message))
            .isNotEmpty,
        barrierColor: Colors.transparent,
      );
      if (!mounted || result == null) return;
      switch (result.action) {
        case MessageAction.react:
          await _controller.react(message.id, result.emoji ?? '');
        case MessageAction.reply:
          setState(() => _replyTo = message);
        case MessageAction.copy:
          await _copy([message]);
        case MessageAction.forward:
          await _forward([message]);
        case MessageAction.save:
          await MediaMessageActions.save(
              context,
              MediaMessageActions.savable(message.attachments,
                  mine: _controller.isMine(message)));
        case MessageAction.info:
          await _showInfo(message);
        case MessageAction.select:
          setState(() => _selected.add(message.id));
        case MessageAction.delete:
          await _delete([message]);
      }
    } finally {
      if (mounted) setState(() => _heldId = null);
    }
  }

  static String _clock(DateTime v) {
    final hour = v.hour % 12 == 0 ? 12 : v.hour % 12;
    return '$hour:${v.minute.toString().padLeft(2, '0')} ${v.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _copy(List<GroupMessage> messages) async {
    final withText =
        messages.where((m) => m.text.trim().isNotEmpty).toList(growable: false);
    if (withText.isEmpty) return;
    final text = withText.length == 1
        ? withText.first.text
        : withText
            .map((m) =>
                '[${_clock(m.createdTime)}] ${_nameFor(m.senderId)}: ${m.text}')
            .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(withText.length == 1
            ? 'Message copied'
            : '${withText.length} messages copied')));
  }

  Future<void> _forward(List<GroupMessage> messages) async {
    final sendable = messages.where((m) => !_notSentYet(m)).toList();
    if (sendable.isEmpty) return;
    for (final m in sendable) {
      MediaMessageActions.markOpened(m.attachments);
    }
    final single = await runForwardFlow(context, [
      for (final m in sendable)
        ForwardItem(text: m.text, attachments: m.attachments),
    ]);
    if (!mounted) return;
    setState(_selected.clear);
    if (single == null) return;
    if (single.isGroup && single.id == widget.group.id) return;
    final route = ForwardHub.instance?.routeFor?.call(single);
    if (route != null) unawaited(Navigator.pushReplacement(context, route));
  }

  Widget _miniBubble(GroupMessage m) {
    final colors = Theme.of(context).colorScheme;
    final mine = _controller.isMine(m);
    final label = m.text.trim().isNotEmpty
        ? m.text
        : replyKindLabel(replyKindFor(m.attachments));
    final fg = mine ? Colors.white : colors.onSurface;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 5),
      decoration: BoxDecoration(
        gradient: mine ? LocalLinkBrand.linearGradient : null,
        color: mine ? null : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(LocalLinkRadius.chat),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(label,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg)),
          ),
          Text(_clock(m.createdTime),
              style: TextStyle(fontSize: 11, color: fg.withValues(alpha: .7))),
        ],
      ),
    );
  }

  Future<void> _delete(List<GroupMessage> messages) async {
    if (messages.isEmpty) return;
    final allowEveryone = messages.every((m) => canDeleteForEveryone(
        mine: _controller.isMine(m), createdAt: m.createdTime));
    final choice = await showDeleteMessagesSheet(
      context,
      count: messages.length,
      allowEveryone: allowEveryone,
      peerName: widget.group.name,
      group: true,
      preview: messages.length == 1
          ? Align(
              alignment: _controller.isMine(messages.first)
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: _miniBubble(messages.first))
          : null,
      barrierColor: _heldId != null ? Colors.transparent : null,
    );
    if (!mounted || choice == null) return;
    final ids = messages.map((m) => m.id).toList(growable: false);
    if (choice == DeleteChoice.forEveryone) {
      final ok = await _controller.deleteForEveryone(ids);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Too late to delete for everyone')));
      }
    } else {
      await _controller.deleteForMe(ids);
    }
    if (mounted) setState(() => _selected.removeAll(ids));
  }

  Future<void> _showInfo(GroupMessage m) => showMessageInfoSheet(
        context,
        preview: _miniBubble(m),
        sentAt: m.createdTime,
        group: true,
        notSentYet: _notSentYet(m),
        barrierColor: _heldId != null ? Colors.transparent : null,
      );

  void _jumpTo(String id) {
    final index = _controller.messages.indexWhere((m) => m.id == id);
    if (index < 0 || !_scrollController.hasClients) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message not found')));
      return;
    }
    setState(() {
      _jumpId = id;
      _flashId = id;
    });
    _scrollController.jumpTo(
        (index * 88.0).clamp(0.0, _scrollController.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _jumpKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx,
            alignment: .4, duration: LocalLinkMotion.quick);
      }
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  PreferredSizeWidget _selectBar(BuildContext context) {
    final picked = _selectedMessages;
    final one = picked.length == 1 ? picked.first : null;
    final colors = Theme.of(context).colorScheme;
    return AppBar(
      key: const ValueKey('select_bar'),
      backgroundColor: colors.primaryContainer.withValues(alpha: .55),
      leading: IconButton(
        tooltip: 'Close',
        onPressed: () => setState(_selected.clear),
        icon: const Icon(Icons.close),
      ),
      titleSpacing: 0,
      title: Text('${picked.length}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      actions: [
        if (one != null)
          IconButton(
            tooltip: 'Reply',
            onPressed: () => setState(() {
              _replyTo = one;
              _selected.clear();
            }),
            icon: const Icon(Icons.reply_rounded),
          ),
        if (one != null && _controller.isMine(one))
          IconButton(
            tooltip: 'Message info',
            onPressed: () => _showInfo(one),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        if (picked.any((m) => m.text.trim().isNotEmpty))
          IconButton(
            tooltip: 'Copy',
            onPressed: () async {
              await _copy(picked);
              if (mounted) setState(_selected.clear);
            },
            icon: const Icon(Icons.copy_outlined),
          ),
        if (picked.isNotEmpty &&
            picked.every((m) =>
                !_notSentYet(m) &&
                !MediaMessageActions.hasRemoved(m.attachments)))
          IconButton(
            tooltip: 'Forward',
            onPressed: () => _forward(picked),
            icon: const Icon(Icons.forward_rounded),
          ),
        IconButton(
          tooltip: 'Delete',
          onPressed: () => _delete(picked),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }

  String _senderName(GroupMessage message) {
    if (_controller.isMine(message)) return 'You';
    return _memberNames[message.senderId] ?? 'Group member';
  }

  @override
  void dispose() {
    widget.notifications?.setActiveGroupConversation(null);
    _flashTimer?.cancel();
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
      builder: (context, state) {
        // Bundle 197a: drop picks that were deleted meanwhile.
        final ids = {for (final m in state.messages) m.id};
        _selected.removeWhere((id) => !ids.contains(id));
        final selecting = _selected.isNotEmpty;
        final scaffold = Scaffold(
        appBar: selecting ? _selectBar(context) : AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              const GroupAvatar(radius: 20),
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
              LocalLinkInlineError(message: friendlyErrorMessage(state.error), onRetry: _controller.load),
            Expanded(
              child: state.isLoading
                  ? const LocalLinkLoadingView(message: 'Loading group messages…')
                  : state.messages.isEmpty
                      ? const LocalLinkEmptyView(
                          icon: Icons.groups_outlined,
                          title: 'Start the group conversation',
                          message: 'Send a message or share a file with everyone in this group.',
                          lottieAsset: 'assets/animations/empty_inbox.json',
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          // Bundle 147: keep ~1.5 screens of bubbles built above/below so
                          // photos/videos are ready before they scroll in.
                          // ignore: deprecated_member_use
                          cacheExtent: 1200,
                          padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.lg),
                          itemCount: state.messages.length,
                          itemBuilder: (_, index) {
                            final message = state.messages[index];
                            final parsed = DateTime.tryParse(message.createdAt)?.toLocal();
                            final previous = index == 0 ? null : DateTime.tryParse(state.messages[index - 1].createdAt)?.toLocal();
                            final showDate = parsed != null && (previous == null || previous.day != parsed.day || previous.month != parsed.month || previous.year != parsed.year);
                            return Column(
                              // Bundle 150: stable row per message.
                              key: ValueKey<String>('gmsg:${message.id}'),
                              children: [
                                if (showDate) MessengerDateDivider(date: parsed),
                                KeyedSubtree(
                                  key: _jumpId == message.id ? _jumpKey : null,
                                  child: _groupRow(message, state, ids, selecting),
                                ),
                              ],
                            );
                          },
                        ),
            ),
            if (_replyTo != null)
              ReplyBar(
                name: _nameFor(_replyTo!.senderId),
                line: replyLine(_replyRefFor(_replyTo!)),
                isYou: _controller.isMine(_replyTo!),
                onClose: () => setState(() => _replyTo = null),
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
      );
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _selected.isNotEmpty) setState(_selected.clear);
          },
          child: Stack(
            children: [
              scaffold,
              if (_heldId != null)
                Positioned.fill(child: HeldBubbleDimmer(target: _heldKey)),
            ],
          ),
        );
      },
    );
  }

  /// Bundle 197a: one bubble row (hold sheet, Select mode, quote).
  Widget _groupRow(GroupMessage message, GroupChatState state, Set<String> ids,
      bool selecting) {
    final reply = message.replyTo;
    final picked = _selected.contains(message.id);
    final bubble = GestureDetector(
      onLongPress: () => _showMessageActions(message),
      onTap: selecting ? () => _toggleSelect(message) : null,
      child: GroupMessageBubble(
        message: message,
        isMine: _controller.isMine(message),
        files: widget.files,
        senderName: _senderName(message),
        reactions: state.reactions[message.id] ?? const [],
        highlighted: picked || _heldId == message.id || _flashId == message.id,
        bubbleKey: _heldId == message.id ? _heldKey : null,
        quoteName: reply == null ? '' : _nameFor(reply.from),
        quoteIsYou: reply?.from == widget.localDeviceId,
        quoteMissing: reply != null &&
            (MessageDeleteBook.instance.isDeleted(reply.id) ||
                !ids.contains(reply.id)),
        onQuoteTap:
            reply == null || selecting ? null : () => _jumpTo(reply.id),
      ),
    );
    if (!selecting) return bubble;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleSelect(message),
      child: Row(
        children: [
          SelectCheck(selected: picked),
          Expanded(child: bubble),
        ],
      ),
    );
  }
}
