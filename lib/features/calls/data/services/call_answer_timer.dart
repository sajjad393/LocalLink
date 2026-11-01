import 'package:locallink/core/services/app_logger.dart';

/// Bundle 186 (A1/A3): how long answering a call takes, step by step.
///
/// One `CALL_ANSWER_STEP name= ms=` line per step and one summary line
/// `CALL_ANSWER_DONE total_ms= since_tap_ms= slowest= steps=` at the end.
/// [sinceTap] is how long ago Accept was tapped on the notification (the
/// app was opening meanwhile); null when Accept was tapped inside the app.
class CallAnswerTimer {
  CallAnswerTimer({
    required this.callId,
    this.sinceTap,
    Stopwatch? stopwatch,
    void Function(String event, String detail)? log,
  })  : _watch = (stopwatch ?? Stopwatch())..start(),
        _log = log ?? ((event, detail) => AppLogger.info(event, detail: detail));

  final String callId;
  final Duration? sinceTap;
  final Stopwatch _watch;
  final void Function(String event, String detail) _log;
  final List<MapEntry<String, int>> _steps = [];
  int _last = 0;
  bool _done = false;

  List<MapEntry<String, int>> get steps => List.unmodifiable(_steps);

  int get totalMs => _watch.elapsedMilliseconds;

  void step(String name) {
    if (_done) return;
    final now = _watch.elapsedMilliseconds;
    final ms = now - _last;
    _last = now;
    _steps.add(MapEntry(name, ms));
    _log('CALL_ANSWER_STEP', 'call=$callId name=$name ms=$ms');
  }

  /// Summary line. Returns it (for tests). Only once.
  String? done() {
    if (_done) return null;
    _done = true;
    final total = _watch.elapsedMilliseconds;
    var slowest = '-';
    var slowestMs = -1;
    for (final s in _steps) {
      if (s.value > slowestMs) {
        slowestMs = s.value;
        slowest = s.key;
      }
    }
    final tap = sinceTap == null
        ? '-'
        : '${sinceTap!.inMilliseconds + total}';
    final detail = 'call=$callId total_ms=$total since_tap_ms=$tap '
        'slowest=$slowest steps=${_steps.map((s) => '${s.key}:${s.value}').join(',')}';
    _log('CALL_ANSWER_DONE', detail);
    return detail;
  }
}

/// Bundle 186 (A3): the caller side - how long from "invite sent" to
/// "they answered", and from "they answered" to "our sound started".
abstract final class CallConnectTiming {
  static String line({
    required String callId,
    required int? inviteToAcceptMs,
    required int acceptToAudioMs,
  }) =>
      'call=$callId invite_to_accept_ms=${inviteToAcceptMs ?? '-'} '
      'accept_to_audio_ms=$acceptToAudioMs';
}
