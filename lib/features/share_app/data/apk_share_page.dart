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

const String _css = '''
*{box-sizing:border-box}
body{margin:0;font-family:sans-serif;background:#f6f8fc;color:#161b2d}
.w{max-width:480px;margin:0 auto;padding:24px 18px 40px}
.logo{width:84px;height:84px;margin:8px auto 0;display:block}
h1{text-align:center;font-size:26px;margin:10px 0 4px}
.sub{text-align:center;color:#626a80;margin:2px 0}
.small{font-size:14px}
.btn{display:block;margin:22px 0 6px;padding:16px;border-radius:30px;background:#1e5bff;color:#fff;text-align:center;font-size:19px;font-weight:bold;text-decoration:none}
.ur{direction:rtl;text-align:right;font-size:16px;color:#626a80;margin:2px 0 0;line-height:1.8}
.urc{text-align:center;color:#1e5bff}
h2{font-size:19px;margin:28px 0 6px}
ol{padding-left:22px;margin:0}
li{margin:10px 0;font-size:16px;line-height:1.4}
.note{background:#fff7e6;color:#7a4800;border-radius:12px;padding:12px;margin-top:18px;font-size:14px}
''';

const String _logo = '''
<svg class="logo" viewBox="0 0 84 84" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#1e5bff"/><stop offset="1" stop-color="#23e0d8"/></linearGradient></defs>
<rect width="84" height="84" rx="22" fill="url(#g)"/>
<text x="42" y="58" font-size="44" font-family="sans-serif" font-weight="bold" fill="#fff" text-anchor="middle">L</text>
</svg>''';

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
  return '''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LinkUp</title><style>$_css</style></head>
<body><div class="w">
$_logo
<h1>LinkUp</h1>
<p class="sub">Chat and call without internet</p>
<p class="ur urc" lang="ur" dir="rtl">بغیر انٹرنیٹ کے بات اور کال کریں</p>
<p class="sub small">$shared</p>
<a class="btn" href="$shareApkPath" download="${shareApkFileName(version)}">&#11015; Download LinkUp</a>
<p class="ur urc" lang="ur" dir="rtl">لنک اپ ڈاؤن لوڈ کریں</p>
<h2>How to install</h2>
<p class="ur" lang="ur" dir="rtl">انسٹال کرنے کا طریقہ</p>
<ol>
<li>Tap Download LinkUp. If Chrome warns, tap Keep / Download anyway.
<p class="ur" lang="ur" dir="rtl">ڈاؤن لوڈ پر ٹیپ کریں۔ اگر کروم خبردار کرے تو Keep یا Download anyway دبائیں۔</p></li>
<li>Tap the file (or open Downloads) and tap Install.
<p class="ur" lang="ur" dir="rtl">فائل کھولیں (یا ڈاؤن لوڈز میں جائیں) اور انسٹال پر ٹیپ کریں۔</p></li>
<li>If Android says "not allowed to install unknown apps", tap Settings, turn on "Allow from this source", go back and tap Install.
<p class="ur" lang="ur" dir="rtl">اگر فون اجازت مانگے تو سیٹنگز میں جا کر "اس ذریعے سے اجازت دیں" آن کریں، پھر واپس آ کر انسٹال کریں۔</p></li>
<li>Open LinkUp. You can now chat with $who with no internet.
<p class="ur" lang="ur" dir="rtl">لنک اپ کھولیں۔ اب آپ بغیر انٹرنیٹ کے $whoUr سے بات کر سکتے ہیں۔</p></li>
</ol>
<div class="note">Play Protect may say "unknown app". That is normal for apps not from Play Store. Tap "Install anyway".
<p class="ur" lang="ur" dir="rtl">اگر Play Protect خبردار کرے تو یہ عام بات ہے۔ Install anyway دبائیں۔</p></div>
</div></body></html>''';
}

/// Shown to a 4th phone while 3 are already downloading.
String buildBusyPage() => '''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LinkUp</title><style>$_css</style></head>
<body><div class="w">
$_logo
<h1>Busy</h1>
<p class="sub">3 phones are downloading now. Try again in a minute.</p>
<p class="ur urc" lang="ur" dir="rtl">ابھی تین فون ڈاؤن لوڈ کر رہے ہیں۔ ایک منٹ بعد دوبارہ کوشش کریں۔</p>
<a class="btn" href="/">Try again</a>
</div></body></html>''';
