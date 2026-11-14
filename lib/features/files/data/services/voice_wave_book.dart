import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 303 (G): what a voice note sounds like - its length and its
/// loudness (0..1 per slice, the loudest slice = 1). Drawn as the bars in the
/// voice bubble, like WhatsApp.
@immutable
class VoiceWaveInfo {
  const VoiceWaveInfo({required this.durationMs, required this.levels});

  final int durationMs;
  final List<double> levels;

  bool get hasLevels => levels.isNotEmpty;
}

/// Bundle 303 (G): reads each voice note file ONCE (on the phone, Android's
/// own decoder) and remembers the result, so old voice notes get real bars
/// too. One file at a time (slow phones), never during a call, kept in
/// memory and in the app settings (survives a restart).
class VoiceWaveBook {
  VoiceWaveBook();

  static VoiceWaveBook instance = VoiceWaveBook();

  static const MethodChannel _channel = MethodChannel('locallink/voice_notes');

  /// Slices asked from the phone (the bubble squeezes them into its bars).
  static const int buckets = 120;

  /// Remembered files (newest kept).
  static const int maxKept = 400;

  static const String settingKey = 'voice_waves_303';

  /// Test hook: replaces the native reader.
  @visibleForTesting
  Future<Map<Object?, Object?>?> Function(String path)? readerForTest;

  final Map<String, VoiceWaveInfo> _known = <String, VoiceWaveInfo>{};
  final Map<String, Future<VoiceWaveInfo?>> _running = <String, Future<VoiceWaveInfo?>>{};
  // The read before this one (null = none running).
  Future<void>? _queue;

  Future<String?> Function(String key)? _read;
  Future<void> Function(String key, String value)? _write;
  bool Function() _inCall = () => false;
  Future<void>? _loaded;
  Timer? _saveTimer;

  /// Called once the local store is open (home screen).
  void attachStore({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    bool Function()? inCall,
  }) {
    _read = read;
    _write = write;
    if (inCall != null) _inCall = inCall;
    _loaded ??= _loadSaved();
  }

  @visibleForTesting
  int reads = 0;

  @visibleForTesting
  void resetForTest() {
    _known.clear();
    _running.clear();
    _queue = null;
    _read = null;
    _write = null;
    _loaded = null;
    _saveTimer?.cancel();
    _inCall = () => false;
    reads = 0;
    readerForTest = null;
  }

  /// Already known (no wait), or null.
  VoiceWaveInfo? peek(String key) => _known[key];

  /// Length + bars for the file [path] of the voice note [key] (attachment
  /// id + size). Null when the phone cannot read it.
  Future<VoiceWaveInfo?> load(String key, String path) {
    final known = _known[key];
    if (known != null) return Future<VoiceWaveInfo?>.value(known);
    final running = _running[key];
    if (running != null) return running;
    final future = _loadOne(key, path);
    _running[key] = future;
    return future.whenComplete(() => _running.remove(key));
  }

  Future<VoiceWaveInfo?> _loadOne(String key, String path) async {
    final loaded = _loaded;
    if (loaded != null) await loaded;
    final saved = _known[key];
    if (saved != null) return saved;
    // One decode at a time.
    final done = Completer<void>();
    final before = _queue;
    _queue = done.future;
    try {
      if (before != null) await before;
      var waited = 0;
      while (_inCall() && waited < 3600) {
        await Future<void>.delayed(const Duration(seconds: 5));
        waited += 5;
      }
      reads++;
      final raw = await (readerForTest?.call(path) ??
          _channel.invokeMethod<Map<Object?, Object?>>('voice_wave', {'path': path, 'buckets': buckets}));
      final info = fromNative(raw);
      if (info == null) return null;
      _known[key] = info;
      _trim();
      _saveSoon();
      return info;
    } on MissingPluginException {
      return null;
    } catch (error) {
      AppLogger.warning('VOICE_WAVE_FAILED', detail: '$error');
      return null;
    } finally {
      done.complete();
      if (identical(_queue, done.future)) _queue = null;
    }
  }

  /// How many dB under the note's loudest part still shows a bar.
  static const double rangeDb = 36;

  /// Native answer -> info. Peaks are sound levels 0..32767 per slice. Like
  /// the ear (dB), measured from the note's OWN loudest part: loudest = 1,
  /// [rangeDb] quieter or silence = the smallest bar. So a soft voice still
  /// shows its words, and every note gets its own shape.
  static VoiceWaveInfo? fromNative(Map<Object?, Object?>? raw) {
    if (raw == null) return null;
    final duration = (raw['duration_ms'] as num?)?.toInt() ?? 0;
    final peaks = (raw['peaks'] as List<Object?>?) ?? const <Object?>[];
    final levels = earLevels([for (final p in peaks) (p as num?)?.toInt() ?? 0]);
    if (duration <= 0 && levels.isEmpty) return null;
    return VoiceWaveInfo(durationMs: duration, levels: levels);
  }

  /// Peaks (0..32767) -> 0..1 on a dB scale from the loudest peak.
  static List<double> earLevels(List<int> peaks) {
    double db(int p) => 20 * math.log(p / 32767.0) / math.ln10;
    var top = 0;
    for (final p in peaks) {
      if (p > top) top = p;
    }
    if (top <= 0) return peaks.map((_) => 0.0).toList(growable: false);
    final floor = db(top) - rangeDb;
    return [
      for (final p in peaks) p <= 0 ? 0.0 : ((db(p) - floor) / rangeDb).clamp(0.0, 1.0),
    ];
  }

  /// Loudest = 1; all silent stays all 0.
  static List<double> normalise(List<double> levels) {
    var top = 0.0;
    for (final v in levels) {
      if (v > top) top = v;
    }
    if (top <= 0) return levels.map((_) => 0.0).toList(growable: false);
    return levels.map((v) => (v / top).clamp(0.0, 1.0)).toList(growable: false);
  }

  void _trim() {
    while (_known.length > maxKept) {
      _known.remove(_known.keys.first);
    }
  }

  Future<void> _loadSaved() async {
    final read = _read;
    if (read == null) return;
    try {
      final text = await read(settingKey);
      if (text == null || text.isEmpty) return;
      final map = jsonDecode(text) as Map<String, dynamic>;
      map.forEach((key, value) {
        if (_known.containsKey(key) || value is! Map) return;
        final d = (value['d'] as num?)?.toInt() ?? 0;
        final p = value['p'] as String? ?? '';
        final bytes = p.isEmpty ? const <int>[] : base64Decode(p);
        _known[key] = VoiceWaveInfo(durationMs: d, levels: [for (final b in bytes) b / 255.0]);
      });
      _trim();
    } catch (error) {
      AppLogger.warning('VOICE_WAVE_LOAD_FAILED', detail: '$error');
    }
  }

  void _saveSoon() {
    if (_write == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () => unawaited(_save()));
  }

  Future<void> _save() async {
    final write = _write;
    if (write == null) return;
    try {
      await write(settingKey, encode(_known));
    } catch (error) {
      AppLogger.warning('VOICE_WAVE_SAVE_FAILED', detail: '$error');
    }
  }

  /// One byte per slice (0..255), base64 - about 160 characters a note.
  @visibleForTesting
  static String encode(Map<String, VoiceWaveInfo> known) => jsonEncode({
        for (final e in known.entries)
          e.key: {
            'd': e.value.durationMs,
            'p': base64Encode(Uint8List.fromList(
                [for (final v in e.value.levels) (v.clamp(0.0, 1.0) * 255).round()])),
          },
      });
}
