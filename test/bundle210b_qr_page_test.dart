// Bundle 210 (D1, D2, C6): QR texts, sizes and the download page.

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/share_app/data/apk_share_page.dart';
import 'package:locallink/features/share_app/domain/wifi_qr.dart';

void main() {
  group('Wi-Fi QR', () {
    test('normal WPA', () {
      expect(wifiQrText(ssid: 'AndroidShare_4821', password: 'k7m2x9qp'),
          'WIFI:T:WPA;S:AndroidShare_4821;P:k7m2x9qp;;');
    });
    test('escapes \\ ; , : "', () {
      expect(wifiQrEscape(r'a\b;c,d:e"f'), r'a\\b\;c\,d\:e\"f');
      expect(wifiQrText(ssid: 'My;Net', password: 'p:a,s"s'),
          r'WIFI:T:WPA;S:My\;Net;P:p\:a\,s\"s;;');
    });
    test('SAE, nopass, unknown type', () {
      expect(wifiQrText(ssid: 'X', password: 'longpass1', type: 'SAE'),
          'WIFI:T:SAE;S:X;P:longpass1;;');
      expect(wifiQrText(ssid: 'X', password: 'longpass1', type: 'nopass'),
          'WIFI:T:nopass;S:X;;');
      expect(wifiQrText(ssid: 'X', password: ''), 'WIFI:T:nopass;S:X;;');
      expect(wifiQrText(ssid: 'X', password: 'longpass1', type: 'WEP'),
          'WIFI:T:WPA;S:X;P:longpass1;;');
    });
    test('download URL and label', () {
      expect(shareDownloadUrl('192.168.43.1', 8080), 'http://192.168.43.1:8080');
      expect(shareDownloadLabel('192.168.43.1', 8081), '192.168.43.1:8081');
    });
    test('size label', () {
      expect(shareSizeLabel(62 * 1024 * 1024), '62 MB');
      expect(shareSizeLabel(1000), '1 MB');
      expect(shareSizeLabel(0), '1 MB');
    });
  });

  group('page', () {
    test('file name', () {
      expect(shareApkFileName('3.0.51'), 'LinkUp-3.0.51.apk');
      expect(shareApkFileName(''), 'LinkUp.apk');
      expect(shareApkFileName('3.0/../x'), 'LinkUp-3.0..x.apk');
    });
    test('with a name: Shared by, chat with name (EN + UR)', () {
      final html = buildSharePage(
          ownerName: 'Sajjad', version: '3.0.51', sizeBytes: 59 * 1024 * 1024);
      expect(html, contains('Shared by Sajjad &middot; 3.0.51 &middot; 59 MB'));
      expect(html, contains('chat with Sajjad with no internet'));
      expect(html, contains('Sajjad سے بات'));
      expect(html, contains('lang="ur" dir="rtl"'));
      expect(html, contains('download="LinkUp-3.0.51.apk"'));
    });
    test('no name: no "Shared by", says your friend', () {
      final html =
          buildSharePage(ownerName: '  ', version: '3.0.51', sizeBytes: 1);
      expect(html, isNot(contains('Shared by')));
      expect(html, contains('chat with your friend'));
    });
    test('html escape', () {
      expect(htmlEscape('<a href="x">&\''), '&lt;a href=&quot;x&quot;&gt;&amp;&#39;');
    });
    test('busy page EN + UR', () {
      final html = buildBusyPage();
      expect(html, contains('Try again in a minute'));
      expect(html, contains('dir="rtl"'));
    });
  });
}
