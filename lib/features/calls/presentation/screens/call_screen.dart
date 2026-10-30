import 'dart:async';
import 'package:locallink/core/bloc/bloc_utils.dart';

import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' as call_bloc;
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/widgets/call_action_bar.dart';
import 'package:locallink/features/calls/presentation/widgets/call_header.dart';
import 'package:locallink/features/calls/presentation/widgets/call_palette.dart';
import 'package:locallink/features/calls/presentation/widgets/call_video_view.dart';

/// WhatsApp-style call screen, identical layout on both the caller and the
/// receiver side once the call is answered.
class CallScreen extends StatefulWidget {
  /// Bundle 146: id of the call whose screen is on the navigator stack, so
  /// notification Accept / Calls tab / "return to call" never push a second
  /// call screen for the same call.
  static String? visibleCallId;

  final call_bloc.CallBloc controller;
  final CallSession initialSession;

  const CallScreen(
      {super.key, required this.controller, required this.initialSession});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late CallSession _session = widget.initialSession;
  Timer? _ticker;
  bool _switchDialogOpen = false;

  @override
  void initState() {
    super.initState();
    CallScreen.visibleCallId = widget.initialSession.id;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    if (CallScreen.visibleCallId == widget.initialSession.id) {
      CallScreen.visibleCallId = null;
    }
    _videoUiTimer?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String _cleanError(Object error) => cleanBlocError(error);

  String _statusTextFor(CallSession session) => switch (session.state) {
        CallState.ringing => session.direction == CallDirection.outgoing
            ? 'Ringing…'
            : 'Incoming call',
        // Bundle 137: plain "Calling…" instead of "Trying to reach…".
        CallState.connecting =>
          session.direction == CallDirection.outgoing &&
                  !session.signalingConnected
              ? 'Calling…'
              : 'Connecting…',
        CallState.reconnecting => session.answeredAt == null
            ? 'Calling…'
            : 'Reconnecting…',
        CallState.connected => _formatDuration(
            (session.endedAt ?? DateTime.now())
                .difference(session.answeredAt ?? DateTime.now())
                .inSeconds),
        CallState.ending => 'Ending…',
        CallState.rejected =>
          session.reason == 'busy' ? 'Busy' : 'Declined',
        CallState.missed => 'Missed call',
        CallState.canceled => 'Call canceled',
        CallState.failed => switch (session.reason) {
            'unreachable' => "Couldn't reach them — try again",
            'microphone_permission' =>
              'Microphone permission needed — allow it, then answer again',
            'transport_unavailable' =>
              'Local calling service unavailable — reconnect and try again',
            'identity_blocked' =>
              'Identity changed or revoked — verify this user again',
            _ => 'Call failed',
          },
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
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(_cleanError(error))));
          });
        }
        if (session.isFinished && session.id == _session.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
        }

        // Bundle 93: peer turned their camera on mid-call while ours is off —
        // WhatsApp-style consent dialog. Accepting starts our camera; Not now
        // keeps the call audio-only and suppresses re-asks for this episode.
        if (session.videoSwitchRequested &&
            !session.videoSwitchDeclined &&
            !_switchDialogOpen &&
            session.answeredAt != null &&
            !session.videoEnabled) {
          _switchDialogOpen = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showVideoSwitchDialog(session);
          });
        }
        if (!session.videoSwitchRequested && _switchDialogOpen) {
          // Flag cleared elsewhere (accepted/declined already); mark closed
          // so the next switch request can surface again.
          _switchDialogOpen = false;
        }

        final statusText = _statusTextFor(session);
        final videoMode = session.videoEnabled || session.peerVideoActive;

        return Scaffold(
          backgroundColor: CallPalette.background,
          body: videoMode
              ? _buildVideoLayout(session, statusText)
              : _buildAudioLayout(session, statusText),
        );
      },
    );
  }

  Widget _buildAudioLayout(CallSession session, String statusText) {
    final typeLabel = session.videoEnabled || session.peerVideoActive
        ? 'LocalLink video call'
        : 'LocalLink voice call';
    return Container(
      decoration: const BoxDecoration(gradient: CallPalette.backdrop),
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Minimize',
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: CallPalette.textPrimary, size: 30),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              typeLabel,
              style: const TextStyle(
                color: CallPalette.green,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const Spacer(),
            CallHeader(session: session, statusText: statusText),
            const Spacer(flex: 2),
            CallActionBar(controller: widget.controller, session: session),
          ],
        ),
      ),
    );
  }

  // --- WhatsApp-style tap-to-toggle chrome for VIDEO calls only (the voice
  // UI is untouched): taps fade the top/bottom chrome, and any activity
  // re-arms a 4s auto-hide so the full-screen video stays unobstructed.
  bool _videoUiVisible = true;
  Timer? _videoUiTimer;

  void _toggleVideoUi() {
    setState(() {
      _videoUiVisible = !_videoUiVisible;
      if (_videoUiVisible) _armVideoUiTimer();
    });
  }

  void _armVideoUiTimer() {
    _videoUiTimer?.cancel();
    _videoUiTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _videoUiVisible = false);
    });
  }

  /// Fades/pointer-wraps video chrome while leaving the Positioned parent
  /// as a direct Stack child (required by Stack layout).
  Widget _videoChrome(Widget child) {
    return IgnorePointer(
      ignoring: !_videoUiVisible,
      child: AnimatedOpacity(
        opacity: _videoUiVisible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: child,
      ),
    );
  }

  Future<void> _showVideoSwitchDialog(CallSession session) async {
    final name = session.peerName.isEmpty ? 'Your contact' : session.peerName;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.videocam_rounded, size: 36),
        title: const Text('Switch to video call?'),
        content: Text('$name turned on their camera. Accept to switch this call to video.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.controller.declineVideoSwitch();
            },
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              widget.controller.acceptVideoSwitch();
            },
            icon: const Icon(Icons.videocam_rounded),
            label: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoLayout(CallSession session, String statusText) {
    final name =
        session.peerName.isEmpty ? 'LocalLink user' : session.peerName;
    // Any rebuild counts as activity: keep the chrome visible briefly.
    _armVideoUiTimer();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleVideoUi,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CallVideoView(
            session: session,
            onSelfPreviewTap: session.videoEnabled && session.directMode
                ? widget.controller.switchCamera
                : null,
          ),
          // Top overlay: name + status over a fading dark scrim.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _videoChrome(
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 16, 22),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Minimize',
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: Colors.white, size: 28),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                statusText,
                                style: TextStyle(
                                  color: CallHeader.statusColorFor(session),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Bottom overlay: WhatsApp-style control pill.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _videoChrome(
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: CallActionBar(
                        controller: widget.controller, session: session),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
