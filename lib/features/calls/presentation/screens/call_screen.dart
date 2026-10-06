import 'dart:async';

import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' as call_bloc;
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/widgets/call_action_bar.dart';
import 'package:locallink/features/calls/presentation/widgets/call_header.dart';
import 'package:locallink/features/calls/presentation/widgets/call_quality_card.dart';
import 'package:locallink/features/calls/presentation/widgets/call_video_view.dart';

class CallScreen extends StatefulWidget {
  final call_bloc.CallBloc controller;
  final CallSession initialSession;

  const CallScreen({super.key, required this.controller, required this.initialSession});

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
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _cleanError(Object error) => error.toString().replaceFirst('Exception: ', '').trim();

  String _statusTextFor(CallSession session) => switch (session.state) {
        CallState.ringing => session.direction == CallDirection.outgoing ? 'Calling…' : 'Incoming call',
        CallState.connecting => 'Connecting…',
        CallState.reconnecting => 'Reconnecting…',
        CallState.connected => _formatDuration((session.endedAt ?? DateTime.now()).difference(session.answeredAt ?? DateTime.now()).inSeconds),
        CallState.ending => 'Ending…',
        CallState.rejected => session.reason == 'busy' ? 'Busy' : 'Declined',
        CallState.missed => 'Missed call',
        CallState.canceled => 'Call canceled',
        CallState.failed => 'Call failed',
        CallState.ended => 'Call ended',
      };

  String _formatDuration(int seconds) {
    final value = seconds < 0 ? 0 : seconds;
    return '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<call_bloc.CallBloc, call_bloc.CallState>(
      bloc: widget.controller,
      builder: (context, state) {
        final session = state.session ?? _session;
        _session = session;
        final error = state.error;

        if (error != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.controller.clearError();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
          });
        }
        if (session.isFinished && session.id == _session.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
        }

        final hasVideo = session.videoEnabled || session.localVideoTextureId != null || session.remoteVideoTextureId != null;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Call'),
            leading: IconButton(tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back)),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.lg, LocalLinkSpacing.md, LocalLinkSpacing.lg, LocalLinkSpacing.md),
                    child: Column(
                      children: [
                        if (hasVideo) ...[
                          CallVideoView(
                            localTextureId: session.localVideoTextureId,
                            remoteTextureId: session.remoteVideoTextureId,
                          ),
                          const SizedBox(height: LocalLinkSpacing.lg),
                        ] else ...[
                          const SizedBox(height: 48),
                        ],
                        CallHeader(session: session, statusText: _statusTextFor(session)),
                        if (session.state == CallState.ringing || session.state == CallState.connecting)
                          const Align(
                            alignment: Alignment.center,
                            child: Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('WebRTC—Coming Soon.'),
                            ),
                          ),
                        if (session.state == CallState.connected || session.state == CallState.reconnecting) ...[
                          const SizedBox(height: LocalLinkSpacing.xl),
                          CallQualityCard(session: session),
                        ],
                      ],
                    ),
                  ),
                ),
                CallActionBar(controller: widget.controller, session: session),
              ],
            ),
          ),
        );
      },
    );
  }
}
