import 'package:flutter/material.dart';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/presentation/widgets/call_history_tile.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';

class CallsScreen extends StatefulWidget {
  final CallBloc controller;
  final String selfId;

  const CallsScreen({
    super.key,
    required this.controller,
    required this.selfId,
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

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _title(CallRecord call) =>
      widget.controller.deviceNames[call.peerId(widget.selfId)] ??
      call.peerId(widget.selfId);

  String _status(CallRecord call) {
    switch (call.status) {
      case 'connected':
        return 'Connected';
      case 'rejected':
        return call.endReason == 'busy' ? 'Busy' : 'Rejected';
      case 'missed':
        return 'Missed';
      case 'canceled':
        return 'Canceled';
      case 'failed':
        return 'Failed';
      case 'ringing':
        return 'Ringing';
      default:
        return call.durationSeconds > 0 ? 'Call ended' : 'No answer';
    }
  }

  String _duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> _refresh() => widget.controller.refreshHistory();

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<CallBloc, CallState>(
        bloc: widget.controller,
        builder: (context, state) {
          final calls = state.history;
          return Scaffold(
            appBar: AppBar(title: const Text('Call history')),
            body: RefreshIndicator(
              onRefresh: _refresh,
              child: calls.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 220),
                        Center(child: Text('No calls yet')),
                      ],
                    )
                  : ListView.separated(
                      itemCount: calls.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final call = calls[index];
                        return CallHistoryTile(
                          call: call,
                          selfId: widget.selfId,
                          title: _title(call),
                          status: _status(call),
                          date: _date(call.startedAt),
                          duration: call.durationSeconds > 0
                              ? _duration(call.durationSeconds)
                              : null,
                        );
                      },
                    ),
            ),
          );
        });
  }
}
