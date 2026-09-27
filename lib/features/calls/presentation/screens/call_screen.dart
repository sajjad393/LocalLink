import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';

import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' as call_bloc;
import 'package:locallink/features/calls/presentation/widgets/call_action_bar.dart';
import 'package:locallink/features/calls/presentation/widgets/call_header.dart';
import 'package:locallink/features/calls/presentation/widgets/call_quality_card.dart';
import 'package:locallink/features/calls/presentation/widgets/call_video_view.dart';

class CallScreen extends StatefulWidget {
  final call_bloc.CallBloc controller;
  final CallSession initialSession;

  const CallScreen({
    super.key,
    required this.controller,
    required this.initialSession,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late CallSession _session = widget.initialSession;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '').trim();

  String _statusTextFor(CallSession session) {
    switch (session.state) {
      case CallState.ringing:
        return session.direction == CallDirection.outgoing
            ? 'Calling…'
            : 'Incoming call';
      case CallState.connecting:
        return 'Connecting…';
      case CallState.reconnecting:
        return 'Reconnecting through local mesh…';
      case CallState.connected:
        return _formatDuration(
          (session.endedAt ?? DateTime.now())
              .difference(session.answeredAt ?? DateTime.now())
              .inSeconds,
        );
      case CallState.ending:
        return 'Ending…';
      case CallState.rejected:
        return session.reason == 'busy' ? 'Busy' : 'Call rejected';
      case CallState.missed:
        return 'Missed call';
      case CallState.canceled:
        return 'Call canceled';
      case CallState.failed:
        return 'Call failed';
      case CallState.ended:
        return 'Call ended';
    }
  }

  String _formatDuration(int seconds) {
    final value = seconds < 0 ? 0 : seconds;
    final minutes = (value ~/ 60).toString().padLeft(2, '0');
    final secs = (value % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<call_bloc.CallBloc, call_bloc.CallState>(
        bloc: widget.controller,
        builder: (context, state) {
          final session = state.session ?? _session;
          final error = state.error;
          if (error != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.controller.clearError();
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(_cleanError(error))));
            });
          }
          if (session.isFinished && session.id == _session.id) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).maybePop();
            });
          }
          return Scaffold(
            appBar: AppBar(title: const Text('LocalLink Call')),
            body: SafeArea(
              child: Column(
                children: [
                  if (session.videoEnabled ||
                      session.localVideoTextureId != null ||
                      session.remoteVideoTextureId != null) ...[
                    const SizedBox(height: 16),
                    CallVideoView(
                      localTextureId: session.localVideoTextureId,
                      remoteTextureId: session.remoteVideoTextureId,
                    ),
                    const SizedBox(height: 10),
                    CallHeader(
                        session: session, statusText: _statusTextFor(session)),
                  ] else ...[
                    const Spacer(),
                    CallHeader(
                        session: session, statusText: _statusTextFor(session)),
                    const Spacer(),
                  ],
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('WebRTC—Coming Soon.'),
                  ),
                  if (session.state == CallState.connected ||
                      session.state == CallState.reconnecting) ...[
                    const SizedBox(height: 10),
                    CallQualityCard(session: session),
                  ],
                  CallActionBar(
                      controller: widget.controller, session: session),
                ],
              ),
            ),
          );
        });
  }
}
