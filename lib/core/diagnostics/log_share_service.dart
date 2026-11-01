import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/diagnostics/log_report.dart';
import 'package:locallink/core/diagnostics/log_rules.dart';

/// Bundle 180: builds the last hour of logs as one text file and opens the
/// Android share sheet. Only runs when the user taps "Chats" 5 times.
class LogShareService {
  const LogShareService._();

  static const MethodChannel _channel = MethodChannel('locallink/logs');

  /// Merges both sides, keeps [from]..[to], sorts by time, builds the text.
  /// Pure apart from the input lists; runs in a background isolate.
  static String buildFromFiles(LogBuildInput input) {
    final from = DateTime.fromMillisecondsSinceEpoch(input.fromMs);
    final to = DateTime.fromMillisecondsSinceEpoch(input.toMs);
    final entries = <LogEntry>[];
    void addAll(String text, LogEntry? Function(String) parse) {
      for (final line in const LineSplitter().convert(text)) {
        final e = parse(line);
        if (e == null) continue;
        final ms = e.time.millisecondsSinceEpoch;
        if (ms < input.fromMs || ms > input.toMs) continue;
        entries.add(e);
      }
    }

    for (final t in input.nativeTexts) {
      addAll(t, LogReport.parseNativeLine);
    }
    for (final t in input.appTexts) {
      addAll(t, LogReport.parseAppLine);
    }
    // Stable sort by time (same time keeps file order).
    final indexed = entries.asMap().entries.toList()
      ..sort((a, b) {
        final c = a.value.time.compareTo(b.value.time);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return LogReport.build(
      indexed.map((e) => e.value).toList(),
      from: from,
      to: to,
      phone: input.phone,
      android: input.android,
      version: input.version,
    );
  }

  /// File name part from the phone model: letters, digits and dashes.
  static String safeName(String v) {
    final s = v.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    final t = s.replaceAll(RegExp(r'^-+|-+$'), '');
    return t.isEmpty ? 'phone' : t;
  }

  static String fileName(String model, DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'LinkUp-logs-${safeName(model)}-${now.year}-${two(now.month)}-'
        '${two(now.day)}-${two(now.hour)}${two(now.minute)}.txt';
  }

  /// Writes the file and returns its path (null when it can't).
  static Future<String?> prepare({DateTime? now}) async {
    final info = await _channel.invokeMapMethod<String, Object?>('info');
    if (info == null) return null;
    AppLogFile.instance.flushNow();
    final dir = info['dir']?.toString() ?? '';
    final cacheDir = info['cache_dir']?.toString() ?? '';
    if (dir.isEmpty || cacheDir.isEmpty) return null;
    final to = now ?? DateTime.now();
    final from = to.subtract(LogRules.keep);
    final firstSlot = LogRules.slotOf(from.millisecondsSinceEpoch);
    final nativeTexts = <String>[];
    final appTexts = <String>[];
    final files = Directory(dir).listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final slot = LogRules.slotFromName(name);
      if (slot == null || slot < firstSlot) continue;
      final bytes = await f.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      (LogRules.isNativeFile(name) ? nativeTexts : appTexts).add(text);
    }
    final model = info['model']?.toString() ?? '';
    final version = '${info['version_name'] ?? ''}+${info['version_code'] ?? ''}';
    final input = LogBuildInput(
      fromMs: from.millisecondsSinceEpoch,
      toMs: to.millisecondsSinceEpoch,
      nativeTexts: nativeTexts,
      appTexts: appTexts,
      phone: LogReport.phoneName(info['manufacturer']?.toString() ?? '', model),
      android: info['android']?.toString() ?? '?',
      version: version,
    );
    final text = await compute(buildFromFiles, input);
    // Only the newest shared file is kept in the cache.
    try {
      for (final e in Directory(cacheDir).listSync()) {
        final n = e.uri.pathSegments.last;
        if (e is File && n.startsWith('LinkUp-logs-') && n.endsWith('.txt')) {
          e.deleteSync();
        }
      }
    } catch (_) {}
    final out = File('$cacheDir/${fileName(model, to)}');
    await out.writeAsString(text, flush: true);
    return out.path;
  }

  static Future<void> share(String path) async {
    await Share.shareXFiles(
      <XFile>[XFile(path, mimeType: 'text/plain')],
      subject: 'LinkUp logs',
      text: 'LinkUp logs (last 1 hour)',
    );
  }
}

class LogBuildInput {
  const LogBuildInput({
    required this.fromMs,
    required this.toMs,
    required this.nativeTexts,
    required this.appTexts,
    required this.phone,
    required this.android,
    required this.version,
  });

  final int fromMs;
  final int toMs;
  final List<String> nativeTexts;
  final List<String> appTexts;
  final String phone;
  final String android;
  final String version;
}
