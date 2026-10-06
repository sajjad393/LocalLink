import 'package:flutter/material.dart';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/presentation/widgets/call_history_tile.dart';

class CallsScreen extends StatefulWidget {
  final CallBloc controller;
  final String selfId;

  const CallsScreen({super.key, required this.controller, required this.selfId});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.refreshHistory();
  }

  String _title(CallRecord call) => widget.controller.deviceNames[call.peerId(widget.selfId)] ?? 'LocalLink user';

  String _status(CallRecord call) => switch (call.status) {
        'connected' => 'Completed',
        'rejected' => call.endReason == 'busy' ? 'Busy' : 'Declined',
        'missed' => 'Missed',
        'canceled' => 'Canceled',
        'failed' => 'Failed',
        'ringing' => 'No answer',
        _ => call.durationSeconds > 0 ? 'Completed' : 'No answer',
      };

  String _duration(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  String _date(DateTime value) => '${value.day}/${value.month}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<CallBloc, CallState>(
      bloc: widget.controller,
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: const Text('Calls'),
          actions: [IconButton(tooltip: 'Refresh', onPressed: widget.controller.refreshHistory, icon: const Icon(Icons.refresh))],
        ),
        body: RefreshIndicator(
          onRefresh: widget.controller.refreshHistory,
          child: state.history.isEmpty
              ?  ListView(
                  physics: AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: 180),
                    SizedBox(height: 360, child: LocalLinkEmptyView(icon: Icons.call_outlined, title: 'No calls yet', message: 'Your recent LocalLink calls will appear here.')),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: LocalLinkSpacing.sm),
                  itemCount: state.history.length,
                  separatorBuilder: (_, __) => const Divider(indent: 84),
                  itemBuilder: (_, index) {
                    final call = state.history[index];
                    return CallHistoryTile(
                      call: call,
                      selfId: widget.selfId,
                      title: _title(call),
                      status: _status(call),
                      date: _date(call.startedAt),
                      duration: call.durationSeconds > 0 ? _duration(call.durationSeconds) : null,
                    );
                  },
                ),
        ),
      ),
    );
  }
}
