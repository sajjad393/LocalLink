// Bundle 210: the small page the friend's phone opens (English + Urdu).
// No outside files: the friend has no internet. No JavaScript needed.

import 'package:locallink/features/share_app/domain/wifi_qr.dart';

String htmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

const String shareApkPath = '/LinkUp.apk';

String shareApkFileName(String version) {
  final v = version.replaceAll(RegExp(r'[^0-9A-Za-z.+_-]'), '');
  return v.isEmpty ? 'LinkUp.apk' : 'LinkUp-$v.apk';
}

// Bundle 299 R: same look as the server page (http://linkup.local/download):
// navy hero with the LinkUp rings, one card with the button, step cards.
// Light and dark follow the phone.
const String _css = '''
*{box-sizing:border-box}
:root{--bg:#f4f6fb;--card:#fff;--text:#111827;--muted:#5b6472;--line:#e2e6ec;--step:#eef3ff;--warn:#fff7e6;--warnt:#7a4800}
@media (prefers-color-scheme:dark){:root{--bg:#0b1020;--card:#141a2a;--text:#e8edf4;--muted:#9ca6b5;--line:#263049;--step:#1a2440;--warn:#2a2210;--warnt:#fcd58a}}
body{margin:0;font-family:Roboto,system-ui,sans-serif;background:var(--bg);color:var(--text)}
.hero{background:radial-gradient(circle at 15% 10%,rgba(47,123,246,.45),transparent 55%),radial-gradient(circle at 90% 100%,rgba(34,211,238,.35),transparent 55%),linear-gradient(160deg,#0a1022,#0e1a33);color:#fff;padding:30px 20px 70px;text-align:center}
.logo{width:84px;height:84px;display:block;margin:0 auto;border-radius:24px;box-shadow:0 10px 30px rgba(47,123,246,.45)}
h1{font-size:28px;margin:12px 0 2px}
.tag{margin:0;color:rgba(255,255,255,.78);font-size:15px}
.tag.ur{color:#7cc4ff;text-align:center}
.w{max-width:480px;margin:-50px auto 0;padding:0 16px 34px}
.card{background:var(--card);border:1px solid var(--line);border-radius:22px;padding:18px;box-shadow:0 10px 30px rgba(10,16,34,.10)}
.ver{display:flex;justify-content:center;gap:8px;flex-wrap:wrap;margin:0 0 14px}
.pill{font-size:13px;font-weight:600;padding:5px 11px;border-radius:99px;background:var(--step);color:var(--muted)}
.pill.new{background:rgba(18,161,80,.14);color:#12a150}
.btn{display:block;padding:16px;border-radius:30px;background:linear-gradient(90deg,#2f7bf6,#22b8e8);color:#fff;text-align:center;font-size:19px;font-weight:700;text-decoration:none;box-shadow:0 8px 22px rgba(47,123,246,.35)}
.ur.urc{text-align:center;color:#2f7bf6;margin-top:8px}
h2{font-size:17px;margin:22px 4px 8px}
.steps{list-style:none;margin:0;padding:0}
.steps li{display:flex;gap:12px;align-items:flex-start;background:var(--card);border:1px solid var(--line);border-radius:16px;padding:12px 14px;margin:8px 0;font-size:15px;line-height:1.4}
.n{flex:none;width:28px;height:28px;border-radius:50%;background:var(--step);color:#2f7bf6;font-weight:700;display:grid;place-items:center;font-size:14px}
.ur{direction:rtl;text-align:right;color:var(--muted);font-size:15px;line-height:1.7;margin:2px 0 0;font-family:"Noto Naskh Arabic","Noto Sans Arabic",sans-serif}
.note{background:var(--warn);color:var(--warnt);border-radius:14px;padding:12px 14px;margin-top:14px;font-size:14px;line-height:1.45}
.note .ur{color:var(--warnt)}
''';

const String _logo = '''
<svg class="logo" viewBox="0 0 96 96" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2f7bf6"/><stop offset="1" stop-color="#22d3ee"/></linearGradient></defs>
<rect width="96" height="96" rx="26" fill="#0e1a33"/>
<circle cx="37" cy="48" r="15" fill="none" stroke="url(#g)" stroke-width="8.4"/>
<circle cx="59" cy="48" r="15" fill="none" stroke="url(#g)" stroke-width="8.4"/>
</svg>''';

const String _head = '''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>LinkUp</title><style>$_css</style></head>''';

/// The download page. [ownerName] may be empty (then no "Shared by").
String buildSharePage({
  required String ownerName,
  required String version,
  required int sizeBytes,
}) {
  final name = htmlEscape(ownerName.trim());
  final hasName = name.isNotEmpty;
  final size = shareSizeLabel(sizeBytes);
  final v = htmlEscape(version);
  final shared = [
    if (hasName) 'Shared by $name',
    if (v.isNotEmpty) v,
    size,
  ].join(' &middot; ');
  final who = hasName ? name : 'your friend';
  final whoUr = hasName ? name : 'اپنے دوست';
  String step(int n, String en, String ur) =>
      '<li><span class="n">$n</span><div>$en<p class="ur" lang="ur" dir="rtl">$ur</p></div></li>';
  return '''$_head
<body><div class="hero">
$_logo
<h1>LinkUp</h1>
<p class="tag">Chat and call without internet</p>
<p class="tag ur" lang="ur" dir="rtl">بغیر انٹرنیٹ کے بات اور کال کریں</p>
</div><div class="w"><div class="card">
<div class="ver"><span class="pill">$shared</span></div>
<a class="btn" href="$shareApkPath" download="${shareApkFileName(version)}">&#11015; Download LinkUp</a>
<p class="ur urc" lang="ur" dir="rtl">لنک اپ ڈاؤن لوڈ کریں</p>
</div>
<h2>How to install</h2>
<p class="ur" lang="ur" dir="rtl">انسٹال کرنے کا طریقہ</p>
<ol class="steps">
${step(1, 'Tap Download LinkUp. If Chrome warns, tap Keep / Download anyway.', 'ڈاؤن لوڈ پر ٹیپ کریں۔ اگر کروم خبردار کرے تو Keep یا Download anyway دبائیں۔')}
${step(2, 'Tap the file (or open Downloads) and tap Install.', 'فائل کھولیں (یا ڈاؤن لوڈز میں جائیں) اور انسٹال پر ٹیپ کریں۔')}
${step(3, 'If Android says "not allowed to install unknown apps", tap Settings, turn on "Allow from this source", go back and tap Install.', 'اگر فون اجازت مانگے تو سیٹنگز میں جا کر "اس ذریعے سے اجازت دیں" آن کریں، پھر واپس آ کر انسٹال کریں۔')}
${step(4, 'Open LinkUp. You can now chat with $who with no internet.', 'لنک اپ کھولیں۔ اب آپ بغیر انٹرنیٹ کے $whoUr سے بات کر سکتے ہیں۔')}
</ol>
<div class="note">Play Protect may say "unknown app". That is normal for apps not from Play Store. Tap "Install anyway".
<p class="ur" lang="ur" dir="rtl">اگر Play Protect خبردار کرے تو یہ عام بات ہے۔ Install anyway دبائیں۔</p></div>
</div></body></html>''';
}

/// Shown to a 4th phone while 3 are already downloading.
String buildBusyPage() => '''$_head
<body><div class="hero">
$_logo
<h1>Busy</h1>
<p class="tag">3 phones are downloading now. Try again in a minute.</p>
<p class="tag ur" lang="ur" dir="rtl">ابھی تین فون ڈاؤن لوڈ کر رہے ہیں۔ ایک منٹ بعد دوبارہ کوشش کریں۔</p>
</div><div class="w"><div class="card">
<a class="btn" href="/">Try again</a>
</div></div></body></html>''';
