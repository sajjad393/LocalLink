import 'dart:async';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
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

  /// Bundle 136: set from Home so this chat can show a "Return to call" chip
  /// whenever the live call belongs to THIS peer (back on CallScreen hides the
  /// UI; the session lives in CallSessionManager).
  final CallBloc? calls;
  final LocalLinkNotificationService? notifications;
  final String? initialMessageId;
  final String? initialAttachmentId;

  const ChatScreen({
    super.key,
    required this.controller,
    required this.files,
    this.onStartCall,
    this.calls,
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
  int _recAmplitude = 0;
  Timer? _recAmplitudeTimer;
  /// Bundle 130: start stamp drives the composer "0:05" elapsed counter —
  /// refreshed by the same 8x/s amplitude poll, so no extra ticker exists.
  DateTime? _recStartedAt;

  int get _recElapsedSeconds {
    if (_recStartedAt == null) return 0;
    final s = DateTime.now().difference(_recStartedAt!).inSeconds;
    return s < 0 ? 0 : (s > 35999 ? 35999 : s);
  }

  @override
  void initState() {
    super.initState();
    _transferController = FileTransferBloc(repository: widget.files);
    widget.notifications?.setActiveDirectConversation(widget.controller.device.id);
    // Show the jump-to-latest arrow whenever the reader drifts off the tail.
    _scrollController.addListener(_syncJumpArrow);
    unawaited(_load());
  }

  bool _showJumpArrow = false;

  void _syncJumpArrow() {
    if (!_scrollController.hasClients || !mounted) return;
    final show = _scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 220;
    if (show != _showJumpArrow) setState(() => _showJumpArrow = show);
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

  int _lastSeenCount = -1;

  /// Incoming/outgoing messages glide the list to the newest entry. Glide
  /// rules that match WhatsApp: always for your own send, always while you
  /// sit near the tail; never while you read older history.
  void _maybeAutoScroll(int count, {required bool lastIsMine}) {
    final previous = _lastSeenCount;
    _lastSeenCount = count;
    if (previous < 0 || count <= previous) return;
    final nearEnd = _scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 220;
    final shouldGlide = lastIsMine || nearEnd || previous == 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && shouldGlide) _scrollToBottom(animated: true);
    });
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

  /// Bundle 133+ (approved mock): WhatsApp-minimal recording bar — trash
  /// discards the in-progress note, the gradient orb sends it immediately.
  Future<void> _cancelVoiceNote() async {
    try {
      await _voiceNotes.cancel();
    } catch (_) {}
    _recAmplitudeTimer?.cancel();
    _recAmplitudeTimer = null;
    if (mounted) {
      setState(() {
        _recording = false;
        _recAmplitude = 0;
        _recStartedAt = null;
      });
    }
  }

  Future<void> _finishVoiceNoteSend() async {
    if (!_recording) return;
    _recAmplitudeTimer?.cancel();
    _recAmplitudeTimer = null;
    try {
      final file = await _voiceNotes.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recAmplitude = 0;
        _recStartedAt = null;
      });
      widget.controller.addPendingAttachments([file]);
      // Stop+send in one gesture, like WhatsApp — no detached strip step.
      await widget.controller.send('');
      if (mounted) _scrollToBottom(animated: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _recAmplitude = 0;
          _recStartedAt = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_cleanError(error))));
      }
    }
  }

  Future<void> _toggleVoiceNote() async {
    if (_recording) {
      _recAmplitudeTimer?.cancel();
      _recAmplitudeTimer = null;
      try {
        final file = await _voiceNotes.stop();
        if (!mounted) return;
        setState(() {
          _recording = false;
          _recAmplitude = 0;
          _recStartedAt = null;
        });
        widget.controller.addPendingAttachments([file]);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice note ready to send')));
      } catch (error) {
        if (mounted) { setState(() { _recording = false; _recAmplitude = 0; _recStartedAt = null; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error)))); }
      }
      return;
    }
    try {
      await _voiceNotes.record();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recAmplitude = 0;
        _recStartedAt = DateTime.now();
      });
      // Mirrors WhatsApp's mic-meter poll cadence; native amplitude is
      // reset 8x/s into the composer's live bars.
      _recAmplitudeTimer?.cancel();
      _recAmplitudeTimer =
          Timer.periodic(const Duration(milliseconds: 120), (_) async {
        final amp = await _voiceNotes.amplitude();
        if (mounted && _recording) setState(() => _recAmplitude = amp);
      });
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

  String _cleanError(Object error) => cleanBlocError(error);

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

  String _presenceLabel(Device device) =>
      // Presence with path, app-wide: Nearby (direct link survives a dead
      // server/router) vs Online (server path only) vs Offline.
      device.presenceLabel();

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
    _recAmplitudeTimer?.cancel();
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
        _maybeAutoScroll(
          visibleMessages.length,
          lastIsMine: visibleMessages.isNotEmpty &&
              visibleMessages.last.senderId == state.localDeviceId,
        );
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
                      // Bundle 130: presence badge rides ON the avatar's
                      // upper-right edge — the standalone status icon is gone
                      // from the app-bar actions.
                      PresenceAvatar(
                        avatar: AccountAvatar(name: device.name, radius: 20),
                        device: device,
                      ),
                      const SizedBox(width: LocalLinkSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              device.name.isEmpty ? 'LocalLink user' : device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16.5,
                                    letterSpacing: .1,
                                  ),
                            ),
                            Text(_presenceLabel(device), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
            actions: _searching
                ? []
                : [
                    // Bundle 136: resume-live-call chip for THIS peer.
                    if (widget.calls != null)
                      _ReturnToCallChip(calls: widget.calls!, peerId: device.id),
                    // Bundle 130: the hollow/presence circle moved onto the
                    // title avatar as a badge — nothing else changed here.
                    if (widget.onStartCall != null)
                      IconButton(tooltip: 'Call', onPressed: _startCall, icon: const Icon(Icons.call_outlined)),
                    PopupMenuButton<String>(
                      tooltip: 'More options',
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'search',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.search),
                            title: Text('Search messages'),
                          ),
                        ),
                        PopupMenuItem(value: 'info', child: Text('Conversation info')),
                      ],
                      onSelected: (value) {
                        if (value == 'search') _startSearch();
                        if (value == 'info') _showConversationInfo();
                      },
                    ),
                  ],
          ),
          body: Column(
            children: [
              if (state.error != null)
                LocalLinkInlineError(message: friendlyErrorMessage(state.error!), onRetry: () => widget.controller.load()),
              Expanded(
                // Loading no longer blanks the whole chat: the shimmer only
                // shows for the very first paint (no messages at all).
                child: (state.isLoading && visibleMessages.isEmpty)
                    ? const LocalLinkLoadingView(message: 'Loading messages…')
                    : visibleMessages.isEmpty
                        ? LocalLinkEmptyView(
                            icon: searchQuery.isEmpty ? Icons.forum_outlined : Icons.search_off,
                            title: searchQuery.isEmpty ? 'Start the conversation' : 'No messages found',
                            message: searchQuery.isEmpty
                                ? 'Send a message, photo or file to begin chatting privately.'
                                : 'Try a different word or phrase.',
                          )
                        : Stack(
                            children: [
                              ListView.builder(
                                controller: _scrollController,
                                // Bundle 147: keep ~1.5 screens of bubbles built above/below so
                                // photos/videos are ready before they scroll in.
                                // ignore: deprecated_member_use
                                cacheExtent: 1200,
                                physics: const AlwaysScrollableScrollPhysics(),
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.lg),
                                itemCount: visibleMessages.length,
                                itemBuilder: (_, index) {
                                  final message = visibleMessages[index];
                                  final showDate = index == 0 || !_sameDay(visibleMessages[index - 1].createdAt, message.createdAt);
                                  // Bundle 132 (G): a transport section label
                                  // renders where the RECEIVE transport of
                                  // incoming history changes (walking back to
                                  // the previous labeled row). Untagged rows
                                  // and outgoing rows never open a section.
                                  final sectionLabel = _transportSectionLabelAt(visibleMessages, index, state.localDeviceId);
                                  return Column(
                                    children: [
                                      if (sectionLabel != null)
                                        _TransportDivider(label: sectionLabel),
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
                              if (_showJumpArrow)
                                Positioned(
                                  right: LocalLinkSpacing.md,
                                  bottom: LocalLinkSpacing.md,
                                  child: FloatingActionButton.small(
                                    heroTag: null,
                                    tooltip: 'Jump to latest',
                                    onPressed: () => _scrollToBottom(animated: true),
                                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                                  ),
                                ),
                            ],
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
                onVoiceCancel: _cancelVoiceNote,
                onVoiceSend: _finishVoiceNoteSend,
                hasAttachments: state.pendingAttachments.isNotEmpty,
                isRecording: _recording,
                recordingAmplitude: _recAmplitude,
                recordingElapsedSeconds: _recElapsedSeconds,
              ),
            ],
          ),
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Bundle 132 (G): transport label for ONE message — null when the row is
  /// untagged (pre-132 history) or outgoing (own rows never wear a label).
  static String? _transportLabel(Message m, String localDeviceId) {
    if (m.senderId == localDeviceId) return null;
    switch (m.channel) {
      case 'server':
        return 'Online';
      case 'wifi_direct':
        return 'Wi-Fi Direct';
      case 'mesh':
        return 'Mesh';
      case 'lan':
      case 'direct': // pre-132 value, no finer claim available
        return 'Local Wi-Fi';
      default:
        return null;
    }
  }

  /// The label rendering above visible[index] when the receive-transport
  /// section changes at that row (walking back to the previous LABELED row).
  static String? _transportSectionLabelAt(
      List<Message> visible, int index, String localDeviceId) {
    final label = _transportLabel(visible[index], localDeviceId);
    if (label == null) return null;
    for (var i = index - 1; i >= 0; i--) {
      final prev = _transportLabel(visible[i], localDeviceId);
      if (prev != null) return prev == label ? null : label;
    }
    return label; // first labeled row opens its section
  }
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

/// Bundle 132 (G): "—— Online ——" style section divider marking WHICH
/// transport delivered the messages below. Approved visual: hairline both
/// sides of a small colored label, no pill. Online=green, Wi-Fi Direct=
/// yellow, Mesh=purple, Local Wi-Fi=teal.
class _TransportDivider extends StatelessWidget {
  final String label;
  const _TransportDivider({required this.label});

  static const Map<String, Color> _labelColors = {
    'Online': Color(0xFF16A34A), // green-600
    'Wi-Fi Direct': Color(0xFFCA8A04), // yellow-600
    'Mesh': Color(0xFF7C3AED), // purple-600
    'Local Wi-Fi': Color(0xFF0D9488), // teal-600
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _labelColors[label] ?? scheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LocalLinkSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.md),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
            ),
          ),
          Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
        ],
      ),
    );
  }
}

/// Bundle 136: compact green chip in the chat app bar — only for a LIVE call
/// with THIS peer — reopening the (still running) CallScreen.
class _ReturnToCallChip extends StatelessWidget {
  final CallBloc calls;
  final String peerId;
  const _ReturnToCallChip({required this.calls, required this.peerId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CallSession?>(
      stream: calls.sessionStream,
      initialData: calls.session,
      builder: (context, snapshot) {
        final session = snapshot.data;
        if (session == null || session.isFinished || session.peerId != peerId) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: ActionChip(
            avatar: const Icon(Icons.call, size: 15, color: Color(0xFF14532D)),
            label: const Text('Return',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF14532D))),
            backgroundColor: const Color(0xFFDFF3E6),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      CallScreen(controller: calls, initialSession: session)),
            ),
          ),
        );
      },
    );
  }
}
