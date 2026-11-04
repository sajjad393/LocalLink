import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/security/gcm_parts.dart';
import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/core/security/sensitive_file_protection_service.dart';
import 'package:locallink/core/services/media_prepare_progress.dart';
import 'package:locallink/features/files/presentation/widgets/prepare_ring.dart';

import 'support/safe_delete.dart';

Uint8List _hex(String h) => Uint8List.fromList([
      for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)
    ]);
String _toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

class _Keys extends SecureStorageService {
  final Map<String, String> m = <String, String>{};
  @override
  Future<String?> read({required String key}) async => m[key];
  @override
  Future<void> write({required String key, required String value}) async => m[key] = value;
}

const _sqlChannel = MethodChannel('com.davidmartos96.sqflite_sqlcipher');

void main() {
  final magic = utf8.encode('LLFILE1');

  group('208 D1: AES-256-GCM in parts = the package, byte for byte', () {
    test('NIST GCM test cases 13, 14 and 16', () async {
      final z = Uint8List(32);
      var box = await GcmParts.encryptBytes(const [], key: z, nonce: Uint8List(12));
      expect(_toHex(box.mac.bytes), '530f8afbc74536b9a963b4f1c4cb738b');
      box = await GcmParts.encryptBytes(Uint8List(16), key: z, nonce: Uint8List(12));
      expect(_toHex(box.cipherText), 'cea7403d4d606b6e074ec5d3baf39d18');
      expect(_toHex(box.mac.bytes), 'd0d1c8a799996bf0265b98b5d48ab919');
      final k = _hex('feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308');
      final p = _hex('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
          '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39');
      final a = _hex('feedfacedeadbeeffeedfacedeadbeefabaddad2');
      final iv = _hex('cafebabefacedbaddecaf888');
      box = await GcmParts.encryptBytes(p, key: k, nonce: iv, aad: a);
      expect(_toHex(box.cipherText),
          '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
          '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662');
      expect(_toHex(box.mac.bytes), '76fc6ece0f4e1768cddf8853bb2d551b');
      expect(await GcmParts.decryptBytes(box, key: k, aad: a), p);
    });

    test('44 random sizes both ways (0 B .. 1 MB + 1)', () async {
      final r = Random(2080);
      final sizes = <int>[0, 1, 2, 15, 16, 17, 31, 32, 33, 47, 48, 49, 255, 256, 257, 4095, 4096, 4097,
        65535, 65536, 65537, 1048575, 1048576, 1048577,
        for (var i = 0; i < 20; i++) r.nextInt(300000)];
      for (final n in sizes) {
        final key = List<int>.generate(32, (_) => r.nextInt(256));
        final nonce = List<int>.generate(12, (_) => r.nextInt(256));
        final aad = r.nextBool() ? magic : List<int>.generate(r.nextInt(40), (_) => r.nextInt(256));
        final data = Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
        final pkg = await AesGcm.with256bits()
            .encrypt(data, secretKey: SecretKey(key), nonce: nonce, aad: aad);
        final mine = await GcmParts.encryptBytes(data, key: key, nonce: nonce, aad: aad);
        expect(mine.mac, pkg.mac, reason: 'mac n=$n');
        expect(mine.cipherText, pkg.cipherText, reason: 'cipher n=$n');
        expect(await GcmParts.decryptBytes(pkg, key: key, aad: aad), data, reason: 'n=$n');
      }
    });

    test('GHASH blocks continue across odd part sizes', () async {
      final h = Uint8List.fromList(List<int>.generate(16, (i) => i * 13 + 5));
      final data = Uint8List.fromList(List<int>.generate(1000, (i) => (i * 7) & 255));
      final one = GcmHash(h)..add(data, 0, data.length);
      final a = one.finish(0, data.length);
      final parts = GcmHash(h);
      var i = 0;
      for (final step in [1, 15, 16, 17, 3, 100, 333]) {
        final end = min(i + step, data.length);
        parts.add(data, i, end);
        i = end;
      }
      parts.add(data, i, data.length);
      expect(parts.finish(0, data.length), a);
    });
  });

  group('208 D1: files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('b208d'));
    tearDown(() => safeDeleteDir(dir));

    Future<(File, Uint8List, List<int>)> lockedByPackage(int n, {int seed = 1}) async {
      final r = Random(seed);
      final key = List<int>.generate(32, (_) => r.nextInt(256));
      final data = Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
      final src = File('${dir.path}/src.bin')..writeAsBytesSync(data);
      final out = File('${dir.path}/locked.enc');
      await SensitiveFileProtectionService.encryptFileForTest(src.path, out.path, key);
      return (out, data, key);
    }

    test('a file locked the old way opens in parts; progress goes up to the end', () async {
      final (locked, data, key) = await lockedByPackage(2500000);
      final seen = <int>[];
      int? total;
      await GcmParts.decryptFile(locked.path, '${dir.path}/view.bin', key, magic,
          progress: (d, t) {
        seen.add(d);
        total = t;
      });
      expect(File('${dir.path}/view.bin').readAsBytesSync(), data);
      expect(seen.first, 0);
      expect(seen.last, total);
      expect(seen.length, 4, reason: '0 + three 1 MB parts');
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThan(seen[i - 1]));
      }
    });

    test('locked in parts opens the old way (same format)', () async {
      final r = Random(9);
      final key = List<int>.generate(32, (_) => r.nextInt(256));
      final data = Uint8List.fromList(List<int>.generate(1500001, (_) => r.nextInt(256)));
      final src = File('${dir.path}/plain.bin')..writeAsBytesSync(data);
      final nonce = List<int>.generate(12, (_) => r.nextInt(256));
      await GcmParts.encryptFile(src.path, '${dir.path}/p.enc', key, magic, nonce);
      await SensitiveFileProtectionService.decryptFileForTest(
          '${dir.path}/p.enc', '${dir.path}/old_view.bin', key);
      expect(File('${dir.path}/old_view.bin').readAsBytesSync(), data);
    });

    test('a changed byte / wrong key fails and leaves no plain file', () async {
      final (locked, _, key) = await lockedByPackage(70000, seed: 3);
      final bytes = locked.readAsBytesSync();
      bytes[bytes.length - 10] ^= 1;
      locked.writeAsBytesSync(bytes);
      final view = '${dir.path}/v.bin';
      await expectLater(GcmParts.decryptFile(locked.path, view, key, magic),
          throwsA(isA<SecretBoxAuthenticationError>()));
      expect(File(view).existsSync(), isFalse);
      final (good, _, key2) = await lockedByPackage(5000, seed: 4);
      final wrong = List<int>.from(key2)..[0] ^= 1;
      await expectLater(GcmParts.decryptFile(good.path, view, wrong, magic),
          throwsA(isA<SecretBoxAuthenticationError>()));
      expect(File(view).existsSync(), isFalse);
    });

    test('not our file -> FormatException (as before)', () async {
      final f = File('${dir.path}/x.enc')..writeAsBytesSync(utf8.encode('NOTOURS...........'));
      await expectLater(GcmParts.decryptFile(f.path, '${dir.path}/v', List.filled(32, 0), magic),
          throwsA(isA<FormatException>()));
    });
  });

  group('208 D3/D4: the protection service reports progress', () {
    late Directory dir;
    setUp(() {
      dir = Directory('${Directory.systemTemp.createTempSync('b208s').path}/attachments')
        ..createSync(recursive: true);
      MediaPrepareProgress.instance.resetForTest();
      SensitiveFileProtectionService.resetPartsForTest();
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_sqlChannel, (call) async {
        if (call.method == 'getDatabasesPath') return dir.parent.path;
        return null;
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_sqlChannel, null);
      SensitiveFileProtectionService.resetPartsForTest();
      safeDeleteDir(dir.parent);
    });

    test('lock + open: first half, then second half; the old way can read it', () async {
      final keys = _Keys();
      final svc = SensitiveFileProtectionService(secureStorage: keys);
      final r = Random(5);
      final data = Uint8List.fromList(List<int>.generate(2200000, (_) => r.nextInt(256)));
      final plain = File('${dir.path}/clip.mp4')..writeAsBytesSync(data);
      final locked = '${plain.path}.enc';
      final values = <double>[];
      final slot = MediaPrepareProgress.instance.watch(locked);
      void on() {
        final v = slot.value;
        if (v != null) values.add(v);
      }
      slot.addListener(on);
      await svc.protectFile(plain.path, locked);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(values, isNotEmpty);
      expect(values.last, closeTo(0.5, 0.001), reason: 'lock = the first half');
      // the old one-step way still reads it
      final keyBytes = base64Url.decode(_pad(keys.m.values.single));
      await SensitiveFileProtectionService.decryptFileForTest(
          locked, '${dir.path}/old.bin', keyBytes);
      expect(File('${dir.path}/old.bin').readAsBytesSync(), data);
      values.clear();
      final view = await svc.materializeForView(locked, extension: '.mp4');
      expect(File(view).readAsBytesSync(), data);
      expect(values, isNotEmpty);
      expect(values.first, greaterThanOrEqualTo(0.5));
      expect(values.where((v) => v > 0.99), isNotEmpty);
      expect(slot.value, isNull, reason: 'ready: the number goes away');
      slot.removeListener(on);
    });

    test('parts off: the old way still works (fallback path)', () async {
      SensitiveFileProtectionService.resetPartsForTest(enabled: false);
      final svc = SensitiveFileProtectionService(secureStorage: _Keys());
      final plain = File('${dir.path}/a.jpg')..writeAsBytesSync(List<int>.filled(3000, 9));
      await svc.protectFile(plain.path, '${plain.path}.enc');
      final view = await svc.materializeForView('${plain.path}.enc', extension: '.jpg');
      expect(File(view).readAsBytesSync(), List<int>.filled(3000, 9));
    });
  });

  group('208 D5/D6: only the percent', () {
    setUp(() => MediaPrepareProgress.instance.resetForTest());

    testWidgets('ring turns with no text, then shows "45%"', (t) async {
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: Center(child: PrepareRing(path: '/a/clip.mp4')))));
      expect(find.byKey(const Key('prepare_ring')), findsOneWidget);
      expect(find.byKey(const Key('prepare_ring_pct')), findsNothing);
      expect(find.byType(Text), findsNothing, reason: 'no words');
      MediaPrepareProgress.instance.reportOpen('/a/clip.mp4.enc', 45, 100);
      await t.pump();
      expect(find.text('45%'), findsOneWidget);
      final ring = t.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, closeTo(.45, .001));
      MediaPrepareProgress.instance.done('/a/clip.mp4.enc');
      await t.pump();
      expect(find.byKey(const Key('prepare_ring_pct')), findsNothing);
    });

    test('lock + open count as one bar', () {
      final p = MediaPrepareProgress.instance;
      p.reportLock('/x.enc', 50, 100);
      expect(p.fractionFor('/x'), closeTo(.25, .001));
      p.reportOpen('/x.enc', 50, 100);
      expect(p.fractionFor('/x.enc'), closeTo(.75, .001));
      p.done('/x.enc');
      p.reportOpen('/x.enc', 10, 100);
      expect(p.fractionFor('/x.enc'), closeTo(.10, .001), reason: 'no lock this time');
      expect(MediaPrepareProgress.label(.456), '45%');
    });

    test('viewer + chat bubble use the ring; old words are gone (source)', () {
      final v = File('lib/features/files/presentation/widgets/media_gallery_viewer.dart')
          .readAsStringSync();
      expect(v, contains("Key('media_gallery_prepare_ring')"));
      expect(v, isNot(contains("'Preparing…'")));
      expect(v, isNot(contains('media_gallery_preparing_line')));
      final tile = File('lib/features/files/presentation/widgets/attachment_tile.dart')
          .readAsStringSync();
      expect(tile, contains("Key('chat_video_prepare_ring')"));
      expect(tile, contains('a.size > ringMinBytes'));
    });
  });
}

String _pad(String s) {
  var x = s;
  while (x.length % 4 != 0) {
    x += '=';
  }
  return x;
}
