import 'dart:async';
import 'package:locallink/features/storage/presentation/media_message_actions.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/widgets/presence_way.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/directory/presentation/contact_sheets.dart';
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
import 'package:locallink/features/messaging/presentation/widgets/peer_offline_builder.dart';
import 'package:locallink/features/messaging/data/services/voice_note_service.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recorder_controller.dart';
import 'package:locallink/features/files/presentation/widgets/media_playback_coordinator.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/message_delete_book.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';
import 'package:locallink/features/messaging/presentation/screens/forward_screen.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';
import 'package:locallink/features/messaging/presentation/widgets/pinch_text_zoom.dart';
import 'package:locallink/features/messaging/presentation/widgets/quote_thumb.dart';
import 'package:locallink/features/messaging/presentation/widgets/swipe_to_reply.dart';
import 'package:locallink/core/services/ui_sounds.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';
import 'package:locallink/features/files/domain/file_size_rule.dart';
import 'package:locallink/features/files/presentation/widgets/file_too_big_dialog.dart';

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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  /// Bundle 199: the message box, so a reply can open the keyboard.
  final FocusNode _composerFocus = FocusNode();
  bool _searching = false;
  late final FileTransferBloc _transferController;
  final _voiceNotes = VoiceNoteService();

  /// Bundle 181 (approved mock): WhatsApp-style voice recorder.
  late final VoiceRecorderController _voice;

  @override
  void initState() {
    super.initState();
    _transferController = FileTransferBloc(repository: widget.files);
    widget.notifications?.setActiveDirectConversation(widget.controller.device.id);
    _voice = VoiceRecorderController(
      backend: _voiceNotes,
      onSend: _sendVoiceNote,
      onError: _voiceError,
      haptic: (strong) => strong ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact(),
      onRecordStart: () => MediaPlaybackCoordinator.instance.claim(_voice, _voice.interrupt),
      // Something opened over the chat (a call screen...): pause.
      shouldPause: () => mounted && !(ModalRoute.of(context)?.isCurrent ?? true),
      // Bundle 198: tik / swoosh / tok.
      tone: (t) => UiSounds.play(switch (t) {
        VoiceTone.start => UiSound.voiceStart,
        VoiceTone.send => UiSound.voiceSend,
        VoiceTone.cancel => UiSound.voiceCancel,
      }),
    );
    final draft = VoiceDraftStore.take(widget.controller.device.id);
    if (draft != null) _voice.restore(draft);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_lookupPeer());
    // Show the jump-to-latest arrow whenever the reader drifts off the tail.
    _scrollController.addListener(_syncJumpArrow);
    unawaited(_load());
  }

  bool _showJumpArrow = false;

  /// Bundle 197a: reply bar, held bubble, Select mode, quote jump flash.
  Message? _replyTo;
  String? _heldId;
  final GlobalKey _heldKey = GlobalKey();
  final Set<String> _selected = <String>{};
  String? _flashId;
  String? _jumpId;
  final GlobalKey _jumpKey = GlobalKey();
  Timer? _flashTimer;

  /// Bundle 196: who is behind this phone (for Block + the info sheet).
  String _peerUserId = '';
  String _peerUsername = '';
  bool _blockLogged = false;

  Future<void> _lookupPeer() async {
    final who = await BlockHub.instance.lookup(widget.controller.device.id);
    if (!mounted || who == null) return;
    setState(() {
      _peerUserId = who.userId;
      _peerUsername = who.username;
    });
  }

  String _peerName(Device device) =>
      device.name.isEmpty ? 'LinkUp user' : device.name;

  /// The blocked person behind this phone (falls back to the phone itself).
  BlockedPerson _blockedPerson(Device device) =>
      BlockHub.instance.personForDevice(device.id) ??
      BlockHub.instance.personForUser(_peerUserId) ??
      BlockedPerson(
        userId: _peerUserId.isNotEmpty ? _peerUserId : device.id,
        deviceId: device.id,
        name: _peerName(device),
        username: _peerUsername,
      );

  Future<void> _unblock(Device device) =>
      runUnblockFlow(context, _blockedPerson(device), from: 'chat');

  Future<void> _block(Device device) async {
    var userId = _peerUserId;
    if (userId.isEmpty) {
      userId = (await BlockHub.instance.lookup(device.id))?.userId ?? '';
    }
    if (!mounted) return;
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Open this person from People to block them.')));
      return;
    }
    await runBlockFlow(context,
        userId: userId,
        name: _peerName(device),
        username: _peerUsername,
        from: 'chat');
  }

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
      final all = await _transferController.pickFiles(allowMultiple: true);
      if (!mounted || all.isEmpty) return;
      // Bundle 203 (5): files over 50 MB are dropped with a pop-up.
      final split = FileSizeRule.split(all);
      final picked = split.keep;
      if (picked.isNotEmpty) widget.controller.addPendingAttachments(picked);
      if (split.dropped.isNotEmpty) {
        await showFileTooBigDialog(context, [
          for (final f in split.dropped)
            TooBigFile(f.name, f.size, isVideo: f.contentType.startsWith('video/')),
        ]);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
    }
  }

  /// Bundle 181: one voice note is ready (one file, parts already joined).
  Future<void> _sendVoiceNote(PickedFile file) async {
    widget.controller.addPendingAttachments([file]);
    final reply = _takeReply();
    await widget.controller.send('', reply: reply);
    if (mounted) _scrollToBottom(animated: true);
  }

  void _voiceError(Object error) {
    if (!mounted) return;
    // No microphone permission: Android asks by itself, no extra message.
    if (error is PlatformException && error.code == 'PERMISSION') return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Bundle 181: Home key / screen off while recording = pause, keep it.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _voice.interrupt();
    }
    // Bundle 198: back to this open chat -> what came meanwhile is read.
    if (state == AppLifecycleState.resumed &&
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(widget.notifications
          ?.markDirectConversationRead(widget.controller.device.id));
    }
  }

  Future<void> _send() async {
    final body = _textController.text.trim();
    if (body.isEmpty && widget.controller.pendingAttachments.isEmpty) return;
    _textController.clear();
    final reply = _takeReply();
    UiSounds.play(UiSound.messageSent); // Bundle 198: soft "tick"
    await widget.controller.send(body, reply: reply);
    if (mounted) _scrollToBottom(animated: true);
  }

  // ---------------------------------------------------------------------
  // Bundle 197a: message options (mock v8).
  // ---------------------------------------------------------------------

  /// The quote for the next send (the bar closes).
  ReplyRef? _takeReply() {
    final m = _replyTo;
    if (m == null) return null;
    setState(() => _replyTo = null);
    return _replyRefFor(m);
  }

  /// Bundle 199: start a reply (swipe / Hold > Reply / Select > Reply):
  /// the reply bar opens and the keyboard opens (WhatsApp).
  void _startReply(Message m, {required String from}) {
    if (!mounted) return;
    setState(() {
      _replyTo = m;
      _selected.clear();
    });
    AppLogger.info('REPLY_START',
        detail: 'from=$from kind=${replyKindFor(m.attachments)}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _composerFocus.canRequestFocus) {
        _composerFocus.requestFocus();
      }
    });
  }

  static ReplyRef _replyRefFor(Message m) => ReplyRef(
        id: m.id,
        from: m.senderId,
        snip: cutSnippet(m.text),
        kind: replyKindFor(m.attachments),
      );

  bool _isMine(Message m) => m.senderId == widget.controller.localDeviceId;

  static bool _notSentYet(Message m) => const {
        'queued',
        'sending',
        'pending',
        'failed',
      }.contains(m.status.toLowerCase());

  String _nameOf(Message m) =>
      _isMine(m) ? 'You' : _peerName(widget.controller.device);

  void _toggleSelect(Message m) {
    setState(() {
      if (!_selected.remove(m.id)) _selected.add(m.id);
    });
  }

  List<Message> get _selectedMessages => widget.controller.messages
      .where((m) => _selected.contains(m.id))
      .toList(growable: false);

  Future<void> _onHold(Message message) async {
    if (_selected.isNotEmpty) {
      _toggleSelect(message);
      return;
    }
    final hub = BlockHub.instance;
    final device = widget.controller.device;
    final blocked =
        hub.isBlockedDevice(device.id) || hub.hasBlockedMe(device.id);
    setState(() => _heldId = message.id);
    try {
      final result = await showMessageActionsSheet(
        context,
        mine: _isMine(message),
        hasText: message.text.trim().isNotEmpty,
        canReply: !blocked,
        canForward: !_notSentYet(message) &&
            !MediaMessageActions.hasRemoved(message.attachments),
        canSave: MediaMessageActions.savable(message.attachments,
                mine: _isMine(message))
            .isNotEmpty,
        barrierColor: Colors.transparent,
      );
      if (!mounted || result == null) return;
      switch (result.action) {
        case MessageAction.react:
          await widget.controller.react(message.id, result.emoji ?? '');
        case MessageAction.reply:
          _startReply(message, from: 'hold');
        case MessageAction.copy:
          await _copy([message]);
        case MessageAction.forward:
          await _forward([message]);
        case MessageAction.save:
          await MediaMessageActions.save(
              context,
              MediaMessageActions.savable(message.attachments,
                  mine: _isMine(message)));
        case MessageAction.info:
          await _showInfo(message);
        case MessageAction.select:
          setState(() => _selected.add(message.id));
        case MessageAction.delete:
          await _delete([message]);
        // Bundle G5b: group-only rows (never shown here).
        case MessageAction.pin:
        case MessageAction.unpin:
          break;
      }
    } finally {
      if (mounted) setState(() => _heldId = null);
    }
  }

  Future<void> _copy(List<Message> messages) async {
    final withText =
        messages.where((m) => m.text.trim().isNotEmpty).toList(growable: false);
    if (withText.isEmpty) return;
    final text = withText.length == 1
        ? withText.first.text
        : withText
            .map((m) => '[${_clock(m.createdAt)}] ${_nameOf(m)}: ${m.text}')
            .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(withText.length == 1
            ? 'Message copied'
            : '${withText.length} messages copied')));
  }

  static String _clock(DateTime raw) {
    final v = raw.toLocal();
    final hour = v.hour % 12 == 0 ? 12 : v.hour % 12;
    return '$hour:${v.minute.toString().padLeft(2, '0')} ${v.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _forward(List<Message> messages) async {
    final sendable = messages.where((m) => !_notSentYet(m)).toList();
    if (sendable.isEmpty) return;
    for (final m in sendable) {
      MediaMessageActions.markOpened(m.attachments);
    }
    final items = [
      for (final m in sendable)
        ForwardItem(text: m.text, attachments: m.attachments),
    ];
    final single = await runForwardFlow(context, items);
    if (!mounted) return;
    setState(_selected.clear);
    if (single == null) return;
    if (!single.isGroup && single.id == widget.controller.device.id) return;
    final route = ForwardHub.instance?.routeFor?.call(single);
    if (route != null) unawaited(Navigator.pushReplacement(context, route));
  }

  /// Small copy of a bubble for the Delete / Message info sheets.
  Widget _miniBubble(Message m) {
    final colors = Theme.of(context).colorScheme;
    final label = m.text.trim().isNotEmpty
        ? m.text
        : replyKindLabel(replyKindFor(m.attachments));
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 5),
      decoration: BoxDecoration(
        color: _isMine(m) ? colors.surfaceContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(LocalLinkRadius.chat),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(label, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
          Text(_clock(m.createdAt),
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _delete(List<Message> messages) async {
    if (messages.isEmpty) return;
    final allowEveryone = messages.every((m) =>
        canDeleteForEveryone(mine: _isMine(m), createdAt: m.createdAt));
    final choice = await showDeleteMessagesSheet(
      context,
      count: messages.length,
      allowEveryone: allowEveryone,
      peerName: _peerName(widget.controller.device),
      preview: messages.length == 1
          ? Align(
              alignment: _isMine(messages.first)
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: _miniBubble(messages.first))
          : null,
      barrierColor: _heldId != null ? Colors.transparent : null,
    );
    if (!mounted || choice == null) return;
    final ids = messages.map((m) => m.id).toList(growable: false);
    if (choice == DeleteChoice.forEveryone) {
      final ok = await widget.controller.deleteForEveryone(ids);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Too late to delete for everyone')));
      }
    } else {
      await widget.controller.deleteForMe(ids);
    }
    if (mounted) setState(() => _selected.removeAll(ids));
  }

  Future<void> _showInfo(Message m) async {
    final status = m.status.toLowerCase();
    final delivered = const {'delivered', 'direct_delivered', 'read', 'played'}
            .contains(status)
        ? (DateTime.tryParse(m.deliveredAt ?? '') ?? m.createdAt)
        : null;
    // Bundle 198: Read / Played times (local only).
    final isRead = status == 'read' || status == 'played';
    final readAt = isRead
        ? (DateTime.tryParse(m.readAt ?? '')?.toLocal() ?? delivered)
        : null;
    final playedAt = status == 'played'
        ? (DateTime.tryParse(m.playedAt ?? '')?.toLocal() ?? readAt)
        : null;
    await showMessageInfoSheet(
      context,
      preview: _miniBubble(m),
      sentAt: m.createdAt,
      deliveredAt: delivered,
      peerName: _peerName(widget.controller.device),
      barrierColor: _heldId != null ? Colors.transparent : null,
      readAt: readAt,
      playedAt: playedAt,
      receiptsOff: !ReadReceiptsSetting.instance.on,
    );
  }

  /// Tap a quote: scroll to the old message and flash it.
  void _jumpTo(String id, List<Message> visible) {
    final index = visible.indexWhere((m) => m.id == id);
    if (index < 0 || !_scrollController.hasClients) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message not found')));
      return;
    }
    setState(() {
      _jumpId = id;
      _flashId = id;
    });
    final offset =
        (index * 88.0).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.jumpTo(offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _jumpKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx,
            alignment: .4, duration: LocalLinkMotion.quick);
      }
    });
    _flashTimer?.cancel();
    // Bundle 199: blue border for 2 s (was a grey ring for 1.4 s).
    _flashTimer = Timer(FlashRing.hold, () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  Future<void> _clearChat() async {
    final ok = await showClearChatSheet(context,
        name: _peerName(widget.controller.device));
    if (!ok || !mounted) return;
    await widget.controller.clearChat();
  }

  /// Select mode top bar (mock 13): X, count, Copy, Forward, Delete; Reply
  /// and Info only when one is picked.
  PreferredSizeWidget _selectBar(BuildContext context, bool blocked) {
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
        if (one != null && !blocked)
          IconButton(
            key: const ValueKey('select_reply'),
            tooltip: 'Reply',
            onPressed: () => _startReply(one, from: 'select'),
            icon: const Icon(Icons.reply_rounded),
          ),
        if (one != null && _isMine(one))
          IconButton(
            key: const ValueKey('select_info'),
            tooltip: 'Message info',
            onPressed: () => _showInfo(one),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        if (picked.any((m) => m.text.trim().isNotEmpty))
          IconButton(
            key: const ValueKey('select_copy'),
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
            key: const ValueKey('select_forward'),
            tooltip: 'Forward',
            onPressed: () => _forward(picked),
            icon: const Icon(Icons.forward_rounded),
          ),
        IconButton(
          key: const ValueKey('select_delete'),
          tooltip: 'Delete',
          onPressed: () => _delete(picked),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
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

  /// Bundle 182: my message with an attachment still in the outbox.
  static bool _awaitingSend(Message message) {
    final status = message.status;
    if (status != 'queued' && status != 'sending' && status != 'pending') {
      return false;
    }
    // The tile itself shows "Waiting" only on photos and videos.
    return message.attachments.isNotEmpty;
  }

  String _presenceLabel(Device device) =>
      // Bundle 148: the one app-wide live status (PresenceHub) — identical
      // to the Chats list, Calls tab, Contacts and Nearby screen.
      // Bundle 201 (F): with the way (mock ST).
      PresenceHub.instance.wayLabelOf(device.id);

  /// Bundle 162 (4.6): tap on the red (!) - "Message not sent" sheet.
  Future<void> _showFailedActions(String messageId) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Message not sent',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Resend'),
                onTap: () => Navigator.pop(sheetContext, 'resend'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete'),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final bloc = widget.controller;
    if (choice == 'resend') {
      final ok = await bloc.resendFailed(messageId);
      if (!mounted || ok) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This message cannot be resent')));
    } else if (choice == 'delete') {
      await bloc.deleteFailed(messageId);
    }
  }

  /// Bundle 196 (10.6): Conversation info is a bottom sheet (mock 14b/c).
  Future<void> _showConversationInfo() async {
    final device = widget.controller.device;
    final hub = BlockHub.instance;
    final iBlocked = hub.isBlockedDevice(device.id);
    final blockedMe = !iBlocked && hub.hasBlockedMe(device.id);
    final presence = _presenceLabel(device);
    final choice = await showChatInfoSheet(
      context,
      name: _peerName(device),
      subtitle: _peerUsername.isEmpty
          ? presence
          : '@$_peerUsername · $presence',
      username: _peerUsername.isEmpty ? '' : '@$_peerUsername',
      blocked: iBlocked,
      showCall: widget.onStartCall != null && !blockedMe,
      avatar: PresenceAvatar(
        avatar: AccountAvatar(name: device.name, radius: 23, peerId: device.id),
        device: device,
      ),
      // Bundle 201 (F, mock ST S3): "Connected by …".
      wayCard: PresenceWayCard(deviceId: device.id),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case ChatInfoChoice.call:
        await _startCall();
      case ChatInfoChoice.search:
        _startSearch();
      case ChatInfoChoice.block:
        await _block(device);
      case ChatInfoChoice.unblock:
        await _unblock(device);
    }
  }

  /// Bundle 196 (10.3 / 12.6): the bar that replaces the message box.
  Widget _blockedBar(BuildContext context, Device device,
      {required bool mine}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('chat_blocked_bar'),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, mine ? 6 : 16, 8, mine ? 6 : 16),
          child: Row(
            children: [
              Icon(Icons.block, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mine
                      ? 'You blocked ${_peerName(device)}.'
                      : "You can't message ${_peerName(device)}.",
                  style: TextStyle(
                      fontSize: 14,
                      color: colors.onSurfaceVariant,
                      letterSpacing: 0),
                ),
              ),
              if (mine)
                TextButton(
                  key: const ValueKey('chat_blocked_unblock'),
                  onPressed: () => _unblock(device),
                  style: TextButton.styleFrom(
                    textStyle: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Unblock'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "You blocked Ali · 8:49 PM" at the end of the messages (not stored).
  Widget _blockedChip(BuildContext context, Device device) {
    final colors = Theme.of(context).colorScheme;
    final at = blockTimeLabel(_blockedPerson(device).blockedAt);
    return Center(
      key: const ValueKey('chat_blocked_chip'),
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          at.isEmpty
              ? 'You blocked ${_peerName(device)}'
              : 'You blocked ${_peerName(device)} · $at',
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _composerFocus.dispose();
    _textController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    widget.notifications?.setActiveDirectConversation(null);
    widget.controller.close();
    WidgetsBinding.instance.removeObserver(this);
    MediaPlaybackCoordinator.instance.release(_voice);
    // Bundle 181: leaving the chat keeps a paused voice note as a draft.
    final voice = _voice;
    final chatId = widget.controller.device.id;
    unawaited(voice.suspend().then((draft) {
      if (draft != null) VoiceDraftStore.put(chatId, draft);
      voice.dispose();
    }));
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
                return message.text.toLowerCase().contains(searchQuery) ||
                    message.attachments.any((attachment) => attachment.originalName.toLowerCase().contains(searchQuery));
              }).toList();
        _maybeAutoScroll(
          visibleMessages.length,
          lastIsMine: visibleMessages.isNotEmpty &&
              visibleMessages.last.senderId == state.localDeviceId,
        );
        // Bundle 196: block / unblock switches the chat at once.
        return ListenableBuilder(
          listenable: BlockHub.instance,
          builder: (context, _) {
        final hub = BlockHub.instance;
        final iBlocked = hub.isBlockedDevice(device.id);
        // My own block wins over theirs (13.2).
        final blockedMe = !iBlocked && hub.hasBlockedMe(device.id);
        if ((iBlocked || blockedMe) && !_blockLogged) {
          _blockLogged = true;
          AppLogger.info('CHAT_BLOCKED_VIEW',
              detail: 'side=${iBlocked ? 'mine' : 'theirs'}');
        }
        final showChip = iBlocked && searchQuery.isEmpty;
        // Bundle 197a: drop picks that were deleted meanwhile.
        final ids = {for (final m in state.messages) m.id};
        // Bundle 199: the original of a quote (its small picture).
        final byId = {for (final m in state.messages) m.id: m};
        _selected.removeWhere((id) => !ids.contains(id));
        final selecting = _selected.isNotEmpty;
        final scaffold = Scaffold(
          appBar: selecting
              ? _selectBar(context, iBlocked || blockedMe)
              : AppBar(
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
                      if (iBlocked)
                        MutedAvatar(name: device.name, radius: 20)
                      else
                        PresenceAvatar(
                          avatar: AccountAvatar(name: device.name, radius: 20, peerId: device.id),
                          device: device,
                        ),
                      const SizedBox(width: LocalLinkSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              device.name.isEmpty ? 'LinkUp user' : device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16.5,
                                    letterSpacing: .1,
                                  ),
                            ),
                            if (iBlocked)
                              Row(
                                key: const ValueKey('chat_blocked_subtitle'),
                                children: [
                                  Icon(Icons.block,
                                      size: 12,
                                      color:
                                          Theme.of(context).colorScheme.error),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Blocked',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              )
                            else
                              // Bundle 201 (F, mock ST S1): icon + way words.
                              PresenceWayLine(
                                deviceId: device.id,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
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
                    // Bundle 196: no call icon when either side blocked.
                    if (widget.onStartCall != null && !iBlocked && !blockedMe)
                      IconButton(tooltip: 'Call', onPressed: _startCall, icon: const Icon(Icons.call_outlined)),
                    // Bundle 197a (mock 15A): tidy pop-up under the ⋮, an
                    // icon on every row, a divider above Clear chat.
                    PopupMenuButton<String>(
                      key: const ValueKey('chat_more_menu'),
                      tooltip: 'More options',
                      position: PopupMenuPosition.under,
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
                        PopupMenuItem(
                          value: 'info',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.info_outline),
                            title: Text('Conversation info'),
                          ),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'clear',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.clear_all_rounded),
                            title: Text('Clear chat'),
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'search') _startSearch();
                        if (value == 'info') _showConversationInfo();
                        if (value == 'clear') _clearChat();
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
                              // Bundle 199: two fingers = text size; the list
                              // stops scrolling while two fingers are down.
                              PinchTextZoom(
                                scrollController: _scrollController,
                                builder: (context, pinching) => ListView.builder(
                                controller: _scrollController,
                                // Bundle 147: keep ~1.5 screens of bubbles built above/below so
                                // photos/videos are ready before they scroll in.
                                // ignore: deprecated_member_use
                                cacheExtent: 1200,
                                physics: pinching
                                    ? const NeverScrollableScrollPhysics()
                                    : const AlwaysScrollableScrollPhysics(),
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.lg),
                                itemCount: visibleMessages.length + (showChip ? 1 : 0),
                                itemBuilder: (_, index) {
                                  if (index >= visibleMessages.length) {
                                    return _blockedChip(context, device);
                                  }
                                  final message = visibleMessages[index];
                                  final showDate = index == 0 || !_sameDay(visibleMessages[index - 1].createdAt, message.createdAt);
                                  // Bundle 132 (G): a transport section label
                                  // renders where the RECEIVE transport of
                                  // incoming history changes (walking back to
                                  // the previous labeled row). Untagged rows
                                  // and outgoing rows never open a section.
                                  final sectionLabel = _transportSectionLabelAt(visibleMessages, index, state.localDeviceId);
                                  final reply = message.replyTo;
                                  final picked = _selected.contains(message.id);
                                  final bubble = PeerOfflineBuilder(
                                    listenable: PresenceHub.instance,
                                    isOffline: () => !PresenceHub.instance.isReachable(device.id),
                                    enabled: message.senderId == state.localDeviceId &&
                                        _awaitingSend(message),
                                    builder: (offline) => MessageBubble(
                                      message: message,
                                      isMine: message.senderId == state.localDeviceId,
                                      files: widget.files,
                                      reactions: state.reactions[message.id] ?? const [],
                                      onLongPress: () => _onHold(message),
                                      onFailedTap: () => _showFailedActions(message.id),
                                      peerOffline: offline,
                                      highlighted: picked ||
                                          _heldId == message.id,
                                      flashed: _flashId == message.id,
                                      bubbleKey: _heldId == message.id ? _heldKey : null,
                                      onTap: selecting ? () => _toggleSelect(message) : null,
                                      quoteName: reply == null
                                          ? ''
                                          : (reply.from == state.localDeviceId
                                              ? 'You'
                                              : _peerName(device)),
                                      quoteIsYou: reply?.from == state.localDeviceId,
                                      quoteMissing: reply != null &&
                                          (MessageDeleteBook.instance.isDeleted(reply.id) ||
                                              !ids.contains(reply.id)),
                                      onQuoteTap: reply == null || selecting
                                          ? null
                                          : () => _jumpTo(reply.id, visibleMessages),
                                      senderName: _peerName(device),
                                      quoteThumb: reply == null
                                          ? null
                                          : QuoteThumb.forMessage(
                                              byId[reply.id]?.attachments ??
                                                  const <Attachment>[]),
                                      quoteLine: reply == null
                                          ? null
                                          : replyLineFor(reply,
                                              byId[reply.id]?.attachments),
                                    ),
                                  );
                                  // Bundle 199: slide right to reply (same
                                  // rule as Hold > Reply: not when blocked).
                                  final swipeable = SwipeToReply(
                                    enabled: !selecting &&
                                        _heldId == null &&
                                        !iBlocked &&
                                        !blockedMe,
                                    onReply: () =>
                                        _startReply(message, from: 'swipe'),
                                    child: bubble,
                                  );
                                  return Column(
                                    // Bundle 150: one row = one message, so a
                                    // row never inherits another message's
                                    // media state when new messages arrive.
                                    key: ValueKey<String>('msg:${message.id}'),
                                    children: [
                                      if (sectionLabel != null)
                                        _TransportDivider(label: sectionLabel),
                                      if (showDate) _DateDivider(date: message.createdAt),
                                      // Bundle 182: my unsent photo/video
                                      // follows the friend's live status
                                      // (Offline -> "Waiting").
                                      // Bundle 197a: Select mode = round
                                      // check on the left, tap the row.
                                      KeyedSubtree(
                                        key: _jumpId == message.id ? _jumpKey : null,
                                        child: selecting
                                            ? GestureDetector(
                                                behavior: HitTestBehavior.opaque,
                                                onTap: () => _toggleSelect(message),
                                                child: Row(
                                                  children: [
                                                    SelectCheck(selected: picked),
                                                    Expanded(child: bubble),
                                                  ],
                                                ),
                                              )
                                            : swipeable,
                                      ),
                                    ],
                                  );
                                },
                              )),
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
              // Bundle 196 (10.3 / 12.6): the message box is replaced on
              // both phones; the draft stays in the controllers.
              if (iBlocked)
                _blockedBar(context, device, mine: true)
              else if (blockedMe)
                _blockedBar(context, device, mine: false)
              else ...[
                if (_replyTo != null)
                  ReplyBar(
                    name: _nameOf(_replyTo!),
                    line: replyLineFor(
                        _replyRefFor(_replyTo!), _replyTo!.attachments),
                    isYou: _isMine(_replyTo!),
                    onClose: () => setState(() => _replyTo = null),
                    thumb: QuoteThumb.forMessage(_replyTo!.attachments),
                  ),
                PendingAttachmentStrip(
                  attachments: state.pendingAttachments,
                  onRemove: widget.controller.removePendingAttachment,
                  onAdd: state.isSending ? null : _pickFiles,
                ),
                ChatComposer(
                  controller: _textController,
                  isSending: state.isSending,
                  onPickAttachments: _pickFiles,
                  onSend: _send,
                  voice: _voice,
                  hasAttachments: state.pendingAttachments.isNotEmpty,
                  focusNode: _composerFocus,
                ),
              ],
            ],
          ),
        );
        // Bundle 197a: back leaves Select mode first; while a sheet is open
        // for a held message the chat dims except that bubble.
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
      },
    );
  }

  bool _sameDay(DateTime x, DateTime y) {
    // Bundle 174 (7): compare in the phone's own time.
    final a = x.toLocal();
    final b = y.toLocal();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

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
    final date = this.date.toLocal(); // Bundle 174 (7)
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
