import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/messaging/data/services/voice_note_service.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_levels.dart';

/// Bundle 181 (approved mock `mocks/bundle181_full_mock.svg`): the voice
/// note recorder, WhatsApp style.
///   idle -> (hold the mic) holding -> let go = send / slide left = cancel /
///   slide up = locked -> Pause = paused (listen, continue, send, delete).
enum VoiceRecState { idle, holding, locked, paused }

/// Bundle 198: the three recorder sounds.
enum VoiceTone { start, send, cancel }

/// A paused voice note kept while you are away from the chat.
class VoiceDraft {
  const VoiceDraft({required this.parts, required this.levels, required this.recordedMs});

  final List<String> parts;
  final List<double> levels;
  final int recordedMs;
}

/// Drafts per chat while the app is running (lost if the app is closed).
class VoiceDraftStore {
  const VoiceDraftStore._();

  static final Map<String, VoiceDraft> _drafts = <String, VoiceDraft>{};

  static void put(String chatId, VoiceDraft draft) => _drafts[chatId] = draft;

  static VoiceDraft? take(String chatId) => _drafts.remove(chatId);

  @visibleForTesting
  static void clear() => _drafts.clear();
}

class VoiceRecorderController extends ChangeNotifier {
  VoiceRecorderController({
    required this.backend,
    required this.onSend,
    this.onError,
    this.haptic,
    this.onRecordStart,
    this.shouldPause,
    DateTime Function()? clock,
    this.holdDelay = const Duration(milliseconds: 250),
    this.minLength = const Duration(seconds: 1),
    this.maxLength = const Duration(minutes: 15),
    this.tick = const Duration(milliseconds: 100),
    this.hintTime = const Duration(seconds: 2),
    this.tone,
    this.toneLead = const Duration(milliseconds: 90),
  }) : _clock = clock ?? DateTime.now;

  /// Bundle 198: start "tik" / send "swoosh" / cancel "tok". The mic opens
  /// [toneLead] after the start tik so the tik is not recorded (only when
  /// [tone] is set).
  final void Function(VoiceTone tone)? tone;
  final Duration toneLead;

  final VoiceRecorderBackend backend;
  final Future<void> Function(PickedFile file) onSend;
  final void Function(Object error)? onError;

  /// true = strong (start), false = light (lock / cancel).
  final void Function(bool strong)? haptic;

  /// Stop other sound (chat voice notes, videos) before recording / listening.
  final VoidCallback? onRecordStart;

  /// Checked every tick: true = something covers the chat (a call) -> pause.
  final bool Function()? shouldPause;

  final DateTime Function() _clock;
  final Duration holdDelay;
  final Duration minLength;
  final Duration maxLength;
  final Duration tick;
  final Duration hintTime;

  static const int maxLevels = 15 * 60 * 10 + 50;

  VoiceRecState _state = VoiceRecState.idle;
  final List<String> _parts = <String>[];
  final List<double> _levels = <double>[];
  int _doneMs = 0;
  DateTime? _runStart;
  double _slideDx = 0;
  double _slideDy = 0; // Bundle 198: 0 .. -lockDistance (finger up)
  bool _hint = false;
  bool _previewPlaying = false;
  double _previewProgress = 0;
  int _previewMs = 0;
  DateTime? _previewStart;
  bool _fingerDown = false;
  bool _disposed = false;

  Timer? _holdTimer;
  Timer? _tickTimer;
  Timer? _hintTimer;
  Timer? _previewTimer;

  /// Bundle 199b (mic lock): after a slide-up lock the closed lock is shown
  /// for [lockShowTime] before the locked panel replaces the bar.
  bool _lockClosing = false;
  Timer? _lockShowTimer;
  static const Duration lockShowTime = Duration(milliseconds: 250);
  Future<void> _chain = Future<void>.value();

  VoiceRecState get state => _state;
  bool get isRecordingNow => _state == VoiceRecState.holding || _state == VoiceRecState.locked;
  bool get active => _state != VoiceRecState.idle;
  List<double> get levels => List<double>.unmodifiable(_levels);
  double get slideDx => _slideDx;
  double get slideDy => _slideDy;

  /// Bundle 199b: true for a moment after the finger reached the lock - the
  /// bar still shows the big mic at the top and the CLOSED blue lock.
  bool get lockClosing => _lockClosing;

  /// Bundle 198: 0 (finger at the mic) .. 1 (at the lock).
  double get lockProgress =>
      (-_slideDy / VoiceHoldGesture.lockDistance).clamp(0.0, 1.0);
  bool get hintVisible => _hint;
  bool get previewPlaying => _previewPlaying;
  double get previewProgress => _previewProgress;
  bool get canPreview => _state == VoiceRecState.paused && _parts.length == 1;

  @visibleForTesting
  List<String> get partsForTest => List<String>.unmodifiable(_parts);

  Duration get recorded {
    final start = _runStart;
    var run = 0;
    if (start != null) {
      run = _clock().difference(start).inMilliseconds;
      if (run < 0) run = 0;
    }
    return Duration(milliseconds: _doneMs + run);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _queue(Future<void> Function() op) {
    final next = _chain.then((_) => op()).catchError((Object e) {
      onError?.call(e);
    });
    _chain = next;
    return next;
  }

  // ---------------------------------------------------------------- mic finger

  void pressDown() {
    if (_state != VoiceRecState.idle || _disposed) return;
    _fingerDown = true;
    _holdTimer?.cancel();
    _holdTimer = Timer(holdDelay, () {
      _holdTimer = null;
      if (_fingerDown) _beginHold();
    });
  }

  /// [moved] = finger position minus where it went down.
  void pressMove(Offset moved, double barWidth) {
    if (_state != VoiceRecState.holding) return;
    switch (VoiceHoldGesture.decide(moved, barWidth)) {
      case VoiceHoldDecision.cancel:
        _fingerDown = false;
        haptic?.call(false);
        discard();
      case VoiceHoldDecision.lock:
        // Bundle 199b: show the lock closing first, then the panel.
        _lockClosing = true;
        _slideDy = -VoiceHoldGesture.lockDistance;
        lock();
        if (_state == VoiceRecState.locked) {
          _slideDy = -VoiceHoldGesture.lockDistance;
          _lockShowTimer?.cancel();
          _lockShowTimer = Timer(lockShowTime, _endLockShow);
        } else {
          _lockClosing = false;
        }
      case VoiceHoldDecision.none:
        final dx = moved.dx < 0 ? moved.dx : 0.0;
        // Bundle 198: the big mic follows the finger up (to the lock).
        final dy = moved.dy < 0
            ? math.max(moved.dy, -VoiceHoldGesture.lockDistance)
            : 0.0;
        var changed = false;
        if (dx != _slideDx) {
          _slideDx = dx;
          changed = true;
        }
        if ((dy - _slideDy).abs() >= 1 || (dy == 0 && _slideDy != 0)) {
          _slideDy = dy;
          changed = true;
        }
        if (changed) notifyListeners();
    }
  }

  void pressUp() {
    _fingerDown = false;
    if (_holdTimer != null) {
      // A quick tap: no recording, show the hint.
      _holdTimer!.cancel();
      _holdTimer = null;
      _showHint();
      return;
    }
    if (_state == VoiceRecState.holding) {
      _queue(() async {
        if (_state != VoiceRecState.holding) return;
        if (recorded < minLength) {
          await _discardNow();
        } else {
          await _sendNow();
        }
      });
    }
  }

  /// Android took the finger away (app left, call...): keep what was said.
  void pressCancel() {
    _fingerDown = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_state == VoiceRecState.holding) pause();
  }

  void _beginHold() {
    if (_disposed) return;
    _state = VoiceRecState.holding;
    _slideDx = 0;
    _slideDy = 0;
    _levels.clear();
    _parts.clear();
    _doneMs = 0;
    _hideHint();
    haptic?.call(true);
    onRecordStart?.call();
    notifyListeners();
    final playTone = tone;
    if (playTone != null) playTone(VoiceTone.start); // Bundle 198
    _queue(() async {
      if (playTone != null && toneLead > Duration.zero) {
        // Bundle 198: let the "tik" finish before the mic opens.
        await Future<void>.delayed(toneLead);
        if (_disposed || !isRecordingNow) return;
      }
      try {
        final path = await backend.startPart();
        _parts.add(path);
        _runStart = _clock();
        _startTick();
      } catch (e) {
        _reset();
        onError?.call(e);
      }
      notifyListeners();
    });
  }

  // ------------------------------------------------------------------ buttons

  void lock() {
    if (_state != VoiceRecState.holding) return;
    _state = VoiceRecState.locked;
    _slideDx = 0;
    // Bundle 199b: a slide-up lock keeps the mic at the top for a moment.
    _slideDy = _lockClosing ? -VoiceHoldGesture.lockDistance : 0;
    haptic?.call(false);
    notifyListeners();
  }

  void _endLockShow() {
    _lockShowTimer?.cancel();
    _lockShowTimer = null;
    if (!_lockClosing || _disposed) return;
    _lockClosing = false;
    _slideDy = 0;
    notifyListeners();
  }

  Future<void> pause() => _queue(_pauseNow);

  Future<void> resume() => _queue(() async {
        if (_state != VoiceRecState.paused) return;
        await _stopPreviewNow();
        onRecordStart?.call();
        try {
          final path = await backend.startPart();
          _parts.add(path);
          _runStart = _clock();
          _state = VoiceRecState.locked;
          haptic?.call(false);
          _startTick();
        } catch (e) {
          onError?.call(e);
        }
        notifyListeners();
      });

  Future<void> send() => _queue(_sendNow);

  Future<void> discard() => _queue(_discardNow);

  Future<void> togglePreview() => _queue(() async {
        if (!canPreview) return;
        if (_previewPlaying) {
          await _stopPreviewNow();
          notifyListeners();
          return;
        }
        onRecordStart?.call();
        final ms = await backend.play(_parts.single);
        _previewMs = ms > 0 ? ms : _doneMs;
        if (_previewMs <= 0) _previewMs = 1;
        _previewPlaying = true;
        _previewProgress = 0;
        _previewStart = _clock();
        _previewTimer?.cancel();
        _previewTimer = Timer.periodic(tick, (_) {
          final start = _previewStart;
          if (start == null) return;
          final p = _clock().difference(start).inMilliseconds / _previewMs;
          if (p >= 1) {
            _previewTimer?.cancel();
            _previewTimer = null;
            _previewPlaying = false;
            _previewProgress = 0;
          } else {
            _previewProgress = p.clamp(0.0, 1.0);
          }
          notifyListeners();
        });
        notifyListeners();
      });

  /// The app went to the background / a call covers the chat.
  void interrupt() {
    _fingerDown = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (isRecordingNow) {
      pause();
    } else if (_previewPlaying) {
      _queue(() async {
        await _stopPreviewNow();
        notifyListeners();
      });
    }
  }

  // ------------------------------------------------------------------- drafts

  /// Leaving the chat: pause if needed and hand back the draft (if any).
  Future<VoiceDraft?> suspend() async {
    _fingerDown = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    await _queue(() async {
      if (isRecordingNow) await _pauseNow();
      await _stopPreviewNow();
    });
    if (_state != VoiceRecState.paused || _parts.isEmpty) return null;
    final draft = VoiceDraft(
      parts: List<String>.of(_parts),
      levels: List<double>.of(_levels),
      recordedMs: _doneMs,
    );
    _parts.clear();
    _reset();
    return draft;
  }

  void restore(VoiceDraft draft) {
    if (_state != VoiceRecState.idle || draft.parts.isEmpty) return;
    _parts
      ..clear()
      ..addAll(draft.parts);
    _levels
      ..clear()
      ..addAll(draft.levels);
    _doneMs = draft.recordedMs;
    _runStart = null;
    _state = VoiceRecState.paused;
    notifyListeners();
  }

  // ------------------------------------------------------------------ inside

  void _startTick() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(tick, (_) async {
      if (!isRecordingNow || _runStart == null) return;
      final amp = await backend.amplitude();
      if (!isRecordingNow || _runStart == null) return;
      _levels.add(VoiceLevels.levelOf(amp));
      if (_levels.length > maxLevels) _levels.removeAt(0);
      if (shouldPause?.call() == true) {
        interrupt();
      } else if (recorded >= maxLength) {
        pause();
      }
      notifyListeners();
    });
  }

  void _stopTick() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// Ends the running part; false when nothing is left.
  Future<void> _endRun() async {
    _stopTick();
    final start = _runStart;
    if (start == null) return;
    final run = _clock().difference(start).inMilliseconds;
    _runStart = null;
    String? path;
    try {
      path = await backend.stopPart();
    } catch (e) {
      path = null;
      onError?.call(e);
    }
    if (path == null) {
      if (_parts.isNotEmpty) _parts.removeLast();
    } else {
      _doneMs += run < 0 ? 0 : run;
    }
  }

  Future<void> _pauseNow() async {
    if (!isRecordingNow) return;
    await _endRun();
    if (_parts.isEmpty) {
      _reset();
      notifyListeners();
      return;
    }
    if (_parts.length > 1) {
      try {
        final joined = await backend.join(List<String>.of(_parts));
        _parts
          ..clear()
          ..add(joined.path);
      } catch (e) {
        onError?.call(e);
      }
    }
    _state = VoiceRecState.paused;
    // Bundle 199b: a call during the lock moment - no closed-lock moment left.
    _lockShowTimer?.cancel();
    _lockShowTimer = null;
    _lockClosing = false;
    notifyListeners();
  }

  Future<void> _sendNow() async {
    if (_state == VoiceRecState.idle) return;
    await _stopPreviewNow();
    if (isRecordingNow) await _endRun();
    final parts = List<String>.of(_parts);
    final total = _doneMs;
    _parts.clear();
    _reset();
    notifyListeners();
    if (parts.isEmpty) {
      tone?.call(VoiceTone.cancel); // Bundle 198
      return;
    }
    if (total < minLength.inMilliseconds) {
      tone?.call(VoiceTone.cancel); // Bundle 198: too short
      for (final p in parts) {
        backend.deleteFile(p);
      }
      return;
    }
    tone?.call(VoiceTone.send); // Bundle 198
    final file = await backend.join(parts);
    await onSend(file);
  }

  Future<void> _discardNow() async {
    if (_state == VoiceRecState.idle) return;
    tone?.call(VoiceTone.cancel); // Bundle 198
    _stopTick();
    await _stopPreviewNow();
    if (isRecordingNow && _runStart != null) {
      _runStart = null;
      await backend.cancelPart();
      if (_parts.isNotEmpty) _parts.removeLast();
    }
    for (final p in _parts) {
      backend.deleteFile(p);
    }
    _parts.clear();
    _reset();
    notifyListeners();
  }

  Future<void> _stopPreviewNow() async {
    if (!_previewPlaying) return;
    _previewTimer?.cancel();
    _previewTimer = null;
    _previewPlaying = false;
    _previewProgress = 0;
    _previewStart = null;
    await backend.stopPlayback();
  }

  void _reset() {
    _stopTick();
    _lockShowTimer?.cancel();
    _lockShowTimer = null;
    _lockClosing = false;
    _state = VoiceRecState.idle;
    _runStart = null;
    _doneMs = 0;
    _slideDx = 0;
    _slideDy = 0;
    _levels.clear();
  }

  void _showHint() {
    _hint = true;
    _hintTimer?.cancel();
    _hintTimer = Timer(hintTime, _hideHint);
    notifyListeners();
  }

  void _hideHint() {
    _hintTimer?.cancel();
    _hintTimer = null;
    if (!_hint) return;
    _hint = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _holdTimer?.cancel();
    _tickTimer?.cancel();
    _hintTimer?.cancel();
    _previewTimer?.cancel();
    _lockShowTimer?.cancel();
    super.dispose();
  }
}
