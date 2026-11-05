// Bundle 210: the text inside the two Share LinkUp QR codes.

/// Escapes `\ ; , : "` with a backslash (Wi-Fi QR format).
String wifiQrEscape(String value) =>
    value.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');

/// QR 1: join the hotspot. [type] is `WPA` (WPA2 / WPA3 mixed), `SAE`
/// (WPA3 only) or `nopass`. Unknown types count as `WPA`.
String wifiQrText({
  required String ssid,
  String? password,
  String type = 'WPA',
}) {
  final t = (type == 'SAE' || type == 'nopass') ? type : 'WPA';
  final s = wifiQrEscape(ssid);
  if (t == 'nopass' || password == null || password.isEmpty) {
    return 'WIFI:T:nopass;S:$s;;';
  }
  return 'WIFI:T:$t;S:$s;P:${wifiQrEscape(password)};;';
}

/// QR 2: the download page (no path, so the page always opens first).
String shareDownloadUrl(String ip, int port) => 'http://$ip:$port';

/// What the user types by hand: `192.168.43.1:8080`.
String shareDownloadLabel(String ip, int port) => '$ip:$port';

/// `59 MB` (whole MB, at least 1).
String shareSizeLabel(int bytes) {
  final mb = (bytes / (1024 * 1024)).round();
  return '${mb < 1 ? 1 : mb} MB';
}
