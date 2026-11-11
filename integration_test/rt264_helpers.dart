// Bundle 264: helpers for the GitHub run-time test (emulator + real server).
// Only used by integration_test/; never part of the app.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/diagnostics/log_share_service.dart';

/// The control script on the GitHub machine (`tool/rt264/server_ctl.py`).
/// 10.0.2.2 = the machine, as the emulator sees it.
class Ctl264 {
  Ctl264({this.base = 'http://10.0.2.2:8099'});

  final String base;
  final List<String> steps = <String>[];
  int _shot = 0;

  Future<Map<String, dynamic>> _get(String path,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$base$path')).timeout(timeout);
      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      final decoded = body.isEmpty ? null : jsonDecode(body);
      return decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'status': res.statusCode, 'body': decoded};
    } finally {
      client.close(force: true);
    }
  }

  Future<void> start({String env = ''}) async =>
      _get('/start${env.isEmpty ? '' : '?$env'}');
  Future<void> stop() async => _get('/stop');
  Future<Map<String, dynamic>> admin(String action, [Map<String, String>? args]) {
    final q = args == null || args.isEmpty
        ? ''
        : '?${args.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    return _get('/admin/$action$q');
  }

  Future<void> shot(String name) async {
    _shot++;
    final n = _shot.toString().padLeft(2, '0');
    try {
      await _get('/shot/${n}_$name');
    } catch (_) {}
  }

  Future<void> mark(String name) async => _get('/mark/$name');
  Future<void> waitMark(String name, {int seconds = 600}) async =>
      _get('/wait/$name?s=$seconds', timeout: Duration(seconds: seconds + 30));

  /// One line per step in the summary (PASS / FAIL + why).
  void step(String name, bool ok, [String why = '']) {
    final line = 'RT264_STEP ${ok ? 'PASS' : 'FAIL'} $name${why.isEmpty ? '' : ' - $why'}';
    steps.add(line);
    // ignore: avoid_print
    print(line);
  }

  bool get allPassed => steps.every((s) => s.contains(' PASS '));
}

/// All app log lines written so far (both engines), oldest first.
List<String> appLogLines() {
  AppLogFile.instance.flushNow();
  final dir = AppLogFile.instance.dir;
  final out = <String>[...AppLogFile.instance.pendingForTest];
  if (dir == null) return out;
  try {
    final files = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      out.addAll(const LineSplitter()
          .convert(utf8.decode(f.readAsBytesSync(), allowMalformed: true)));
    }
  } catch (_) {}
  return out;
}

/// Waits (pumping the app) until a log line has [tag] and every [contains]
/// part. Lines from before [after] (count of lines) are skipped.
Future<String?> waitLog(WidgetTester tester, String tag,
    {List<String> contains = const <String>[],
    Duration timeout = const Duration(seconds: 30),
    int after = 0}) async {
  final until = DateTime.now().add(timeout);
  while (true) {
    final lines = appLogLines();
    for (var i = after; i < lines.length; i++) {
      final l = lines[i];
      if (l.contains('|$tag|') && contains.every(l.contains)) return l;
    }
    if (DateTime.now().isAfter(until)) return null;
    await tester.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

/// Pumps real time until [finder] shows (or the time is over).
Future<bool> waitFor(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final until = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(until)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (finder.evaluate().isNotEmpty) return true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return finder.evaluate().isNotEmpty;
}

/// Lets the app run for [d] of real time.
Future<void> idle(WidgetTester tester, Duration d) async {
  final until = DateTime.now().add(d);
  while (DateTime.now().isBefore(until)) {
    await tester.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<bool> tapText(WidgetTester tester, String text,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final f = find.text(text);
  if (!await waitFor(tester, f, timeout: timeout)) return false;
  await tester.ensureVisible(f.first);
  await tester.tap(f.first);
  await tester.pump(const Duration(milliseconds: 500));
  return true;
}

Future<bool> enterField(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextField, label);
  if (!await waitFor(tester, field, timeout: const Duration(seconds: 10))) {
    return false;
  }
  await tester.enterText(field.first, value);
  await tester.pump(const Duration(milliseconds: 300));
  return true;
}

/// 3.0.80 "must NOT show" texts (TODO 264 G). Returns the ones on screen.
List<String> shownForbidden() {
  const list = <String>[
    'carried by',
    'Account saved',
    'Publish',
    'Waiting for the server to be updated',
    'on the server now',
    "Couldn't sync right now",
    'Account published to the server.',
    'will update when online',
    'Find server now',
    "Can't reach LinkUp",
    'Server connected',
    'No server',
    'Copy device id',
    'Saved on this phone',
    'Could not check your account history',
  ];
  return [
    for (final t in list)
      if (find.textContaining(t).evaluate().isNotEmpty) t,
  ];
}

/// Prints the same log file the Send logs button makes, and asks the
/// machine to pull it too (the test run may remove the app at the end).
Future<void> dumpLogs(Ctl264 ctl) async {
  String? path;
  try {
    path = await LogShareService.prepare();
  } catch (_) {}
  // ignore: avoid_print
  print('RT264_LOG_BEGIN');
  try {
    final lines = path == null
        ? appLogLines()
        : const LineSplitter().convert(await File(path).readAsString());
    for (final l in lines) {
      // ignore: avoid_print
      print('RT264_LOG $l');
    }
  } catch (_) {}
  // ignore: avoid_print
  print('RT264_LOG_END');
  try {
    await ctl._get('/pull-logs');
  } catch (_) {}
}
