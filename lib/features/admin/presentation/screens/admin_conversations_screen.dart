import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/data/actions/admin_action_book.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_request_sheet.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 221 (mock A-1): the Owner's chat list. Online it is the server's
/// list (who / how many / when, no text); offline the chats this phone
/// knows. "Get chat" makes a Get chat request; a row with an answer opens
/// the viewer (half answers too).
///
/// Bundle 307 (TODO_307 B2-B7, B10): bold iOS-style cards. Requests tab =
/// "Live" carousel (one Uber-like card per running request) + "In
/// progress" cards + a grouped "Finished" list; Chats tab = search,
/// "Ready to read" tiles and "All chats". No path words on this screen.
class AdminConversationsScreen extends StatefulWidget {
  const AdminConversationsScreen({super.key, this.viewMode, this.requests});

  final AppViewModeCubit? viewMode;
  final ChatRequests221? requests;

  /// A2: how often the server pill re-checks the link.
  static const Duration pillEvery = Duration(seconds: 10);

  /// B4: carousel auto-advance, and the pause after a touch.
  static const Duration advanceEvery = Duration(seconds: 5);
  static const Duration pauseAfterTouch = Duration(seconds: 10);

  @override
  State<AdminConversationsScreen> createState() => _AdminConversationsScreenState();
}

class _AdminConversationsScreenState extends State<AdminConversationsScreen> {
  int _tab = 0; // 0 chats, 1 requests
  List<Map<String, dynamic>> _chats = const [];
  List<ChatRequestRow221> _rows = const [];
  bool _loading = true;
  String _error = '';
  String _query = '';
  StreamSubscription<AppViewModeState>? _viewSub;
  Timer? _pill;

  // B4 carousel.
  int _live = 0;
  int _swipeDir = 1;
  Timer? _advance;
  int _pauseTicks = 0; // ticks left to skip after a touch (10 s / 5 s)
  String _focusId = '';
  String _dropId = '';
  final GlobalKey _progressHead = GlobalKey();

  ChatRequests221? get _svc => widget.requests ?? ChatRequests221.instance;
  bool _srvOnline = false;
  bool get _online => _srvOnline && (widget.viewMode?.state.serverConnected ?? true);

  @override
  void initState() {
    super.initState();
    AdminActionBook.instance.addListener(_reload);
    ChatAnswerCarrier.progress.addListener(_reload);
    _viewSub = widget.viewMode?.stream.listen((_) => _reload());
    // A2: the pill flips within 10 s when the server drops or comes back.
    _pill = Timer.periodic(AdminConversationsScreen.pillEvery, (_) => unawaited(_checkPill()));
    unawaited(_load());
  }

  @override
  void dispose() {
    AdminActionBook.instance.removeListener(_reload);
    ChatAnswerCarrier.progress.removeListener(_reload);
    unawaited(_viewSub?.cancel());
    _pill?.cancel();
    _advance?.cancel();
    super.dispose();
  }

  void _reload() => unawaited(_load());

  Future<void> _checkPill() async {
    final s = _svc;
    if (s == null) return;
    try {
      final online = await s.online();
      if (mounted && online != _srvOnline) setState(() => _srvOnline = online);
    } catch (_) {}
  }

  Future<void> _load() async {
    final s = _svc;
    if (s == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final online = await s.online();
      final chats = await s.conversations();
      final rows = await s.requests();
      if (!mounted) return;
      setState(() {
        _srvOnline = online;
        _chats = chats;
        _rows = rows;
        _loading = false;
        _error = '';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_chats.isEmpty && _rows.isEmpty) _error = '$error'.replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  /// The newest get_chat request of a chat row (to show its status).
  ChatRequestRow221? _requestOf(Map<String, dynamic> chat) {
    final pick = chatPickOfRow(chat);
    if (pick == null) return null;
    for (final r in _rows) {
      if (r.action != 'get_chat' || r.cancelled) continue;
      final p = ChatPick221.fromRef(r.chat);
      if (p == null || p.kind != pick.kind) continue;
      if (pick.isGroup ? p.groupId == pick.groupId : {p.userA, p.userB}.containsAll([pick.userA, pick.userB])) {
        return r;
      }
    }
    return null;
  }

  Future<void> _ask([ChatPick221? pick]) async {
    final s = _svc;
    if (s == null) return;
    final before = {for (final r in _rows) r.id};
    final sent = await showChatRequestSheet(context, service: s, preset: pick, online: _online);
    if (sent == true && mounted) {
      adminSnack216(context, _online ? L.t.requestSentByTheServer : L.t.requestSentToNearbyPhones);
      setState(() => _tab = 1);
      await _load();
      // B8 / E: the new live card drops in at the front of the carousel.
      if (!mounted) return;
      final fresh = [for (final r in _rows) if (!before.contains(r.id) && r.action == 'get_chat') r];
      if (fresh.isNotEmpty) setState(() => _focusId = fresh.first.id);
    }
  }

  Future<void> _open(ChatRequestRow221 r) async {
    final s = _svc;
    if (s == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AdminTheme216Scope(child: AdminChatViewerScreen(service: s, request: r))));
    unawaited(_load());
  }

  Future<void> _cancel(ChatRequestRow221 r) async {
    final ok = await confirmAdmin216(context,
        title: L.t.cancelThisRequest,
        body: L.t.phonesThatHavenTAnsweredYet,
        yes: L.t.cancelRequest,
        danger: true,
        yesKey: const ValueKey('chat_request_cancel_yes'));
    if (!ok || !mounted) return;
    try {
      await (_svc?.actions ?? AdminActionService.instance)?.cancel(r.id);
      ChatRequests221.changed307?.call(); // C3: the phone card goes at once
      if (mounted) adminSnack216(context, L.t.cancelled);
    } catch (error) {
      if (mounted) adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
    }
    unawaited(_load());
  }

  static bool _canCancel(ChatRequestRow221 r) => r.state == 'pending' && !r.ready && r.parts == 0;

  /// B4: a card that is not Ready opens a small sheet (where it is + Cancel).
  Future<void> _liveTap(ChatRequestRow221 r) async {
    final step = RequestStep307.of(r);
    if (step.step == Step307.ready || r.parts > 0) return _open(r);
    final cancel = await showAdminSheet216<bool>(context, builder: (ctx) {
      final k = K307.of(ctx);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AvatarPair307(names: _namesOf(r), size: 40, group: _isGroup(r)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(17, FontWeight.w700, k.ink)),
              const SizedBox(height: 2),
              Text(_range(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(13, FontWeight.w400, k.grey)),
            ]),
          ),
          ProgressRing307(step: step, size: 44),
        ]),
        const SizedBox(height: 16),
        Text(step.big, style: k.text(20, FontWeight.w700, k.ink, 1.2)),
        const SizedBox(height: 4),
        Text(step.sub, style: k.text(14, FontWeight.w400, k.grey, 1.35)),
        const SizedBox(height: 14),
        RequestTrack307(step: step),
        if (_canCancel(r)) ...[
          const SizedBox(height: 18),
          Text(L.t.phonesThatHavenTAnsweredYet, style: k.text(13.5, FontWeight.w400, k.grey, 1.4)),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: AdminButton216(L.t.cancelRequest,
                key: const ValueKey('live307_cancel'),
                kind: A216ButtonKind.danger,
                height: 52,
                onTap: () => Navigator.of(ctx).pop(true)),
          ),
        ],
      ]);
    });
    if (cancel == true && mounted) await _cancel(r);
  }

  // ------------------------------------------------------------- words

  static List<String> _namesOf(ChatRequestRow221 r) =>
      r.label.contains(' & ') ? r.label.split(' & ') : [r.label.isEmpty ? L.t.chat : r.label];

  static bool _isGroup(ChatRequestRow221 r) => ChatPick221.fromRef(r.chat)?.isGroup ?? false;

  static String _title(ChatRequestRow221 r) => r.label.isEmpty ? L.t.chat : r.label;

  /// "Full chat" / "Last 7 days" / "1 Nov - 7 Nov" (no path words: A6).
  static String _range(ChatRequestRow221 r) {
    final w = r.words.replaceFirst('Get chat \u00b7 ', '').trim();
    if (w.isNotEmpty) return w;
    if (r.from.isEmpty) return L.t.fullChat;
    String day(String d) {
      final t = DateTime.tryParse(d);
      return t == null ? d : dMMM216(t);
    }

    return '${day(r.from)} - ${day(r.to)}';
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return dMMM216(t);
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final requests = [for (final r in _rows) if (r.action == 'get_chat') r];
    return AdminTheme216Scope(
      child: Builder(builder: (context) {
        final k = K307.of(context);
        return Scaffold(
          key: const ValueKey('a216_page'),
          backgroundColor: k.bg,
          body: SafeArea(
            bottom: false,
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _header(context),
                const AdminUiCheckBanner216(),
                const ServerClockBar255(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Segmented307(
                    labels: [L.t.chats, L.t.requests],
                    counts: [_chats.length, requests.length],
                    keys: const [ValueKey('tabs221_0'), ValueKey('tabs221_1')],
                    selected: _tab,
                    onSelected: (i) => setState(() => _tab = i),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      key: const ValueKey('a216_list'),
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 110),
                      children: _loading
                          ? [_pad(const Shimmer307())]
                          : _error.isNotEmpty
                              ? [_pad(_errorCard(context))]
                              : _tab == 0
                                  ? _chatsTab(context)
                                  : _requestsTab(context, requests),
                    ),
                  ),
                ),
              ]),
              Positioned(
                right: 16,
                bottom: 20 + MediaQuery.paddingOf(context).bottom,
                child: Fab307(L.t.newRequest, key: const ValueKey('chats221_new_request'), onTap: () => _ask()),
              ),
            ]),
          ),
        );
      }),
    );
  }

  static Widget _pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: w);

  /// B2: row 1 = round back + round crown; row 2 = title + server pill.
  Widget _header(BuildContext context) {
    final k = K307.of(context);
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (canPop)
            Material(
              key: const ValueKey('conv307_back'),
              color: k.card,
              shape: const CircleBorder(),
              elevation: 0,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                    width: 38, height: 38, child: Icon(Icons.chevron_left_rounded, color: k.ink, size: 26)),
              ),
            ),
          const Spacer(),
          const OwnerChip221(),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Flexible(
            child: Text(L.en('Conversations'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: k.text(30, FontWeight.w700, k.ink, 1.1, -0.6)),
          ),
          const SizedBox(width: 10),
          ServerPill307(
            online: _online,
            label: _online ? L.t.serverConnected : L.t.noServer307,
            onTap: () => adminSnack216(
                context, _online ? L.t.serverConnectedRequestsGoByThe : L.t.noServerTip307),
          ),
        ]),
      ]),
    );
  }

  Widget _errorCard(BuildContext context) {
    final k = K307.of(context);
    return Container(
      key: const ValueKey('conv307_error'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: k.cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(L.en(_error), style: k.text(14.5, FontWeight.w500, k.ink, 1.4)),
        const SizedBox(height: 14),
        SizedBox(
          height: 46,
          child: AdminButton216(L.t.tryAgain,
              key: const ValueKey('conv307_retry'),
              kind: A216ButtonKind.tonal,
              height: 46,
              onTap: () {
                setState(() {
                  _loading = true;
                  _error = '';
                });
                unawaited(_load());
              }),
        ),
      ]),
    );
  }

  // --------------------------------------------------------- requests tab

  List<Widget> _requestsTab(BuildContext context, List<ChatRequestRow221> requests) {
    final live = RequestStep307.liveOrder(requests);
    final running = [for (final r in requests) if (RequestStep307.of(r).active) r];
    final done = [for (final r in requests) if (!RequestStep307.of(r).active) r];
    return [
      if (live.isNotEmpty) ...[
        _pad(SectionHead307(L.t.live,
            count: live.length,
            link: running.isEmpty ? null : L.t.seeAll307,
            linkKey: const ValueKey('live307_see_all'),
            onLink: () {
              final c = _progressHead.currentContext;
              if (c != null) {
                unawaited(Scrollable.ensureVisible(c, duration: Motion307.d(context, 350), curve: Curves.easeOutCubic));
              }
            })),
        _carousel(context, live),
      ],
      _pad(SectionHead307(L.t.inProgress307, key: _progressHead, count: running.length)),
      if (running.isEmpty)
        _pad(AdminEmptyState216(
          key: const ValueKey('requests221_empty'),
          icon: Icons.pending_actions_rounded,
          tone: A216Tone.orange,
          title: L.t.noRequests,
          body: L.t.requestsWaitHereUntilAPhone,
        ))
      else
        for (var i = 0; i < running.length; i++)
          _pad(Enter307(
              index: i,
              child: Padding(
                  padding: EdgeInsets.only(bottom: i == running.length - 1 ? 0 : 10),
                  child: _progressCard(context, running[i])))),
      if (done.isNotEmpty) ...[
        _pad(SectionHead307(L.t.finished307, count: done.length)),
        _pad(Container(
          key: const ValueKey('requests307_finished'),
          decoration: K307.of(context).cardBox(),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < done.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 70),
                  child: Divider(height: 1, thickness: 1, color: K307.of(context).line),
                ),
              _finishedRow(context, done[i]),
            ],
          ]),
        )),
      ],
    ];
  }

  void _syncAdvance(BuildContext context, int count) {
    final want = count >= 2 && Motion307.loops(context);
    if (!want) {
      _advance?.cancel();
      _advance = null;
      return;
    }
    _advance ??= Timer.periodic(AdminConversationsScreen.advanceEvery, (_) {
      if (!mounted || _tab != 1) return;
      if (_pauseTicks > 0) {
        _pauseTicks--;
        return;
      }
      setState(() {
        _swipeDir = 1;
        _live = _live + 1;
        _dropId = '';
      });
    });
  }

  void _touched() => _pauseTicks = AdminConversationsScreen.pauseAfterTouch.inSeconds ~/
      AdminConversationsScreen.advanceEvery.inSeconds;

  Widget _carousel(BuildContext context, List<ChatRequestRow221> live) {
    if (_focusId.isNotEmpty) {
      final i = live.indexWhere((r) => r.id == _focusId);
      if (i >= 0) {
        _live = i;
        _dropId = _focusId; // E: the new card drops in from above
      }
      _focusId = '';
    }
    final n = live.length;
    final index = ((_live % n) + n) % n;
    _syncAdvance(context, n);
    final r = live[index];
    final step = RequestStep307.of(r);
    final card = LiveCard307(
      key: ValueKey('live307_card_${r.id}'),
      step: step,
      names: _namesOf(r),
      title: _title(r),
      range: _range(r),
      brand: L.t.getChat,
      group: _isGroup(r),
      onTap: () {
        _touched();
        unawaited(_liveTap(r));
      },
    );
    final dir = _swipeDir;
    return Column(children: [
      GestureDetector(
        key: const ValueKey('live307_carousel'),
        behavior: HitTestBehavior.translucent,
        onPanDown: (_) => _touched(),
        onHorizontalDragEnd: n < 2
            ? null
            : (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() < 80) return;
                _touched();
                setState(() {
                  _swipeDir = v < 0 ? 1 : -1;
                  _live = index + _swipeDir;
                  _dropId = '';
                });
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: Motion307.d(context, r.id == _dropId ? 600 : 550),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (child, a) {
                // In: from the swipe side. Out (animation runs back): to the other side.
                final incoming = child.key == card.key;
                if (incoming && r.id == _dropId) {
                  // E (send): a small spring from above.
                  return FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, -0.35), end: Offset.zero)
                          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                      child: child,
                    ),
                  );
                }
                final begin = Offset(incoming ? dir * 1.05 : -dir * 1.05, 0);
                return SlideTransition(position: Tween(begin: begin, end: Offset.zero).animate(a), child: child);
              },
              child: card,
            ),
          ),
        ),
      ),
      if (n > 1) ...[
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < n; i++)
            AnimatedContainer(
              key: ValueKey('live307_dot_$i'),
              duration: Motion307.d(context, 550),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? K307.of(context).blue : K307.of(context).dash,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ]),
      ],
    ]);
  }

  /// B5: one card per running request.
  Widget _progressCard(BuildContext context, ChatRequestRow221 r) {
    final k = K307.of(context);
    final step = RequestStep307.of(r);
    // The chip: "Sent" / "1 of 2 phones" / "40 of 80 parts".
    final chip = step.step == Step307.coming ? L.t.ofParts(r.parts, r.of) : step.chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('requests221_row_${r.id}'),
        borderRadius: BorderRadius.circular(20),
        onTap: r.parts > 0 ? () => _open(r) : () => _liveTap(r),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: k.cardBox(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              AvatarPair307(names: _namesOf(r), size: 42, group: _isGroup(r)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_title(r),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(16, FontWeight.w700, k.ink, 1.2)),
                  const SizedBox(height: 2),
                  Text(step.sub,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(13.5, FontWeight.w400, k.grey, 1.3)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Chip307(chip, step.step),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(_range(r),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(12.5, FontWeight.w400, k.grey, 1.2)),
                    ),
                    if (_canCancel(r)) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        key: ValueKey('requests221_cancel_${r.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _cancel(r),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Text(L.t.cancel, style: k.text(13, FontWeight.w700, A216.colors(context).red, 1.2)),
                        ),
                      ),
                    ],
                  ]),
                ]),
              ),
              const SizedBox(width: 10),
              ProgressRing307(step: step),
            ]),
            if (r.half) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: r.of <= 0 ? 0 : (r.parts / r.of).clamp(0, 1).toDouble()),
                    duration: Motion307.d(context, 400),
                    builder: (context, v, _) => LinearProgressIndicator(
                      key: const ValueKey('parts221_bar'),
                      value: v,
                      backgroundColor: k.track,
                      color: k.blue,
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// B6: Ready / No messages / Cancelled rows (no "since", no path note).
  Widget _finishedRow(BuildContext context, ChatRequestRow221 r) {
    final k = K307.of(context);
    final step = RequestStep307.of(r);
    final made = DateTime.tryParse(r.madeAt)?.toLocal();
    final sub = [
      if (r.of > 0) L.t.tapToOpenParts307(r.of).split('\u00b7').last.trim(),
      if (made != null) dMMM216(made),
    ].join(' \u00b7 ');
    final opens = step.step == Step307.ready || r.parts > 0;
    return InkWell(
      key: ValueKey('requests221_row_${r.id}'),
      onTap: opens ? () => _open(r) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(children: [
          AvatarPair307(names: _namesOf(r), size: 36, group: _isGroup(r)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title(r),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(15, FontWeight.w700, k.ink, 1.2)),
              const SizedBox(height: 4),
              Row(children: [
                Chip307(step.chip, step.step, check: step.step == Step307.ready),
                if (sub.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(sub,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(12.5, FontWeight.w400, k.grey, 1.2)),
                  ),
                ],
              ]),
            ]),
          ),
          if (opens) Icon(Icons.chevron_right_rounded, color: k.grey2),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ chats tab

  List<Widget> _chatsTab(BuildContext context) {
    final k = K307.of(context);
    final q = _query.trim().toLowerCase();
    bool match(Map<String, dynamic> chat) {
      if (q.isEmpty) return true;
      final words = [
        ...chatNamesOfRow(chat),
        chat['group_name']?.toString() ?? '',
        for (final x in (chat['participants'] as List? ?? const []))
          if (x is Map) x['username']?.toString() ?? '',
      ];
      return words.any((w) => w.toLowerCase().contains(q));
    }

    final shown = [for (final c in _chats) if (match(c)) c];
    final ready = [
      for (final c in shown)
        if (_readyReq(c) != null) c,
    ];
    return [
      _pad(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: k.card,
            borderRadius: BorderRadius.circular(14),
            border: k.dark ? Border.all(color: k.cardEdge) : null,
            boxShadow: k.shadowSmall,
          ),
          child: TextField(
            key: const ValueKey('chats307_search'),
            onChanged: (v) => setState(() => _query = v),
            style: k.text(15, FontWeight.w400, k.ink, 1.2),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              prefixIcon: Icon(Icons.search_rounded, color: k.grey, size: 20),
              hintText: L.t.searchPeopleOrGroups307,
              hintStyle: k.text(15, FontWeight.w400, k.grey, 1.2),
            ),
          ),
        ),
      )),
      if (ready.isNotEmpty) ...[
        _pad(SectionHead307(L.t.readyToReadSection307, count: ready.length)),
        SizedBox(
          height: 146,
          child: ListView.separated(
            key: const ValueKey('chats307_ready'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: ready.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _readyTile(context, ready[i]),
          ),
        ),
      ],
      _pad(SectionHead307(L.t.allChats307, count: shown.length)),
      if (_chats.isEmpty)
        _pad(AdminEmptyState216(
          key: const ValueKey('chats221_empty'),
          icon: Icons.forum_outlined,
          tone: A216Tone.blue,
          title: L.t.noChatsYet,
          body: L.t.useNewRequestToAskThe,
        ))
      else
        _pad(Container(
          key: const ValueKey('chats221_list'),
          decoration: k.cardBox(),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 76),
                  child: Divider(height: 1, thickness: 1, color: k.line),
                ),
              _chatRow(context, shown[i]),
            ],
          ]),
        )),
    ];
  }

  /// A finished answer whose copy is still kept.
  ChatRequestRow221? _readyReq(Map<String, dynamic> chat) {
    final r = _requestOf(chat);
    if (r == null || r.closed) return null;
    return RequestStep307.of(r).step == Step307.ready ? r : null;
  }

  String _chatSub(Map<String, dynamic> chat) {
    if (chat['kind'] == 'group') {
      final members = chat['member_count'] is int ? chat['member_count'] as int : 0;
      return L.t.groupMembers(members);
    }
    final count = chat['message_count'] is int ? chat['message_count'] as int : 0;
    final last = DateTime.tryParse('${chat['last_message_at'] ?? ''}')?.toLocal();
    return last == null ? L.t.messages3(count) : L.t.messagesAt307(count, _when(last));
  }

  String _chatTitle(Map<String, dynamic> chat) => chat['kind'] == 'group'
      ? (chat['group_name']?.toString() ?? L.t.group)
      : chatNamesOfRow(chat).join(' & ');

  Widget _readyTile(BuildContext context, Map<String, dynamic> chat) {
    final k = K307.of(context);
    final r = _readyReq(chat)!;
    final group = chat['kind'] == 'group';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('chats307_ready_${chat['id']}'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(r),
        child: Container(
          width: 142,
          padding: const EdgeInsets.all(12),
          decoration: k.cardBox(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AvatarPair307(names: chatNamesOfRow(chat), size: 34, group: group),
            const Spacer(),
            Text(_chatTitle(chat),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(14, FontWeight.w700, k.ink, 1.2)),
            const SizedBox(height: 2),
            Text(group ? L.t.group : _chatSubShort(chat),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(12, FontWeight.w400, k.grey, 1.2)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: k.greenSoft, borderRadius: BorderRadius.circular(14)),
              child: Text(L.t.open, style: k.text(12.5, FontWeight.w700, k.green, 1.2)),
            ),
          ]),
        ),
      ),
    );
  }

  /// The tile line: same as the row but its own Text (the row keeps the
  /// "42 messages" text once).
  String _chatSubShort(Map<String, dynamic> chat) {
    final last = DateTime.tryParse('${chat['last_message_at'] ?? ''}')?.toLocal();
    return last == null ? L.t.ready : '${L.t.ready} \u00b7 ${_when(last)}';
  }

  Widget _chatRow(BuildContext context, Map<String, dynamic> chat) {
    final k = K307.of(context);
    final group = chat['kind'] == 'group';
    final req = _requestOf(chat);
    final pick = chatPickOfRow(chat);
    final Widget right;
    if (req == null) {
      right = _capsule(context, L.t.getChat, ValueKey('chats221_ask_${chat['id']}'), () => _ask(pick));
    } else {
      final step = RequestStep307.of(req);
      right = Chip307(step.step == Step307.coming ? step.short : step.chip, step.step);
    }
    return InkWell(
      key: ValueKey('chats221_row_${chat['id']}'),
      onTap: req != null && (req.parts > 0 || req.ready) ? () => _open(req) : () => _ask(pick),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(children: [
          AvatarPair307(names: chatNamesOfRow(chat), size: 42, group: group),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_chatTitle(chat),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(16, FontWeight.w700, k.ink, 1.2)),
              const SizedBox(height: 3),
              Text(_chatSub(chat),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(13.5, FontWeight.w400, k.grey, 1.25)),
            ]),
          ),
          const SizedBox(width: 8),
          right,
        ]),
      ),
    );
  }

  Widget _capsule(BuildContext context, String label, Key key, VoidCallback onTap) {
    final k = K307.of(context);
    return Material(
      color: k.blue,
      shape: const StadiumBorder(),
      child: InkWell(
        key: key,
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label, style: k.text(13.5, FontWeight.w700, Colors.white, 1.2)),
        ),
      ),
    );
  }
}

/// The chat a list row is about (server or local row).
ChatPick221? chatPickOfRow(Map<String, dynamic> chat) {
  final label = chat['kind'] == 'group'
      ? chat['group_name']?.toString() ?? ''
      : chatNamesOfRow(chat).join(' & ');
  if (chat['kind'] == 'group') {
    final g = chat['group_id']?.toString() ?? '';
    return g.isEmpty ? null : ChatPick221.group(g, label: label);
  }
  final p = [for (final x in (chat['participants'] as List? ?? const [])) if (x is Map) x];
  if (p.length < 2) return null;
  return ChatPick221.direct(p[0]['id'].toString(), p[1]['id'].toString(), label: label);
}

List<String> chatNamesOfRow(Map<String, dynamic> chat) {
  if (chat['kind'] == 'group') return [chat['group_name']?.toString() ?? L.t.group];
  return [
    for (final x in (chat['participants'] as List? ?? const []))
      if (x is Map)
        (x['name']?.toString() ?? '').isNotEmpty
            ? x['name'].toString()
            : (x['username']?.toString() ?? '').isNotEmpty
                ? x['username'].toString()
                : L.t.someone,
  ];
}

// ------------------------------------------------------- shared small parts

const List<Color> _avatarColors = [
  Color(0xFF2563EB), Color(0xFFDB5C9A), Color(0xFFF59E0B), Color(0xFF22C55E),
  Color(0xFF14A3A0), Color(0xFF6366F1), Color(0xFFEF4444), Color(0xFF8B5CF6),
];

Color avatarColor221(String name) {
  var h = 0;
  for (final u in name.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return _avatarColors[h % _avatarColors.length];
}

class Letter221 extends StatelessWidget {
  const Letter221(this.name, {super.key, this.size = 40, this.ring = false});
  final String name;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: avatarColor221(name),
        shape: BoxShape.circle,
        border: ring ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Text(letter,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: size * 0.42)),
    );
  }
}

/// Two overlapping letters (a private chat) or one big letter (a group).
class ChatAvatars221 extends StatelessWidget {
  const ChatAvatars221(
      {super.key, required this.names, this.group = false, this.size = 72, this.photoIds});
  final List<String> names;
  final bool group;
  final double size;

  /// Bundle 255 B8: device ids (same order as [names]); photos when this
  /// phone has them, letters stay the fallback.
  final List<String>? photoIds;

  Widget _one(int i, double s, {bool ring = false}) {
    final ids = photoIds;
    if (ids == null || ids.length <= i || ids[i].isEmpty) {
      return Letter221(names[i], size: s, ring: ring);
    }
    final photo = AdminPersonAvatar216(
        name: names[i], deviceId: ids[i], radius: ring ? s / 2 - 2 : s / 2, crown: false);
    if (!ring) return photo;
    return Container(
      decoration: BoxDecoration(
          shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      child: photo,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (group || names.length < 2) {
      return SizedBox(
          width: size,
          height: size,
          child: Center(child: Letter221(names.isEmpty ? '?' : names.first, size: size * 0.98)));
    }
    final s = size * 0.56;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        Positioned(left: 0, top: size * 0.12, child: _one(0, s)),
        Positioned(left: size * 0.4, top: size * 0.4, child: _one(1, s, ring: true)),
      ]),
    );
  }
}

class OwnerChip221 extends StatelessWidget {
  const OwnerChip221({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: L.t.ownerOnly,
        child: Material(
          key: const ValueKey('chats221_owner'),
          color: const Color(0xFFFFF6DB),
          shape: const CircleBorder(side: BorderSide(color: Color(0xFFF2D27A))),
          child: SizedBox(width: 38, height: 38, child: Center(child: AdminCrown.mark(15, halo: null))),
        ),
      );
}

/// Green "Server connected" / orange "No server" line (mocks A-1 / A-2).
class LinkBanner221 extends StatelessWidget {
  const LinkBanner221({super.key, required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    final t = A216Text.of(context);
    final bg = online ? const Color(0xFFE7F6EC) : const Color(0xFFFFF4E5);
    final dot = online ? const Color(0xFF12A150) : const Color(0xFFC4320A);
    final fg = online ? const Color(0xFF0B6B35) : const Color(0xFF93370D);
    return Container(
      key: ValueKey(online ? 'chats221_online_bar' : 'chats221_offline_bar'),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              online ? L.t.serverConnectedRequestsGoByThe : L.t.noServerRequestsGoByWi,
              style: t.custom(13, FontWeight.w600, fg)),
        ),
      ]),
    );
  }
}

class Tabs221 extends StatelessWidget {
  const Tabs221({super.key, required this.labels, required this.selected, required this.onSelected});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFFECEFF4), borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: GestureDetector(
              key: ValueKey('tabs221_$i'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == selected ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Text(labels[i],
                    style: t.custom(14, i == selected ? FontWeight.w700 : FontWeight.w500,
                        i == selected ? c.ink : c.grey)),
              ),
            ),
          ),
      ]),
    );
  }
}

class ListCard221 extends StatelessWidget {
  const ListCard221({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(left: 102, right: 16),
              child: Divider(height: 1, thickness: 1, color: c.div),
            ),
          children[i],
        ],
      ]),
    );
  }
}

/// "40 of 80 parts" thin blue bar.
class PartsBar221 extends StatelessWidget {
  const PartsBar221({super.key, required this.have, required this.of});
  final int have;
  final int of;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 5,
          child: LinearProgressIndicator(
            key: const ValueKey('parts221_bar'),
            value: of <= 0 ? 0 : (have / of).clamp(0, 1).toDouble(),
            backgroundColor: const Color(0xFFE5E8EE),
            color: const Color(0xFF2563EB),
          ),
        ),
      );
}
