import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/brand_gradient_fab.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
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

  String _title(CallRecord call) =>
      widget.controller.deviceNames[_peerId(call)] ?? 'Unknown user';

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

  Future<void> _redial(CallRecord call) async {
    final peerId = _peerId(call);
    if (peerId.isEmpty) return;
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
    } catch (_) {}
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
        body: RefreshIndicator(
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
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: .3,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
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
        if (i < records.length - 1) {
          rows.add(Divider(
            height: 1,
            indent: 76,
            color: colors.outlineVariant.withOpacity(.35),
          ));
        }
      }
      children.add(
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.outlineVariant.withOpacity(.5)),
          ),
          child: Column(children: rows),
        ),
      );
    });
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: children,
    );
  }
}
