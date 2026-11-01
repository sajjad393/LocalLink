/// Bundle 180: turns LinkUp's log files into ONE neat text file (approved
/// mock `mocks/bundle180_mock.svg`): summary at the top, then
/// `TIME  LEVEL  AREA  EVENT  DETAILS` in fixed columns. No colour; errors
/// are marked `!!` and warnings `!`. Pure (no files, no platform).
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.area,
    required this.event,
    required this.details,
  });

  final DateTime time;

  /// I, W or E.
  final String level;
  final String area;
  final String event;
  final String details;
}

class LogReport {
  const LogReport._();

  static const int timeWidth = 12;
  static const int levelWidth = 8;
  static const int areaWidth = 7;
  static const int eventWidth = 22;
  static const int detailsWidth = 80;

  static const List<String> areas = <String>[
    'CALLS', 'FILES', 'MSGS', 'NEARBY', 'NOTIFY', 'BG', 'APP', 'SYSTEM',
  ];

  static final RegExp _eventWord = RegExp(r'^[A-Z][A-Z0-9_]{2,}$');
  static final RegExp _native = RegExp(
      r'^\s*(\d+)\.(\d{3})\s+\d+\s+\d+\s+([VDIWEFA])\s+(.*?)\s*:\s?(.*)$');

  /// Tags written by LinkUp itself (anything else in our process = SYSTEM).
  static const Set<String> _ourTags = <String>{
    'NEARBY', 'RELAY', 'ROUTES', 'LOCAL_NET', 'LINK_AUTH', 'FLUTTER',
  };

  static bool _ours(String tag) {
    final t = tag.toUpperCase();
    return t.startsWith('LOCALLINK') ||
        t.startsWith('LOCAL_LINK') ||
        t.startsWith('LINKUP') ||
        _ourTags.contains(t);
  }

  /// One line written by AppLogFile: `epochMs|L|EVENT|details`.
  static LogEntry? parseAppLine(String line) {
    final a = line.indexOf('|');
    if (a <= 0) return null;
    final b = line.indexOf('|', a + 1);
    if (b < 0) return null;
    final c = line.indexOf('|', b + 1);
    if (c < 0) return null;
    final ms = int.tryParse(line.substring(0, a));
    if (ms == null) return null;
    final level = _level(line.substring(a + 1, b));
    final event = line.substring(b + 1, c).trim();
    final details = line.substring(c + 1).trim();
    return LogEntry(
      time: DateTime.fromMillisecondsSinceEpoch(ms),
      level: level,
      area: areaOf('', event, native: false),
      event: event.isEmpty ? 'APP' : event,
      details: details,
    );
  }

  /// One `logcat -v epoch` line from LinkUp's process.
  static LogEntry? parseNativeLine(String line) {
    final m = _native.firstMatch(line);
    if (m == null) return null;
    final ms = int.parse(m.group(1)!) * 1000 + int.parse(m.group(2)!);
    final tag = m.group(4)!.trim();
    final message = m.group(5)!.trim();
    final space = message.indexOf(' ');
    final first = space < 0 ? message : message.substring(0, space);
    String event;
    String details;
    if (_eventWord.hasMatch(first)) {
      event = first;
      details = space < 0 ? '' : message.substring(space + 1).trim();
    } else {
      event = tag.isEmpty ? 'LOG' : tag;
      details = message;
    }
    return LogEntry(
      time: DateTime.fromMillisecondsSinceEpoch(ms),
      level: _level(m.group(3)!),
      area: areaOf(tag, event, native: true),
      event: event,
      details: details,
    );
  }

  static String _level(String raw) => switch (raw.trim().toUpperCase()) {
        'W' => 'W',
        'E' || 'F' || 'A' => 'E',
        _ => 'I',
      };

  /// CALLS, FILES, MSGS, NEARBY, NOTIFY, BG, APP or SYSTEM.
  static String areaOf(String tag, String event, {required bool native}) {
    final e = event.toUpperCase();
    final t = tag.toUpperCase();
    bool any(List<String> prefixes) => prefixes.any(e.startsWith);
    if (any(['CALL', 'RING', 'BG_CALL']) || t == 'LOCALLINKCALL' || e.contains('OPUS')) {
      return 'CALLS';
    }
    if (any(['FILE', 'DIRECT_FILE', 'MEDIA', 'ATTACH', 'UPLOAD', 'DOWNLOAD']) ||
        e.contains('_FILE')) {
      return 'FILES';
    }
    if (e.contains('NOTIF') || t.contains('NOTIF')) return 'NOTIFY';
    if (t == 'LOCALLINKBOOT' ||
        t == 'LOCALLINKBACKGROUND' ||
        any(['BOOT', 'BG_', 'KEEP', 'HEALTH', 'BATTERY', 'FGS']) ||
        e.contains('FOREGROUND')) {
      return 'BG';
    }
    if (const {'NEARBY', 'RELAY', 'ROUTES', 'LOCAL_NET', 'LINK_AUTH', 'LOCAL_LINK_TRANSPORT'}
            .contains(t) ||
        any(['WD_', 'WIFI', 'NEARBY', 'MESH', 'ROUTE', 'LINK', 'LAN', 'HOTSPOT',
          'RELAY', 'TOPOLOGY', 'PEER', 'TRANSPORT', 'LOCAL_NET'])) {
      return 'NEARBY';
    }
    if (any(['MSG', 'MESSAGE', 'DIRECT_', 'DELIVER', 'SYNC', 'OUTBOX', 'GROUP', 'CHAT']) ||
        e.contains('MESSAG')) {
      return 'MSGS';
    }
    if (native && !_ours(tag)) return 'SYSTEM';
    return 'APP';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _date(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';
  static String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
  static String _time(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';

  static String levelText(String level) => switch (level) {
        'E' => 'ERROR !!',
        'W' => 'WARN  ! ',
        _ => 'INFO    ',
      };

  static String _plural(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';

  static ({int errors, int warnings, int calls, int files, int nearby}) summary(
      List<LogEntry> entries) {
    final callIds = <String>{};
    final fileIds = <String>{};
    var errors = 0, warnings = 0, nearby = 0;
    final callRe = RegExp(r'call=([A-Za-z0-9_\-]+)');
    final fileRe = RegExp(r'(?:transfer|message|file)=([A-Za-z0-9_\-]+)');
    for (final e in entries) {
      if (e.level == 'E') errors++;
      if (e.level == 'W') warnings++;
      switch (e.area) {
        case 'CALLS':
          final m = callRe.firstMatch(e.details);
          if (m != null) callIds.add(m.group(1)!);
        case 'FILES':
          final m = fileRe.firstMatch(e.details);
          if (m != null) fileIds.add(m.group(1)!);
        case 'NEARBY':
          nearby++;
      }
    }
    return (
      errors: errors,
      warnings: warnings,
      calls: callIds.length,
      files: fileIds.length,
      nearby: nearby,
    );
  }

  /// Wraps [text] into pieces of at most [width] characters, at spaces when
  /// possible. Nothing is cut away.
  static List<String> wrap(String text, int width) {
    if (text.length <= width) return <String>[text];
    final out = <String>[];
    var rest = text;
    while (rest.length > width) {
      var cut = rest.lastIndexOf(' ', width);
      if (cut < width ~/ 2) cut = width;
      out.add(rest.substring(0, cut).trimRight());
      rest = rest.substring(cut).trimLeft();
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  static String _pad(String v, int w) => v.length >= w ? v : v.padRight(w);

  /// The whole file. [entries] must already be sorted by time.
  static String build(
    List<LogEntry> entries, {
    required DateTime from,
    required DateTime to,
    required String phone,
    required String android,
    required String version,
  }) {
    final b = StringBuffer();
    const bar = '=====================================================';
    final s = summary(entries);
    final minutes = to.difference(from).inMinutes;
    final span = minutes % 60 == 0 ? '${minutes ~/ 60} h' : '$minutes min';
    b.writeln('==================== LinkUp logs ====================');
    b.writeln('Phone     : $phone (Android $android)');
    b.writeln('LinkUp    : $version');
    b.writeln('From - To : ${_date(from)} ${_hm(from)}  ->  ${_date(to)} ${_hm(to)} ($span)');
    b.writeln('Summary   : ${_plural(s.errors, 'error')}, ${_plural(s.warnings, 'warning')}, '
        '${_plural(s.calls, 'call')}, ${_plural(s.files, 'file')}, '
        '${_plural(s.nearby, 'Nearby event')}');
    b.writeln('Lines     : ${entries.length}');
    b.writeln('Marks     : ERROR !!   WARN !   (search "!!" for errors)');
    b.writeln(bar);
    b.writeln();
    b.writeln('${_pad('TIME', timeWidth)}  ${_pad('LEVEL', levelWidth)}  '
        '${_pad('AREA', areaWidth)}  ${_pad('EVENT', eventWidth)}  DETAILS');
    b.writeln('${'-' * timeWidth}  ${'-' * levelWidth}  ${'-' * areaWidth}  '
        '${'-' * eventWidth}  ${'-' * 18}');
    if (entries.isEmpty) {
      b.writeln('(no log lines in this time)');
      return b.toString();
    }
    final indent = ' ' * (timeWidth + levelWidth + areaWidth + eventWidth + 8);
    var day = _date(from);
    for (final e in entries) {
      final d = _date(e.time);
      if (d != day) {
        day = d;
        b.writeln('----- $d -----');
      }
      final head = '${_time(e.time)}  ${levelText(e.level)}  '
          '${_pad(e.area, areaWidth)}  ${_pad(e.event, eventWidth)}  ';
      final parts = e.details.isEmpty ? <String>[''] : wrap(e.details, detailsWidth);
      b.writeln('$head${parts.first}'.trimRight());
      for (final p in parts.skip(1)) {
        b.writeln('$indent$p');
      }
    }
    return b.toString();
  }

  /// "ZTE Blade A73", without repeating the brand.
  static String phoneName(String manufacturer, String model) {
    final brand = manufacturer.trim();
    final m = model.trim();
    if (brand.isEmpty) return m.isEmpty ? 'Android phone' : m;
    if (m.toLowerCase().startsWith(brand.toLowerCase())) return m;
    final nice = brand.length <= 3
        ? brand.toUpperCase()
        : '${brand[0].toUpperCase()}${brand.substring(1)}';
    return '$nice $m'.trim();
  }
}
