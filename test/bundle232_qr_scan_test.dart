import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart'
    show QrCode, QrErrorCorrectLevel, QrImage;

import 'package:locallink/core/services/qr_scan_config_232.dart';

/// Bundle 232: QR scanner could not read any LinkUp code.
/// Cause: 640x480 picture + dense codes + scanWindow filter.
void main() {
  const scanners = [
    'lib/features/directory/presentation/my_qr_screen.dart',
    'lib/features/groups/presentation/screens/group_qr_screens.dart',
    'lib/features/transfer/presentation/screens/account_transfer_scan_screen.dart',
  ];

  test('every scanner uses the 232 setup and no scanWindow filter', () {
    for (final path in scanners) {
      final src = File(path).readAsStringSync();
      expect(src, contains('linkUpQrScannerController()'), reason: path);
      expect(src.contains('MobileScannerController()'), isFalse,
          reason: '$path still uses the 640x480 default');
      expect(RegExp(r'scanWindow\s*:').hasMatch(src), isFalse,
          reason: '$path still filters with scanWindow');
    }
  });

  test('scanner setup asks for a sharper picture and QR only', () {
    final c = linkUpQrScannerController();
    addTearDown(c.dispose);
    expect(c.cameraResolution, kQrScanResolution);
    expect(kQrScanResolution.width * kQrScanResolution.height,
        greaterThanOrEqualTo(1280 * 720));
    expect(c.formats, [BarcodeFormat.qrCode]);
    expect(c.useNewCameraSelector, isTrue);
  });

  test('shown codes use error level Q, not H', () {
    final contact = File('lib/features/directory/presentation/my_qr_screen.dart')
        .readAsStringSync();
    final group =
        File('lib/features/groups/presentation/screens/group_qr_screens.dart')
            .readAsStringSync();
    expect(contact, contains('errorCorrectionLevel: QrErrorCorrectLevel.Q'));
    expect(contact.contains('QrErrorCorrectLevel.H'), isFalse);
    expect(group, contains('errorCorrectLevel: QrErrorCorrectLevel.Q'));
    expect(group.contains('QrErrorCorrectLevel.H'), isFalse);
  });

  test('a full contact code is clearly smaller at Q than at H', () {
    String b(int n) =>
        base64Url.encode(List<int>.generate(n, (i) => (i * 37) & 255))
            .replaceAll('=', '');
    final payload = jsonEncode({
      'v': 1,
      'profile': {
        'user_id': '6f1c2a8e-3b4d-4e5f-9a1b-2c3d4e5f6a7b',
        'device_id': 'android-9e62fd63d5d181c0',
        'username': 'sajjad_ahmed',
        'display_name': 'Sajjad Ahmed',
        'phone_number': '',
        'avatar_url': '',
        'profile_version': 12,
        'updated_at': '2026-11-07T12:25:31.123456Z',
        'signing_public_key': b(32),
        'identity_public_key': b(32),
        'phone_visibility': 'contacts',
        'discoverable_by_phone': true,
        'discoverable_by_name': true,
        'directory_sync_enabled': true,
        'signature': '',
        'source': 'qr',
        'synced_at': '',
      },
      'signature': b(64),
    });
    int modules(int level) =>
        QrImage(QrCode.fromData(data: payload, errorCorrectLevel: level))
            .moduleCount;
    final h = modules(QrErrorCorrectLevel.H);
    final q = modules(QrErrorCorrectLevel.Q);
    expect(q, lessThan(h));
    expect(q, lessThanOrEqualTo(117)); // version 25 or lower
  });
}
