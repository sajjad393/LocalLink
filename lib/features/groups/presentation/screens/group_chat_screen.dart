import 'dart:async';

import 'package:locallink/core/widgets/chat_search_bar.dart';
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
import 'package:locallink/features/groups/presentation/screens/group_info_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_info_sheets.dart';
import 'package:locallink/features/groups/presentation/group_people_hub.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/core/models/group_event.dart';
import 'package:locallink/features/groups/data/group_mute_book.dart';
import 'package:locallink/features/groups/presentation/widgets/group_sheets.dart';
import 'package:locallink/features/messaging/presentation/widgets/chat_composer.dart';
import 'package:locallink/features/messaging/presentation/widgets/pending_attachment_strip.dart';
import 'package:locallink/features/messaging/data/services/voice_note_service.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recorder_controller.dart';
import 'package:locallink/features/files/presentation/widgets/media_playback_coordinator.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_bubble.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/message_delete_book.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';
import 'package:locallink/features/messaging/presentation/screens/forward_screen.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';
import 'package:locallink/features/messaging/presentation/widgets/pinch_text_zoom.dart';
import 'package:locallink/features/messaging/presentation/widgets/quote_thumb.dart';
import 'package:locallink/features/messaging/presentation/widgets/swipe_to_reply.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/widgets/reaction_chips.dart';
import 'package:locallink/core/services/ui_sounds.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart'
    show GroupInviteState;
import 'package:locallink/features/groups/presentation/widgets/group_nearby_widgets.dart';
import 'package:locallink/features/groups/data/group_receipts.dart';
import 'package:locallink/features/groups/data/group_mention_book.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_info_sheet.dart';
import 'package:locallink/features/groups/presentation/widgets/group_mention_widgets.dart';
import 'package:locallink/features/groups/presentation/widgets/group_media_strip.dart';
import 'package:locallink/core/models/group_mentions.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';
import 'package:locallink/core/models/group_extras.dart';
import 'package:locallink/core/models/chat_preview.dart' show chatPreviewMediaWord;
import 'package:locallink/features/groups/data/group_extras_book.dart';
import 'package:locallink/features/groups/presentation/widgets/group_extras_widgets.dart';
import 'package:locallink/features/files/domain/file_size_rule.dart';
import 'package:locallink/features/files/presentation/widgets/file_too_big_dialog.dart';

class GroupChatScreen extends StatefulWidget {
  final LocalGroup group;
  final String localDeviceId;
  final GroupMessagingRepositoryContract messaging;
  final GroupRepositoryContract groups;
  final FileTransferRepositoryContract files;
  final LocalLinkNotificationService? notifications;
  final String? initialMessageId;
  final String? initialAttachmentId;

  /// Bundle G2: Group info › Search opens the chat with search on.
  final bool startSearch;

  /// Bundle 207 (L1): opened from the Chats search - jump to this message
  /// and flash it.
  final String? jumpToMessageId;

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
    this.startSearch = false,
    this.jumpToMessageId,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen>
    with WidgetsBindingObserver {
  late final GroupChatBloc _controller;
  late final FileTransferBloc _transferController;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  /// Bundle 199: the message box, so a reply can open the keyboard.
  final FocusNode _composerFocus = FocusNode();
  final _pending = <PickedFile>[];
  Map<String, String> _memberNames = const {};

  /// G1: "owner" / "admin" / "member" per device (name label in bubbles).
  Map<String, String> _memberRoles = const {};

  /// Bundle G2: the group as it is now (name, photo, settings, my state)
  /// and its members (who may send).
  late LocalGroup _group = widget.group;

  /// Bundle G3 (mock 6/7): people this phone is still adding Nearby.
  List<GroupInviteState> _invites = const [];
  List<GroupMember> _members = const [];
  StreamSubscription<String>? _groupChanges;

  GroupRules get _rules => GroupRules(_group, _members, widget.localDeviceId);

  /// Bundle G5: receipts per member (ticks + Message info) and typing.
  Map<String, Map<String, GroupReceipt>> _receipts = const {};
  StreamSubscription<String>? _receiptSub;
  StreamSubscription<String>? _typingSub;
  List<String> _typingIds = const [];
  late final GroupTypingSender _typingSender = GroupTypingSender(
      (on) => GroupReceiptHub.sendTyping?.call(widget.group.id, on));
  int _seenCount = -1;

  /// Bundle G5 (mock 16): "@" list - the word after "@" (null = no list)
  /// and the names picked from it (name -> device id).
  String? _mentionQuery;
  final Map<String, String> _mentionPicks = <String, String>{};

  /// G1 (mock 13): hold-to-record voice notes, same as the 1:1 chat.
  late final VoiceRecorderController _voice;
  final _voiceNotes = VoiceNoteService();

  /// G1 (mock 24): search inside the group.
  bool _searching = false;
  final _searchController = TextEditingController();
  int _matchAt = 0; // 0 = newest match

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
    _voice = VoiceRecorderController(
      backend: _voiceNotes,
      onSend: _sendVoiceNote,
      onError: _voiceError,
      haptic: (strong) => strong ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact(),
      onRecordStart: () => MediaPlaybackCoordinator.instance.claim(_voice, _voice.interrupt),
      // Something opened over the chat (a call screen...): pause.
      shouldPause: () => mounted && !(ModalRoute.of(context)?.isCurrent ?? true),
      tone: (t) => UiSounds.play(switch (t) {
        VoiceTone.start => UiSound.voiceStart,
        VoiceTone.send => UiSound.voiceSend,
        VoiceTone.cancel => UiSound.voiceCancel,
      }),
    );
    final draft = VoiceDraftStore.take(_draftKey);
    if (draft != null) _voice.restore(draft);
    WidgetsBinding.instance.addObserver(this);
    _searching = widget.startSearch;
    _groupChanges = GroupChangeHub.instance.changes.listen((id) {
      if (id == widget.group.id) unawaited(_reloadGroup(network: false));
    });
    unawaited(_load());
    unawaited(_reloadGroup(network: true));
    // Bundle G5: ticks follow receipts; "typing…" in the top bar.
    _receiptSub = GroupReceiptHub.changes?.call().listen((id) {
      if (id == widget.group.id) unawaited(_loadReceipts());
    });
    _typingSub = GroupReceiptHub.typingChanges?.call().listen((id) {
      if (id != widget.group.id || !mounted) return;
      setState(() => _typingIds = _typingNow());
    });
    _typingIds = _typingNow();
    _messageController.addListener(_onTextChanged);
    GroupMentionBook.instance.clear(widget.group.id);
    unawaited(_loadReceipts());
    // Bundle G5b: pin bar + poll counts follow the notes.
    GroupExtrasBook.instance.addListener(_onExtras);
    unawaited(GroupExtrasBook.instance
        .loadPin(widget.group.id)
        .then((_) => _onExtras()));
  }

  // ------------------------------------------- Bundle G5b pin + polls

  final Set<String> _pollsAsked = <String>{};
  Timer? _pinTimer;

  void _onExtras() {
    if (!mounted) return;
    setState(() {});
    // The bar goes away by itself when the pin ends.
    _pinTimer?.cancel();
    final pin = GroupExtrasBook.instance.activePin(widget.group.id);
    final end = pin == null ? null : DateTime.tryParse(pin.until);
    if (end != null) {
      final wait = end.difference(DateTime.now().toUtc());
      if (wait > Duration.zero && wait < const Duration(days: 1)) {
        _pinTimer = Timer(wait + const Duration(seconds: 1), _onExtras);
      }
    }
  }

  void _askPolls(List<GroupMessage> messages) {
    final ids = [
      for (final m in messages)
        if (GroupPoll.isPoll(m.body) && _pollsAsked.add(m.id)) m.id
    ];
    if (ids.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(GroupExtrasBook.instance.loadPolls(ids)));
  }

  /// "Ali: Office closed on Friday 🎉" for the pinned bar.
  String _pinLine(GroupMessage m) {
    var text = GroupMentions.plain(m.text).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty && m.attachments.isNotEmpty) {
      final a = m.attachments.first;
      text = chatPreviewMediaWord(a.contentType, isImage: a.isImage);
    }
    if (text.isEmpty) text = 'Message';
    return '${_nameFor(m.senderId)}: $text';
  }

  Widget? _pinnedBar(Map<String, GroupMessage> byId) {
    final pin = GroupExtrasBook.instance.activePin(widget.group.id);
    if (pin == null) return null;
    final m = byId[pin.messageId];
    if (m == null) return null;
    return GroupPinnedBar(
      line: _pinLine(m),
      left: GroupPinNote.leftLabel(
          DateTime.parse(pin.until), DateTime.now()),
      onTap: _selected.isNotEmpty ? null : () => _jumpTo(m.id),
    );
  }

  PinRow _pinRowFor(GroupMessage m) {
    if (!_rules.isAdmin || !_rules.active || _notSentYet(m)) {
      return PinRow.none;
    }
    final pin = GroupExtrasBook.instance.activePin(widget.group.id);
    return pin?.messageId == m.id ? PinRow.unpin : PinRow.pin;
  }

  Future<void> _pin(GroupMessage m) async {
    final length = await showPinLengthSheet(context);
    if (length == null || !mounted) return;
    final ok = await GroupExtrasHub.pin?.call(widget.group.id, m.id, length) ?? false;
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only admins can pin messages')));
    }
  }

  Future<void> _newPoll() async {
    if (!_rules.canSend) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_cantSendText)));
      return;
    }
    final poll = await Navigator.of(context).push<GroupPoll>(
        MaterialPageRoute(builder: (_) => const NewPollScreen()));
    if (poll == null || !mounted) return;
    try {
      // The poll comes back through the incoming stream (like a message).
      await GroupExtrasHub.sendPoll?.call(widget.group.id, poll);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  Widget? _pollContent(GroupMessage m) {
    final poll = m.poll;
    if (poll == null) return null;
    final tally = GroupExtrasBook.instance.tally(m.id, poll);
    return GroupPollView(
      key: ValueKey('poll_view_${m.id}'),
      poll: poll,
      tally: tally,
      self: widget.localDeviceId,
      nameOf: _pollName,
      onTapOption: _selected.isNotEmpty
          ? null
          : (i) {
              if (!_rules.canSend) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(_cantSendText)));
                return;
              }
              // Bundle 207 (K4): after 3 minutes the vote is final.
              final left = tally.changeLeft(widget.localDeviceId, DateTime.now());
              if (left != null && left <= Duration.zero) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Votes can't be changed after 3 minutes")));
                return;
              }
              unawaited(GroupExtrasHub.vote?.call(widget.group.id, m.id,
                  tally.tap(widget.localDeviceId, i)));
            },
      members: _members.length,
      onViewVotes: _selected.isNotEmpty
          ? null
          : () => showPollVotesSheet(context,
              poll: poll,
              tally: GroupExtrasBook.instance.tally(m.id, poll),
              members: _members.isEmpty ? tally.voters : _members.length,
              self: widget.localDeviceId,
              nameOf: _pollName,
              memberIds: _memberIdList()),
    );
  }

  String _pollName(String id) => id == widget.localDeviceId
      ? (_memberNames[id] ?? 'You')
      : (_memberNames[id] ?? 'Group member');

  // ------------------------------------------------- Bundle G5 receipts

  List<String> _typingNow() => (GroupReceiptHub.typing?.call(widget.group.id) ??
          const <String>[])
      .where((id) => id != widget.localDeviceId)
      .toList(growable: false);

  Future<void> _loadReceipts() async {
    final load = GroupReceiptHub.load;
    if (load == null) return;
    try {
      final rows = await load(widget.group.id);
      if (mounted) setState(() => _receipts = rows);
    } catch (_) {}
  }

  /// The chat is on screen: messages from others are read now.
  void _markRead() {
    final mark = GroupReceiptHub.markRead;
    if (mark == null) return;
    GroupMentionBook.instance.clear(widget.group.id);
    unawaited(mark(widget.group.id).catchError((Object _) {}));
  }

  /// Bundle 207 (K6): every member id (Votes sheet "Not voted yet").
  List<String> _memberIdList() => [for (final m in _members) m.deviceId];

  /// Other members now (id -> name), for ticks and Message info.
  Map<String, String> get _otherMembers => {
        for (final m in _members)
          if (m.deviceId != widget.localDeviceId)
            m.deviceId: _memberNames[m.deviceId] ?? 'Group member',
      };

  GroupTick? _tickFor(GroupMessage m) {
    if (!_controller.isMine(m) || _members.isEmpty) return null;
    return groupTickFor(
      sent: !_notSentYet(m),
      others: _otherMembers.keys.toSet(),
      receipts: _receipts[m.id],
      readsOn: ReadReceiptsSetting.instance.on,
    );
  }

  void _onTextChanged() {
    final value = _messageController.value;
    final text = value.text;
    // "I am typing" (server road; at most one per 3 s).
    if (_rules.canSend) _typingSender.changed(text);
    final cursor = value.selection.isValid ? value.selection.baseOffset : text.length;
    final q = GroupMentions.queryAt(text, cursor);
    if (q != _mentionQuery && mounted) setState(() => _mentionQuery = q);
  }

  bool get _iAmAdmin {
    final role = _memberRoles[widget.localDeviceId] ?? '';
    return role == 'owner' || role == 'admin';
  }

  List<GroupMentionChoice> _mentionChoices() {
    final q = (_mentionQuery ?? '').toLowerCase();
    final out = <GroupMentionChoice>[];
    for (final m in _members) {
      if (m.deviceId == widget.localDeviceId) continue;
      final name = _memberNames[m.deviceId] ?? 'Group member';
      if (q.isNotEmpty && !name.toLowerCase().contains(q)) continue;
      out.add(GroupMentionChoice(
          id: m.deviceId,
          name: name,
          sub: switch (m.role) {
            'owner' => 'Owner',
            'admin' => 'Admin',
            _ => 'Member',
          }));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (out.length > 6) out.removeRange(6, out.length);
    // @all: admins only (mock 16).
    if (_iAmAdmin && 'all'.startsWith(q)) {
      out.add(const GroupMentionChoice(
          id: GroupMentions.allId,
          name: 'all',
          sub: 'Admins only: notify everyone',
          everyone: true));
    }
    return out;
  }

  void _pickMention(GroupMentionChoice c) {
    final value = _messageController.value;
    final cursor = value.selection.isValid ? value.selection.baseOffset : value.text.length;
    final (text, at) = GroupMentions.insert(value.text, cursor, c.name);
    _mentionPicks[c.name] = c.id;
    _messageController.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: at));
    setState(() => _mentionQuery = null);
  }

  /// Bundle G2: name, photo, settings, members and my state again.
  Future<void> _reloadGroup({required bool network}) async {
    try {
      final g = network
          ? await widget.groups.refreshGroup(widget.group.id)
          : await widget.groups.localGroup(widget.group.id);
      if (g != null && mounted) setState(() => _group = g);
    } catch (_) {}
    if (!network) await _loadMemberNames();
    await _loadInvites();
  }

  /// Bundle G3: the "Adding…" banner rows (mock 6/7).
  Future<void> _loadInvites() async {
    final load = GroupNearbyHub.loadInvites;
    if (load == null || !_group.worksNearby) return;
    try {
      final rows = await load(widget.group.id);
      if (mounted) setState(() => _invites = rows);
    } catch (_) {}
  }

  bool get _adding =>
      _group.isActive && _invites.any((i) => i.state != 'added');

  Future<void> _openAdding() async {
    final retry = GroupNearbyHub.retry;
    await showAddingPeopleSheet(
      context,
      invites: _invites,
      myName: _memberNames[widget.localDeviceId] ?? 'Your friend',
      onRetry: retry == null
          ? null
          : (id) async {
              await retry(widget.group.id, id);
              await _loadInvites();
            },
    );
  }

  String get _draftKey => 'group:${widget.group.id}';

  /// G1: one voice note is ready (one file) - sent like a photo.
  Future<void> _sendVoiceNote(PickedFile file) async {
    final replyTo = _replyTo;
    if (replyTo != null) setState(() => _replyTo = null);
    try {
      await _controller.send('',
          attachments: [file],
          reply: replyTo == null ? null : _replyRefFor(replyTo));
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: LocalLinkMotion.quick, curve: Curves.easeOut);
      }
    } catch (error) {
      if (mounted) showErrorToast(context, error: error);
    }
  }

  void _voiceError(Object error) {
    if (!mounted) return;
    // No microphone permission: Android asks by itself, no extra message.
    if (error is PlatformException && error.code == 'PERMISSION') return;
    showErrorToast(context, error: error);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Home key / screen off while recording = pause, keep it.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _voice.interrupt();
      _typingSender.stop();
    }
    // Bundle G5: back on the chat = read.
    if (state == AppLifecycleState.resumed) _markRead();
  }

  Future<void> _load() async {
    await Future.wait([
      _controller.load(),
      _loadMemberNames(),
    ]);
    if (!mounted) return;
    await widget.notifications?.markGroupConversationRead(widget.group.id);
    if (!mounted) return;
    _markRead();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (widget.initialMessageId == null) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
      final jump = widget.jumpToMessageId;
      if (jump != null && mounted) _jumpTo(jump);
    });
  }

  Future<void> _loadMemberNames() async {
    try {
      final members = await widget.groups.listMembers(widget.group.id);
      if (mounted) _members = members;
      final map = <String, String>{};
      final roles = <String, String>{};
      for (final member in members) {
        final label = member.name.trim().isEmpty ? 'Group member' : member.name.trim();
        map[member.deviceId] = label;
        roles[member.deviceId] = member.role;
      }
      if (mounted) {
        setState(() {
          _memberNames = map;
          _memberRoles = roles;
        });
      }
    } catch (_) {
      // The chat remains usable even when member metadata is temporarily unavailable.
    }
  }

  Future<void> _pickFiles() async {
    try {
      final all = await _transferController.pickFiles(allowMultiple: true);
      if (!mounted || all.isEmpty) return;
      // Bundle 203 (5): files over 50 MB are dropped with a pop-up.
      final split = FileSizeRule.split(all);
      final files = split.keep;
      if (files.isNotEmpty) setState(() => _pending.addAll(files));
      if (split.dropped.isNotEmpty) {
        await showFileTooBigDialog(context, [
          for (final f in split.dropped)
            TooBigFile(f.name, f.size, isVideo: f.contentType.startsWith('video/')),
        ]);
      }
    } catch (error) {
      if (mounted) showErrorToast(context, error: error);
    }
  }

  Future<void> _send() async {
    // Bundle G5: picked "@Name" words become mentions.
    final body = GroupMentions.encode(
        _messageController.text.trim(), Map.of(_mentionPicks));
    if ((body.isEmpty && _pending.isEmpty) || _controller.isSending) return;
    _mentionPicks.clear();
    _typingSender.stop();
    final files = List<PickedFile>.from(_pending);
    _messageController.clear();
    setState(() => _pending.clear());
    final replyTo = _replyTo;
    if (replyTo != null) setState(() => _replyTo = null);
    UiSounds.play(UiSound.messageSent); // Bundle 198: soft "tick"
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

  /// Bundle 199: start a reply (swipe / Hold > Reply / Select > Reply):
  /// the reply bar opens and the keyboard opens (WhatsApp).
  void _startReply(GroupMessage m, {required String from}) {
    if (!mounted) return;
    setState(() {
      _replyTo = m;
      _selected.clear();
    });
    AppLogger.info('REPLY_START',
        detail: 'from=$from kind=${replyKindFor(m.attachments)} group=y');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _composerFocus.canRequestFocus) {
        _composerFocus.requestFocus();
      }
    });
  }

  static ReplyRef _replyRefFor(GroupMessage m) => ReplyRef(
        id: m.id,
        from: m.senderId,
        snip: cutSnippet(GroupMentions.plain(m.text)),
        kind: replyKindFor(m.attachments),
      );

  bool _notSentYet(GroupMessage m) => _controller.isMine(m) && m.notSentYet; // Bundle G3

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
      final isPoll = GroupPoll.isPoll(message.body);
      final result = await showMessageActionsSheet(
        context,
        mine: _controller.isMine(message),
        hasText: !isPoll && message.text.trim().isNotEmpty,
        canForward: !isPoll &&
            !_notSentYet(message) &&
            !MediaMessageActions.hasRemoved(message.attachments),
        pinRow: _pinRowFor(message),
        canSave: MediaMessageActions.savable(message.attachments,
                mine: _controller.isMine(message))
            .isNotEmpty,
        barrierColor: Colors.transparent,
      );
      if (!mounted || result == null) return;
      // Bundle G2: nothing can be sent when I can't post in this group.
      if ((result.action == MessageAction.react ||
              result.action == MessageAction.reply) &&
          !_rules.canSend) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_cantSendText)));
        return;
      }
      switch (result.action) {
        case MessageAction.react:
          await _controller.react(message.id, result.emoji ?? '');
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
                  mine: _controller.isMine(message)));
        case MessageAction.info:
          await _showInfo(message);
        case MessageAction.select:
          setState(() => _selected.add(message.id));
        case MessageAction.delete:
          await _delete([message]);
        // Bundle G5b (mock P1-P4).
        case MessageAction.pin:
          await _pin(message);
        case MessageAction.unpin:
          await GroupExtrasHub.unpin?.call(widget.group.id);
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
        ? GroupMentions.plain(withText.first.text)
        : withText
            .map((m) =>
                '[${_clock(m.createdTime)}] ${_nameFor(m.senderId)}: ${GroupMentions.plain(m.text)}')
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
        ForwardItem(text: GroupMentions.plain(m.text), attachments: m.attachments),
    ]);
    if (!mounted) return;
    setState(_selected.clear);
    if (single == null) return;
    if (single.isGroup && single.id == widget.group.id) return;
    final route = ForwardHub.instance?.routeFor?.call(single);
    if (route != null) unawaited(Navigator.pushReplacement(context, route));
  }

  Widget _miniBubble(GroupMessage m, {GroupTick? tick}) {
    final colors = Theme.of(context).colorScheme;
    final mine = _controller.isMine(m);
    final label = m.text.trim().isNotEmpty
        ? GroupMentions.plain(m.text)
        : replyKindLabel(replyKindFor(m.attachments));
    final fg = colors.onSurface;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 5),
      decoration: BoxDecoration(
        color: mine ? colors.surfaceContainer : colors.surfaceContainerHighest,
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_clock(m.createdTime),
                  style: TextStyle(fontSize: 11, color: fg.withValues(alpha: .7))),
              if (tick != null) ...[
                const SizedBox(width: 3),
                Icon(
                    tick == GroupTick.sent || tick == GroupTick.pending
                        ? Icons.check_rounded
                        : Icons.done_all_rounded,
                    key: const ValueKey('ginfo_mini_tick'),
                    size: 14,
                    color: tick == GroupTick.read
                        ? colors.primary
                        : colors.onSurfaceVariant),
              ],
            ],
          ),
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

  /// Bundle G5 (mock 19 / 20): who got / read my message.
  Future<void> _showInfo(GroupMessage m) async {
    final refresh = GroupReceiptHub.refresh;
    if (refresh != null && !_notSentYet(m)) {
      try {
        await refresh(widget.group.id).timeout(const Duration(seconds: 2));
      } catch (_) {}
      await _loadReceipts();
    }
    if (!mounted) return;
    final readsOn = ReadReceiptsSetting.instance.on;
    await showGroupMessageInfoSheet(
      context,
      preview: _miniBubble(m, tick: _tickFor(m)),
      info: GroupMessageInfo.build(
          others: _otherMembers, receipts: _receipts[m.id], readsOn: readsOn),
      notSentYet: _notSentYet(m),
      barrierColor: _heldId != null ? Colors.transparent : null,
    );
  }

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
    // Bundle 199: blue border for 2 s (was a grey ring for 1.4 s).
    _flashTimer = Timer(FlashRing.hold, () {
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
            onPressed: () => _startReply(one, from: 'select'),
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

  /// G1 (mock 13): "Admin" / "Owner" next to the name.
  String _roleLabel(String deviceId) => switch (_memberRoles[deviceId]) {
        'owner' => 'Owner',
        'admin' => 'Admin',
        _ => '',
      };

  /// G1 (mock 13): "You, Ali, Sara, Bilal" under the group name.
  String get _membersLine {
    final others = <String>[
      for (final e in _memberNames.entries)
        if (e.key != widget.localDeviceId) e.value,
    ];
    if (_memberNames.isEmpty) return '';
    return ['You', ...others].join(', ');
  }

  /// Bundle G2: Group info (mock 27/28).
  Future<void> _openInfo() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInfoScreen(
            group: _group,
            localDeviceId: widget.localDeviceId,
            groups: widget.groups),
      ),
    );
    if (!mounted) return;
    if (result == 'deleted') {
      Navigator.pop(context);
      return;
    }
    if (result == 'search') {
      setState(() {
        _searching = true;
        _matchAt = 0;
        _searchController.clear();
      });
    }
    unawaited(_reloadGroup(network: false));
  }

  String get _cantSendText => _group.isActive
      ? 'Only admins can send messages.'
      : "You're no longer a participant in this group.";

  /// Mock 31 from the ⋮ menu.
  Future<void> _exitGroup() async {
    final rules = _rules;
    final next = rules.isOwner ? rules.nextOwner : null;
    var me = 'You';
    for (final m in _members) {
      if (m.deviceId == widget.localDeviceId && m.name.trim().isNotEmpty) {
        me = m.name.trim();
      }
    }
    final ok = await showExitGroupSheet(
      context,
      groupName: _group.name,
      me: me,
      owner: rules.isOwner,
      nextOwner: next == null ? '' : (_memberNames[next.deviceId] ?? ''),
      nextIsAdmin: next?.role == 'admin',
    );
    if (!ok || !mounted) return;
    try {
      await widget.groups.leave(_group.id);
    } catch (error) {
      if (mounted) showErrorToast(context, error: error);
    }
    await _reloadGroup(network: false);
  }

  /// Mock 25: "Delete group" (after exit / removal).
  Future<void> _deleteGroup() async {
    final ok = await showDeleteGroupSheet(context, groupName: _group.name);
    if (!ok || !mounted) return;
    try {
      await widget.groups.deleteLocal(_group.id);
    } catch (error) {
      if (mounted) showErrorToast(context, error: error);
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  /// Mock 25 / 26: the grey panel instead of the message box.
  Widget _endedBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = _group.isActive;
    return Container(
      key: const ValueKey('group_ended_bar'),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, 18 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(
            top: BorderSide(color: colors.outlineVariant.withValues(alpha: .6))),
      ),
      child: active
          ? Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Only '),
                TextSpan(
                    text: 'admins',
                    style: TextStyle(
                        color: colors.primary, fontWeight: FontWeight.w600)),
                const TextSpan(text: ' can send messages.'),
              ]),
              key: const ValueKey('group_admins_only'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: colors.onSurfaceVariant),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("You're no longer a participant in this group.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13.5, color: colors.onSurfaceVariant)),
                const SizedBox(height: 4),
                TextButton(
                  key: const ValueKey('group_delete_button'),
                  onPressed: _deleteGroup,
                  child: const Text('Delete group',
                      style:
                          TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
    );
  }

  /// Bundle G2: a system line ("Ali added Sara") as a grey chip.
  Widget _systemLines(GroupMessage message, GroupEvent event) {
    final colors = Theme.of(context).colorScheme;
    final lines = event.lines(widget.localDeviceId,
        nameOf: (id) => _memberNames[id]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Center(
                child: Container(
                  key: ValueKey('group_system_line_${message.id}'),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * .88),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(line,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: colors.onSurfaceVariant)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _clearChat() async {
    final ok =
        await showClearChatSheet(context, name: widget.group.name, group: true);
    if (!ok || !mounted) return;
    await _controller.clearChat();
  }

  /// G1 (mock 34).
  Future<void> _muteFlow() async {
    final choice = await showGroupMuteSheet(context);
    if (choice == null) return;
    await GroupMuteBook.instance.mute(widget.group.id, choice.length);
  }

  /// G1 (mock 14): ⋮ menu, text rows like the mock.
  Widget _moreMenu() {
    final muted = GroupMuteBook.instance.isMuted(widget.group.id);
    return PopupMenuButton<String>(
      key: const ValueKey('group_more_menu'),
      tooltip: 'More options',
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'info', child: Text('Group info')),
        const PopupMenuItem(value: 'search', child: Text('Search')),
        // Bundle G5 (mock 14).
        const PopupMenuItem(value: 'media', child: Text('Media, links and docs')),
        // Bundle G5b (mock Q1).
        if (_rules.canSend)
          const PopupMenuItem(value: 'poll', child: Text('New poll')),
        PopupMenuItem(
            value: muted ? 'unmute' : 'mute',
            child: Text(muted ? 'Unmute notifications' : 'Mute notifications')),
        const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
        if (_group.isActive)
          const PopupMenuItem(
              value: 'exit',
              child: Text('Exit group',
                  style: TextStyle(color: Color(0xFFB3261E))))
        else
          const PopupMenuItem(
              value: 'delete',
              child: Text('Delete group',
                  style: TextStyle(color: Color(0xFFB3261E)))),
      ],
      onSelected: (value) {
        switch (value) {
          case 'info':
            _openInfo();
          case 'search':
            setState(() {
              _searching = true;
              _matchAt = 0;
              _searchController.clear();
            });
          case 'media':
            unawaited(openGroupMedia(context,
                groupId: widget.group.id, name: _group.name));
          case 'poll':
            unawaited(_newPoll());
          case 'mute':
            unawaited(_muteFlow());
          case 'unmute':
            unawaited(GroupMuteBook.instance.unmute(widget.group.id));
          case 'clear':
            unawaited(_clearChat());
          case 'exit':
            unawaited(_exitGroup());
          case 'delete':
            unawaited(_deleteGroup());
        }
      },
    );
  }

  // ---- G1 (mock 24): search ------------------------------------------

  String get _query => _searching ? _searchController.text.trim() : '';

  /// Matching message ids, newest first.
  List<String> _matches(List<GroupMessage> messages) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final m in messages.reversed)
        if (!GroupEvent.isEvent(m.body) &&
                GroupMentions.plain(m.text).toLowerCase().contains(q) ||
            m.attachments.any((a) => a.originalName.toLowerCase().contains(q)))
          m.id,
    ];
  }

  void _closeSearch() => setState(() {
        _searching = false;
        _searchController.clear();
        _matchAt = 0;
      });

  void _goMatch(List<String> matches, int at) {
    if (matches.isEmpty) return;
    final next = at.clamp(0, matches.length - 1);
    setState(() => _matchAt = next);
    _jumpTo(matches[next]);
  }

  /// Bundle 207 (L2): the shared search bar (1:1 uses the same).
  PreferredSizeWidget _searchBar(BuildContext context, List<String> matches) =>
      ChatSearchBar(
        controller: _searchController,
        count: matches.length,
        at: _matchAt,
        onClose: _closeSearch,
        onChanged: (_) => setState(() => _matchAt = 0),
        onGo: (i) => _goMatch(_matches(_controller.messages), i),
      );

  // ---- G1 (mock 21): who reacted --------------------------------------

  /// Bundle 207: tap an emoji chip: add mine (+1), tap my own again to
  /// remove it, or change mine to this one.
  Future<void> _tapReaction(GroupMessage message, String emoji) async {
    final kind = reactionTapKind(
        _controller.state.reactions[message.id] ?? const [],
        widget.localDeviceId,
        emoji);
    if (kind != ReactionTapKind.remove && !_rules.canSend) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_cantSendText)));
      return;
    }
    AppLogger.info('REACTION_TAP', detail: '${kind.name} chat=group');
    if (kind == ReactionTapKind.remove) {
      await _controller.removeReaction(message.id);
    } else {
      await _controller.react(message.id, emoji);
    }
  }

  void _showReactions(GroupMessage message) {
    final list = _controller.state.reactions[message.id] ?? const [];
    if (list.isEmpty) return;
    unawaited(showGroupReactionsSheet(
      context,
      reactions: list,
      localDeviceId: widget.localDeviceId,
      nameOf: _nameFor,
      onRemoveMine: () => _controller.removeReaction(message.id),
    ));
  }

  String _senderName(GroupMessage message) {
    if (_controller.isMine(message)) return 'You';
    return _memberNames[message.senderId] ?? 'Group member';
  }

  @override
  void dispose() {
    widget.notifications?.setActiveGroupConversation(null);
    _groupChanges?.cancel();
    _receiptSub?.cancel();
    _typingSub?.cancel();
    _typingSender.stop();
    _typingSender.dispose();
    _messageController.removeListener(_onTextChanged);
    _flashTimer?.cancel();
    _pinTimer?.cancel();
    GroupExtrasBook.instance.removeListener(_onExtras);
    WidgetsBinding.instance.removeObserver(this);
    MediaPlaybackCoordinator.instance.release(_voice);
    // Leaving the group keeps a paused voice note as a draft.
    final voice = _voice;
    final key = _draftKey;
    unawaited(voice.suspend().then((draft) {
      if (draft != null) VoiceDraftStore.put(key, draft);
      voice.dispose();
    }));
    _controller.close();
    _transferController.close();
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<GroupChatBloc, GroupChatState>(
      bloc: _controller,
      builder: (context, state) {
        // Bundle 197a: drop picks that were deleted meanwhile.
        final ids = {for (final m in state.messages) m.id};
        // Bundle 199: the original of a quote (its small picture).
        final byId = {for (final m in state.messages) m.id: m};
        _selected.removeWhere((id) => !ids.contains(id));
        final selecting = _selected.isNotEmpty;
        // G1 (mock 24): search matches, newest first.
        final matches = _matches(state.messages);
        _askPolls(state.messages); // Bundle G5b
        final pinBar = _searching ? null : _pinnedBar(byId);
        // Bundle G5: new messages while the chat is open are read.
        if (!state.isLoading && state.messages.length != _seenCount) {
          final first = _seenCount < 0;
          _seenCount = state.messages.length;
          if (!first) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _markRead();
            });
          }
        }
        final scaffold = Scaffold(
        appBar: selecting
            ? _selectBar(context)
            : _searching
                ? _searchBar(context, matches)
                : AppBar(
          titleSpacing: 0,
          title: GestureDetector(
            key: const ValueKey('group_title'),
            behavior: HitTestBehavior.opaque,
            onTap: _openInfo,
            child: Row(
              children: [
                GroupAvatar(
                    radius: 20,
                    groupId: _group.id,
                    photoVersion: _group.photoVersion),
                const SizedBox(width: LocalLinkSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListenableBuilder(
                        listenable: GroupMuteBook.instance,
                        builder: (context, _) => Row(
                          children: [
                            Flexible(
                              child: Text(_group.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16.5,
                                          letterSpacing: .1)),
                            ),
                            if (GroupMuteBook.instance.isMuted(widget.group.id)) ...[
                              const SizedBox(width: 5),
                              Icon(Icons.notifications_off_outlined,
                                  key: const ValueKey('group_bar_muted'),
                                  size: 15,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ],
                          ],
                        ),
                      ),
                      // Bundle G5 (mock 15): "Sara is typing…" in blue.
                      if (_typingIds.isNotEmpty)
                        Text(
                            groupTypingText([
                              for (final id in _typingIds)
                                _memberNames[id] ?? 'Someone'
                            ]),
                            key: const ValueKey('group_bar_typing'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w500))
                      else if (_membersLine.isNotEmpty)
                        Text(_membersLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ListenableBuilder(
              listenable: GroupMuteBook.instance,
              builder: (context, _) => _moreMenu(),
            ),
          ],
        ),
        body: Column(
          children: [
            if (state.error != null)
              LocalLinkInlineError(message: friendlyErrorMessage(state.error), onRetry: _controller.load),
            // Bundle G3 (mock 6): "Adding Ali, Sara…".
            if (_adding)
              GroupAddingBanner(invites: _invites, onTap: _openAdding),
            // Bundle G5b (mock P3).
            if (pinBar != null) pinBar,
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
                      // Bundle 199: two fingers = text size.
                      : PinchTextZoom(
                          scrollController: _scrollController,
                          builder: (context, pinching) => ListView.builder(
                          controller: _scrollController,
                          physics: pinching
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          // Bundle 147: keep ~1.5 screens of bubbles built above/below so
                          // photos/videos are ready before they scroll in.
                          // ignore: deprecated_member_use
                          cacheExtent: 1200,
                          padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.md, LocalLinkSpacing.lg),
                          itemCount: state.messages.length +
                              (_typingIds.isEmpty ? 0 : 1),
                          itemBuilder: (_, index) {
                            // Bundle G5 (mock 15): the newest typer's dots.
                            if (index >= state.messages.length) {
                              final who = _typingIds.last;
                              return GroupTypingBubble(
                                  key: const ValueKey('group_typing_bubble'),
                                  name: _memberNames[who] ?? 'Someone',
                                  deviceId: who);
                            }
                            final message = state.messages[index];
                            final parsed = DateTime.tryParse(message.createdAt)?.toLocal();
                            final previous = index == 0 ? null : DateTime.tryParse(state.messages[index - 1].createdAt)?.toLocal();
                            final showDate = parsed != null && (previous == null || previous.day != parsed.day || previous.month != parsed.month || previous.year != parsed.year);
                            // G1 (mock 13): photo + name on the first bubble of a run.
                            final firstOfRun = showDate ||
                                index == 0 ||
                                state.messages[index - 1].senderId != message.senderId ||
                                GroupEvent.isEvent(state.messages[index - 1].body);
                            // Bundle G2: system line.
                            final event = GroupEvent.parse(message.body);
                            return Column(
                              // Bundle 150: stable row per message.
                              key: ValueKey<String>('gmsg:${message.id}'),
                              children: [
                                if (showDate) MessengerDateDivider(date: parsed),
                                if (event != null)
                                  _systemLines(message, event)
                                else
                                KeyedSubtree(
                                  key: _jumpId == message.id ? _jumpKey : null,
                                  child: _groupRow(message, state, ids, selecting, byId,
                                      firstOfRun: firstOfRun),
                                ),
                                // Bundle G3 (mock 6): sealed note after
                                // "created group" of a group with a card.
                                if (event != null &&
                                    event.kind == 'create' &&
                                    _group.worksNearby)
                                  const GroupSealedChip(),
                              ],
                            );
                          },
                        )),
            ),
            if (_replyTo != null)
              ReplyBar(
                name: _nameFor(_replyTo!.senderId),
                line: replyLineFor(_replyRefFor(_replyTo!), _replyTo!.attachments),
                isYou: _controller.isMine(_replyTo!),
                onClose: () => setState(() => _replyTo = null),
                thumb: QuoteThumb.forMessage(_replyTo!.attachments),
              ),
            // G1 (mock 13): the same message box as the 1:1 chat
            // (+, Message, hold the mic for a voice note).
            PendingAttachmentStrip(
              attachments: _pending,
              onRemove: (index) => setState(() => _pending.removeAt(index)),
              // Bundle 202: "+" adds more (same as the message box +).
              onAdd: state.isSending || !_rules.canSend ? null : _pickFiles,
            ),
            // Bundle G5 (mock 16): the "@" list over the message box.
            if (_rules.canSend && _mentionQuery != null)
              Builder(builder: (context) {
                final choices = _mentionChoices();
                if (choices.isEmpty) return const SizedBox.shrink();
                return GroupMentionList(choices: choices, onPick: _pickMention);
              }),
            // Bundle G2 (mock 25 / 26): no message box when I can't post.
            if (_rules.canSend)
            ChatComposer(
              controller: _messageController,
              isSending: state.isSending,
              onPickAttachments: _pickFiles,
              onSend: _send,
              voice: _voice,
              hasAttachments: _pending.isNotEmpty,
              focusNode: _composerFocus,
            )
            else
              _endedBar(context),
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
      bool selecting, Map<String, GroupMessage> byId,
      {bool firstOfRun = true}) {
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
        firstOfRun: firstOfRun,
        role: _roleLabel(message.senderId),
        highlight: _query,
        // Bundle 207: tap = add / remove mine; hold = who reacted.
        onReactionsTap: selecting ? null : () => _showReactions(message),
        myId: widget.localDeviceId,
        onReactionTap:
            selecting ? null : (emoji) => _tapReaction(message, emoji),
        tick: _tickFor(message),
        content: _pollContent(message), // Bundle G5b
        highlighted: picked || _heldId == message.id,
        flashed: _flashId == message.id,
        bubbleKey: _heldId == message.id ? _heldKey : null,
        quoteName: reply == null ? '' : _nameFor(reply.from),
        quoteIsYou: reply?.from == widget.localDeviceId,
        quoteMissing: reply != null &&
            (MessageDeleteBook.instance.isDeleted(reply.id) ||
                !ids.contains(reply.id)),
        onQuoteTap:
            reply == null || selecting ? null : () => _jumpTo(reply.id),
        quoteThumb: reply == null
            ? null
            : QuoteThumb.forMessage(
                byId[reply.id]?.attachments ?? const <Attachment>[]),
        quoteLine: reply == null
            ? null
            : replyLineFor(reply, byId[reply.id]?.attachments),
      ),
    );
    // Bundle 199: slide right to reply.
    if (!selecting) {
      return SwipeToReply(
        enabled: _heldId == null && _rules.canSend,
        onReply: () => _startReply(message, from: 'swipe'),
        child: bubble,
      );
    }
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
