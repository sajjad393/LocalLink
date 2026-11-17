import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/data/actions/admin_action_book.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_request_sheet.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit320.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 221 (mock A-1): the Owner's chat list. Online it is the server's
/// list (who / how many / when, no text); offline the chats this phone
/// knows. "Get chat" makes a Get chat request; a row with an answer opens
/// the viewer (half answers too).
///
/// Bundle 307 (TODO_307 B2-B7, B10): bold iOS-style cards. No path words
/// on this screen.
///
/// Bundle 320 (TODO_320 R1-R4, pick A): ONE list, no tabs. Search "Find a
/// chat", filter chips All / Coming / Ready / Kept, a "Now" card with only
/// the requests on their way (one status line, a thin bar when coming, X =
/// cancel) and a "Chats" card where every chat shows once with one button
/// (Open / New / Get chat). No carousel, nothing slides by itself.
class AdminConversationsScreen extends StatefulWidget {
  const AdminConversationsScreen({super.key, this.viewMode, this.requests});

  final AppViewModeCubit? viewMode;
  final ChatRequests221? requests;

  /// A2: how often the server pill re-checks the link.
  static const Duration pillEvery = Duration(seconds: 10);

  /// Bundle 323 (P6): "Saved 18:44" when the list on screen was saved today,
  /// "Saved 16 Nov 18:44" when it is older, "" when nothing was ever saved.
  /// Offline only - while the server answers the list is today's.
  static String savedLabel323(DateTime? at, DateTime now) {
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(at.hour)}:${two(at.minute)}';
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay ? '${L.t.saved} $time' : '${L.t.saved} ${dMMM216(at)} $time';
  }

  @override
  State<AdminConversationsScreen> createState() => _AdminConversationsScreenState();
}

class _AdminConversationsScreenState extends State<AdminConversationsScreen> {
  /// Bundle 320 (R1): 0 all, 1 coming, 2 ready, 3 kept.
  int _filter = 0;
  List<Map<String, dynamic>> _chats = const [];
  List<ChatRequestRow221> _rows = const [];
  bool _loading = true;
  String _error = '';
  String _query = '';
  StreamSubscription<AppViewModeState>? _viewSub;
  Timer? _pill;

  ChatRequests221? get _svc => widget.requests ?? ChatRequests221.instance;
  bool _srvOnline = false;

  /// Bundle 323 (P6): when this phone last saved the conversation list.
  DateTime? _savedAt;
  bool get _online => _srvOnline && (widget.viewMode?.state.serverConnected ?? true);

  @override
  void initState() {
    super.initState();
    AdminActionBook.instance.addListener(_reload);
    ChatAnswerCarrier.progress.addListener(_reload);
    FileQueue317.trips.addListener(_files317); // Bundle 317 (G8)
    _viewSub = widget.viewMode?.stream.listen((_) => _reload());
    // A2: the pill flips within 10 s when the server drops or comes back.
    _pill = Timer.periodic(AdminConversationsScreen.pillEvery, (_) => unawaited(_checkPill()));
    unawaited(_reload319());
  }

  void _files317() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AdminActionBook.instance.removeListener(_reload);
    ChatAnswerCarrier.progress.removeListener(_reload);
    FileQueue317.trips.removeListener(_files317);
    unawaited(_viewSub?.cancel());
    _pill?.cancel();
    _reload319.close();
    super.dispose();
  }

  /// Bundle 319 (F7): every part / card change reloaded the whole list
  /// (open + decrypt); now merged - max once per 2 s, one at a time.
  void _reload() => unawaited(_reload319());

  late final MergedRun319 _reload319 = MergedRun319(_load, gap: const Duration(seconds: 2));

  Future<void> _checkPill() async {
    final s = _svc;
    if (s == null) return;
    try {
      final online = await s.online();
      if (mounted && online != _srvOnline) setState(() => _srvOnline = online);
    } catch (_) {}
  }

  Future<void> _savedFirst321(ChatRequests221 s) async {
    try {
      final chats = await s.savedConversations321();
      final rows = await s.savedRequests321();
      if (!mounted || (chats.isEmpty && rows.isEmpty) || !_loading) return;
      setState(() {
        _chats = chats;
        _rows = rows;
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    final s = _svc;
    if (s == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // Bundle 323 (P6): the saved list's own time, before anything else.
    final savedAt = await s.savedAt323().catchError((_) => null);
    if (mounted && savedAt != _savedAt) setState(() => _savedAt = savedAt);
    // Bundle 321 (F13): the saved requests + kept copies at once; the
    // server lists fill in behind (8 s max each).
    if (_loading && _chats.isEmpty && _rows.isEmpty) await _savedFirst321(s);
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

  Future<void> _ask([ChatPick221? pick]) async {
    final s = _svc;
    if (s == null) return;
    final sent = await showChatRequestSheet(context,
        service: s, preset: pick, online: _online, onOpen: (r) => unawaited(_openAsked314(r)));
    if (sent == true && mounted) {
      adminSnack216(context, _online ? L.t.requestSentByTheServer : L.t.requestSentToNearbyPhones);
      // Bundle 320 (R2): the new request shows in "Now" (top of the list).
      setState(() => _filter = 0);
      await _load();
    }
  }

  /// Bundle 314 (1b): "Already asked · Open it" - its viewer once parts
  /// came, else (320) the small "where it is" sheet of its Now row.
  Future<void> _openAsked314(ChatRequestRow221 r) async {
    if (!mounted) return;
    if (r.parts > 0 || r.ready) return _open(r);
    await _liveTap(r);
  }

  /// Bundle 320 (R3): "New" on a kept copy = Get new messages only (318 K4).
  Future<void> _askNew320(ChatPick221 pick) async {
    final s = _svc;
    if (s == null) return;
    try {
      await s.requestNew318(pick);
      if (!mounted) return;
      adminSnack216(context, _online ? L.t.requestSentByTheServer : L.t.requestSentToNearbyPhones);
      setState(() => _filter = 0);
    } catch (error) {
      if (mounted) adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
    }
    unawaited(_load());
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
              Text(_title(r), style: k.text(17, FontWeight.w700, k.ink)),
              const SizedBox(height: 2),
              Text(_range(r), style: k.text(13, FontWeight.w400, k.grey)),
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
                // Bundle 315: no server clock banner (the check stays hidden: log + time fix).
                // Bundle 320 (R1): no Chats / Requests tabs - one list.
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
                              : _list320(context, requests),
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
        // Bundle 313 (E1): the title is never cut - with no room the pill
        // moves under it (was one Row: "Conversatio..." on a 360 dp phone).
        Wrap(
            key: const ValueKey('conv313_title_wrap'),
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
          Text(L.en('Conversations'),
              key: const ValueKey('conv313_title'),
              style: k.text(30, FontWeight.w700, k.ink, 1.1, -0.6)),
          ServerPill307(
            online: _online,
            label: _online ? L.t.serverConnected : L.t.noServer307,
            onTap: () => adminSnack216(
                context, _online ? L.t.serverConnectedRequestsGoByThe : L.t.noServerTip307),
          ),
        ]),
        // Bundle 323 (P6): offline, say how old the list on screen is - the
        // one honest line the 17 Nov review asked for. Nothing is shown while
        // the server answers (the list is today's).
        if (!_online && _savedLabel323.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(_savedLabel323,
              key: const ValueKey('conv323_saved'),
              style: k.text(12.5, FontWeight.w500, k.grey, 1.2)),
        ],
      ]),
    );
  }

  /// Bundle 323 (P6): the header line of the saved list.
  String get _savedLabel323 => AdminConversationsScreen.savedLabel323(_savedAt, DateTime.now());

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

  // ------------------------------------------------------------ one list

  /// Bundle 320 (R3): one key per chat (the group / the two people), so a
  /// server chat, its requests and its kept copy are ONE row.
  static String chatKey320(ChatPick221? p) {
    if (p == null) return '';
    if (p.isGroup) return 'g:${p.groupId}';
    final two = <String>[p.userA, p.userB]..sort();
    return 'd:${two.join('|')}';
  }

  static String _keyOf320(ChatRequestRow221 r) => chatKey320(ChatPick221.fromRef(r.chat));

  /// R2: the requests on their way (Sent / Reached / Coming), furthest first.
  List<ChatRequestRow221> _now320(List<ChatRequestRow221> requests) => [
        for (final r in RequestStep307.liveOrder(requests, files: FileQueue317.trips.value))
          if (RequestStep307.of(r).active && !r.closed && !r.inside318) r,
      ];

  /// R3 / R4: every other chat once - server chats first, then chats this
  /// phone only knows from a request (offline, kept copies).
  List<Row320> _rows320(List<ChatRequestRow221> requests, Set<String> busy) {
    final byChat = <String, List<ChatRequestRow221>>{};
    final newest = [...requests]..sort((a, b) => b.madeAt.compareTo(a.madeAt));
    for (final r in newest) {
      final key = _keyOf320(r);
      if (key.isNotEmpty) (byChat[key] ??= <ChatRequestRow221>[]).add(r);
    }
    final out = <Row320>[];
    final seen = <String>{};
    for (final c in _chats) {
      final key = chatKey320(chatPickOfRow(c));
      if (key.isNotEmpty && (busy.contains(key) || !seen.add(key))) continue;
      out.add(_rowOf320(chat: c, reqs: byChat[key] ?? const []));
    }
    for (final e in byChat.entries) {
      if (busy.contains(e.key) || !seen.add(e.key)) continue;
      out.add(_rowOf320(reqs: e.value));
    }
    return out;
  }

  Row320 _rowOf320({Map<String, dynamic>? chat, required List<ChatRequestRow221> reqs}) {
    final first = reqs.isEmpty ? null : reqs.first;
    final group = chat != null ? chat['kind'] == 'group' : (first != null && _isGroup(first));
    final title = chat != null ? _chatTitle(chat) : _title(first!);
    final names = chat != null ? chatNamesOfRow(chat) : _namesOf(first!);
    final pick = chat != null ? chatPickOfRow(chat) : ChatPick221.fromRef(first!.chat, label: first.label);
    final id = chat != null ? '${chat['id']}' : first!.id;
    ChatRequestRow221? ready;
    ChatRequestRow221? kept;
    for (final r in reqs) {
      if (r.cancelled || r.closed) continue;
      if (ready == null && RequestStep307.of(r).step == Step307.ready) ready = r;
      if (kept == null && r.keptUntil318.isNotEmpty) kept = r;
    }
    final until = kept == null ? null : DateTime.tryParse(kept.keptUntil318)?.toLocal();
    if (until == null || !until.isAfter(DateTime.now())) kept = null;
    // Bundle 321 (R1): "Ready to read" only when every file is here.
    final base321 = ready ?? kept;
    final trip = base321 == null ? null : FileQueue317.trips.value[base321.id];
    final coming321 = trip != null && trip.total > 0 && trip.active;
    final notHere321 = trip == null || trip.stopped ? 0 : trip.gone + trip.tooBig;
    Row320 make(Kind320 kind, String status, Tone320 tone, {ChatRequestRow221? open, IconData? icon}) => Row320(
          id: id,
          title: title,
          names: names,
          group: group,
          pick: pick,
          kind: kind,
          status: status,
          tone: tone,
          open: open,
          icon: icon,
          filesComing321: coming321 && (kind == Kind320.ready || kind == Kind320.kept) && tone != Tone320.grey,
          notHere321: kind == Kind320.ready || kind == Kind320.kept ? notHere321 : 0,
        );
    if (chat?['me'] == true) {
      // Bundle 314 (1 / K1): a chat I am in is already on my phone.
      return make(Kind320.mine, _chatSub(chat!), Tone320.grey, open: ready);
    }
    if (ready != null && (!ready.opened || kept == null || pick == null)) {
      final step = RequestStep307.of(ready);
      final words = ready.newOnly318 && ready.newCount318 >= 0
          ? (step.upToDate ? L.t.upToDate318 : '${L.t.ready} \u00b7 ${L.t.nNew318(ready.newCount318)}')
          : L.t.readyToReadSection307;
      if (coming321 && !(ready.newOnly318 && step.upToDate)) {
        return make(Kind320.ready, L.t.messagesHere321('${trip.here}', '${trip.wanted}'), Tone320.blue, open: ready);
      }
      return make(Kind320.ready, words, Tone320.green, open: ready);
    }
    if (kept != null) {
      final up = ready != null && ready.newOnly318 && RequestStep307.of(ready).upToDate;
      final words = L.t.keptUntil320(dMMM216(until!));
      return make(Kind320.kept, up ? '${L.t.upToDate318} \u00b7 $words' : words, Tone320.grey,
          open: ready ?? kept, icon: Icons.lock_rounded);
    }
    if (first != null && RequestStep307.of(first).step == Step307.empty && !first.closed) {
      return make(Kind320.ask, L.t.noPhoneHasThisChat307, Tone320.grey);
    }
    if (first != null && first.cancelled) {
      final made = DateTime.tryParse(first.madeAt)?.toLocal();
      return make(Kind320.ask, made == null ? L.t.cancelled : L.t.cancelledOn320(dMMM216(made)), Tone320.grey);
    }
    return make(Kind320.ask, chat != null ? _chatSub(chat) : _range(first!), Tone320.grey);
  }

  List<Widget> _list320(BuildContext context, List<ChatRequestRow221> requests) {
    final k = K307.of(context);
    final now = _now320(requests);
    final busy = {for (final r in now) _keyOf320(r)}..remove('');
    final rows = _rows320(requests, busy);
    final readyN = rows.where((x) => x.kind == Kind320.ready && !x.filesComing321).length;
    final comingRows321 = rows.where((x) => x.filesComing321).length;
    final keptN = rows.where((x) => x.kind == Kind320.kept).length;
    final q = _query.trim().toLowerCase();
    bool match(String title, List<String> names) =>
        q.isEmpty || [title, ...names].any((w) => w.toLowerCase().contains(q));
    final nowShown = _filter == 0 || _filter == 1
        ? [for (final r in now) if (match(_title(r), _namesOf(r))) r]
        : const <ChatRequestRow221>[];
    final rowsShown = [
      for (final x in rows)
        if (match(x.title, x.names) &&
            (_filter == 0 ||
                (_filter == 1 && x.filesComing321) ||
                (_filter == 2 && x.kind == Kind320.ready && !x.filesComing321) ||
                (_filter == 3 && x.kind == Kind320.kept)))
          x,
    ];
    Widget card(Key key, List<Widget> children) => _pad(Container(
          key: key,
          decoration: k.cardBox(),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 68),
                  child: Divider(height: 1, thickness: 1, color: k.line),
                ),
              children[i],
            ],
          ]),
        ));
    return [
      _pad(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: k.card,
            borderRadius: BorderRadius.circular(23),
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
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              prefixIcon: Icon(Icons.search_rounded, color: k.grey, size: 20),
              hintText: L.t.findAChat320,
              hintStyle: k.text(15, FontWeight.w400, k.grey, 1.2),
            ),
          ),
        ),
      )),
      _pad(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FilterChips320(
          labels: [L.t.filterAll320, L.t.filterComing320, L.t.ready, L.t.filterKept320],
          counts: [now.length + rows.length, now.length + comingRows321, readyN, keptN],
          selected: _filter,
          onSelected: (i) => setState(() => _filter = i),
        ),
      )),
      if (nowShown.isNotEmpty) ...[
        _pad(SmallHead320(L.t.now320)),
        card(const ValueKey('conv320_now'), [for (final r in nowShown) _nowRow320(context, r)]),
      ],
      if (rowsShown.isNotEmpty) ...[
        _pad(SmallHead320(L.t.chats)),
        card(const ValueKey('chats221_list'), [for (final x in rowsShown) _chatRow320(context, x)]),
      ],
      if (_chats.isEmpty && requests.isEmpty)
        _pad(Padding(
          padding: const EdgeInsets.only(top: 16),
          child: AdminEmptyState216(
            key: const ValueKey('chats221_empty'),
            icon: Icons.forum_outlined,
            tone: A216Tone.blue,
            title: L.t.noChatsYet,
            body: L.t.useNewRequestToAskThe,
          ),
        ))
      else if (nowShown.isEmpty && rowsShown.isEmpty)
        _pad(Padding(
          key: const ValueKey('conv320_nothing'),
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text(L.t.nothingHere320, textAlign: TextAlign.center, style: k.text(14, FontWeight.w500, k.grey, 1.3)),
        )),
    ];
  }

  /// R2: one Now row: faces, name, ONE status line, a thin bar + "40 of 80
  /// parts" when coming, X = cancel (asks first). Tap = where it is.
  Widget _nowRow320(BuildContext context, ChatRequestRow221 r) {
    final k = K307.of(context);
    final step = RequestStep307.of(r);
    final coming = step.step == Step307.coming;
    final bar = coming && r.of > 0 && r.parts > 0;
    final String words;
    if (coming) {
      words = r.fromName.isNotEmpty ? L.t.comingFrom320(r.fromName) : L.t.coming320;
    } else {
      final base = step.step == Step307.reached
          ? step.sub
          : (r.oldApp ? L.t.oldApp : L.t.waitingForAPhone320);
      final age = AdminConversationsScreenAge320.of(r.madeAt);
      words = age.isEmpty ? base : '$base \u00b7 $age';
    }
    return InkWell(
      key: ValueKey('requests221_row_${r.id}'),
      onTap: r.parts > 0 ? () => _open(r) : () => _liveTap(r),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(children: [
          AvatarPair307(names: _namesOf(r), size: 42, group: _isGroup(r)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title(r), style: k.text(16, FontWeight.w700, k.ink, 1.2)),
              const SizedBox(height: 3),
              StatusLine320(words, coming ? Tone320.blue : Tone320.orange,
                  key: ValueKey('now320_status_${r.id}'), pulse: !coming),
              if (bar) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: (r.parts / r.of).clamp(0, 1).toDouble()),
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
          const SizedBox(width: 8),
          if (bar)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 78),
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(L.t.ofParts(r.parts, r.of),
                    key: ValueKey('now320_parts_${r.id}'),
                    textAlign: TextAlign.end,
                    style: k.text(12.5, FontWeight.w700, k.ink, 1.3)),
              ),
            )
          else if (_canCancel(r))
            IconButton(
              key: ValueKey('requests221_cancel_${r.id}'),
              tooltip: L.t.cancelRequest,
              onPressed: () => _cancel(r),
              icon: Icon(Icons.close_rounded, color: k.grey, size: 22),
            ),
        ]),
      ),
    );
  }

  /// R3: one Chats row: ONE status line and ONE button.
  Widget _chatRow320(BuildContext context, Row320 x) {
    final k = K307.of(context);
    final r = x.open;
    final pick = x.pick;
    final Widget right;
    VoidCallback? tap;
    switch (x.kind) {
      case Kind320.mine:
        right = Text(L.t.onYourPhone314,
            key: ValueKey('chats314_mine_${x.id}'), style: k.text(12.5, FontWeight.w600, k.grey, 1.2));
        tap = r == null ? null : () => _open(r);
      case Kind320.ready:
        tap = () => _open(r!);
        right = ActionPill320(L.t.open, Pill320.open, key: ValueKey('chats320_open_${x.id}'), onTap: tap);
      case Kind320.kept:
        tap = () => _open(r!);
        right = ActionPill320(L.t.new320, Pill320.tonal,
            key: ValueKey('chats320_new_${x.id}'), icon: Icons.refresh_rounded, onTap: () => _askNew320(pick!));
      case Kind320.ask:
        tap = () => _ask(pick);
        right = ActionPill320(L.t.getChat, Pill320.tonal, key: ValueKey('chats221_ask_${x.id}'), onTap: tap);
    }
    // Bundle 317 (G8): files of a Ready chat still coming - in the same line.
    // Bundle 321 (R1): a Ready row says it in its own words (blue) - no
    // "Files 3/7" added; a kept copy keeps the 317 short count.
    final f = r == null || x.kind == Kind320.ready
        ? null
        : _filesOf320(files: FileQueue317.trips.value[r.id], // Bundle 317 (G8)
            ready: x.kind == Kind320.kept);
    final status = f == null ? x.status : '${x.status} \u00b7 $f';
    return InkWell(
      key: ValueKey('chats221_row_${x.id}'),
      onTap: tap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(children: [
          AvatarPair307(names: x.names, size: 42, group: x.group),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.title, style: k.text(16, FontWeight.w700, k.ink, 1.2)),
              const SizedBox(height: 3),
              StatusLine320(status, x.tone,
                  key: (f != null || x.filesComing321) && r != null
                      ? ValueKey('requests317_files_${r.id}')
                      : ValueKey('chats320_status_${x.id}'),
                  icon: x.icon),
              // Bundle 321 (R1): files that can't come - a grey 2nd line.
              if (x.notHere321 > 0) ...[
                const SizedBox(height: 2),
                StatusLine320(
                    x.notHere321 == 1 ? L.t.fileNotAvailable321 : L.t.filesNotAvailable321('${x.notHere321}'),
                    Tone320.grey,
                    key: ValueKey('chats321_gone_${x.id}'),
                    icon: Icons.block_rounded),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          right,
        ]),
      ),
    );
  }

  /// "Files 3/13" / "Files ✓" while a Ready chat's files come (null = none).
  static String? _filesOf320({FileTrip317? files, required bool ready}) {
    if (!ready || files == null || files.total <= 0 || files.stopped) return null;
    return files.done ? L.t.filesDoneShort317 : L.t.filesShort317(files.here, files.wanted);
  }
}

/// Bundle 320 (R2): "just now" / "5 min" / "2 h" / "3 d" since a request
/// was made (the waiting line of a Now row).
abstract final class AdminConversationsScreenAge320 {
  static String of(String madeAt, [DateTime? now]) {
    final t = DateTime.tryParse(madeAt);
    if (t == null) return '';
    final d = (now ?? DateTime.now()).toUtc().difference(t.toUtc());
    if (d.inMinutes < 1) return L.t.justNow;
    if (d.inMinutes < 60) return L.t.ageMin320(d.inMinutes);
    if (d.inHours < 24) return L.t.ageH320(d.inHours);
    return L.t.ageD320(d.inDays);
  }
}

/// Bundle 320 (R3): what a Chats row shows - Open / New / Get chat / mine.
enum Kind320 { ready, kept, ask, mine }

/// Bundle 320 (R3): one chat of the list (server chat + its requests + its
/// kept copy merged).
class Row320 {
  const Row320({
    required this.id,
    required this.title,
    required this.names,
    required this.group,
    required this.pick,
    required this.kind,
    required this.status,
    required this.tone,
    this.open,
    this.icon,
    this.filesComing321 = false,
    this.notHere321 = 0,
  });

  /// Bundle 321 (R1): the text is here, files still on their way (blue
  /// words; counted under Coming, not Ready).
  final bool filesComing321;

  /// Bundle 321 (R1): files that can't come (grey 2nd line).
  final int notHere321;

  final String id;
  final String title;
  final List<String> names;
  final bool group;
  final ChatPick221? pick;
  final Kind320 kind;
  final String status;
  final Tone320 tone;

  /// The request Open / a row tap opens (null = none).
  final ChatRequestRow221? open;
  final IconData? icon;
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


/// Bundle 313 (E2): the Live card's clip. Left / right = the screen edges
/// (the 16 dp page padding), up / down = room for the card shadow
/// (`K307.shadow`: blur 34, 14 dp down).
class ShadowRoom313 extends CustomClipper<Rect> {
  const ShadowRoom313();

  static const double side = 16;
  static const double up = 40;
  static const double down = 56;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-side, -up, size.width + side, size.height + down);

  @override
  bool shouldReclip(ShadowRoom313 oldClipper) => false;
}
