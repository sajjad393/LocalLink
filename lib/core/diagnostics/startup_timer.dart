import 'package:locallink/core/services/app_logger.dart';

/// Bundle 185 (A4): how long each start step takes. One `STARTUP_STEP` line
/// per step and one `STARTUP_DONE` line with the total and the slowest step.
class StartupTimer {
  StartupTimer({Stopwatch? watch, this.log = true})
      : _watch = (watch ?? Stopwatch())..start();

  final Stopwatch _watch;
  final bool log;
  final List<({String name, int ms})> steps = <({String name, int ms})>[];
  int _last = 0;

  int get totalMs => _watch.elapsedMilliseconds;

  /// Ends the step that started at the previous call (or at the start).
  void step(String name) {
    final now = _watch.elapsedMilliseconds;
    final ms = now - _last;
    _last = now;
    steps.add((name: name, ms: ms));
    if (log) AppLogger.info('STARTUP_STEP', detail: 'name=$name ms=$ms');
  }

  String summary() {
    final slowest = steps.isEmpty
        ? null
        : steps.reduce((a, b) => b.ms > a.ms ? b : a);
    final parts = steps.map((s) => '${s.name}:${s.ms}').join(',');
    return 'total_ms=$totalMs '
        'slowest=${slowest == null ? '-' : '${slowest.name}:${slowest.ms}'} '
        'steps=$parts';
  }

  void done() {
    if (log) AppLogger.info('STARTUP_DONE', detail: summary());
  }
}

/// Bundle 185 (D2): the start order. The chat list shows as soon as the
/// database, settings and keys are ready; the rest starts right after the
/// first frame is on screen.
class StartupSequence {
  const StartupSequence._();

  static Future<void> run({
    required StartupTimer timer,
    required Future<void> Function() core,
    required void Function() showFirstScreen,
    required Future<void> Function() firstFrame,
    required Future<void> Function() rest,
    required void Function() servicesReady,
  }) async {
    await core();
    showFirstScreen();
    timer.step('first_screen');
    await firstFrame();
    timer.step('first_frame');
    await rest();
    timer.step('services');
    servicesReady();
    timer.done();
  }
}
