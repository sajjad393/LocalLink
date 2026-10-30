import 'package:flutter/material.dart';

import 'dart:async';

import 'package:locallink/core/widgets/brand_gradient_fab.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/data/models/call_session.dart'
    show CallSession;
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/features/calls/data/services/call_preflight_exception.dart';
import 'package:locallink/features/calls/presentation/widgets/call_history_tile.dart';
import 'package:locallink/features/connectivity/presentation/widgets/connection_status_indicator.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';

class CallsScreen extends StatefulWidget {
  final CallBloc controller;
  final String selfId;

  /// Same live connectivity chip the Chats tab shows in its app bar.
  final ConnectivityBloc connectivityController;
  final VoidCallback onNewCall;

  const CallsScreen({
    super.key,
    required this.controller,
    required this.selfId,
    required this.connectivityController,
    required this.onNewCall,
  });

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.refreshHistory();
  }

  String _peerId(CallRecord call) => call.peerId(widget.selfId);

  String _title(CallRecord call) {
    // Fresh directory nickname wins; the name frozen into the record at call
    // time (Bundle 130) is the offline-safe fallback. "Unknown user" is now
    // the last resort, not the default.
    final live = widget.controller.deviceNames[_peerId(call)];
    if (live != null && live.isNotEmpty) return live;
    if (call.peerName.isNotEmpty) return call.peerName;
    return 'Unknown user';
  }

  bool _isMissed(CallRecord call) =>
      (call.status == 'missed' || call.status == 'ringing') &&
      !call.isOutgoing(widget.selfId);

  String _status(CallRecord call) => switch (call.status) {
        'connected' => 'Completed',
        'rejected' => call.endReason == 'busy' ? 'Busy' : 'Declined',
        'missed' => 'Missed',
        'canceled' => 'Canceled',
        'failed' => 'Failed',
        'ringing' => 'No answer',
        _ => call.durationSeconds > 0 ? 'Completed' : 'No answer',
      };

  String _duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  String _dayLabel(DateTime value) {
    final now = DateTime.now();
    final sameDay = (DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    if (sameDay(value, now)) return 'Today';
    if (sameDay(value, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return '${value.day}/${value.month}/${value.year}';
  }

  String _timeLabel(DateTime v) {
    final h = v.hour % 12 == 0 ? 12 : v.hour % 12;
    final m = v.minute.toString().padLeft(2, '0');
    return '$h:$m ${v.hour >= 12 ? 'PM' : 'AM'}';
  }

  bool _starting = false;

  String _cleanError(Object error) {
    if (error is CallPreflightException) return error.userMessage;
    return cleanBlocError(error);
  }

  Future<void> _openCallScreen(CallSession session, String reason) async {
    // Bundle 146: never stack a second call screen for the same call.
    if (CallScreen.visibleCallId == session.id) return;
    AppLogger.info('CALL_SCREEN_OPEN', detail: 'reason=$reason call=${session.id}');
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CallScreen(controller: widget.controller, initialSession: session),
      ),
    );
  }

  /// Bundle 146: the Calls tab call button now behaves like Home/Chat:
  /// a live call is resumed, a new call opens the call screen right away
  /// ("Calling…"), and failures show a message instead of nothing.
  Future<void> _redial(CallRecord call) async {
    final peerId = _peerId(call);
    if (peerId.isEmpty || _starting) return;
    final live = widget.controller.session;
    if (live != null && !live.isFinished) {
      await _openCallScreen(live, 'calls_tab_resume');
      return;
    }
    _starting = true;
    try {
      await widget.controller.startCall(
        Device(
          id: peerId,
          // Name resolution is refreshed once the session page shows;
          // redial is accepted even with the provisional name.
          name: _title(call),
          platform: 'android',
          createdAt: '',
          lastSeenAt: DateTime.now().toIso8601String(),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_cleanError(error))),
        );
      }
      return;
    } finally {
      _starting = false;
    }
    if (!mounted) return;
    final session = widget.controller.session;
    if (session == null || session.isFinished) return;
    await _openCallScreen(session, 'calls_tab');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LocalLinkBlocBuilder<CallBloc, CallState>(
      bloc: widget.controller,
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Calls'),
          actions: [
            ConnectionStatusIndicator(
                controller: widget.connectivityController),
            IconButton(
              tooltip: 'Refresh calls',
              onPressed: widget.controller.refreshHistory,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        floatingActionButton: BrandGradientFab(
          heroTag: 'calls_fab',
          tooltip: 'New call',
          // Bundle 104: brand-gradient FAB (People tab look) + modern icon.
          icon: Icons.add_ic_call_rounded,
          onPressed: widget.onNewCall,
        ),
        body: Column(children: [
          _CallInProgressBar(controller: widget.controller),
          Expanded(
            child: RefreshIndicator(
          onRefresh: widget.controller.refreshHistory,
          child: state.history.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      // Fill the viewport so the empty view centers like the
                      // Chats tab, instead of sitting on hardcoded offsets.
                      height: MediaQuery.of(context).size.height * 0.62,
                      child: Center(
                      child: LocalLinkEmptyView(
                        icon: Icons.call_outlined,
                        lottieAsset: LocalLinkAssets.lottieEmptyInbox,
                        title: 'No calls yet',
                        message:
                            'Your recent LocalLink calls will appear here.',
                      ),
                      ),
                    ),
                  ],
                )
              : _groupedList(state.history, colors),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _groupedList(List<CallRecord> history, ColorScheme colors) {
    // Group entries into Today / Yesterday / Date buckets (WhatsApp grouping).
    final groups = <String, List<CallRecord>>{};
    for (final call in history) {
      groups.putIfAbsent(_dayLabel(call.startedAt), () => []).add(call);
    }
    final children = <Widget>[];
    groups.forEach((label, records) {
      // Bundle 153: shared small grey label (same as "Conversations").
      children.add(MessengerGroupLabel(label));
      // One filled card per date bucket (Settings-style grouping): rows live
      // together inside a rounded white container with hairline dividers.
      final rows = <Widget>[];
      for (var i = 0; i < records.length; i++) {
        rows.add(CallHistoryTile(
          call: records[i],
          selfId: widget.selfId,
          title: _title(records[i]),
          status: _status(records[i]),
          date: _timeLabel(records[i].startedAt),
          duration: records[i].durationSeconds > 0
              ? _duration(records[i].durationSeconds)
              : null,
          missed: _isMissed(records[i]),
          onCall: () => _redial(records[i]),
        ));
      }
      // Bundle 153: shared outlined box (same as the Chats list).
      children.add(MessengerListGroup(children: rows));
    });
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: children,
    );
  }
}


/// Bundle 137: the same "Call in progress — tap to return" banner the Chats
/// tab got in 136, plus their state fix: BEFORE the peer answers it reads
/// "Calling {name}…" with NO clock; the timer starts at answeredAt only.
class _CallInProgressBar extends StatefulWidget {
  final CallBloc controller;
  const _CallInProgressBar({required this.controller});

  @override
  State<_CallInProgressBar> createState() => _CallInProgressBarState();
}

class _CallInProgressBarState extends State<_CallInProgressBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _mmss(DateTime from) {
    final seconds = DateTime.now().difference(from).inSeconds.clamp(0, 359999);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CallSession?>(
      stream: widget.controller.sessionStream,
      initialData: widget.controller.session,
      builder: (context, snapshot) {
        final session = snapshot.data;
        if (session == null || session.isFinished) {
          return const SizedBox.shrink();
        }
        final name = session.peerName.isEmpty ? 'LocalLink user' : session.peerName;
        final answered = session.answeredAt;
        final line = answered == null
            ? '$name · Calling… — Tap to return'
            : '$name · ${_mmss(answered)} — Tap to return';
        return SafeArea(
          top: false,
          bottom: false,
          child: GestureDetector(
            onTap: () {
              // Bundle 146: no second call screen for the same call.
              if (CallScreen.visibleCallId == session.id) return;
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                    builder: (_) => CallScreen(
                        controller: widget.controller, initialSession: session)),
              );
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFDFF3E6),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 8,
                      offset: Offset(0, 3)),
                ],
              ),
              child: Row(children: [
                const CircleAvatar(
                  radius: 17,
                  backgroundColor: Color(0xFF1E7D4F),
                  child: Icon(Icons.call, color: Colors.white, size: 17),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Call in progress',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF14532D))),
                      const SizedBox(height: 1),
                      Text(line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF3F6B50))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF3F6B50)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
