// Bundle 210 (D3, D4, B2): which address goes in QR 2; channel maps.

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/share_address_picker.dart';

void main() {
  const wlan = ShareAddress(iface: 'wlan0', ip: '192.168.1.7');
  const p2p = ShareAddress(iface: 'p2p-wlan0-0', ip: '192.168.49.1');
  const ap = ShareAddress(iface: 'ap0', ip: '192.168.77.1', hotspot: true);
  const swlan = ShareAddress(iface: 'swlan0', ip: '192.168.43.1', hotspot: true);
  const odd = ShareAddress(iface: 'wlan2x', ip: '10.0.0.1');

  test('private IPv4', () {
    expect(isPrivateV4('192.168.1.1'), isTrue);
    expect(isPrivateV4('10.2.3.4'), isTrue);
    expect(isPrivateV4('172.16.0.1'), isTrue);
    expect(isPrivateV4('172.32.0.1'), isFalse);
    expect(isPrivateV4('8.8.8.8'), isFalse);
    expect(isPrivateV4('192.168.1'), isFalse);
    expect(isPrivateV4('192.168.1.300'), isFalse);
  });

  test('the address Android found wins (random subnet)', () {
    expect(pickShareIp(nativeIp: '192.168.77.1', list: const [wlan]),
        '192.168.77.1');
  });

  test('Wi-Fi Direct address from Android is ignored', () {
    expect(pickShareIp(nativeIp: '192.168.49.1', list: const [wlan, ap]),
        '192.168.77.1');
  });

  test('hotspot-looking interface beats others; wlan0 / p2p never', () {
    expect(pickShareIp(list: const [wlan, p2p, odd, ap]), '192.168.77.1');
    expect(pickShareIp(list: const [wlan, p2p]), isNull);
  });

  test('only one other private address → that one', () {
    expect(pickShareIp(list: const [wlan, p2p, odd]), '10.0.0.1');
  });

  test('two unknown → null + both offered', () {
    const other = ShareAddress(iface: 'eth9', ip: '10.1.1.1');
    expect(pickShareIp(list: const [odd, other]), isNull);
    expect(shareIpChoices(const [wlan, p2p, odd, other]).map((a) => a.ip),
        ['10.0.0.1', '10.1.1.1']);
  });

  test('own hotspot: 192.168.43.1 first, then hints, then x.x.x.1', () {
    expect(pickTetherIp(const [wlan, ap, swlan]), '192.168.43.1');
    expect(pickTetherIp(const [wlan, ap]), '192.168.77.1');
    expect(pickTetherIp(const [ShareAddress(iface: 'wlan0', ip: '192.168.88.1')]),
        '192.168.88.1');
    expect(pickTetherIp(const [wlan, p2p]), isNull);
  });

  test('channel maps', () {
    final list = ShareAddress.listFrom([
      {'iface': 'ap0', 'ip': '192.168.43.1', 'hotspot': true},
      {'iface': 'x'},
      'junk',
    ]);
    expect(list, hasLength(1));
    expect(list.single.hotspot, isTrue);

    final apk = ApkInfo.fromMap({
      'ok': true, 'path': '/a.apk', 'size': 10, 'version_name': '3.0.51',
      'split': false,
    });
    expect([apk.ok, apk.path, apk.size, apk.version, apk.split],
        [true, '/a.apk', 10, '3.0.51', false]);
    expect(ApkInfo.fromMap(null).ok, isFalse);
    expect(ApkInfo.fromMap({'ok': false, 'reason': 'apk_missing'}).reason,
        'apk_missing');

    final s = ShareStart.fromMap({
      'ok': true, 'ssid': 'A', 'key': 'pass1234', 'qr_type': 'SAE',
      'ip': '192.168.43.1', 'reused': true,
      'addresses': [{'iface': 'ap0', 'ip': '192.168.43.1'}],
    });
    expect([s.ok, s.ssid, s.password, s.qrType, s.ip, s.reused],
        [true, 'A', 'pass1234', 'SAE', '192.168.43.1', true]);
    expect(s.addresses, hasLength(1));
    expect(ShareStart.fromMap({'ok': true, 'ip': ''}).ip, isNull);
    expect(ShareStart.fromMap({'ok': false, 'reason': 'own_hotspot'}).reason,
        'own_hotspot');
    expect(ShareStart.fromMap(42).reason, 'error');

    final a = ShareAddresses.fromMap({'list': [], 'wifi_ip': '192.168.1.7'});
    expect(a.wifiIp, '192.168.1.7');
    expect(ShareAddresses.fromMap({'wifi_ip': ''}).wifiIp, isNull);
  });
}
