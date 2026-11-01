import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Bundle 181: mic level -> bar height (0..1) on an ear-like (dB) scale, so
/// soft talking shows clearly and silence stays low. Pure.
class VoiceLevels {
  const VoiceLevels._();

  static const double quietDb = -50;
  static const double loudDb = -8;

  static double levelOf(int amplitude) {
    if (amplitude <= 0) return 0;
    final db = 20 * math.log(amplitude / 32767.0) / math.ln10;
    return ((db - quietDb) / (loudDb - quietDb)).clamp(0.0, 1.0);
  }

  /// The newest [n] levels, newest last; empty slots on the left are 0.
  static List<double> tail(List<double> levels, int n) {
    if (n <= 0) return const <double>[];
    if (levels.length >= n) return levels.sublist(levels.length - n);
    return <double>[...List<double>.filled(n - levels.length, 0), ...levels];
  }

  /// The whole recording squeezed (or stretched) into [n] bars (average of
  /// each slice, so the shape of what was said stays visible).
  static List<double> fit(List<double> levels, int n) {
    if (n <= 0) return const <double>[];
    if (levels.isEmpty) return List<double>.filled(n, 0);
    return List<double>.generate(n, (i) {
      final a = i * levels.length ~/ n;
      final b = math.max(a + 1, (i + 1) * levels.length ~/ n);
      var sum = 0.0;
      var count = 0;
      for (var k = a; k < b && k < levels.length; k++) {
        sum += levels[k];
        count++;
      }
      return count == 0 ? 0.0 : sum / count;
    });
  }
}

enum VoiceHoldDecision { none, cancel, lock }

/// Bundle 181: while holding the mic - slide left = cancel, slide up = lock.
class VoiceHoldGesture {
  const VoiceHoldGesture._();

  /// About 1 cm up.
  static const double lockDistance = 60;

  /// About 1/3 of the bar to the left (at least 80 px).
  static double cancelDistance(double barWidth) => math.max(80, barWidth / 3);

  static VoiceHoldDecision decide(Offset moved, double barWidth) {
    if (moved.dy <= -lockDistance && moved.dy.abs() > moved.dx.abs()) {
      return VoiceHoldDecision.lock;
    }
    if (moved.dx <= -cancelDistance(barWidth)) return VoiceHoldDecision.cancel;
    return VoiceHoldDecision.none;
  }
}

/// "0:05", "12:30".
String voiceClock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
