import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:locallink/core/models/group_event.dart';
import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:locallink/core/widgets/unread_bar_304.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/kept_copy_318.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';
import 'package:locallink/features/admin/presentation/widgets/viewer_bubbles310.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 221 (mock A-3): the copy of a chat the phones sent. Route tag per
/// message, grey "Deleted by user", greyed "Outside the dates (phone
/// clock)", thumbnails + Get full photo, the parts bar while the rest is on
/// the way. Long-press → Copy text / Delete completely; menu → Delete
/// (range) / Close.
/// Bundle 307 (B9): round header, a progress card (ring + "28 of 40 parts"
/// -> "Ready to read", then it shrinks away), iOS bubbles. The route words
/// are no longer shown; the class stays so nothing else breaks.
/// Route words, same as the web (`ROUTE221`).
abstract final class AdminChatViewerScreenRoutes {
  static String word(String r) => switch (r) {
        'server' => 'Server',
        'wifi_direct' || 'direct' => L.t.wiFiDirect,
        'lan' => 'Local Wi-Fi',
        'mesh' => L.t.mesh,
        _ => '',
      };
}

class AdminChatViewerScreen extends StatefulWidget {
  const AdminChatViewerScreen({super.key, required this.service, required this.request, this.view});

  final ChatRequests221 service;
  final ChatRequestRow221 request;

  /// Tests: a ready view (no loading).
  final ChatAnswerView? view;

  /// Bundle 310 (V4) tests: plays a voice note file (returns its length in
  /// ms); null = the phone's own voice player (`locallink/voice_notes`).
  @visibleForTesting
  static Future<int?> Function(String path)? playForTest;

  @override
  State<AdminChatViewerScreen> createState() => _AdminChatViewerScreenState();
}

class _AdminChatViewerScreenState extends State<AdminChatViewerScreen> {
  ChatAnswerView? _view;
  String _error = '';
  Timer? _poll;

  // B9: the progress card turns "Ready to read" when the last part lands,
  // then shrinks away after 3 s.
  bool _sawHalf = false;
  bool _readyGone = false;
  Timer? _readyTimer;

  // Bundle 310 (V4): voice notes - the Get file request of each file of
  // this chat, the one playing now, and where the play position is.
  Map<String, ChatRequestRow221> _files310 = <String, ChatRequestRow221>{};
  final Set<String> _asked310 = <String>{};
  Timer? _filePoll310;
  String _playing310 = '';
  String _loading310 = '';
  int _playMs310 = 0;
  int _playLen310 = 0;
  Timer? _playTimer310;
  final Set<String> _runStart310 = <String>{};
  static const MethodChannel _voice310 = MethodChannel('locallink/voice_notes');

  @override
  void initState() {
    super.initState();
    _view = widget.view;
    _noteProgress();
    if (_view == null) unawaited(_reload319());
    ChatAnswerCarrier.progress.addListener(_changed);
    FileQueue317.trips.addListener(_files317Changed);
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!(_view?.complete ?? false)) unawaited(_reload319());
    });
    if (widget.view == null) unawaited(_loadFiles310());
  }

  /// V4: the Get file requests of this chat (ready ones can play here).
  Future<void> _loadFiles310() async {
    try {
      // Bundle 318 (K8): files of the whole kept copy (full + new-only
      // requests) and files already kept here - never asked twice.
      final family = await widget.service.family318(widget.request.id);
      final kept = await widget.service.keptFileIds318();
      if (mounted) {
        _family318 = family;
        _keptFiles318 = kept;
      }
      final all = await widget.service.requests();
      final out = <String, ChatRequestRow221>{};
      for (final r in all) {
        if (r.action != 'get_file' || !family.contains(r.parent) || r.fileId.isEmpty) continue;
        if (r.state == 'cancelled') continue;
        final old = out[r.fileId];
        if (old == null || (!_ready310(old) && (_ready310(r) || r.madeAt.compareTo(old.madeAt) > 0))) out[r.fileId] = r;
      }
      if (!mounted) return;
      setState(() => _files310 = out);
      final waiting = _asked310.any((f) => !_ready310(out[f])) || out.values.any((r) => !_ready310(r));
      _filePoll310?.cancel();
      _filePoll310 = waiting ? Timer(const Duration(seconds: 10), () => unawaited(_loadFiles310())) : null;
    } catch (_) {}
  }

  // Bundle 317 (A): here = every part here (`done` = the phone only answered).
  static bool _ready310(ChatRequestRow221? r) => r != null && r.of > 0 && r.parts >= r.of;

  /// V4: play / pause a voice note that came from the phone.
  Future<void> _playVoice310(ChatRequestRow221 r) async {
    if (_loading310.isNotEmpty) return;
    if (_playing310 == r.fileId) {
      _playTimer310?.cancel();
      unawaited(_voice310.invokeMethod<void>('pause').catchError((Object _) {}));
      setState(() => _playing310 = '');
      return;
    }
    await _stopVoice310();
    if (!mounted) return;
    setState(() => _loading310 = r.fileId);
    try {
      final bytes = await widget.service.fileBytes(r);
      if (bytes == null || bytes.isEmpty) throw StateError(L.t.couldNotGetItNow);
      final safe = r.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File('${Directory.systemTemp.path}/admin_voice310_$safe.m4a');
      await file.writeAsBytes(bytes, flush: true);
      final play = AdminChatViewerScreen.playForTest;
      final len = play != null ? await play(file.path) : await _voice310.invokeMethod<int>('play', {'path': file.path});
      if (!mounted) return;
      setState(() {
        _loading310 = '';
        _playing310 = r.fileId;
        _playMs310 = 0;
        _playLen310 = len ?? 0;
      });
      _playTimer310?.cancel();
      if ((len ?? 0) > 0) {
        _playTimer310 = Timer.periodic(const Duration(milliseconds: 120), (t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          setState(() {
            _playMs310 += 120;
            if (_playMs310 >= _playLen310) {
              _playMs310 = 0;
              _playing310 = '';
              t.cancel();
            }
          });
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading310 = '');
      adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _stopVoice310() async {
    _playTimer310?.cancel();
    if (_playing310.isNotEmpty) {
      _playing310 = '';
      await _voice310.invokeMethod<void>('stop').catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    ChatAnswerCarrier.progress.removeListener(_changed);
    FileQueue317.trips.removeListener(_files317Changed);
    _reload319.close();
    _poll?.cancel();
    _readyTimer?.cancel();
    _allHereTimer317?.cancel();
    _filePoll310?.cancel();
    _list318.dispose();
    unawaited(_stopVoice310());
    // Bundle 310: the voice copies played here go with the screen.
    try {
      for (final f in Directory.systemTemp.listSync()) {
        if (f is File && (f.path.contains('admin_voice310_') || f.path.contains('admin_file317_'))) f.deleteSync();
      }
    } catch (_) {}
    super.dispose();
  }

  /// Bundle 319 (F7): a complete answer is not opened (decrypted) again on
  /// every part that lands elsewhere; other reloads are merged (max once
  /// per 2 s, one at a time).
  void _changed() {
    if (_view?.complete ?? false) return;
    unawaited(_reload319());
  }

  late final MergedRun319 _reload319 = MergedRun319(_load, gap: const Duration(seconds: 2));

  // Bundle 318 (K7/K8): the new-messages bar, the list, the copy's requests
  // and the files kept here.
  final GlobalKey _newBar318 = GlobalKey();
  final ScrollController _list318 = ScrollController();
  bool _scrolled318 = false;
  Set<String> _family318 = const {};
  Set<String> _keptFiles318 = const {};

  // Bundle 317 (G6): files come by themselves; the viewer only shows them.
  final Map<String, Uint8List> _bytes317 = <String, Uint8List>{};
  final Set<String> _loading317 = <String>{};
  bool _allHereGone317 = false;
  Timer? _allHereTimer317;

  void _files317Changed() {
    if (!mounted) return;
    setState(() {});
    final trip = FileQueue317.trips.value[widget.request.id];
    if (trip != null && trip.done && !trip.stopped && _allHereTimer317 == null) {
      _allHereTimer317 = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _allHereGone317 = true);
      });
    }
    unawaited(_loadFiles310());
  }

  /// The state of one file: the queue first, else the Get file rows here.
  FileView317 _view317(Map<String, dynamic> a) {
    final fileId = a['file_id']?.toString() ?? '';
    if (a['file_gone'] == true) return const FileView317(FileState317.gone);
    final size = a['size'] is num ? (a['size'] as num).toInt() : 0;
    if (size > 50 * 1024 * 1024) return const FileView317(FileState317.tooBig);
    FileView317? q = FileQueue317.instance?.viewsOf(widget.request.id)[fileId];
    for (final id in _family318) {
      q ??= FileQueue317.instance?.viewsOf(id)[fileId];
    }
    final row = _files310[fileId];
    if (row != null && _ready310(row)) return FileView317(FileState317.here, parts: row.parts, of: row.of, row: row);
    // Bundle 318 (K8): the bytes are kept on this phone already.
    if (_keptFiles318.contains(fileId)) {
      return FileView317(FileState317.here,
          parts: 1,
          of: 1,
          row: ChatRequestRow221(
              id: 'kept318_$fileId',
              action: 'get_file',
              parent: widget.request.id,
              fileId: fileId,
              state: 'done',
              parts: 1,
              of: 1));
    }
    if (q != null) return q;
    if (row != null) {
      if (row.refused == 'file_too_big') return FileView317(FileState317.tooBig, row: row);
      if (row.refused.isNotEmpty || row.empty) return FileView317(FileState317.gone, row: row);
      return FileView317(FileState317.coming, parts: row.parts, of: row.of, row: row);
    }
    return const FileView317(FileState317.next);
  }

  /// The answering phone's owner (for "Coming from kiran's phone").
  String get _who317 {
    final v = _view;
    final o = v == null ? '' : _owner255(v);
    return o.isNotEmpty ? o : (FileQueue317.trips.value[widget.request.id]?.from ?? '');
  }

  Future<Uint8List?> _bytesOf317(ChatRequestRow221 row) async {
    final have = _bytes317[row.fileId];
    if (have != null) return have;
    if (!_loading317.add(row.fileId)) return null;
    try {
      final b = await widget.service.fileBytes(row);
      if (b != null && b.isNotEmpty) _bytes317[row.fileId] = b;
      return b;
    } catch (_) {
      return null;
    } finally {
      _loading317.remove(row.fileId);
      if (mounted) setState(() {});
    }
  }

  /// Tap on a file that is here: photos full screen, others to the phone's apps.
  Future<void> _openFile317(Map<String, dynamic> a, ChatRequestRow221 row) async {
    final bytes = await _bytesOf317(row);
    if (bytes == null || !mounted) return;
    final type = a['type']?.toString() ?? '';
    if (type.startsWith('image/')) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (ctx) => Scaffold(
                key: const ValueKey('viewer317_photo_full'),
                backgroundColor: Colors.black,
                appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                body: Center(child: InteractiveViewer(maxScale: 6, child: Image.memory(bytes))),
              )));
      return;
    }
    try {
      final safe = Viewer310.shortName(a['name']?.toString() ?? 'file').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File('${Directory.systemTemp.path}/admin_file317_$safe');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path, mimeType: type.isEmpty ? null : type)]);
    } catch (error) {
      if (mounted) adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _load() async {
    try {
      final v = await widget.service.open(widget.request);
      if (mounted) {
        setState(() => _view = v);
        _noteProgress();
      }
    } catch (error) {
      if (mounted) setState(() => _error = L.en('$error'.replaceFirst('Bad state: ', '')));
    }
  }

  void _noteProgress() {
    final v = _view;
    if (v == null || v.empty || v.forAdminPhone) return;
    if (!v.complete) {
      _sawHalf = true;
      return;
    }
    if (_sawHalf && _readyTimer == null && !_readyGone) {
      _readyTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _readyGone = true);
      });
    }
  }

  ChatPick221? get _pick =>
      ChatPick221.fromRef(_view?.chat ?? widget.request.chat, label: widget.request.label);

  List<String> get _names =>
      widget.request.label.contains(' & ') ? widget.request.label.split(' & ') : [widget.request.label];

  String get _sub {
    final r = widget.request;
    final range = r.from.isEmpty ? L.t.fullChat : '${_day(r.from)} - ${_day(r.to)}';
    final v = _view;
    // Bundle 318 (K7): "Full chat · got 15 Nov 10:05 · +12 new today 10:43".
    if (v != null && v.fromKept318) {
      final kr = r.inside318 ? range : (v.keptFull318 ? L.t.fullChat : '${_day(v.from)} - ${_day(v.to)}');
      final got = L.t.viewerKept318(kr, Kept318.dayTime(v.keptGotAt318));
      final n = v.newIds318.length;
      return v.newOnly318 && n > 0 ? '$got \u00b7 ${L.t.plusNew318(n, whenSub216(v.keptNewAt318))}' : got;
    }
    final from = v == null ? '' : _owner255(v);
    return from.isEmpty ? range : L.t.fromSPhone(range, from);
  }

  /// Bundle 255 B7: the answering phone's owner: its name in the answer,
  /// else the name on its own messages, else the label name.
  String _owner255(ChatAnswerView v) {
    final named = v.fromName.trim();
    if (named.isNotEmpty && !isDefaultPhoneLabel255(named)) return named;
    for (final m in v.messages) {
      final n = m['sender_name']?.toString().trim() ?? '';
      if (n.isNotEmpty && v.fromDevice.isNotEmpty && m['sender'] == v.fromDevice) return n;
    }
    return '';
  }

  /// Bundle 255 B6: a message with no sender name (old apps, offline
  /// accounts) takes the name from the label "noshad & sajjad": the
  /// answering phone's side or the other one. '' = "Someone".
  String _nameFor255(ChatAnswerView v, Map<String, dynamic> m, bool right) {
    final names = [for (final n in _names) if (n.trim().isNotEmpty) n.trim()];
    if ((_pick?.isGroup ?? false) || names.length != 2) return '';
    final owner = _owner255(v);
    if (!right) return owner.isNotEmpty ? owner : names.first;
    if (owner.isEmpty) return names.last;
    final other = names.where((n) => n != owner).toList();
    return other.isEmpty ? '' : other.first;
  }

  /// Bundle 255 B8: header names in the same order as [_photoIds255]
  /// (answering phone's owner first).
  List<String> get _headerNames255 {
    final v = _view;
    final names = _names;
    if (v == null || names.length != 2 || _photoIds255 == null) return names;
    final owner = _owner255(v);
    return owner.isNotEmpty && names[1].trim() == owner ? [names[1], names[0]] : names;
  }

  /// Bundle 255 B8: device ids for the header photos (answering phone,
  /// then the other person) when both are known; null = letters.
  List<String>? get _photoIds255 {
    final v = _view;
    if (v == null || (_pick?.isGroup ?? false) || v.fromDevice.isEmpty) return null;
    for (final m in v.messages) {
      final s = m['sender']?.toString() ?? '';
      if (s.isNotEmpty && s != v.fromDevice) return [v.fromDevice, s];
    }
    return null;
  }

  static String _day(String d) {
    final t = DateTime.tryParse(d);
    return t == null ? d : dMMM216(t);
  }

  Future<void> _longPress(Map<String, dynamic> m) async {
    final c = A216.colors(context);
    final body = m['body']?.toString() ?? '';
    final pick = await showAdminSheet216<String>(context, builder: (ctx) {
      final t = A216Text.of(ctx);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (body.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(14)),
            child: Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.custom(16, FontWeight.w400, c.ink)),
          ),
        const SizedBox(height: 8),
        ListTile(
          key: const ValueKey('viewer221_copy'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.copy_rounded, color: c.ink2),
          title: Text(L.t.copyText, style: t.custom(17, FontWeight.w500, c.ink)),
          onTap: () => Navigator.of(ctx).pop('copy'),
        ),
        Divider(height: 1, color: c.div),
        ListTile(
          key: const ValueKey('viewer221_delete_one'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.delete_outline_rounded, color: c.red),
          title: Text(L.t.deleteCompletely, style: t.custom(17, FontWeight.w600, c.red)),
          subtitle: Text(L.t.fromEveryPhoneAlsoDeletedCopies, style: t.custom(14, FontWeight.w400, c.grey)),
          onTap: () => Navigator.of(ctx).pop('delete'),
        ),
      ]);
    });
    if (!mounted) return;
    if (pick == 'copy') {
      await Clipboard.setData(ClipboardData(text: body));
      if (mounted) adminSnack216(context, L.t.copied);
    } else if (pick == 'delete') {
      await _delete(scope: 'message', ids: [m['id']?.toString() ?? ''], count: 1);
    }
  }

  /// Menu → Delete: full / 7 / 30 days / dates, with counts from this copy.
  Future<void> _deleteSheet() async {
    final msgs = _view?.messages ?? const <Map<String, dynamic>>[];
    final known = _view != null && !_view!.empty;
    int countSince(int days) {
      final cut = DateTime.now().subtract(Duration(days: days));
      return msgs.where((m) => (DateTime.tryParse('${m['created_at']}') ?? DateTime(0)).isAfter(cut)).length;
    }

    final options = <(String, String, int)>[
      ('full', L.t.fullChat, msgs.length),
      ('7', L.t.last7Days, countSince(7)),
      ('30', L.t.last30Days, countSince(30)),
    ];
    var sel = 0;
    final choice = await showAdminSheet216<int>(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        final c = A216.colors(ctx);
        final t = A216Text(c);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(L.t.deleteCompletely, style: t.custom(20, FontWeight.w700, c.ink)),
          const SizedBox(height: 6),
          Text(L.t.fromEveryPhoneOfThisChat,
              style: t.custom(14, FontWeight.w400, c.grey, 1.4)),
          const SizedBox(height: 12),
          for (var i = 0; i < options.length; i++)
            InkWell(
              key: ValueKey('viewer221_scope_${options[i].$1}'),
              onTap: () => set(() => sel = i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  AdminRadio216(sel == i),
                  const SizedBox(width: 12),
                  Expanded(child: Text(options[i].$2, style: t.custom(16, FontWeight.w500, c.ink))),
                  Text(known ? '${options[i].$3}' : L.t.countUnknown, style: t.custom(14, FontWeight.w400, c.grey)),
                ]),
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: AdminButton216(
                known ? L.t.deleteMessagesCompletely(options[sel].$3) : L.t.deleteCompletely,
                key: const ValueKey('viewer221_delete_go'),
                kind: A216ButtonKind.danger,
                height: 52,
                onTap: () => Navigator.of(ctx).pop(sel)),
          ),
        ]);
      });
    });
    if (choice == null || !mounted) return;
    final o = options[choice];
    await _delete(
        scope: o.$1 == 'full' ? 'full' : 'range', range: o.$1 == 'full' ? '' : o.$1, count: known ? o.$3 : -1);
  }

  Future<void> _delete({required String scope, List<String> ids = const [], String range = '', required int count}) async {
    final pick = _pick;
    if (pick == null) return;
    final ok = await confirmAdmin216(context,
        title: count < 0 ? L.t.deleteCompletely2 : L.t.deleteMessageCompletely(count, count == 1 ? '' : 's'),
        body: L.t.goneFromEveryPhoneAndThe,
        yes: L.t.deleteCompletely,
        danger: true,
        yesKey: const ValueKey('viewer221_delete_yes'));
    if (!ok || !mounted) return;
    try {
      final words = await widget.service.deleteCompletely(pick, scope: scope, ids: ids, range: range);
      if (mounted) adminSnack216(context, words);
    } catch (error) {
      if (mounted) adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _close() async {
    await widget.service.close(widget.request);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final v = _view;
    final k = K307.of(context);
    Widget round(Widget child, {Key? key}) => Material(
          key: key,
          color: k.card,
          shape: CircleBorder(side: BorderSide(color: k.dark ? k.cardEdge : Colors.transparent)),
          child: child,
        );
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              round(InkWell(
                key: const ValueKey('viewer307_back'),
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(width: 38, height: 38, child: Icon(Icons.chevron_left_rounded, color: k.ink, size: 26)),
              )),
              const SizedBox(width: 10),
              ChatAvatars221(
                  names: _headerNames255,
                  group: _pick?.isGroup ?? false,
                  size: 44,
                  photoIds: _photoIds255),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.request.label.isEmpty ? L.t.chat : widget.request.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(16, FontWeight.w700, k.ink, 1.2)),
                  Text(_sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(12.5, FontWeight.w400, k.grey, 1.25)),
                ]),
              ),
              const SizedBox(width: 6),
              round(SizedBox(width: 38, height: 38, child: PopupMenuButton<String>(
                key: const ValueKey('viewer221_menu'),
                icon: Icon(Icons.more_vert_rounded, color: k.ink, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(minimumSize: const Size(38, 38), fixedSize: const Size(38, 38)),
                onSelected: (x) => x == 'delete' ? _deleteSheet() : _close(),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'delete', child: Text(L.t.deleteChatCompletely)),
                  PopupMenuItem(value: 'close', child: Text(L.t.closeDeleteThisCopy)),
                ],
              ))),
            ]),
          ),
          if (v != null && !v.empty && !v.forAdminPhone) _progressCard(v),
          if (v != null && v.complete && !v.forAdminPhone) _filesStrip317(),
          Expanded(
            child: v == null
                ? Center(
                    child: _error.isNotEmpty
                        ? Padding(padding: const EdgeInsets.all(24), child: Text(_error, style: t.rowSub))
                        : const CircularProgressIndicator(strokeWidth: 2))
                : _body(v),
          ),
        ]),
      ),
    );
  }

  /// B9: "28 of 40 parts · the rest is on the way" + ring; all in ->
  /// "Ready to read" with a green edge, then it shrinks away after 3 s.
  Widget _progressCard(ChatAnswerView v) {
    final k = K307.of(context);
    final row = ChatRequestRow221(
        id: v.id, action: 'get_chat', parts: v.parts, of: v.of, state: v.complete ? 'done' : 'pending');
    final step = RequestStep307.of(row);
    final show = !v.complete || (_sawHalf && !_readyGone);
    final Widget inner;
    if (!v.complete) {
      inner = Container(
        key: const ValueKey('viewer221_parts'),
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: k.cardBox(),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(L.t.ofPartsTheRestIsOn(v.parts, v.of), style: k.text(14.5, FontWeight.w700, k.ink, 1.3)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: v.of <= 0 ? 0 : (v.parts / v.of).clamp(0, 1).toDouble()),
                    duration: Motion307.d(context, 400),
                    builder: (context, x, _) => LinearProgressIndicator(
                      key: const ValueKey('parts221_bar'),
                      value: x,
                      backgroundColor: k.track,
                      color: k.blue,
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          ProgressRing307(step: step, size: 42),
        ]),
      );
    } else {
      inner = Container(
        key: const ValueKey('viewer307_ready'),
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: k.cardBox(edge: K307.ok, edgeWidth: 2),
        child: Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: step.bigBefore),
                TextSpan(text: step.highlight, style: TextStyle(color: k.green, fontWeight: FontWeight.w800)),
                TextSpan(text: step.bigAfter),
              ]),
              style: k.text(16, FontWeight.w700, k.ink, 1.25),
            ),
          ),
          ProgressRing307(step: step, size: 42),
        ]),
      );
    }
    return AnimatedSize(
      duration: Motion307.d(context, 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: show ? inner : const SizedBox(width: double.infinity),
    );
  }

  /// Bundle 317 (G8): the files of this chat on the top: "3 of 13 files ·
  /// 6.2 of 24 MB", from / via, a bar; "All files here" fades after 3 s.
  Widget _filesStrip317() {
    final trip = FileQueue317.trips.value[widget.request.id];
    final k = K307.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = A216Text.of(context);
    final show = trip != null && trip.total > 0 && !(trip.done && _allHereGone317) && !trip.stopped;
    Widget inner = const SizedBox(width: double.infinity);
    if (show) {
      final done = trip.done;
      final color = done ? k.green : (trip.waiting ? k.orange : k.blue);
      final line1 = done
          ? L.t.allFilesHere317
          : '${L.t.filesOf317(trip.here, trip.wanted)} \u00b7 ${L.t.mbOf317(size216(trip.bytesHere), size216(trip.bytesTotal))}';
      final line2 = [
        if (trip.waiting && !done) L.t.filesWaiting317,
        if (trip.from.isNotEmpty) L.t.fromPhone317(trip.from),
        if (trip.via.isNotEmpty) L.t.viaName317(trip.via),
      ].join(' \u00b7 ');
      inner = Container(
        key: const ValueKey('viewer317_files_strip'),
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: k.cardBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(done ? Icons.check_circle_rounded : Icons.photo_library_rounded, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(line1, style: t.custom(14, FontWeight.w700, cs.onSurface, 1.3))),
            // Bundle 317 (G7): Stop files (the files not here yet stop).
            if (!done)
              TextButton(
                key: const ValueKey('viewer317_stop_files'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 36),
                  foregroundColor: cs.error,
                ),
                onPressed: () =>
                    unawaited(FileQueue317.instance?.stopFiles(widget.request.id).catchError((Object _) {})),
                child: Text(L.t.stopFiles317, style: t.custom(13, FontWeight.w600, cs.error, 1.2)),
              ),
          ]),
          if (line2.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(line2, style: t.custom(12, FontWeight.w400, cs.onSurface.withValues(alpha: 0.62), 1.3)),
          ],
          if (!done) ...[
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(minHeight: 3, value: trip.fill, backgroundColor: k.track, color: color),
            ),
          ],
        ]),
      );
    }
    return AnimatedSize(
      duration: Motion307.d(context, 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: inner,
    );
  }

  Widget _body(ChatAnswerView v) {
    final c = A216.colors(context);
    final t = A216Text(c);
    if (v.forAdminPhone) {
      return _note(L.t.madeOnAdminPhone304);
    }
    if (v.empty) {
      // Bundle 317 (A): the phone answered, the chat is not here yet.
      final r = widget.request;
      if (r.state == 'done') {
        final who = r.fromName.isNotEmpty ? L.t.namesPhone317(r.fromName) : L.t.thePhone317;
        return _note(
            '${L.t.phoneAnswered317(who)}\n${r.action == 'get_file' ? L.t.fileOnTheWay317 : L.t.chatOnTheWay317}',
            key: const ValueKey('viewer317_answered'));
      }
      return _note(L.t.waitingForPhoneOfChat304);
    }
    final items = <Widget>[];
    String lastDay = '';
    var shown = 0; // E: batches of 3 fade in
    // Bundle 318 (K7): the "12 new messages" bar above the first new one.
    final news318 = v.newOnly318 ? v.newIds318.toSet() : const <String>{};
    var barAt318 = -1;
    // Bundle 310 (V4): a group shows the name on the first bubble of a run.
    _runStart310.clear();
    String? lastSender;
    for (final m in v.messages) {
      final at = DateTime.tryParse('${m['created_at']}')?.toLocal();
      final day = at == null ? '' : dMMM216(at);
      final sender = '${m['sender'] ?? m['sender_name'] ?? ''}';
      if (sender != lastSender || (day.isNotEmpty && day != lastDay)) _runStart310.add('${m['id']}');
      lastSender = sender;
      if (day.isNotEmpty && day != lastDay) {
        lastDay = day;
        items.add(Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
            child: Text(day, style: t.custom(11.5, FontWeight.w500, Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ));
      }
      // Bundle 317 (B): a group event ("kiran created group ...") is a
      // centred system line, never raw `llev:v1:` code; the next bubble
      // starts a new run (so it shows its name).
      final event = GroupEvent.parse(m['body']?.toString() ?? '');
      if (event != null) {
        lastSender = null;
        items.add(Batch307(batch: shown++ ~/ 3, child: _systemLines317(v, m, event)));
        continue;
      }
      if (barAt318 < 0 && news318.contains('${m['id']}')) {
        barAt318 = items.length;
        items.add(UnreadBar304(
            key: _newBar318,
            count: news318.length,
            bleed: 14,
            text: news318.length == 1 ? L.t.newMessage : L.t.newMessages2(news318.length)));
      }
      items.add(Batch307(batch: shown++ ~/ 3, child: _bubble(v, m)));
    }
    if (barAt318 >= 0 && !_scrolled318) {
      _scrolled318 = true;
      final at = barAt318;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_list318.hasClients) return;
        _list318.jumpTo(_list318.position.maxScrollExtent);
        showUnreadBar304(_list318, _newBar318, at);
      });
    }
    return Column(children: [
      Expanded(
        // Bundle 310 (V4): the app's chat surface behind the bubbles.
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: ListView(
          key: const ValueKey('viewer221_list'),
          controller: _list318,
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          children: [
            if (v.trimmed)
              _info(L.t.someOldPicturesWereLeftOut),
            if (v.messages.isEmpty) _info(L.t.noMessagesInTheseDates),
            ...items,
          ],
        ),
        ),
      ),
    ]);
  }

  /// Bundle 317 (B): names for a group event - the people in this copy
  /// (sender id -> name), then the names inside the event.
  Widget _systemLines317(ChatAnswerView v, Map<String, dynamic> m, GroupEvent event) {
    final cs = Theme.of(context).colorScheme;
    final t = A216Text.of(context);
    final names = <String, String>{};
    for (final x in v.messages) {
      final id = x['sender']?.toString() ?? '';
      final n = x['sender_name']?.toString().trim() ?? '';
      if (id.isNotEmpty && n.isNotEmpty) names[id] = n;
    }
    final lines = event.lines('', nameOf: (id) => names[id]);
    return Padding(
      key: ValueKey('viewer317_sys_${m['id']}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Center(
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .88),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(11)),
                child: Text(line, textAlign: TextAlign.center, style: t.custom(12, FontWeight.w400, cs.onSurfaceVariant, 1.35)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _note(String text, {Key? key}) {
    final t = A216Text.of(context);
    return Center(key: key, child: Padding(padding: const EdgeInsets.all(28), child: Text(text, textAlign: TextAlign.center, style: t.emptyBody)));
  }

  Widget _info(String text) {
    final c = A216.colors(context);
    final t = A216Text(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: t.custom(13, FontWeight.w400, c.grey)),
    );
  }

  Widget _bubble(ChatAnswerView v, Map<String, dynamic> m) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final k = K307.of(context);
    final cs = Theme.of(context).colorScheme;
    final group = _pick?.isGroup ?? false;
    // The answering phone's owner on the left, the other person on the right.
    final right = !group && v.fromDevice.isNotEmpty && m['sender'] != v.fromDevice;
    final deleted = (m['deleted_at']?.toString() ?? '').isNotEmpty;
    final outside = m['outside'] == true;
    final sent = m['sender_name']?.toString().trim() ?? '';
    final name = sent.isNotEmpty ? sent : _nameFor255(v, m, right);
    final at = DateTime.tryParse('${m['created_at']}')?.toLocal();
    final time = at == null ? '' : TimeOfDay.fromDateTime(at).format(context);
    final body = m['body']?.toString() ?? '';
    final atts = [for (final a in (m['attachments'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
    // Bundle 310 (V4): like the app's Messages screen - grey bubbles (left =
    // surfaceContainerHighest, right = surfaceContainer), the time inside at
    // the bottom right, the name only in groups on the first bubble of a run.
    final bg = right ? cs.surfaceContainer : cs.surfaceContainerHighest;
    // Bundle 317 (C): a deleted message keeps its bubble; the text is faded
    // (55 %) and one small red line says "Deleted 11:41".
    final ink = deleted ? cs.onSurface.withValues(alpha: 0.55) : cs.onSurface;
    final soft = cs.onSurface.withValues(alpha: 0.62);
    final shown = name.isEmpty ? L.t.someone : name;
    final showName = group && _runStart310.contains('${m['id']}');
    const r = Radius.circular(18);
    const tail = Radius.circular(6);
    final timeStyle = t.custom(11, FontWeight.w500, soft);
    final bubble = GestureDetector(
      key: ValueKey('viewer221_msg_${m['id']}'),
      onLongPress: () => _longPress(m),
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 2.5),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
              topLeft: r, topRight: r, bottomLeft: right ? r : tail, bottomRight: right ? tail : r),
        ),
        child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(shown,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: t.custom(12.5, FontWeight.w700, avatarColor221(shown))),
            ),
          for (final a in _oneEach317(atts))
            deleted ? Opacity(opacity: 0.55, child: _attachment(m, a)) : _attachment(m, a),
          if (body.isNotEmpty)
            BubbleText310(
                text: body + ((m['cut'] == true) ? ' …' : ''),
                time: time,
                style: t.custom(15, FontWeight.w400, ink, 1.35),
                timeStyle: timeStyle),
          if (deleted) ...[
            const SizedBox(height: 3),
            Row(
              key: ValueKey('viewer221_deleted_${m['id']}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_rounded, size: 13, color: k.dark ? const Color(0xFFF97066) : c.red),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(_deletedWords(m['deleted_at'].toString(), m['created_at']?.toString() ?? ''),
                      style: t.custom(12, FontWeight.w600, k.dark ? const Color(0xFFF97066) : c.red)),
                ),
              ],
            ),
          ],
          if (outside) ...[
            const SizedBox(height: 4),
            Text(L.t.outsideTheDatesPhoneClock, style: t.custom(12, FontWeight.w500, soft)),
          ],
          // No text: the time sits alone on the last line, right.
          SizedBox(height: body.isEmpty ? 16 : 2),
        ]),
        if (body.isEmpty) Positioned(right: 0, bottom: 2, child: Text(time, style: timeStyle)),
        ]),
      ),
    );
    return Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(opacity: outside ? 0.5 : 1, child: bubble),
    );
  }

  /// Bundle 317 (C): "Deleted 11:41"; the date only when it is another day
  /// than the message.
  static String _deletedWords(String iso, [String sentIso = '']) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return L.t.deletedByUser;
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final sent = DateTime.tryParse(sentIso)?.toLocal();
    final sameDay = sent != null && sent.year == t.year && sent.month == t.month && sent.day == t.day;
    return L.t.deletedAt317(sameDay ? hm : '${dMMM216(t)} $hm');
  }

  /// Bundle 317 (D): one row per file id (the same file twice in one
  /// message is shown once); no id -> same name + size + type once.
  static List<Map<String, dynamic>> _oneEach317(List<Map<String, dynamic>> atts) {
    final seen = <String>{};
    return [
      for (final a in atts)
        if (seen.add((a['file_id']?.toString() ?? '').isNotEmpty
            ? 'id:${a['file_id']}'
            : 'nt:${a['name']}|${a['size']}|${a['type']}'))
          a,
    ];
  }

  /// Bundle 317 (D / G6): photo / video / file - no Get button. Next in
  /// line / Coming x / y / shows (tap opens) / Not on the phone any more /
  /// Too big to bring. Video icon for videos; size under the name.
  Widget _attachment(Map<String, dynamic> m, Map<String, dynamic> a) {
    final cs = Theme.of(context).colorScheme;
    final t = A216Text.of(context);
    final k = K307.of(context);
    Uint8List? thumb;
    try {
      final s = a['thumb']?.toString() ?? '';
      if (s.isNotEmpty) thumb = base64.decode(s);
    } catch (_) {}
    final type = a['type']?.toString() ?? '';
    final name = a['name']?.toString() ?? '';
    if (Viewer310.isAudio(type, name)) return _voice310Row(m, a, a['file_gone'] == true);
    final fileId = a['file_id']?.toString() ?? '';
    final size = a['size'] is num ? (a['size'] as num).toInt() : 0;
    final video = type.startsWith('video/');
    final photo = type.startsWith('image/');
    final sizeWords = size <= 0
        ? ''
        : (video ? L.t.videoSize317(size216(size)) : (photo ? L.t.photoSize317(size216(size)) : L.t.fileSize317(size216(size))));
    final st = _view317(a);
    final who = _who317;
    final soft = cs.onSurface.withValues(alpha: 0.62);
    final icon = video ? Icons.videocam_rounded : (photo ? Icons.image_rounded : Icons.insert_drive_file_rounded);
    final row = st.row;
    if (st.state == FileState317.here && row != null) {
      final bytes = photo ? _bytes317[fileId] : null;
      if (photo && bytes == null) unawaited(_bytesOf317(row));
      final Widget pic = bytes != null
          ? Image.memory(bytes, width: 220, height: 160, fit: BoxFit.cover, gaplessPlayback: true)
          : thumb != null
              ? Image.memory(thumb, width: 220, height: 160, fit: BoxFit.cover, gaplessPlayback: true)
              : Container(
                  width: 220,
                  height: 120,
                  color: cs.surfaceContainerHigh,
                  child: Icon(icon, color: cs.onSurfaceVariant, size: 30));
      return Padding(
        key: ValueKey('viewer317_file_${fileId}_here'),
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          onTap: () => unawaited(_openFile317(a, row)),
          borderRadius: BorderRadius.circular(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(alignment: Alignment.center, children: [
                pic,
                if (video)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                  ),
              ]),
            ),
            const SizedBox(height: 3),
            Text([Viewer310.shortName(name.isEmpty ? L.t.file : name), sizeWords].where((x) => x.isNotEmpty).join(' \u00b7 '),
                maxLines: 2, style: t.custom(12, FontWeight.w400, soft, 1.3)),
          ]),
        ),
      );
    }
    final card = Row(mainAxisSize: MainAxisSize.min, children: [
      if (thumb != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(thumb, width: 44, height: 44, fit: BoxFit.cover, gaplessPlayback: true),
        )
      else
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: cs.onSurfaceVariant, size: 22),
        ),
      const SizedBox(width: 10),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(Viewer310.shortName(name.isEmpty ? L.t.file : name),
              maxLines: 2, style: t.custom(13.5, FontWeight.w600, cs.onSurface, 1.3)),
          if (sizeWords.isNotEmpty) Text(sizeWords, style: t.custom(12, FontWeight.w400, soft, 1.3)),
        ]),
      ),
    ]);
    Widget? below;
    switch (st.state) {
      case FileState317.next || FileState317.coming:
        final coming = st.state == FileState317.coming;
        final words = coming
            ? (who.isEmpty ? L.t.coming317 : L.t.comingFrom317(who))
            : (who.isEmpty ? L.t.nextInLine317 : L.t.nextInLineFrom317(who));
        below = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text(words, style: t.custom(12, FontWeight.w500, soft, 1.3))),
            if (st.of > 0) Text('${st.parts} / ${st.of}', style: t.custom(12, FontWeight.w600, soft)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              key: ValueKey('viewer317_bar_$fileId'),
              minHeight: 3,
              value: st.of > 0 ? (st.parts / st.of).clamp(0, 1).toDouble() : 0,
              backgroundColor: k.track,
              color: k.blue,
            ),
          ),
        ]);
      case FileState317.gone || FileState317.tooBig || FileState317.stopped:
        final words = switch (st.state) {
          FileState317.tooBig => L.t.tooBigToBring317,
          FileState317.stopped => L.t.filesStopped317,
          // The phone's own 60-day clean-up (flag in the chat) keeps its words.
          _ when a['file_gone'] == true => L.t.fileRemovedAfter60DaysThumbnail,
          _ => who.isEmpty ? L.t.notOnThePhoneAnyMore317 : L.t.notOnPhoneAnyMore317(who),
        };
        below = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.block_rounded, size: 13, color: soft),
          const SizedBox(width: 4),
          Flexible(child: Text(words, style: t.custom(12, FontWeight.w500, soft, 1.3))),
        ]);
      case FileState317.here:
        break;
    }
    return Padding(
      key: ValueKey('viewer317_file_${fileId}_${st.state.name}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 210),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          card,
          if (below != null) ...[const SizedBox(height: 7), below],
        ]),
      ),
    );
  }

  /// Bundle 310 (V4): a voice note = the voice row (bars + length). Get =
  /// ask the phones (as Get file); when the file is here it plays here.
  Widget _voice310Row(Map<String, dynamic> m, Map<String, dynamic> a, bool gone) {
    final fileId = a['file_id']?.toString() ?? '';
    final voice = a['voice'] is Map ? Map<String, dynamic>.from(a['voice'] as Map) : const <String, dynamic>{};
    final levels = Viewer310.bars(voice['bars']);
    final ms = voice['ms'] is num ? (voice['ms'] as num).toInt() : 0;
    final size = a['size'] is num ? (a['size'] as num).toInt() : 0;
    final f = _files310[fileId];
    var label = ms > 0 ? Viewer310.clock(ms) : (size > 0 ? size216(size) : '');
    VoiceState310 state;
    double played = 0;
    double? progress;
    VoidCallback? onTap;
    // Bundle 317 (G6): no Get button - the voice note comes by itself.
    final st = _view317(a);
    if (gone || st.state == FileState317.gone || st.state == FileState317.tooBig || st.state == FileState317.stopped) {
      state = VoiceState310.gone;
      final who = _who317;
      label = switch (st.state) {
        FileState317.tooBig => L.t.tooBigToBring317,
        FileState317.stopped => L.t.filesStopped317,
        _ when gone => L.t.fileRemovedAfter60DaysThumbnail,
        _ => who.isEmpty ? L.t.notOnThePhoneAnyMore317 : L.t.notOnPhoneAnyMore317(who),
      };
    } else if (_loading310 == fileId) {
      state = VoiceState310.getting;
    } else if (f != null && _ready310(f)) {
      final playing = _playing310 == fileId;
      state = playing ? VoiceState310.playing : VoiceState310.ready;
      if (playing) {
        final len = _playLen310 > 0 ? _playLen310 : ms;
        played = len > 0 ? _playMs310 / len : 0;
        label = '${Viewer310.clock(_playMs310)} / ${Viewer310.clock(len)}';
      }
      onTap = () => unawaited(_playVoice310(f));
    } else if (f != null || _asked310.contains(fileId)) {
      state = VoiceState310.getting;
      if (f != null && f.of > 0) {
        progress = f.parts / f.of;
        label = '${f.parts} / ${f.of}';
      }
    } else {
      state = VoiceState310.getting;
      progress = 0;
      label = L.t.nextInLine317;
    }
    return Padding(
      key: ValueKey('viewer310_voice_$fileId'),
      padding: const EdgeInsets.only(bottom: 2),
      child: VoiceRow310(state: state, levels: levels, label: label, played: played, progress: progress, onTap: onTap),
    );
  }
}
