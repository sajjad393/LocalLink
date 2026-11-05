/// Bundle 216: text formats for the admin pages (UI_SPEC_216 §1.8).
/// Pure functions, no Flutter imports, so they are easy to test.
library;

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Test hook: a fixed "now" for page tests and the UI check data.
DateTime Function() adminNow216 = DateTime.now;

/// Server time → local DateTime. Accepts ISO text, unix seconds or ms.
DateTime? parseAdminTime216(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  if (v is num) {
    if (v <= 0) return null;
    final ms = v > 100000000000 ? v.toInt() : (v * 1000).toInt();
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final n = num.tryParse(s);
  if (n != null) return parseAdminTime216(n);
  final d = DateTime.tryParse(s);
  if (d == null || d.year < 2000) return null;
  return d.toLocal();
}

String _hm(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
String dMMM216(DateTime t) => '${t.day} ${_months[t.month - 1]}';

int _dayDiff(DateTime t, DateTime now) {
  final a = DateTime(t.year, t.month, t.day);
  final b = DateTime(now.year, now.month, now.day);
  return b.difference(a).inDays;
}

/// Sub line: `today 10:42`, `yesterday`, `2 Nov`.
String whenSub216(Object? v, {DateTime? now}) {
  final t = parseAdminTime216(v);
  if (t == null) return '';
  final n = now ?? adminNow216();
  final d = _dayDiff(t, n);
  if (d <= 0) return 'today ${_hm(t)}';
  if (d == 1) return 'yesterday';
  return dMMM216(t);
}

/// "When" column: `10:40`, `Yesterday`, `2 Nov`.
String whenCol216(Object? v, {DateTime? now}) {
  final t = parseAdminTime216(v);
  if (t == null) return '';
  final n = now ?? adminNow216();
  final d = _dayDiff(t, n);
  if (d <= 0) return _hm(t);
  if (d == 1) return 'Yesterday';
  return dMMM216(t);
}

/// Audit: `10:40`, `Yesterday 18:05`, `3 Nov 12:00`.
String whenAudit216(Object? v, {DateTime? now}) {
  final t = parseAdminTime216(v);
  if (t == null) return '';
  final n = now ?? adminNow216();
  final d = _dayDiff(t, n);
  if (d <= 0) return _hm(t);
  if (d == 1) return 'Yesterday ${_hm(t)}';
  return '${dMMM216(t)} ${_hm(t)}';
}

/// Audit day group: Today / Yesterday / Earlier.
String dayGroup216(Object? v, {DateTime? now}) {
  final t = parseAdminTime216(v);
  if (t == null) return 'Earlier';
  final d = _dayDiff(t, now ?? adminNow216());
  if (d <= 0) return 'Today';
  if (d == 1) return 'Yesterday';
  return 'Earlier';
}

/// Age: `now`, `5 min ago`, `2 h ago`, `yesterday`, `3 days ago`,
/// `last week`, `2 Nov`.
String age216(Object? v, {DateTime? now}) {
  final t = parseAdminTime216(v);
  if (t == null) return '';
  final n = now ?? adminNow216();
  final diff = n.difference(t);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  final days = _dayDiff(t, n);
  if (days <= 0) return '${diff.inHours} h ago';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return 'last week';
  return dMMM216(t);
}

/// `seen yesterday`, `seen 3 days ago`.
String seen216(Object? v, {DateTime? now}) {
  final a = age216(v, now: now);
  return a.isEmpty ? '' : 'seen $a';
}

/// Call length `m:ss` (`h:mm:ss` from 1 h).
String callLength216(num seconds) {
  final s = seconds.round();
  if (s < 0) return '0:00';
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final r = (s % 60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$r';
  return '$m:$r';
}

/// `0.3 MB`, `2.4 MB`, `38 MB`, `1.2 GB`.
String size216(num bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
  if (mb >= 10) return '${mb.round()} MB';
  final one = mb.toStringAsFixed(1);
  return '${one == '0.0' && bytes > 0 ? '0.1' : one} MB';
}

/// `999`, `1.4k`, `18.2k`.
String count216(num n) {
  if (n < 1000) return '${n.round()}';
  final k = n / 1000;
  final t = k.toStringAsFixed(1);
  return '${t.endsWith('.0') ? t.substring(0, t.length - 2) : t}k';
}

/// `3d 4h`, `5h 12m`, `12m`.
String uptime216(num seconds) {
  final s = seconds.round();
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

String percent216(num p) => '${p.round()}%';

/// `1 phone` / `2 phones`; `1 person` / `2 people`.
String plural216(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

String people216(int n) => plural216(n, 'person', 'people');

/// Server role → shown level.
String level216(Object? role) {
  final r = (role ?? '').toString().toLowerCase();
  return switch (r) {
    'owner' || 'super_admin' || 'superadmin' => 'Owner',
    'operator' || 'admin' => 'Operator',
    'security' || 'security_admin' => 'Security',
    'auditor' || 'viewer' || 'read_only' => 'Auditor',
    '' => '',
    _ => r[0].toUpperCase() + r.substring(1),
  };
}

/// Short rights per level for the hero line.
String levelRights216(String level) => switch (level) {
      'Owner' => 'all tools',
      'Operator' => 'phones, Wi-Fi rules, recovery',
      'Security' => 'recovery, can look',
      'Auditor' => 'can only look',
      _ => 'admin tools',
    };

/// Name shown for a person: display name → @username → fallback.
String personName216(Map<String, dynamic> m, {String fallback = ''}) {
  for (final k in const ['display_name', 'name', 'username']) {
    final v = m[k]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  return fallback;
}

/// `ABCD-EFGH-…` code shown in groups of 4 joined by ` ‑ `.
String groupCode216(String code) {
  final c = code.replaceAll(RegExp(r'[\s-]'), '');
  final parts = <String>[];
  for (var i = 0; i < c.length; i += 4) {
    parts.add(c.substring(i, i + 4 > c.length ? c.length : i + 4));
  }
  return parts.join(' \u2011 ');
}
