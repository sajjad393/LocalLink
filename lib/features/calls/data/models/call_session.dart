import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/call_quality.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';

enum CallDirection { outgoing, incoming }

enum CallState {
  ringing,
  connecting,
  connected,
  reconnecting,
  ending,
  ended,
  rejected,
  missed,
  canceled,
  failed,
}

enum CallQuality { unknown, excellent, good, fair, poor, reconnecting }

extension CallRecordStatusX on String {
  bool get isFinishedCallStatus => const {
        'rejected',
        'ended',
        'missed',
        'canceled',
        'failed'
      }.contains(this);
}

extension CallQualityText on CallQuality {
  String get label => switch (this) {
        CallQuality.unknown => 'Unknown',
        CallQuality.excellent => 'Excellent',
        CallQuality.good => 'Good',
        CallQuality.fair => 'Fair',
        CallQuality.poor => 'Poor',
        CallQuality.reconnecting => 'Reconnecting',
      };
}

class CallSession {
  final String id;
  final String peerId;
  final String peerName;
  final CallDirection direction;
  final CallState state;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final String reason;
  final bool muted;
  final bool speakerOn;
  final CallQuality quality;
  final CallQualitySample? qualitySample;
  final bool signalingConnected;
  final int recoveryAttempts;
  final bool directMode;
  final CallTransportMode transportMode;
  final String mediaCodec;
  final List<String> supportedMediaCodecs;
  final bool videoEnabled;
  final int? localVideoTextureId;
  final int? remoteVideoTextureId;
  /// Display rotation (0/90/180/270) for each video surface, so the receiver
  /// can undo the sensor-orientation stretch on a portrait-held phone.
  final int localVideoRotation;
  final int remoteVideoRotation;
  /// Actual encoded geometry of each feed (the peer advertises its ladder
  /// pick inside call_video_config; defaults match the old fixed 640x360).
  final int localVideoWidth;
  final int localVideoHeight;
  final int remoteVideoWidth;
  final int remoteVideoHeight;
  /// True while the peer's camera is actually streaming video for this call.
  /// Drives the WhatsApp-style fullscreen video view (and its avatar fallback
  /// when the peer turns the camera off mid-call).
  final bool peerVideoActive;
  final String? mediaNextHopId;
  final int? mediaHopCount;

  /// Bundle 92 on-screen diagnostics: live verdicts of the native video
  /// pipeline (decoder configured? frames arriving? drops by named reason?).
  /// Rendered small in the video-waiting overlay so a screenshot instantly
  /// tells transport problems apart from decode/config problems.
  final bool videoRemoteConfigured;
  final int videoRxFrames;
  final String videoDropSummary; // '' = no drops seen

  /// Bundle 93: WhatsApp-style audio→video switch CONSENT. Set when the peer
  /// turns their camera on while OUR camera is off; the call screen surfaces
  /// a dialog. Only when the user Accepts do we start our side of video
  /// ('declined' suppresses both the dialog and the auto-viewer until the
  /// peer turns video off/on fresh).
  final bool videoSwitchRequested;
  final bool videoSwitchDeclined;

  /// Stable id of the DEBUG overlay: '' hides it.
  String get videoDebugLine {
    if (!videoEnabled) return '';
    final cfg = videoRemoteConfigured ? 'cfg:ok' : 'cfg:--';
    final drops = videoDropSummary.isEmpty ? 'drops:none' : 'drops:$videoDropSummary';
    return 'video dbg · $cfg · rx:$videoRxFrames · $drops';
  }

  const CallSession({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.direction,
    required this.state,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.reason = '',
    this.muted = false,
    this.speakerOn = true,
    this.quality = CallQuality.unknown,
    this.qualitySample,
    this.signalingConnected = true,
    this.recoveryAttempts = 0,
    this.directMode = false,
    this.transportMode = CallTransportMode.auto,
    this.mediaCodec = 'auto',
    this.supportedMediaCodecs = const ['opus', 'pcm_s16le'],
    this.videoEnabled = false,
    this.localVideoTextureId,
    this.remoteVideoTextureId,
    this.localVideoRotation = 0,
    this.remoteVideoRotation = 0,
    this.localVideoWidth = 640,
    this.localVideoHeight = 360,
    this.remoteVideoWidth = 640,
    this.remoteVideoHeight = 360,
    this.peerVideoActive = false,
    this.mediaNextHopId,
    this.mediaHopCount,
    this.videoRemoteConfigured = false,
    this.videoRxFrames = 0,
    this.videoDropSummary = '',
    this.videoSwitchRequested = false,
    this.videoSwitchDeclined = false,
  });

  bool get isFinished => const {
        CallState.ended,
        CallState.rejected,
        CallState.missed,
        CallState.canceled,
        CallState.failed,
      }.contains(state);

  CallSession copyWith({
    CallState? state,
    DateTime? answeredAt,
    DateTime? endedAt,
    String? reason,
    bool? muted,
    bool? speakerOn,
    CallQuality? quality,
    CallQualitySample? qualitySample,
    bool? signalingConnected,
    int? recoveryAttempts,
    bool? directMode,
    CallTransportMode? transportMode,
    String? mediaCodec,
    List<String>? supportedMediaCodecs,
    bool? videoEnabled,
    bool? videoSwitchRequested,
    bool? videoSwitchDeclined,
    bool? videoRemoteConfigured,
    int? videoRxFrames,
    String? videoDropSummary,
    int? localVideoTextureId,
    int? remoteVideoTextureId,
    int? localVideoRotation,
    int? remoteVideoRotation,
    int? localVideoWidth,
    int? localVideoHeight,
    int? remoteVideoWidth,
    int? remoteVideoHeight,
    bool? peerVideoActive,
    String? mediaNextHopId,
    int? mediaHopCount,
  }) =>
      CallSession(
        id: id,
        peerId: peerId,
        peerName: peerName,
        direction: direction,
        state: state ?? this.state,
        startedAt: startedAt,
        answeredAt: answeredAt ?? this.answeredAt,
        endedAt: endedAt ?? this.endedAt,
        reason: reason ?? this.reason,
        muted: muted ?? this.muted,
        speakerOn: speakerOn ?? this.speakerOn,
        quality: quality ?? this.quality,
        qualitySample: qualitySample ?? this.qualitySample,
        signalingConnected: signalingConnected ?? this.signalingConnected,
        recoveryAttempts: recoveryAttempts ?? this.recoveryAttempts,
        directMode: directMode ?? this.directMode,
        transportMode: transportMode ?? this.transportMode,
        mediaCodec: mediaCodec ?? this.mediaCodec,
        supportedMediaCodecs: supportedMediaCodecs ?? this.supportedMediaCodecs,
        videoEnabled: videoEnabled ?? this.videoEnabled,
        localVideoTextureId: localVideoTextureId ?? this.localVideoTextureId,
        remoteVideoTextureId: remoteVideoTextureId ?? this.remoteVideoTextureId,
        localVideoRotation: localVideoRotation ?? this.localVideoRotation,
        remoteVideoRotation: remoteVideoRotation ?? this.remoteVideoRotation,
        localVideoWidth: localVideoWidth ?? this.localVideoWidth,
        localVideoHeight: localVideoHeight ?? this.localVideoHeight,
        remoteVideoWidth: remoteVideoWidth ?? this.remoteVideoWidth,
        remoteVideoHeight: remoteVideoHeight ?? this.remoteVideoHeight,
        peerVideoActive: peerVideoActive ?? this.peerVideoActive,
        videoRemoteConfigured: videoRemoteConfigured ?? this.videoRemoteConfigured,
        videoRxFrames: videoRxFrames ?? this.videoRxFrames,
        videoDropSummary: videoDropSummary ?? this.videoDropSummary,
        videoSwitchRequested: videoSwitchRequested ?? this.videoSwitchRequested,
        videoSwitchDeclined: videoSwitchDeclined ?? this.videoSwitchDeclined,
        mediaNextHopId: mediaNextHopId ?? this.mediaNextHopId,
        mediaHopCount: mediaHopCount ?? this.mediaHopCount,
      );

  CallRecord toRecord(String selfId) => CallRecord(
        id: id,
        callerId: direction == CallDirection.outgoing ? selfId : peerId,
        calleeId: direction == CallDirection.outgoing ? peerId : selfId,
        status: _recordStatus,
        startedAt: startedAt,
        answeredAt: answeredAt,
        endedAt: endedAt,
        durationSeconds: _durationSeconds,
        endReason: reason,
      );

  int get _durationSeconds {
    if (answeredAt == null) return 0;
    final seconds =
        (endedAt ?? DateTime.now()).difference(answeredAt!).inSeconds;
    if (seconds < 0) return 0;
    if (seconds > 1 << 31) return 1 << 31;
    return seconds;
  }

  String get _recordStatus {
    switch (state) {
      case CallState.ringing:
      case CallState.connecting:
        return 'ringing';
      case CallState.connected:
      case CallState.reconnecting:
        return 'connected';
      case CallState.ending:
        return 'ended';
      case CallState.rejected:
        return 'rejected';
      case CallState.missed:
        return 'missed';
      case CallState.canceled:
        return 'canceled';
      case CallState.failed:
        return 'failed';
      case CallState.ended:
        return 'ended';
    }
  }
}
